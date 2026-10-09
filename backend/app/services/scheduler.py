"""Prayer-stop scheduler — a dynamic-programming constraint solver.

Problem: for each prayer event encountered during a journey, choose one mosque
candidate or "skip", subject to hard constraints, minimizing a weighted
objective. The state is (event index, accumulated extra minutes, accumulated
driving-detour minutes); transitions add detour + waiting + stop duration to
the running timeline, which is exactly how an early stop can make a later
prayer unreachable.

Hard constraints
* driving detour <= options.max_detour_min (total)
* arrival at the mosque <= prayer + prayer_buffer_min
* waiting before the prayer <= options.planning_window_min
* stops are processed in journey order (monotone anchors)

Soft objective (weights configurable per route variant)
  w_detour * detour_min + w_wait * wait_min + w_missing * missed_prayers
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

from ..domain.prayer import PrayerEvent, PrayerName
from ..domain.route import PlanningOptions
from .candidate_eval import RouteCandidate

# Objective weights used for the named route variants.
WEIGHT_PROFILES: dict[str, dict[str, float]] = {
    "balanced": {"detour": 1.0, "waiting": 0.4, "missing": 20.0},
    "prayer_friendly": {"detour": 0.4, "waiting": 0.25, "missing": 60.0},
    "strict": {"detour": 0.2, "waiting": 0.15, "missing": 10_000.0},
}

# Relative value of missing each prayer (fairness across the day).
MISS_WEIGHT: dict[PrayerName, float] = {
    PrayerName.FAJR: 1.0,
    PrayerName.DHUHR: 1.0,
    PrayerName.ASR: 1.0,
    PrayerName.MAGHRIB: 1.1,
    PrayerName.ISHA: 1.1,
}


@dataclass
class StopChoice:
    event: PrayerEvent
    candidate: RouteCandidate
    arrival_utc: datetime
    wait_s: int
    depart_utc: datetime
    detour_s: int

    @property
    def start_utc(self) -> datetime:
        return self.arrival_utc + timedelta(seconds=self.wait_s)


@dataclass
class ScheduleResult:
    stops: list[StopChoice] = field(default_factory=list)
    missed: list[PrayerEvent] = field(default_factory=list)
    total_detour_s: int = 0
    total_wait_s: int = 0
    total_extra_s: int = 0        # detour + waiting + stop time
    notes: list[str] = field(default_factory=list)
    feasible: bool = True
    skipped_by_budget: list[PrayerEvent] = field(default_factory=list)


def match_candidates_to_events(
    events: list[PrayerEvent],
    candidates: list[RouteCandidate],
    depart_utc: datetime,
    options: PlanningOptions,
) -> dict[int, list[RouteCandidate]]:
    """Index candidate lists per event, pruning impossible pairings early."""
    buffer_s = options.prayer_buffer_min * 60
    matched: dict[int, list[RouteCandidate]] = {}
    for ei, event in enumerate(events):
        usable: list[RouteCandidate] = []
        for cand in candidates:
            # With zero prior delay, the earliest we reach the mosque:
            arrival_0 = depart_utc + timedelta(
                seconds=cand.eta_at_anchor_s + cand.leg_seconds
            )
            if arrival_0 > event.utc + timedelta(seconds=buffer_s):
                continue  # can never make the deadline, even with no earlier stops
            usable.append(cand)
        if usable:
            # Cheapest first — helpful for pruning and deterministic ties.
            usable.sort(key=lambda c: (c.detour_seconds, c.leg_seconds))
            matched[ei] = usable
    return matched


def solve(
    events: list[PrayerEvent],
    candidates: list[RouteCandidate],
    depart_utc: datetime,
    options: PlanningOptions,
    weights: dict[str, float] | None = None,
) -> ScheduleResult:
    """Choose mosque stops for the given journey prayer events."""
    result = ScheduleResult()
    if options.prayer_stops == "none" or not events:
        result.missed = list(events)
        return result

    weights = weights or WEIGHT_PROFILES["balanced"]
    w_detour = weights.get("detour", 1.0)
    w_wait = weights.get("waiting", 0.6)
    w_missing = weights.get("missing", 8.0)
    if options.prayer_stops == "mandatory":
        w_missing = max(w_missing, WEIGHT_PROFILES["strict"]["missing"])

    matched = match_candidates_to_events(events, candidates, depart_utc, options)
    if not matched:
        result.missed = list(events)
        result.notes.append(
            "No mosque candidates could reach any journey prayer within the "
            "planning window."
        )
        return result

    detour_budget_s = options.max_detour_min * 60
    stop_s = options.stop_duration_min * 60
    window_s = options.planning_window_min * 60
    buffer_s = options.prayer_buffer_min * 60
    # Timeline cap: detour budget + worst-case wait/stop accumulation.
    total_cap_s = detour_budget_s + len(events) * (window_s + stop_s) + 3600

    # Layered DP: state -> (cost, prev_state, choice)
    State = tuple[int, int]  # (total_extra_s, detour_s) — 60 s granularity
    GRAIN = 60

    layer: dict[State, tuple[float, State | None, StopChoice | None]] = {
        (0, 0): (0.0, None, None)
    }
    parents: list[dict[State, tuple[float, State | None, StopChoice | None]]] = []

    for ei, event in enumerate(events):
        new_layer: dict[State, tuple[float, State | None, StopChoice | None]] = {}
        miss_penalty = w_missing * MISS_WEIGHT.get(event.name, 1.0)
        options_for_event = matched.get(ei, [])

        for state, (cost, _prev, _choice) in layer.items():
            total_s, detour_s = state[0] * GRAIN, state[1] * GRAIN

            # Option A: skip this prayer.
            skip_cost = cost + miss_penalty
            skip_state = state
            current = new_layer.get(skip_state)
            if current is None or skip_cost < current[0]:
                new_layer[skip_state] = (skip_cost, state, None)

            # Option B: stop at each feasible candidate.
            for cand in options_for_event:
                new_detour = detour_s + cand.detour_seconds
                if new_detour > detour_budget_s:
                    continue
                arrival_s = (
                    cand.eta_at_anchor_s + total_s + cand.leg_seconds
                )
                arrival_utc = depart_utc + timedelta(seconds=arrival_s)
                delta = (event.utc - arrival_utc).total_seconds()
                wait_s = int(max(0, delta))
                if wait_s > window_s:
                    continue           # would wait longer than planning window
                if arrival_utc > event.utc + timedelta(seconds=buffer_s):
                    continue           # arrives too late for this prayer
                new_total = total_s + cand.detour_seconds + wait_s + stop_s
                if new_total > total_cap_s:
                    continue
                stop_choice = StopChoice(
                    event=event,
                    candidate=cand,
                    arrival_utc=arrival_utc,
                    wait_s=wait_s,
                    depart_utc=arrival_utc
                    + timedelta(seconds=wait_s + stop_s),
                    detour_s=cand.detour_seconds,
                )
                add = (
                    w_detour * cand.detour_seconds / 60.0
                    + w_wait * wait_s / 60.0
                )
                step_cost = cost + add
                new_state: State = (new_total // GRAIN, new_detour // GRAIN)
                current = new_layer.get(new_state)
                if current is None or step_cost < current[0]:
                    new_layer[new_state] = (step_cost, state, stop_choice)

        parents.append(new_layer)
        layer = new_layer

    # Backtrack best final state.
    best_state = min(layer.items(), key=lambda kv: kv[1][0])[0]
    chain: list[StopChoice | None] = []
    state = best_state
    for li in range(len(events) - 1, -1, -1):
        entry = parents[li].get(state)
        if entry is None:
            chain.append(None)
            continue
        _cost, prev_state, choice = entry
        chain.append(choice)
        state = prev_state if prev_state is not None else (0, 0)
    chain.reverse()

    for event, choice in zip(events, chain):
        if choice is None:
            result.missed.append(event)
        else:
            result.stops.append(choice)

    result.total_detour_s = sum(c.detour_s for c in result.stops)
    result.total_wait_s = sum(c.wait_s for c in result.stops)
    result.total_extra_s = sum(
        c.detour_s + c.wait_s + stop_s for c in result.stops
    )

    if result.missed:
        budget_skipped = [
            e for e in result.missed
            if events.index(e) in matched
        ]
        no_data = [e for e in result.missed if e not in budget_skipped]
        result.skipped_by_budget = budget_skipped
        if budget_skipped and options.prayer_stops == "mandatory":
            result.notes.append(
                "Some journey prayers could not be given a stop within your "
                f"limits (max detour {options.max_detour_min} min)."
            )
        if no_data:
            result.notes.append(
                "No mosque data was available near: "
                + ", ".join(e.name.value.capitalize() for e in no_data)
                + " — this indicates missing coverage, not necessarily an "
                  "absence of mosques."
            )

    return result

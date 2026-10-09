"""End-to-end prayer-aware route planning.

Flow: route alternatives → prayer sampling along the route → mosque discovery
→ routed detour evaluation → DP scheduling per variant → plan construction
with metrics, explanations and explicit uncertainties.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from ..core.timeutil import resolve_tz
from ..domain.geo import GeoPoint, haversine_m
from ..domain.prayer import PrayerEvent, PrayerName
from ..domain.route import (
    PlanningOptions,
    Preference,
    RouteMetrics,
    RoutePlan,
    RouteRequest,
    RouteResponse,
    ScheduledStop,
    StopKind,
    TravelLeg,
    TravelMode,
)
from ..providers.base import MosqueProvider, PrayerTimeProvider, RouteResult, RoutingProvider
from ..providers.google_common import ProviderError
from . import prayer_sampling as sampling
from .candidate_eval import (
    RouteCandidate,
    discover_mosques_along_route,
    evaluate_detours,
)
from .scheduler import WEIGHT_PROFILES, ScheduleResult, StopChoice, solve

MAX_PLANS = 5


@dataclass
class PlanBuildOutput:
    plan: RoutePlan
    schedule: ScheduleResult
    events: list[PrayerEvent] = field(default_factory=list)


class RoutePlanner:
    """Orchestrates providers into comparable route plans."""

    def __init__(
        self,
        routing: RoutingProvider,
        prayer: PrayerTimeProvider,
        mosques: MosqueProvider,
    ) -> None:
        self.routing = routing
        self.prayer = prayer
        self.mosques = mosques

    async def plan(self, req: RouteRequest) -> RouteResponse:
        depart = _as_utc(req.depart_at)
        raw_routes = await self.routing.route(
            origin=req.origin,
            destination=req.destination,
            waypoints=req.waypoints,
            mode=req.mode,
            depart_at=depart,
            alternatives=req.max_alternatives,
        )
        if not raw_routes:
            raise ProviderError("Routing provider returned no routes")

        primary = raw_routes[0]
        notes: list[str] = []
        provider_notes: dict[str, str] = {}

        if not primary.live:
            notes.append(
                "ROUTING FIXTURE ACTIVE: distances and durations are estimates, "
                "not road-network routes."
            )

        # --- anchors, ETAs, prayer sampling -------------------------------
        anchors = sampling.select_sample_indices(primary.geometry)
        cum = sampling.cumulative_distances(primary.geometry)
        base_etas = {
            i: sampling.eta_seconds_at_vertex(cum, i, primary)
            for i in anchors
        }

        events, sample_notes = await sampling.sample_journey_prayers(
            self.prayer, primary, depart, req.prayer,
            waypoints=req.waypoints,
        )
        notes.extend(sample_notes)

        # --- mosque discovery + detour evaluation ------------------------
        candidates: list[RouteCandidate] = []
        mosque_status = "not_searched"
        mosque_message: str | None = None
        if events and req.options.prayer_stops != "none":
            search = await discover_mosques_along_route(
                self.mosques, primary.geometry, anchors
            )
            mosque_status = search.status
            mosque_message = search.message
            if search.candidates:
                candidates, detour_notes = await evaluate_detours(
                    self.routing, primary.geometry, base_etas,
                    search.candidates, req.mode, depart,
                )
                notes.extend(detour_notes)
                if any(c.detour_method == "great_circle_estimate" for c in candidates):
                    notes.append(
                        "Some detour times are great-circle estimates "
                        "(routing matrix unavailable) and are marked uncertain."
                    )
                if search.status == "fixture":
                    notes.append(
                        "MOSQUE FIXTURE ACTIVE: candidate mosques are synthetic "
                        "development data."
                    )

        # --- build variants ---------------------------------------------
        plans: list[RoutePlan] = []

        # 1) Fastest: no planned mosque stops (on every provider alternative).
        fastest = self._build_plan(
            req=req, route=primary, depart=depart, events=events,
            schedule=ScheduleResult(missed=list(events)),
            candidates=candidates,
            preference=Preference.FASTEST,
            mosque_status=mosque_status,
            mosque_message=mosque_message,
        )
        plans.append(fastest)

        # 2) Prayer-friendly + 3) Balanced on the primary geometry.
        if events and req.options.prayer_stops != "none":
            friendly_opts = req.options.model_copy(
                update={"preference": Preference.PRAYER_FRIENDLY}
            )
            friendly = self._build_scheduled_plan(
                req=req, route=primary, depart=depart, events=events,
                candidates=candidates, options=friendly_opts,
                weights=WEIGHT_PROFILES["prayer_friendly"],
                preference=Preference.PRAYER_FRIENDLY,
                base_fastest=fastest,
                mosque_status=mosque_status,
                mosque_message=mosque_message,
            )
            plans.append(friendly.plan)

            balanced_opts = req.options.model_copy(
                update={"preference": Preference.BALANCED}
            )
            balanced = self._build_scheduled_plan(
                req=req, route=primary, depart=depart, events=events,
                candidates=candidates, options=balanced_opts,
                weights={
                    "detour": req.options.weight_detour,
                    "waiting": req.options.weight_waiting,
                    "missing": req.options.weight_missing_prayer,
                },
                preference=Preference.BALANCED,
                base_fastest=fastest,
                mosque_status=mosque_status,
                mosque_message=mosque_message,
            )
            plans.append(balanced.plan)
        else:
            reason = (
                "No mosque stops requested."
                if req.options.prayer_stops == "none"
                else "No prayer times fall within this journey window."
            )
            for p in (plans[0],):
                p.explanation.append(reason)

        # 4) Additional provider geometries as fastest variants.
        for extra_route in raw_routes[1:]:
            if len(plans) >= MAX_PLANS or len(plans) >= req.max_alternatives:
                break
            alt = self._build_plan(
                req=req, route=extra_route, depart=depart, events=events,
                schedule=ScheduleResult(missed=list(events)),
                candidates=[],
                preference=Preference.FASTEST,
                mosque_status="not_searched",
                mosque_message=None,
            )
            alt.explanation.insert(
                0,
                "Alternative road geometry returned by the routing provider; "
                "shown without planned mosque stops for comparison.",
            )
            plans.append(alt)

        providers = {
            "routing": f"{primary.provider} ({'live' if primary.live else 'FIXTURE'})",
            "prayer": f"{self.prayer.name} ({'live' if self.prayer.live else 'FIXTURE'})",
            "mosques": f"{self.mosques.name} ({'live' if self.mosques.live else 'FIXTURE'})",
        }
        return RouteResponse(
            alternatives=plans,
            requested_at=datetime.now(timezone.utc),
            notes=notes,
            providers=providers,
        )

    # ------------------------------------------------------------------
    # plan construction
    # ------------------------------------------------------------------

    def _build_scheduled_plan(
        self, *, req, route, depart, events, candidates, options, weights,
        preference, base_fastest, mosque_status, mosque_message,
    ) -> PlanBuildOutput:
        schedule = solve(events, candidates, depart, options, weights)
        plan = self._build_plan(
            req=req, route=route, depart=depart, events=events,
            schedule=schedule, candidates=candidates,
            preference=preference, mosque_status=mosque_status,
            mosque_message=mosque_message, base_fastest=base_fastest,
        )
        return PlanBuildOutput(plan=plan, schedule=schedule, events=events)

    def _build_plan(
        self, *,
        req: RouteRequest,
        route: RouteResult,
        depart: datetime,
        events: list[PrayerEvent],
        schedule: ScheduleResult,
        candidates: list[RouteCandidate],
        preference: Preference,
        mosque_status: str = "ok",
        mosque_message: str | None = None,
        base_fastest: RoutePlan | None = None,
    ) -> RoutePlan:
        options = req.options
        stops, legs, uncertainties = _simulate(
            route, depart, req, schedule, options
        )
        destination_tz = resolve_tz(req.destination)

        arrival_utc = depart + timedelta(seconds=route.duration_s) \
            + timedelta(seconds=schedule.total_extra_s)
        arrival_local = arrival_utc.astimezone(ZoneInfo(destination_tz))

        detour_s = schedule.total_detour_s
        if base_fastest is not None:
            detour_s = max(
                0,
                int((arrival_utc - base_fastest.metrics.arrival_utc).total_seconds())
                - schedule.total_wait_s - len(schedule.stops) * options.stop_duration_min * 60,
            )

        metrics = RouteMetrics(
            total_distance_m=route.distance_m + sum(
                s.detour_distance_m for s in stops if s.kind == StopKind.MOSQUE
            ),
            total_duration_s=int((arrival_utc - depart).total_seconds()),
            driving_duration_s=sum(l.duration_s for l in legs),
            waiting_duration_s=schedule.total_wait_s,
            detour_duration_s=detour_s,
            detour_distance_m=sum(
                s.detour_distance_m for s in stops if s.kind == StopKind.MOSQUE
            ),
            arrival_utc=arrival_utc,
            arrival_local=arrival_local.strftime("%Y-%m-%d %H:%M"),
            arrival_tz=destination_tz,
            mosque_stop_count=sum(1 for s in stops if s.kind == StopKind.MOSQUE),
            prayers_served=[
                s.prayer.name.value for s in stops if s.prayer is not None
            ],
            prayers_missed=[e.name.value for e in schedule.missed],
        )

        plan = RoutePlan(
            preference=preference,
            legs=legs,
            stops=stops,
            metrics=metrics,
            prayer_events=events,
            explanation=[],
            uncertainties=uncertainties + schedule.notes + list(route.warnings),
            route_provider=route.provider,
            route_live=route.live,
            geometry=route.geometry,
            feasible=schedule.feasible,
        )

        plan.explanation = self._explain(
            preference, schedule, events, options, route,
            base_fastest, mosque_status, mosque_message,
        )
        return plan

    # ------------------------------------------------------------------

    @staticmethod
    def _explain(
        preference: Preference,
        schedule: ScheduleResult,
        events: list[PrayerEvent],
        options: PlanningOptions,
        route: RouteResult,
        base_fastest: RoutePlan | None,
        mosque_status: str,
        mosque_message: str | None,
    ) -> list[str]:
        lines: list[str] = []

        if preference == Preference.FASTEST:
            lines.append(
                "Fastest route: minimizes journey duration with no planned "
                "mosque stops."
            )
        served = len(schedule.stops)
        total = len(events)
        if preference != Preference.FASTEST and events:
            lines.append(
                f"Plan serves {served} of {total} prayer(s) falling during this "
                "journey."
            )
        if base_fastest is not None and preference != Preference.FASTEST:
            extra = int(
                (schedule.total_extra_s) / 60
            )
            detour_min = schedule.total_detour_s // 60
            wait_min = schedule.total_wait_s // 60
            if served:
                lines.append(
                    f"Adds ~{extra} min vs the fastest plan "
                    f"({detour_min} min driving detour + {wait_min} min waiting)."
                )
            else:
                lines.append(
                    "No mosque stop was selected — the plan matches the "
                    "fastest route."
                )

        for stop in schedule.stops:
            prayer = stop.event
            arrival_local = stop.arrival_utc.astimezone(
                ZoneInfo(prayer.tz)
            ).strftime("%H:%M")
            prayer_local = prayer.local.strftime("%H:%M")
            wait_min = stop.wait_s // 60
            detour_min = stop.detour_s // 60
            lines.append(
                f"{stop.candidate.mosque.label}: arrive {arrival_local} "
                f"({prayer.name.value.capitalize()} {prayer_local}), "
                f"{detour_min} min detour"
                + (f", {wait_min} min wait" if wait_min else "")
                + "."
            )
            if stop.candidate.detour_method == "great_circle_estimate":
                lines.append(
                    f"Detour time for {stop.candidate.mosque.label} is an "
                    "estimate (routing matrix unavailable)."
                )

        if preference != Preference.FASTEST:
            for event in schedule.missed:
                lines.append(
                    f"{event.name.value.capitalize()} "
                    f"({event.local.strftime('%H:%M')} local): no stop planned."
                )

        if mosque_status == "no_data" and preference != Preference.FASTEST:
            lines.append(
                mosque_message
                or "Mosque data unavailable for this route — a route without a "
                   "planned mosque stop is shown."
            )
        elif mosque_status == "provider_error":
            lines.append(
                mosque_message
                or "Mosque provider error — plans generated without mosque stops."
            )

        # de-duplicate while preserving order
        seen: set[str] = set()
        unique: list[str] = []
        for line in lines:
            if line not in seen:
                seen.add(line)
                unique.append(line)
        return unique


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        # Naive input is interpreted as UTC (API contract: offset required for
        # local times — clients should send offsets; this is a safe default).
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


# ---------------------------------------------------------------------------
# timeline simulation
# ---------------------------------------------------------------------------


def _simulate(
    route: RouteResult,
    depart: datetime,
    req: RouteRequest,
    schedule: ScheduleResult,
    options: PlanningOptions,
) -> tuple[list[ScheduledStop], list[TravelLeg], list[str]]:
    """Produce ordered stops and legs using the same model as the solver."""
    uncertainties: list[str] = []
    geometry = route.geometry
    if not geometry:
        return [], [], uncertainties

    stop_dur = options.stop_duration_min * 60
    haversine_cum = sampling.cumulative_distances(geometry)
    route_len_h = haversine_cum[-1]
    dist_scale = (route.distance_m / route_len_h) if route_len_h > 0 else 1.0

    def eta_s(vertex: int) -> int:
        if route.distance_m <= 0:
            return 0
        fraction = min(max(haversine_cum[vertex] / route_len_h, 0.0), 1.0)
        return int(route.duration_s * fraction)

    def nearest_vertex(point: GeoPoint) -> int:
        best_i, best_d = 0, float("inf")
        for i, v in enumerate(geometry):
            d = haversine_m(v, point)
            if d < best_d:
                best_i, best_d = i, d
        return best_i

    # mandatory nodes: origin, waypoints, destination
    node_defs: list[tuple[int, GeoPoint, StopKind, str]] = [
        (nearest_vertex(req.origin), req.origin, StopKind.ORIGIN, "Origin"),
    ]
    for i, wp in enumerate(req.waypoints):
        node_defs.append(
            (nearest_vertex(wp), wp, StopKind.WAYPOINT, f"Waypoint {i + 1}")
        )
    node_defs.append(
        (nearest_vertex(req.destination), req.destination, StopKind.DESTINATION,
         req.destination.name or "Destination")
    )

    # visit ordering: (eta at anchor, rank) — nodes before mosques at same point
    visits: list[tuple[int, int, str, object]] = []
    for v, point, kind, label in node_defs:
        visits.append((eta_s(v), 0, "node", (v, point, kind, label)))
    for choice in schedule.stops:
        visits.append(
            (choice.candidate.eta_at_anchor_s, 1, "mosque", choice)
        )
    visits.sort(key=lambda item: (item[0], item[1]))

    # Walk visits, tracking accumulated extra time.
    extra = 0
    t_prev = depart
    prev_pos_s = eta_s(node_defs[0][0])
    prev_loc = req.origin
    prev_stop = ScheduledStop(
        kind=StopKind.ORIGIN,
        name="Origin",
        location=req.origin,
        arrival_utc=depart,
        departure_utc=depart,
        locked=True,
    )
    stops: list[ScheduledStop] = [prev_stop]
    legs: list[TravelLeg] = []
    served_events: set[tuple] = set()

    for _eta, rank, kind, payload in visits[1:]:
        if kind == "node":
            v, point, stop_kind, label = payload
            arrival = depart + timedelta(seconds=eta_s(v) + extra)
            leg = _mk_leg(
                prev_loc, point, t_prev, arrival, route,
                prev_pos_s, eta_s(v), haversine_cum, dist_scale,
                from_label=prev_stop.name, to_label=label,
            )
            legs.append(leg)
            node_stop = ScheduledStop(
                kind=stop_kind,
                name=label,
                location=point,
                arrival_utc=arrival,
                departure_utc=arrival,
                locked=True,
            )
            stops.append(node_stop)
            prev_stop = node_stop
            prev_loc = point
            prev_pos_s = eta_s(v)
            t_prev = arrival
        else:
            choice: StopChoice = payload
            cand = choice.candidate
            arrival = choice.arrival_utc
            depart_mosque = choice.depart_utc

            leg = _mk_leg_detour(
                prev_loc, cand.mosque.location, t_prev, arrival,
                cand.leg_distance_m,
                from_label=prev_stop.name,
                to_label=cand.mosque.label,
            )
            legs.append(leg)

            served_events.add((choice.event.name, choice.event.utc))
            rationale = _stop_rationale(choice)
            mosque_stop = ScheduledStop(
                kind=StopKind.MOSQUE,
                name=cand.mosque.label,
                location=cand.mosque.location,
                arrival_utc=arrival,
                departure_utc=depart_mosque,
                prayer=choice.event,
                mosque_id=cand.mosque.id,
                mosque=cand.mosque,
                rationale=rationale,
                detour_seconds=cand.detour_seconds,
                detour_distance_m=cand.detour_distance_m,
                uncertainties=_mosque_uncertainties(cand),
            )
            stops.append(mosque_stop)

            extra += cand.detour_seconds + choice.wait_s + stop_dur
            prev_stop = mosque_stop
            prev_loc = cand.mosque.location
            # route position after returning to the road
            prev_pos_s = min(
                eta_s(min(cand.anchor_index + 1, len(geometry) - 1)),
                route.duration_s,
            )
            t_prev = depart_mosque

    # final leg to destination if not already emitted
    dest_vertex = node_defs[-1][0]
    if prev_stop.kind != StopKind.DESTINATION:
        arrival = depart + timedelta(
            seconds=route.duration_s + schedule.total_extra_s
        )
        if legs and legs[-1].to_point == req.destination:
            pass
        else:
            # If the destination node was already visited (sorted before a
            # mosque), skip duplicates.
            already = any(s.kind == StopKind.DESTINATION for s in stops)
            if not already:
                legs.append(
                    _mk_leg(
                        prev_loc, req.destination, t_prev, arrival, route,
                        prev_pos_s, eta_s(dest_vertex), haversine_cum,
                        dist_scale, from_label=prev_stop.name,
                        to_label="Destination",
                    )
                )
                stops.append(
                    ScheduledStop(
                        kind=StopKind.DESTINATION,
                        name="Destination",
                        location=req.destination,
                        arrival_utc=arrival,
                        departure_utc=arrival,
                        locked=True,
                    )
                )

    # Data-honesty checks.
    for s in stops:
        if s.kind == StopKind.MOSQUE and s.mosque is not None:
            if s.mosque.opening_hours is None:
                s.uncertainties.append(
                    "Opening hours not published by the data source."
                )
            elif not s.mosque.quality.provider:
                s.uncertainties.append("Source quality unknown.")
    return stops, legs, uncertainties


def _mk_leg(
    a: GeoPoint, b: GeoPoint, t0: datetime, t1: datetime,
    route: RouteResult, pos_a_s: int, pos_b_s: int,
    haversine_cum: list[float], dist_scale: float,
    from_label: str, to_label: str,
) -> TravelLeg:
    """Direct (no-detour) leg. Distance is derived proportionally from the
    provider's exact route total; duration comes from the simulated timeline."""
    duration = max(int((t1 - t0).total_seconds()), 0)
    if route.duration_s > 0:
        distance = int(route.distance_m * min(duration / route.duration_s, 1.0))
    else:
        distance = 0
    return TravelLeg(
        from_point=a, to_point=b,
        departure_utc=t0, arrival_utc=t1,
        distance_m=distance, duration_s=duration,
        from_label=from_label, to_label=to_label,
    )


def _mk_leg_detour(
    a: GeoPoint, b: GeoPoint, t0: datetime, t1: datetime,
    distance_m: int, from_label: str, to_label: str,
) -> TravelLeg:
    duration = max(int((t1 - t0).total_seconds()), 0)
    return TravelLeg(
        from_point=a, to_point=b,
        departure_utc=t0, arrival_utc=t1,
        distance_m=max(distance_m, 0), duration_s=duration,
        from_label=from_label, to_label=to_label,
    )


def _stop_rationale(choice: StopChoice) -> str:
    prayer = choice.event
    arrival = choice.arrival_utc.astimezone(ZoneInfo(prayer.tz)).strftime("%H:%M")
    prayer_time = prayer.local.strftime("%H:%M")
    wait = choice.wait_s // 60
    detour = choice.detour_s // 60
    relation = (
        f"{wait} min before {prayer.name.value.capitalize()}"
        if wait else
        f"at {prayer.name.value.capitalize()} time ({prayer_time})"
    )
    if choice.arrival_utc > prayer.utc:
        relation = (
            f"{(choice.arrival_utc - prayer.utc).total_seconds() // 60} min after "
            f"{prayer.name.value.capitalize()} start"
        )
    return (
        f"Selected: arrival {arrival}, {relation}; {detour} min detour; "
        f"data from {choice.candidate.mosque.quality.provider} "
        f"({'live' if choice.candidate.mosque.quality.source == 'live' else 'fixture'})."
    )


def _mosque_uncertainties(cand: RouteCandidate) -> list[str]:
    out: list[str] = []
    if cand.detour_method == "great_circle_estimate":
        out.append("Detour time is a great-circle estimate, not a routed value.")
    if cand.mosque.opening_hours is None:
        out.append("Opening hours unknown — not provided by the data source.")
    if cand.mosque.quality.source != "live":
        out.append("DEVELOPMENT FIXTURE data — not a real mosque record.")
    if cand.mosque.congregation_utc is None:
        out.append(
            "Congregation (iqama) time unknown — only prayer start time shown."
        )
    return out

"""Prayer-window scheduling: feasibility rules, budgets, objective behaviour."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.domain.geo import GeoPoint
from app.domain.mosque import DataQuality, MosqueCandidate
from app.domain.prayer import (
    AsrSchool,
    PrayerConfig,
    PrayerEvent,
    PrayerName,
)
from app.domain.route import PlanningOptions
from app.services.candidate_eval import RouteCandidate
from app.services.scheduler import solve

LOC = GeoPoint(lat=48.85, lon=2.35, tz="UTC", name="Test point")
DEPART = datetime(2025, 6, 15, 12, 0, tzinfo=timezone.utc)


def make_event(name=PrayerName.DHUHR, minute=20) -> PrayerEvent:
    return PrayerEvent.from_local(
        name=name,
        local_dt=datetime(2025, 6, 15, 12, minute),
        tz="UTC",
        location=LOC,
        method=PrayerConfig().method,
        school=AsrSchool.STANDARD,
        source="fixture",
        live=False,
    )


def make_candidate(
    cand_id="m1",
    detour_s=300,
    eta_s=300,
    leg_s=120,
    anchor=0,
) -> RouteCandidate:
    mosque = MosqueCandidate(
        id=cand_id,
        name=f"Mosque {cand_id}",
        location=LOC,
        quality=DataQuality(provider="fixture", source="fixture"),
    )
    return RouteCandidate(
        mosque=mosque,
        anchor_index=anchor,
        detour_seconds=detour_s,
        detour_distance_m=detour_s * 15,
        detour_method="routed",
        eta_at_anchor_s=eta_s,
        leg_seconds=leg_s,
        return_seconds=detour_s,
    )


def test_feasible_candidate_is_selected():
    event = make_event(minute=20)
    cand = make_candidate(detour_s=300, eta_s=300, leg_s=120)
    # arrival = depart + 300 + 120 = 12:07, prayer 12:20 -> 13 min wait
    result = solve([event], [cand], DEPART, PlanningOptions())
    assert len(result.stops) == 1
    stop = result.stops[0]
    assert stop.arrival_utc == DEPART + timedelta(seconds=420)
    assert stop.wait_s == 13 * 60
    assert result.total_detour_s == 300
    assert result.missed == []


def test_none_mode_plans_no_stops():
    event = make_event()
    options = PlanningOptions(prayer_stops="none")
    result = solve([event], [make_candidate()], DEPART, options)
    assert result.stops == []
    assert result.missed == [event]


def test_waiting_beyond_planning_window_is_rejected():
    # arrival 12:02, prayer 13:00 => 58 min wait > 30 min window
    event = make_event(minute=0)
    event = event.model_copy(update={"utc": DEPART + timedelta(hours=1)})
    cand = make_candidate(eta_s=60, leg_s=60, detour_s=120)
    result = solve([event], [cand], DEPART, PlanningOptions())
    assert result.stops == []
    assert event in result.missed


def test_arrival_after_buffer_is_rejected():
    # arrival = depart + 3600 + 60 = 13:01, prayer 12:20, buffer 10 -> too late
    event = make_event(minute=20)
    cand = make_candidate(eta_s=3600, leg_s=60, detour_s=120)
    result = solve([event], [cand], DEPART, PlanningOptions())
    assert result.stops == []
    assert event in result.missed


def test_detour_budget_is_a_hard_constraint():
    event = make_event(minute=20)
    over = make_candidate(cand_id="far", detour_s=30 * 60, eta_s=300, leg_s=120)
    # default max_detour_min = 25
    result = solve([event], [over], DEPART, PlanningOptions())
    assert result.stops == []
    assert event in result.missed


def test_scheduler_picks_the_cheaper_of_two_candidates():
    event = make_event(minute=20)
    cheap = make_candidate("cheap", detour_s=120, eta_s=300, leg_s=120)
    expensive = make_candidate("expensive", detour_s=900, eta_s=300, leg_s=120)
    result = solve([event], [expensive, cheap], DEPART, PlanningOptions())
    assert len(result.stops) == 1
    assert result.stops[0].candidate.mosque.id == "cheap"


def test_mandatory_mode_schedules_even_with_high_detour():
    event = make_event(minute=20)
    costly = make_candidate(detour_s=20 * 60, eta_s=300, leg_s=120)
    options = PlanningOptions(prayer_stops="mandatory", max_detour_min=25)
    result = solve([event], [costly], DEPART, options)
    assert len(result.stops) == 1  # mandatory: pay the (budgeted) detour


def test_earlier_stop_delays_later_events():
    """An early stop's extra time must shift later arrival computations."""
    fajr = make_event(PrayerName.FAJR, minute=10)
    fajr = fajr.model_copy(update={"utc": DEPART + timedelta(minutes=50)})
    dhuhr = make_event(PrayerName.DHUHR, minute=10)
    dhuhr = dhuhr.model_copy(update={"utc": DEPART + timedelta(minutes=90)})

    # Stop 1 (Fajr): arrival 12:45 (40 min anchor + 5 min leg), 5 min wait,
    # 5 min detour, 15 min stop => +25 min extra for everything after it.
    first = make_candidate("first", detour_s=300, eta_s=40 * 60, leg_s=300, anchor=0)
    # Stop 2 (Dhuhr at 13:30): anchor 60 min + 3 min leg => base arrival 13:03.
    # Taken AFTER stop 1, its arrival shifts to 13:28 (wait only 2 min).
    second = make_candidate("second", detour_s=600, eta_s=60 * 60, leg_s=180, anchor=1)

    result = solve([fajr, dhuhr], [first, second], DEPART,
                   PlanningOptions(stop_duration_min=15))
    assert [s.candidate.mosque.id for s in result.stops] == ["first", "second"]
    # Base arrival for stop 2 would be 13:03; the first stop must have pushed
    # it 25 minutes later: 12:00 + 60 min anchor + 25 min extra + 3 min leg.
    assert result.stops[1].arrival_utc == DEPART + timedelta(minutes=88)
    assert result.total_detour_s == 900
    assert result.total_wait_s == (5 + 2) * 60


def test_budget_exhaustion_leaves_later_prayer_unserved():
    """After a max-budget stop, no further detour may be spent."""
    p1 = make_event(PrayerName.DHUHR, minute=20)
    p2 = make_event(PrayerName.ASR, minute=45)
    big = make_candidate("big", detour_s=24 * 60, eta_s=300, leg_s=120, anchor=0)
    also = make_candidate("also", detour_s=5 * 60, eta_s=90 * 60, leg_s=120, anchor=1)
    result = solve([p1, p2], [big, also], DEPART,
                   PlanningOptions(max_detour_min=25))
    assert result.total_detour_s <= 25 * 60
    # only one of them fits the shared budget
    assert len(result.stops) <= 1


def test_no_candidates_reports_missed_not_fake_stops():
    event = make_event()
    result = solve([event], [], DEPART, PlanningOptions())
    assert result.stops == []
    assert result.missed == [event]
    assert any("No mosque candidates" in n for n in result.notes)

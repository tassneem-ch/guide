"""Route feasibility: plan structure, metrics consistency, waypoints."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.domain.geo import GeoPoint
from app.domain.prayer import PrayerConfig
from app.domain.route import (
    PlanningOptions,
    Preference,
    RouteRequest,
    StopKind,
    TravelMode,
)

PARIS = GeoPoint(lat=48.8566, lon=2.3522, tz="Europe/Paris", name="Paris")
LYON = GeoPoint(lat=45.7640, lon=4.8357, tz="Europe/Paris", name="Lyon")
DIJON = GeoPoint(lat=47.3220, lon=5.0415, tz="Europe/Paris", name="Dijon")


def make_request(depart: datetime | None = None, **kwargs) -> RouteRequest:
    return RouteRequest(
        origin=kwargs.pop("origin", PARIS),
        destination=kwargs.pop("destination", LYON),
        depart_at=depart or datetime(2025, 6, 15, 11, 50,
                                     tzinfo=timezone(timedelta(hours=2))),
        mode=TravelMode.DRIVING,
        options=kwargs.pop("options", PlanningOptions()),
        prayer=kwargs.pop("prayer", PrayerConfig()),
        **kwargs,
    )


@pytest.mark.asyncio
async def test_three_named_alternatives_are_returned(planner):
    response = await planner.plan(make_request())
    kinds = {p.preference for p in response.alternatives}
    assert {Preference.FASTEST, Preference.PRAYER_FRIENDLY,
            Preference.BALANCED} <= kinds
    fastest = next(p for p in response.alternatives
                   if p.preference == Preference.FASTEST)
    assert fastest.metrics.mosque_stop_count == 0


@pytest.mark.asyncio
async def test_metrics_are_self_consistent(planner):
    response = await planner.plan(make_request())
    req_depart = response.alternatives[0].legs[0].departure_utc
    for plan in response.alternatives:
        m = plan.metrics
        assert m.total_duration_s >= 0
        arrival = req_depart + timedelta(seconds=m.total_duration_s)
        assert abs((arrival - m.arrival_utc).total_seconds()) <= 1
        assert m.total_distance_m >= 0
        assert m.arrival_local  # formatted local arrival present
        # legs form a coherent non-decreasing timeline
        for a, b in zip(plan.legs, plan.legs[1:]):
            assert b.departure_utc >= a.arrival_utc - timedelta(seconds=1)


@pytest.mark.asyncio
async def test_prayer_friendly_never_beats_fastest_on_time(planner):
    response = await planner.plan(make_request())
    fastest = next(p for p in response.alternatives
                   if p.preference == Preference.FASTEST)
    friendly = next(p for p in response.alternatives
                    if p.preference == Preference.PRAYER_FRIENDLY)
    assert friendly.metrics.arrival_utc >= fastest.metrics.arrival_utc
    assert friendly.metrics.detour_duration_s >= 0


@pytest.mark.asyncio
async def test_waypoints_are_mandatory_stops(planner):
    response = await planner.plan(make_request(waypoints=[DIJON]))
    for plan in response.alternatives:
        kinds = [s.kind for s in plan.stops]
        assert StopKind.ORIGIN in kinds
        assert StopKind.WAYPOINT in kinds
        assert StopKind.DESTINATION in kinds
        waypoint = next(s for s in plan.stops if s.kind == StopKind.WAYPOINT)
        assert waypoint.locked is True


@pytest.mark.asyncio
async def test_fixture_data_is_labelled_in_notes_and_flags(planner):
    response = await planner.plan(make_request())
    assert any("FIXTURE" in note for note in response.notes)
    assert all(plan.route_live is False for plan in response.alternatives)
    assert "FIXTURE" in response.providers["routing"]


@pytest.mark.asyncio
async def test_mosque_stops_carry_honesty_fields(planner):
    response = await planner.plan(make_request())
    friendly = next(p for p in response.alternatives
                    if p.preference == Preference.PRAYER_FRIENDLY)
    for stop in friendly.stops:
        if stop.kind != StopKind.MOSQUE:
            continue
        assert stop.mosque is not None
        assert stop.prayer is not None
        assert stop.rationale
        assert stop.uncertainties, "fixture stops must disclose their nature"
        assert any("FIXTURE" in u for u in stop.uncertainties)
        assert stop.detour_seconds >= 0
        # arrival must fit the prayer window (planning 30 / buffer 10 min)
        assert stop.arrival_utc <= stop.prayer.utc + timedelta(minutes=10)
        wait = (stop.prayer.utc - stop.arrival_utc).total_seconds()
        assert wait <= 30 * 60


@pytest.mark.asyncio
async def test_explanations_exist_for_each_plan(planner):
    response = await planner.plan(make_request())
    for plan in response.alternatives:
        assert plan.explanation, "every plan must explain its choices"

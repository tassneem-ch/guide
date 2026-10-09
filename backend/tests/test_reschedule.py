"""Recalculation: departure-time and option changes trigger new plans."""
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
Cairo = GeoPoint(lat=30.0444, lon=31.2357, tz="Africa/Cairo", name="Cairo")

TZ2 = timezone(timedelta(hours=2))


def request(depart: datetime, **kw) -> RouteRequest:
    return RouteRequest(
        origin=kw.pop("origin", PARIS),
        destination=kw.pop("destination", LYON),
        depart_at=depart,
        mode=TravelMode.DRIVING,
        options=kw.pop("options", PlanningOptions()),
        prayer=kw.pop("prayer", PrayerConfig()),
        **kw,
    )


@pytest.mark.asyncio
async def test_departure_shift_moves_arrival(planner):
    base = datetime(2025, 6, 15, 11, 50, tzinfo=TZ2)
    later = base + timedelta(hours=2)
    first = await planner.plan(request(base))
    second = await planner.plan(request(later))

    a1 = first.alternatives[0].metrics.arrival_utc
    a2 = second.alternatives[0].metrics.arrival_utc
    assert (a2 - a1) == timedelta(hours=2)


@pytest.mark.asyncio
async def test_departure_change_changes_journey_prayers(planner):
    morning = await planner.plan(request(datetime(2025, 6, 15, 4, 0, tzinfo=TZ2)))
    evening = await planner.plan(request(datetime(2025, 6, 15, 17, 0, tzinfo=TZ2)))
    m_names = {e.name for e in morning.alternatives[0].prayer_events}
    e_names = {e.name for e in evening.alternatives[0].prayer_events}
    assert m_names != e_names, "prayer window must depend on departure time"
    assert "fajr" in {n.value for n in m_names}


@pytest.mark.asyncio
async def test_zero_detour_budget_blocks_detours(planner):
    generous = await planner.plan(
        request(datetime(2025, 6, 15, 11, 50, tzinfo=TZ2))
    )
    tight = await planner.plan(
        request(
            datetime(2025, 6, 15, 11, 50, tzinfo=TZ2),
            options=PlanningOptions(max_detour_min=0),
        )
    )

    def friendly(response):
        return next(p for p in response.alternatives
                    if p.preference == Preference.PRAYER_FRIENDLY)

    assert friendly(generous).metrics.detour_duration_s >= 0
    tight_plan = friendly(tight)
    # Zero budget: no stop may add driving detour time.
    assert tight_plan.metrics.detour_duration_s == 0
    for stop in tight_plan.stops:
        if stop.kind == StopKind.MOSQUE:
            assert stop.detour_seconds == 0


@pytest.mark.asyncio
async def test_prayer_stops_none_suppresses_all_stops(planner):
    response = await planner.plan(
        request(
            datetime(2025, 6, 15, 11, 50, tzinfo=TZ2),
            options=PlanningOptions(prayer_stops="none"),
        )
    )
    for plan in response.alternatives:
        assert all(s.kind != StopKind.MOSQUE for s in plan.stops)


@pytest.mark.asyncio
async def test_optimize_endpoint_replans_with_new_constraints(client):
    body = {
        "origin": {"lat": PARIS.lat, "lon": PARIS.lon, "tz": "Europe/Paris"},
        "destination": {"lat": LYON.lat, "lon": LYON.lon, "tz": "Europe/Paris"},
        "depart_at": "2025-06-15T11:50:00+02:00",
        "mode": "driving",
        "options": {"max_detour_min": 25, "prayer_stops": "optional"},
        "prayer": {"method": "mwl", "school": "standard"},
    }
    first = client.post("/v1/routes/alternatives", json=body)
    assert first.status_code == 200
    body["options"]["prayer_stops"] = "none"
    second = client.post("/v1/routes/optimize", json=body)
    assert second.status_code == 200
    a = first.json()["alternatives"]
    b = second.json()["alternatives"]
    assert a and b
    # rescheduling with stops disabled must remove mosque stops
    for plan in b:
        assert all(s["kind"] != "mosque" for s in plan["stops"])


@pytest.mark.asyncio
async def test_cross_country_replan_uses_destination_region_times(planner):
    """Planning into another country uses that region's prayer times."""
    response = await planner.plan(
        request(
            datetime(2025, 6, 15, 6, 0, tzinfo=timezone.utc),
            origin=PARIS,
            destination=Cairo,
        )
    )
    events = response.alternatives[0].prayer_events
    zones = {e.tz for e in events}
    assert "Europe/Paris" in zones
    assert "Africa/Cairo" in zones

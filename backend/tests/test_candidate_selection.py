"""Candidate discovery, detour evaluation and selection honesty."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.domain.geo import GeoPoint
from app.domain.mosque import MosqueSearchResult
from app.domain.prayer import PrayerConfig
from app.domain.route import PlanningOptions, RouteRequest, StopKind, TravelMode
from app.services.candidate_eval import (
    discover_mosques_along_route,
    evaluate_detours,
)

PARIS = GeoPoint(lat=48.8566, lon=2.3522, tz="Europe/Paris", name="Paris")
LYON = GeoPoint(lat=45.7640, lon=4.8357, tz="Europe/Paris", name="Lyon")


class EmptyMosqueProvider:
    """Simulates a provider that was reachable but has no data (or failed)."""

    name = "stub"
    live = True

    def __init__(self, status: str = "no_data", message: str | None = None):
        self.status = status
        self.message = message

    async def search_near(self, center, radius_m, query=None):
        return MosqueSearchResult(
            candidates=[], status=self.status, message=self.message
        )

    async def close(self):
        return None


@pytest.mark.asyncio
async def test_discovery_returns_deduped_candidates_with_anchor(mosque_provider):
    geometry = [PARIS, LYON]
    result = await discover_mosques_along_route(mosque_provider, geometry, [0, 1])
    assert result.status in ("ok", "fixture")
    assert result.candidates
    ids = [c.id for c in result.candidates]
    assert len(ids) == len(set(ids)), "candidates must be de-duplicated"
    assert all(c.assigned_route_index in (0, 1) for c in result.candidates)
    assert all(c.quality.source == "fixture" for c in result.candidates)


@pytest.mark.asyncio
async def test_detours_are_non_negative_and_labelled(
    routing_provider, mosque_provider
):
    geometry = [PARIS, LYON]
    search = await discover_mosques_along_route(mosque_provider, geometry, [0, 1])
    cands, notes = await evaluate_detours(
        routing_provider,
        geometry,
        {0: 0, 1: 40_000},
        search.candidates,
        TravelMode.DRIVING,
        datetime(2025, 6, 15, 9, 50, tzinfo=timezone.utc),
    )
    assert cands
    for c in cands:
        assert c.detour_seconds >= 0
        assert c.detour_distance_m >= 0
        assert c.detour_method in ("routed", "great_circle_estimate")
        assert c.leg_seconds >= 0


@pytest.mark.asyncio
async def test_no_mosque_data_yields_explicit_no_data_plan(planner):
    """Provider reachable but empty => plans still return, clearly explained."""
    from app.services.route_planner import RoutePlanner

    planner_with_gaps = RoutePlanner(
        planner.routing, planner.prayer, EmptyMosqueProvider()
    )
    response = await planner_with_gaps.plan(
        RouteRequest(
            origin=PARIS,
            destination=LYON,
            depart_at=datetime(2025, 6, 15, 11, 50,
                               tzinfo=timezone(timedelta(hours=2))),
            options=PlanningOptions(),
            prayer=PrayerConfig(),
        )
    )
    friendly = next(
        p for p in response.alternatives
        if p.preference.value == "prayer_friendly"
    )
    assert friendly.metrics.mosque_stop_count == 0
    assert any("no mosques" in line.lower() or "no mosque data" in line.lower()
               for line in friendly.explanation)
    # never fabricate: no mosque stop may appear anywhere
    assert all(s.kind != StopKind.MOSQUE
               for p in response.alternatives for s in p.stops)


@pytest.mark.asyncio
async def test_provider_error_is_reported_not_masked():
    class FailingProvider(EmptyMosqueProvider):
        def __init__(self):
            super().__init__(status="provider_error",
                             message="Overpass unavailable: timeout")

    from app.services.route_planner import RoutePlanner
    from app.providers.prayer_fixture import FixturePrayerProvider
    from app.providers.routing_fixture import FixtureRoutingProvider

    broken = RoutePlanner(
        FixtureRoutingProvider(), FixturePrayerProvider(), FailingProvider()
    )
    response = await broken.plan(
        RouteRequest(
            origin=PARIS,
            destination=LYON,
            depart_at=datetime(2025, 6, 15, 11, 50,
                               tzinfo=timezone(timedelta(hours=2))),
        )
    )
    friendly = next(p for p in response.alternatives
                    if p.preference.value == "prayer_friendly")
    assert friendly.metrics.mosque_stop_count == 0
    assert any("error" in line.lower() for line in friendly.explanation)

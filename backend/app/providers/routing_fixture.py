"""Development routing fixture — straight-line estimates, NOT road routing.

Every result is labelled live=False, estimated and carries an explicit warning
so the UI can never present it as a real routed journey.
"""
from __future__ import annotations

from datetime import datetime

from ..domain.geo import GeoPoint, haversine_m
from ..domain.route import TravelMode
from .base import MatrixResult, RouteResult

# Assumed average speeds (m/s) — deliberately coarse estimates.
_SPEED_MPS = {
    TravelMode.DRIVING: 16.7,   # ~60 km/h
    TravelMode.WALKING: 1.4,    # ~5 km/h
    TravelMode.CYCLING: 4.2,    # ~15 km/h
}

WARNING = (
    "DEVELOPMENT FIXTURE: straight-line estimate, not road-network routing. "
    "Set ROUTING_PROVIDER=osrm (keyless) or google (key required) for real routes."
)


class FixtureRoutingProvider:
    name = "fixture"
    live = False

    async def route(
        self,
        origin: GeoPoint,
        destination: GeoPoint,
        waypoints: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
        alternatives: int = 1,
    ) -> list[RouteResult]:
        points = [origin, *waypoints, destination]
        speed = _SPEED_MPS[mode]
        distance = 0.0
        for a, b in zip(points, points[1:]):
            distance += haversine_m(a, b)
        # Straight lines underestimate distance; apply a fixed detour factor so
        # numbers are not wildly optimistic, and label them as estimates anyway.
        distance *= 1.25
        duration = distance / speed
        return [
            RouteResult(
                geometry=points,
                distance_m=int(distance),
                duration_s=int(duration),
                provider=self.name,
                live=False,
                summary="Fixture route (estimated)",
                warnings=[WARNING],
            )
        ]

    async def matrix(
        self,
        origins: list[GeoPoint],
        destinations: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
    ) -> MatrixResult:
        speed = _SPEED_MPS[mode]
        durations: list[list[int | None]] = []
        distances: list[list[int | None]] = []
        for o in origins:
            d_row: list[int | None] = []
            s_row: list[int | None] = []
            for d in destinations:
                est = haversine_m(o, d) * 1.25
                s_row.append(int(est))
                d_row.append(int(est / speed))
            durations.append(d_row)
            distances.append(s_row)
        return MatrixResult(
            durations_s=durations,
            distances_m=distances,
            provider=self.name,
            live=False,
            estimated=True,
        )

    async def close(self) -> None:  # pragma: no cover
        return None

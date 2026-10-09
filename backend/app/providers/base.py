"""Provider-independent interfaces.

Every external service (Google, AlAdhan, OSRM, OSM, fixtures) implements one of
these protocols, so the engine and the API never import a vendor SDK directly
and any provider can be swapped for coverage/pricing reasons.
"""
from __future__ import annotations

from datetime import date, datetime
from typing import Protocol, runtime_checkable

from pydantic import BaseModel, Field

from ..domain.geo import GeoPoint
from ..domain.mosque import MosqueSearchResult
from ..domain.prayer import DayPrayers, PrayerCapabilities, PrayerConfig
from ..domain.route import TravelMode


class RouteResult(BaseModel):
    """One routed path as returned by a routing provider (road network)."""

    geometry: list[GeoPoint]
    distance_m: int
    duration_s: int
    provider: str
    live: bool = True                  # False => development fixture
    traffic_used: bool = False
    summary: str | None = None
    warnings: list[str] = Field(default_factory=list)


class MatrixResult(BaseModel):
    """Durations (seconds) and distances (metres) origin x destination.

    `None` marks an unroutable/unknown pair — never fabricated.
    """

    durations_s: list[list[int | None]]
    distances_m: list[list[int | None]]
    provider: str
    live: bool = True
    estimated: bool = False            # True => great-circle fallback (labelled)


@runtime_checkable
class RoutingProvider(Protocol):
    name: str
    live: bool

    async def route(
        self,
        origin: GeoPoint,
        destination: GeoPoint,
        waypoints: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
        alternatives: int = 1,
    ) -> list[RouteResult]: ...

    async def matrix(
        self,
        origins: list[GeoPoint],
        destinations: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
    ) -> MatrixResult: ...

    async def close(self) -> None: ...


@runtime_checkable
class PrayerTimeProvider(Protocol):
    name: str
    live: bool

    async def day_prayers(
        self, point: GeoPoint, local_date: date, config: PrayerConfig
    ) -> DayPrayers: ...

    def capabilities(self) -> PrayerCapabilities: ...

    async def close(self) -> None: ...


@runtime_checkable
class MosqueProvider(Protocol):
    name: str
    live: bool

    async def search_near(
        self, center: GeoPoint, radius_m: int, query: str | None = None
    ) -> MosqueSearchResult: ...

    async def close(self) -> None: ...


@runtime_checkable
class GeocodingProvider(Protocol):
    name: str
    live: bool

    async def geocode(
        self, query: str, language: str = "en", limit: int = 5
    ) -> list[GeoPoint]: ...

    async def reverse(self, point: GeoPoint, language: str = "en") -> str | None: ...

    async def close(self) -> None: ...


class OptimizationContext(BaseModel):
    """Input for a hosted stop-ordering solver (e.g. Google Route Optimization)."""

    starts: list[GeoPoint]
    ends: list[GeoPoint]
    visits: list[GeoPoint]
    depart_at: datetime
    mode: TravelMode
    time_windows_s: list[tuple[int, int]] | None = None
    service_times_s: list[int] | None = None


class OptimizationSolution(BaseModel):
    visit_order: list[int]
    total_duration_s: int
    provider: str
    live: bool = True
    raw_notes: list[str] = Field(default_factory=list)


@runtime_checkable
class OptimizationProvider(Protocol):
    """Optional hosted solver; the built-in scheduler remains the default."""

    name: str
    live: bool

    async def optimize(self, ctx: OptimizationContext) -> OptimizationSolution: ...

    async def close(self) -> None: ...

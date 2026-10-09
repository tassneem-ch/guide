"""Provider registry — the only place that constructs concrete providers.

Selected by environment (see .env.example / docs/PROVIDERS.md):
each slot can be a live provider or a clearly-labelled development fixture.
"""
from __future__ import annotations

from functools import lru_cache

from ..config import Settings, get_settings
from .base import (
    GeocodingProvider,
    MosqueProvider,
    OptimizationProvider,
    PrayerTimeProvider,
    RoutingProvider,
)
from .geocoding_fixture import FixtureGeocodingProvider
from .geocoding_google import GoogleGeocodingProvider
from .geocoding_nominatim import NominatimGeocodingProvider
from .mosques_fixture import FixtureMosqueProvider
from .mosques_google import GoogleMosqueProvider
from .mosques_osm import OsmMosqueProvider
from .optimize_google import GoogleRouteOptimizationProvider
from .prayer_aladhan import METHOD_LABELS, AladhanPrayerProvider
from .prayer_fixture import FixturePrayerProvider
from .routing_fixture import FixtureRoutingProvider
from .routing_google import GoogleRoutesProvider
from .routing_osrm import OsrmRoutingProvider

ALL_METHOD_LABELS = METHOD_LABELS


class ProviderBundle:
    """Holds one implementation per slot; created once per process."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.prayer: PrayerTimeProvider = _make_prayer(settings)
        self.routing: RoutingProvider = _make_routing(settings)
        self.mosques: MosqueProvider = _make_mosques(settings)
        self.geocoding: GeocodingProvider = _make_geocoding(settings)
        self.optimization: OptimizationProvider | None = _make_optimization(settings)

    def report(self) -> dict[str, str]:
        """Provider modes for /v1/health — makes fixture mode visible."""
        def label(p, slot: str) -> str:
            if p is None:
                return "disabled"
            mode = "live" if p.live else "FIXTURE (development data)"
            return f"{p.name} ({mode})"

        return {
            "prayer": label(self.prayer, "prayer"),
            "routing": label(self.routing, "routing"),
            "mosques": label(self.mosques, "mosques"),
            "geocoding": label(self.geocoding, "geocoding"),
            "optimization": label(self.optimization, "optimization"),
        }

    async def close(self) -> None:
        for provider in (self.prayer, self.routing, self.mosques,
                         self.geocoding, self.optimization):
            if provider is not None:
                await provider.close()


def _make_prayer(s: Settings) -> PrayerTimeProvider:
    if s.prayer_provider == "fixture":
        return FixturePrayerProvider()
    if s.prayer_provider == "aladhan":
        return AladhanPrayerProvider()
    raise ValueError(f"Unknown PRAYER_PROVIDER: {s.prayer_provider}")


def _make_routing(s: Settings) -> RoutingProvider:
    if s.routing_provider == "fixture":
        return FixtureRoutingProvider()
    if s.routing_provider == "osrm":
        return OsrmRoutingProvider()
    if s.routing_provider == "google":
        return GoogleRoutesProvider()
    raise ValueError(f"Unknown ROUTING_PROVIDER: {s.routing_provider}")


def _make_mosques(s: Settings) -> MosqueProvider:
    if s.mosque_provider == "fixture":
        return FixtureMosqueProvider()
    if s.mosque_provider == "osm":
        return OsmMosqueProvider()
    if s.mosque_provider == "google":
        return GoogleMosqueProvider()
    raise ValueError(f"Unknown MOSQUE_PROVIDER: {s.mosque_provider}")


def _make_geocoding(s: Settings) -> GeocodingProvider:
    if s.geocoding_provider == "fixture":
        return FixtureGeocodingProvider()
    if s.geocoding_provider == "nominatim":
        return NominatimGeocodingProvider()
    if s.geocoding_provider == "google":
        return GoogleGeocodingProvider()
    raise ValueError(f"Unknown GEOCODING_PROVIDER: {s.geocoding_provider}")


def _make_optimization(s: Settings) -> OptimizationProvider | None:
    if s.optimization_provider == "google":
        return GoogleRouteOptimizationProvider()
    return None  # internal scheduler handles optimization


@lru_cache
def get_providers() -> ProviderBundle:
    return ProviderBundle(get_settings())


def reset_providers() -> None:
    """Test hook — drop the cached bundle so settings changes take effect."""
    get_providers.cache_clear()

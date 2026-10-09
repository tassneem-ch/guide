"""Development geocoding fixture — resolves only a small set of known cities
and otherwise echoes coordinates parsed from the query ("lat,lon").

Clearly labelled: results carry the fixture name so callers can display them
as development data.
"""
from __future__ import annotations

from ..domain.geo import GeoPoint
from ..core.timeutil import tz_at

_KNOWN_CITIES: dict[str, tuple[float, float, str]] = {
    "tunis": (36.8065, 10.1815, "Africa/Tunis"),
    "paris": (48.8566, 2.3522, "Europe/Paris"),
    "london": (51.5074, -0.1278, "Europe/London"),
    "new york": (40.7128, -74.0060, "America/New_York"),
    "tokyo": (35.6762, 139.6503, "Asia/Tokyo"),
    "dubai": (25.2048, 55.2708, "Asia/Dubai"),
    "istanbul": (41.0082, 28.9784, "Europe/Istanbul"),
    "cairo": (30.0444, 31.2357, "Africa/Cairo"),
    "kuala lumpur": (3.139, 101.6869, "Asia/Kuala_Lumpur"),
    "jakarta": (-6.2088, 106.8456, "Asia/Jakarta"),
    "riyadh": (24.7136, 46.6753, "Asia/Riyadh"),
    "casablanca": (33.5731, -7.5898, "Africa/Casablanca"),
}


class FixtureGeocodingProvider:
    name = "fixture"
    live = False

    async def geocode(
        self, query: str, language: str = "en", limit: int = 5
    ) -> list[GeoPoint]:
        q = query.strip().lower()
        if "," in q:
            parts = [p.strip() for p in q.split(",")]
            try:
                lat, lon = float(parts[0]), float(parts[1])
                return [GeoPoint(lat=lat, lon=lon, tz=tz_at(lat, lon),
                                 name=f"{lat:.4f}, {lon:.4f} (fixture)")]
            except (ValueError, IndexError):
                pass
        for city, (lat, lon, tz) in _KNOWN_CITIES.items():
            if city in q:
                return [GeoPoint(lat=lat, lon=lon, tz=tz,
                                 name=f"{query} (fixture)")]
        return []

    async def reverse(self, point: GeoPoint, language: str = "en") -> str | None:
        for city, (lat, lon, _tz) in _KNOWN_CITIES.items():
            if abs(lat - point.lat) < 0.1 and abs(lon - point.lon) < 0.1:
                return f"{city.title()} (fixture)"
        return None

    async def close(self) -> None:  # pragma: no cover
        return None

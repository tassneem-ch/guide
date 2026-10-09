"""Shared time-zone resolution: point -> IANA zone."""
from __future__ import annotations

from functools import lru_cache

from ..domain.geo import GeoPoint

_resolver = None


def _get_resolver():
    global _resolver
    if _resolver is None:
        from timezonefinder import TimezoneFinder

        _resolver = TimezoneFinder()
    return _resolver


@lru_cache(maxsize=4096)
def tz_at(lat: float, lon: float) -> str | None:
    try:
        return _get_resolver().timezone_at(lat=lat, lng=lon)
    except Exception:  # pragma: no cover - defensive: resolver data missing
        return None


def resolve_tz(point: GeoPoint) -> str:
    """Return the point's IANA zone: explicit value, then offline lookup, then UTC."""
    if point.tz:
        return point.tz
    return tz_at(point.lat, point.lon) or "UTC"

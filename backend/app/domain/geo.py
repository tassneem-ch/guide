"""Geographic primitives shared across the backend."""
from __future__ import annotations

import math

from pydantic import BaseModel, Field


class GeoPoint(BaseModel):
    """A WGS84 point, optionally carrying its IANA time zone and a label."""

    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    tz: str | None = None
    name: str | None = None

    def as_tuple(self) -> tuple[float, float]:
        return (self.lat, self.lon)


EARTH_RADIUS_M = 6_371_000.0


def haversine_m(a: GeoPoint, b: GeoPoint) -> float:
    """Great-circle distance in metres (estimates only — routing uses road data)."""
    lat1, lat2 = math.radians(a.lat), math.radians(b.lat)
    dlat = lat2 - lat1
    dlon = math.radians(b.lon - a.lon)
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


def bounds_of(points: list[GeoPoint], pad_deg: float = 0.05) -> tuple[float, float, float, float]:
    """(min_lat, min_lon, max_lat, max_lon) bounding box with padding."""
    if not points:
        raise ValueError("bounds_of requires at least one point")
    lats = [p.lat for p in points]
    lons = [p.lon for p in points]
    return (
        min(lats) - pad_deg,
        min(lons) - pad_deg,
        max(lats) + pad_deg,
        max(lons) + pad_deg,
    )


def point_segment_distance_m(p: GeoPoint, a: GeoPoint, b: GeoPoint) -> float:
    """Approximate perpendicular distance from p to segment a-b, in metres.

    Uses an equirectangular projection around the segment latitude — accurate
    enough for corridor filtering; all detour *costs* use routed distances.
    """
    lat0 = math.radians((a.lat + b.lat) / 2)
    m_per_deg_lat = 111_320.0
    m_per_deg_lon = 111_320.0 * max(math.cos(lat0), 1e-6)

    ax, ay = a.lon * m_per_deg_lon, a.lat * m_per_deg_lat
    bx, by = b.lon * m_per_deg_lon, b.lat * m_per_deg_lat
    px, py = p.lon * m_per_deg_lon, p.lat * m_per_deg_lat

    dx, dy = bx - ax, by - ay
    seg_len2 = dx * dx + dy * dy
    if seg_len2 == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / seg_len2))
    proj_x, proj_y = ax + t * dx, ay + t * dy
    return math.hypot(px - proj_x, py - proj_y)

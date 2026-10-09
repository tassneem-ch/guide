"""Geocoding via Google Geocoding API — key required."""
from __future__ import annotations

import httpx

from ..config import get_settings
from ..core.timeutil import tz_at
from ..domain.geo import GeoPoint
from .google_common import make_client


class GoogleGeocodingProvider:
    name = "google"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._key = settings.google_maps_api_key
        self._client = make_client(timeout=15.0)

    async def geocode(
        self, query: str, language: str = "en", limit: int = 5
    ) -> list[GeoPoint]:
        if not self._key:
            return []
        try:
            response = await self._client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={
                    "address": query,
                    "key": self._key,
                    "language": language,
                },
            )
            response.raise_for_status()
            rows = response.json().get("results", [])
        except (httpx.HTTPError, ValueError):
            return []
        results: list[GeoPoint] = []
        for row in rows[:limit]:
            location = (row.get("geometry") or {}).get("location") or {}
            if "lat" not in location:
                continue
            lat, lon = location["lat"], location["lng"]
            tz_name = ((row.get("geometry") or {}).get("time_zone")
                       or row.get("address_components") and None)
            results.append(
                GeoPoint(lat=lat, lon=lon, tz=tz_name or tz_at(lat, lon),
                         name=row.get("formatted_address"))
            )
        return results

    async def reverse(self, point: GeoPoint, language: str = "en") -> str | None:
        if not self._key:
            return None
        try:
            response = await self._client.get(
                "https://maps.googleapis.com/maps/api/geocode/json",
                params={
                    "latlng": f"{point.lat},{point.lon}",
                    "key": self._key,
                    "language": language,
                },
            )
            response.raise_for_status()
            rows = response.json().get("results", [])
        except (httpx.HTTPError, ValueError):
            return None
        return rows[0].get("formatted_address") if rows else None

    async def close(self) -> None:
        await self._client.aclose()

"""Geocoding via OpenStreetMap Nominatim (keyless, live).

Nominatim usage policy requires a descriptive User-Agent and forbids heavy
batch use — one request per query, results capped.
"""
from __future__ import annotations

import httpx

from ..config import get_settings
from ..domain.geo import GeoPoint
from .google_common import make_client
from ..core.timeutil import tz_at


class NominatimGeocodingProvider:
    name = "nominatim"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._base = settings.nominatim_api_base.rstrip("/")
        self._client = make_client(timeout=15.0)
        self._client.headers["User-Agent"] = "guide-prayer-travel/1.0 (backend)"

    async def geocode(
        self, query: str, language: str = "en", limit: int = 5
    ) -> list[GeoPoint]:
        try:
            response = await self._client.get(
                f"{self._base}/search",
                params={
                    "q": query,
                    "format": "jsonv2",
                    "limit": limit,
                    "addressdetails": 1,
                    "accept-language": language,
                },
            )
            response.raise_for_status()
            rows = response.json()
        except (httpx.HTTPError, ValueError):
            return []
        results: list[GeoPoint] = []
        for row in rows:
            lat, lon = float(row["lat"]), float(row["lon"])
            results.append(
                GeoPoint(
                    lat=lat,
                    lon=lon,
                    tz=tz_at(lat, lon),
                    name=row.get("display_name"),
                )
            )
        return results

    async def reverse(self, point: GeoPoint, language: str = "en") -> str | None:
        try:
            response = await self._client.get(
                f"{self._base}/reverse",
                params={
                    "lat": point.lat,
                    "lon": point.lon,
                    "format": "jsonv2",
                    "accept-language": language,
                },
            )
            response.raise_for_status()
            data = response.json()
        except (httpx.HTTPError, ValueError):
            return None
        return data.get("display_name")

    async def close(self) -> None:
        await self._client.aclose()

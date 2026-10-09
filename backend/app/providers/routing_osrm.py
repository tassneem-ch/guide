"""Routing via OSRM (keyless, real road network — development/zero-cost mode).

The public demo server (router.project-osrm.org) is rate-limited and intended
for development. Production deployments should use Google Routes API or a
self-hosted OSRM — see docs/PROVIDERS.md.
"""
from __future__ import annotations

from datetime import datetime
from typing import Any

import httpx

from ..config import get_settings
from ..core.cache import TTLCache
from ..domain.geo import GeoPoint
from ..domain.route import TravelMode
from .base import MatrixResult, RouteResult
from .google_common import ProviderError

_PROFILES = {
    TravelMode.DRIVING: "driving",
    TravelMode.WALKING: "walking",
    TravelMode.CYCLING: "cycling",
}


class OsrmRoutingProvider:
    name = "osrm"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._base = settings.osrm_api_base.rstrip("/")
        self._client = httpx.AsyncClient(timeout=httpx.Timeout(20.0, connect=5.0))
        self._cache = TTLCache(settings.route_cache_ttl_seconds)
        self._max_matrix = settings.max_matrix_elements

    async def route(
        self,
        origin: GeoPoint,
        destination: GeoPoint,
        waypoints: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
        alternatives: int = 1,
    ) -> list[RouteResult]:
        coords = [origin, *waypoints, destination]
        coord_str = ";".join(f"{p.lon:.6f},{p.lat:.6f}" for p in coords)
        profile = _PROFILES[mode]
        url = f"{self._base}/route/v1/{profile}/{coord_str}"
        params = {
            "overview": "full",
            "geometries": "geojson",
            "alternatives": "true" if (alternatives > 1 and mode == TravelMode.DRIVING) else "false",
        }
        cache_key = ("route", url, params["alternatives"], mode.value)

        async def fetch() -> dict[str, Any]:
            try:
                response = await self._client.get(url, params=params)
                response.raise_for_status()
                data = response.json()
            except httpx.HTTPError as exc:
                raise ProviderError(f"OSRM route request failed: {exc}") from exc
            if data.get("code") != "Ok" or not data.get("routes"):
                raise ProviderError(f"OSRM returned no route: {data.get('message') or data.get('code')}")
            return data

        data = await self._cache.get_or_fetch(cache_key, fetch)
        results: list[RouteResult] = []
        for route in data["routes"]:
            geometry = [
                GeoPoint(lat=lat, lon=lon)
                for lon, lat in route["geometry"]["coordinates"]
            ]
            results.append(
                RouteResult(
                    geometry=geometry,
                    distance_m=int(route["distance"]),
                    duration_s=int(route["duration"]),
                    provider=self.name,
                    live=True,
                    summary=f"OSRM {profile}",
                    warnings=[] if route is data["routes"][0] else
                        ["Alternative route from OSRM; durations ignore live traffic."],
                )
            )
        return results

    async def matrix(
        self,
        origins: list[GeoPoint],
        destinations: list[GeoPoint],
        mode: TravelMode,
        depart_at: datetime,
    ) -> MatrixResult:
        total = len(origins) * len(destinations)
        if total > self._max_matrix:
            raise ProviderError(
                f"matrix too large ({total} > {self._max_matrix}); reduce candidates"
            )
        coords = list(dict.fromkeys(
            [f"{p.lon:.6f},{p.lat:.6f}" for p in origins + destinations]
        ))
        profile = _PROFILES[mode]
        url = f"{self._base}/table/v1/{profile}/{';'.join(coords)}"
        params = {"annotations": "duration,distance"}
        cache_key = ("table", url)

        async def fetch() -> dict[str, Any]:
            try:
                response = await self._client.get(url, params=params)
                response.raise_for_status()
                data = response.json()
            except httpx.HTTPError as exc:
                raise ProviderError(f"OSRM table request failed: {exc}") from exc
            if data.get("code") != "Ok":
                raise ProviderError(f"OSRM table error: {data.get('code')}")
            return data

        data = await self._cache.get_or_fetch(cache_key, fetch)
        durations = data.get("durations") or []
        distances = data.get("distances") or []
        # Map merged coordinate list back onto (origins x destinations).
        coord_index = {c: i for i, c in enumerate(coords)}

        def pick(matrix: list[list[float | None]], i: int, j: int) -> int | None:
            oi = coord_index[f"{origins[i].lon:.6f},{origins[i].lat:.6f}"]
            dj = coord_index[f"{destinations[j].lon:.6f},{destinations[j].lat:.6f}"]
            try:
                value = matrix[oi][dj]
            except (IndexError, TypeError):
                return None
            return None if value is None else int(value)

        return MatrixResult(
            durations_s=[[pick(durations, i, j) for j in range(len(destinations))]
                         for i in range(len(origins))],
            distances_m=[[pick(distances, i, j) for j in range(len(destinations))]
                         for i in range(len(origins))],
            provider=self.name,
            live=True,
        )

    async def close(self) -> None:
        await self._client.aclose()

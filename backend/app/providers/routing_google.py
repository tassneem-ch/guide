"""Routing via Google Routes API (v2) — production provider, key required."""
from __future__ import annotations

from datetime import datetime

from ..config import get_settings
from ..core.cache import TTLCache
from ..core.polyline import decode_polyline
from ..domain.geo import GeoPoint
from ..domain.route import TravelMode
from .base import MatrixResult, RouteResult
from .google_common import (
    ProviderError,
    google_headers,
    make_client,
    parse_duration_seconds,
)

_MODES = {
    TravelMode.DRIVING: "DRIVE",
    TravelMode.WALKING: "WALK",
    TravelMode.CYCLING: "BICYCLE",
}

_ROUTE_FIELD_MASK = ",".join(
    [
        "routes.duration",
        "routes.distanceMeters",
        "routes.polyline.encodedPolyline",
        "routes.description",
        "routes.legs.duration",
        "routes.legs.distanceMeters",
        "routes.staticDuration",
    ]
)

_MATRIX_FIELD_MASK = ",".join(
    ["rows.elements.duration", "rows.elements.distanceMeters", "rows.elements.status"]
)


def _latlng(point: GeoPoint) -> dict:
    return {"latitude": point.lat, "longitude": point.lon}


class GoogleRoutesProvider:
    name = "google"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._key = settings.google_maps_api_key
        self._client = make_client()
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
        body: dict = {
            "origin": {"location": {"latLng": _latlng(origin)}},
            "destination": {"location": {"latLng": _latlng(destination)}},
            "travelMode": _MODES[mode],
            "computeAlternativeRoutes": alternatives > 1,
            "languageCode": "en",
            "units": "METRIC",
        }
        if waypoints:
            body["intermediateWaypoints"] = [
                {"location": {"latLng": _latlng(p)}} for p in waypoints
            ]
        if mode == TravelMode.DRIVING:
            body["departureTime"] = depart_at.isoformat()
            body["routingPreference"] = "TRAFFIC_AWARE"

        cache_key = ("google-route", body)

        async def fetch() -> dict:
            try:
                response = await self._client.post(
                    "https://routes.googleapis.com/directions/v2:computeRoutes",
                    json=body,
                    headers=google_headers(self._key, _ROUTE_FIELD_MASK),
                )
                response.raise_for_status()
                return response.json()
            except Exception as exc:  # httpx + header errors
                raise ProviderError(f"Google Routes API failed: {exc}") from exc

        data = await self._cache.get_or_fetch(cache_key, fetch)
        routes = data.get("routes") or []
        if not routes:
            raise ProviderError("Google Routes API returned no routes for this query")

        results: list[RouteResult] = []
        for i, route in enumerate(routes):
            duration = parse_duration_seconds(route.get("duration"))
            static_duration = parse_duration_seconds(route.get("staticDuration"))
            distance = route.get("distanceMeters")
            encoded = (route.get("polyline") or {}).get("encodedPolyline")
            if duration is None or distance is None or not encoded:
                raise ProviderError("Google Routes API route missing core fields")
            warnings: list[str] = []
            if static_duration and duration > static_duration * 1.3:
                warnings.append(
                    f"Traffic adds ~{int((duration - static_duration) / 60)} min "
                    "to this route at the requested departure time."
                )
            results.append(
                RouteResult(
                    geometry=decode_polyline(encoded, precision=5),
                    distance_m=int(distance),
                    duration_s=duration,
                    provider=self.name,
                    live=True,
                    traffic_used=static_duration is not None and duration != static_duration,
                    summary=route.get("description") or f"Google route {i + 1}",
                    warnings=warnings,
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
        body = {
            "origins": [{"location": {"latLng": _latlng(p)}} for p in origins],
            "destinations": [{"location": {"latLng": _latlng(p)}} for p in destinations],
            "travelMode": _MODES[mode],
            "languageCode": "en",
            "units": "METRIC",
        }
        if mode == TravelMode.DRIVING:
            body["departureTime"] = depart_at.isoformat()
            body["routingPreference"] = "TRAFFIC_AWARE"

        try:
            response = await self._client.post(
                "https://routes.googleapis.com/v2/distanceMatrix",
                json=body,
                headers=google_headers(self._key, _MATRIX_FIELD_MASK),
            )
            response.raise_for_status()
            data = response.json()
        except Exception as exc:
            raise ProviderError(f"Google Distance Matrix failed: {exc}") from exc

        rows = data.get("rows", [])
        durations: list[list[int | None]] = []
        distances: list[list[int | None]] = []
        for row in rows:
            dur_row: list[int | None] = []
            dist_row: list[int | None] = []
            for element in row.get("elements", []):
                status = element.get("status", "OK")
                if status != "OK":
                    dur_row.append(None)
                    dist_row.append(None)
                    continue
                dur_row.append(parse_duration_seconds(element.get("duration")))
                dist_row.append(parse_duration_seconds(element.get("distanceMeters")))
            durations.append(dur_row)
            distances.append(dist_row)

        return MatrixResult(
            durations_s=durations,
            distances_m=distances,
            provider=self.name,
            live=True,
        )

    async def close(self) -> None:
        await self._client.aclose()

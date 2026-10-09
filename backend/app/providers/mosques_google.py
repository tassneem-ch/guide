"""Mosque discovery via Google Places API (New) — key required.

Field masks keep payload and quota cost minimal (id, displayName, location,
regularOpeningHours, viewport). No caching of raw place data beyond the shared
TTL cache (see docs/PROVIDERS.md for caching-terms notes).
"""
from __future__ import annotations

from datetime import datetime, timezone

from ..config import get_settings
from ..core.cache import TTLCache
from ..domain.geo import GeoPoint
from ..domain.mosque import DataQuality, MosqueCandidate, MosqueSearchResult, Verification
from .google_common import ProviderError, make_client

_FIELD_MASK = ",".join(
    [
        "places.id",
        "places.displayName",
        "places.location",
        "places.formattedAddress",
        "places.regularOpeningHours.weekdayDescriptions",
        "places.nationalPhoneNumber",
        "places.websiteUri",
        "places.accessibilityOptions.wheelchairAccessibleEntrance",
        "places.types",
    ]
)


class GoogleMosqueProvider:
    name = "google"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._key = settings.google_maps_api_key
        self._client = make_client()
        self._cache = TTLCache(settings.route_cache_ttl_seconds)

    async def search_near(
        self, center: GeoPoint, radius_m: int, query: str | None = None
    ) -> MosqueSearchResult:
        if not self._key:
            return MosqueSearchResult(
                candidates=[],
                status="no_data",
                message="GOOGLE_MAPS_API_KEY not configured — Places unavailable.",
            )
        body = {
            "locationRestriction": {
                "circle": {
                    "center": {"latitude": center.lat, "longitude": center.lon},
                    "radius": min(radius_m, 50_000),
                }
            },
            "maxResultCount": 20,
            "languageCode": "en",
            "includedTypes": ["mosque"] if not query else None,
        }
        if query:
            body = {
                "textQuery": f"{query} mosque near {center.lat},{center.lon}",
                "maxResultCount": 20,
                "languageCode": "en",
            }
        body = {k: v for k, v in body.items() if v is not None}

        cache_key = ("google-places", body)

        async def fetch() -> dict:
            try:
                response = await self._client.post(
                    "https://places.googleapis.com/v1/places:searchNearby"
                    if "locationRestriction" in body
                    else "https://places.googleapis.com/v1/places:searchText",
                    json=body,
                    headers={
                        "Content-Type": "application/json",
                        "X-Goog-Api-Key": self._key,
                        "X-Goog-FieldMask": _FIELD_MASK,
                    },
                )
                response.raise_for_status()
                return response.json()
            except Exception as exc:
                raise ProviderError(f"Google Places failed: {exc}") from exc

        try:
            data = await self._cache.get_or_fetch(cache_key, fetch)
        except ProviderError as exc:
            return MosqueSearchResult(
                candidates=[],
                status="provider_error",
                message=str(exc),
            )

        fetched_at = datetime.now(timezone.utc)
        candidates: list[MosqueCandidate] = []
        for place in data.get("places", []):
            location = place.get("location") or {}
            if "latitude" not in location or "longitude" not in location:
                continue
            hours = (place.get("regularOpeningHours") or {}).get("weekdayDescriptions")
            display = place.get("displayName") or {}
            accessibility = place.get("accessibilityOptions") or {}
            candidates.append(
                MosqueCandidate(
                    id=f"google-{place.get('id')}",
                    name=display.get("text"),
                    location=GeoPoint(
                        lat=location["latitude"], lon=location["longitude"]
                    ),
                    quality=DataQuality(
                        provider=self.name,
                        source="live",
                        fetched_at=fetched_at,
                        notes=["Google Places data — opening hours reflect the "
                               "provider's recorded information."],
                    ),
                    opening_hours="\n".join(hours) if hours else None,
                    opening_hours_verification=(
                        Verification.VERIFIED if hours else Verification.UNKNOWN
                    ),
                    phone=place.get("nationalPhoneNumber"),
                    website=place.get("websiteUri"),
                    wheelchair_accessible=accessibility.get(
                        "wheelchairAccessibleEntrance"
                    ),
                )
            )

        return MosqueSearchResult(
            candidates=candidates,
            status="ok" if candidates else "no_data",
            message=(
                None if candidates
                else "Places provider returned no mosques for this area."
            ),
        )

    async def close(self) -> None:
        await self._client.aclose()

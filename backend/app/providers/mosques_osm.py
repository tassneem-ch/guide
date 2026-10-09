"""Mosque discovery via OpenStreetMap Overpass (keyless, live crowdsourced data).

Coverage varies by region — sparse results are reported as low-coverage, which
is different from a verified "no mosques here" answer.
"""
from __future__ import annotations

import math
from datetime import datetime, timezone

import httpx

from ..config import get_settings
from ..domain.geo import GeoPoint, bounds_of
from ..domain.mosque import DataQuality, MosqueCandidate, MosqueSearchResult, Verification
from .google_common import ProviderError, make_client

_QUERY = """
[out:json][timeout:25];
(
  node["amenity"="mosque"]({bbox});
  way["amenity"="mosque"]({bbox});
  relation["amenity"="mosque"]({bbox});
);
out center tags;
"""


class OsmMosqueProvider:
    name = "osm"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._base = settings.overpass_api_base.rstrip("/")
        self._client = make_client(timeout=30.0)

    async def search_near(
        self, center: GeoPoint, radius_m: int, query: str | None = None
    ) -> MosqueSearchResult:
        # Approximate radius -> degrees bounding box (good enough for a filter;
        # candidates are later verified against the actual route).
        dlat = radius_m / 111_320.0
        cos_lat = max(abs(math.cos(math.radians(center.lat))), 1e-6)
        dlon = radius_m / (111_320.0 * cos_lat)
        bbox = (center.lat - dlat, center.lon - dlon, center.lat + dlat, center.lon + dlon)
        overpass_bbox = f"{bbox[0]:.5f},{bbox[1]:.5f},{bbox[2]:.5f},{bbox[3]:.5f}"
        query = _QUERY.format(bbox=overpass_bbox)

        try:
            response = await self._client.post(
                self._base, data={"data": query},
                headers={"User-Agent": "guide-prayer-travel/1.0 (backend)"},
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            return MosqueSearchResult(
                candidates=[],
                queried_bbox=bbox,
                status="no_data",
                message=f"Overpass unavailable: {exc}. Mosque data could not be checked.",
            )

        fetched_at = datetime.now(timezone.utc)
        candidates: list[MosqueCandidate] = []
        for element in payload.get("elements", []):
            tags = element.get("tags") or {}
            if element.get("type") == "node":
                lat, lon = element.get("lat"), element.get("lon")
            else:
                center_el = element.get("center") or {}
                lat, lon = center_el.get("lat"), center_el.get("lon")
            if lat is None or lon is None:
                continue
            name = tags.get("name") or tags.get("name:ar") or tags.get("name:fr")
            wheelchair = tags.get("wheelchair")
            candidates.append(
                MosqueCandidate(
                    id=f"osm-{element.get('type')}{element.get('id')}",
                    name=name,
                    location=GeoPoint(lat=lat, lon=lon),
                    quality=DataQuality(
                        provider=self.name,
                        source="live",
                        fetched_at=fetched_at,
                        location_accuracy_m=None if element.get("type") == "node" else 30.0,
                        notes=["OpenStreetMap crowdsourced data — completeness varies by region."],
                    ),
                    opening_hours=tags.get("opening_hours"),
                    # Crowdsourced hours: present but not authoritative.
                    opening_hours_verification=(
                        Verification.UNVERIFIED if tags.get("opening_hours") else Verification.UNKNOWN
                    ),
                    phone=tags.get("phone") or tags.get("contact:phone"),
                    website=tags.get("website") or tags.get("contact:website"),
                    wheelchair_accessible=(
                        wheelchair == "yes" if wheelchair in ("yes", "no") else None
                    ),
                    female_facilities=(
                        tags.get("female") == "yes" if "female" in tags else None
                    ),
                )
            )

        return MosqueSearchResult(
            candidates=candidates,
            queried_bbox=bbox,
            status="ok" if candidates else "no_data",
            message=(
                None if candidates
                else "Overpass returned no mosques in this area — coverage may be "
                     "incomplete; this does not confirm there are no mosques."
            ),
        )

    async def close(self) -> None:
        await self._client.aclose()

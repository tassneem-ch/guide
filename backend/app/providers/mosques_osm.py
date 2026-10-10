"""Mosque discovery via OpenStreetMap Overpass (keyless, live crowdsourced data).

Coverage varies by region — sparse results are reported as low-coverage, which
is different from a verified "no mosques here" answer.
"""
from __future__ import annotations

import math
import time
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


def _interpreter_url(base: str) -> str:
    """The configured URL is the service base; the query endpoint is
    `<base>/interpreter` — without that path Overpass answers 404."""
    base = base.rstrip("/")
    return base if base.endswith("/interpreter") else f"{base}/interpreter"


# Interactive planning budget: Overpass normally answers in a few seconds;
# a slow instance should not hold a plan hostage (route planning queries
# several anchors in sequence).
_REQUEST_TIMEOUT_S = 8.0

# After every instance failed once, later anchors of the SAME plan get the
# failure immediately instead of re-trying the whole walk.
_COOLDOWN_S = 60.0


class OsmMosqueProvider:
    name = "osm"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._bases = [
            _interpreter_url(settings.overpass_api_base),
            *(_interpreter_url(u) for u in settings.overpass_fallbacks),
        ]
        self._client = make_client(timeout=_REQUEST_TIMEOUT_S)
        # Instance that answered with data last — tried first next time.
        self._preferred: str | None = None
        self._cooldown_until = 0.0

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

        if time.monotonic() < self._cooldown_until:
            # Every instance just failed — a sibling anchor of this same
            # plan would only burn the same time for the same answer.
            return MosqueSearchResult(
                candidates=[],
                queried_bbox=bbox,
                status="no_data",
                message=(
                    "Overpass was unavailable moments ago; mosque data was "
                    "not re-checked. This does not confirm there are no "
                    "mosques nearby."
                ),
            )

        payload = await self._fetch(query)
        if payload is None:
            self._cooldown_until = time.monotonic() + _COOLDOWN_S
            return MosqueSearchResult(
                candidates=[],
                queried_bbox=bbox,
                status="no_data",
                message=(
                    "Overpass unavailable on all instances. Mosque data "
                    "could not be checked."
                ),
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

    async def _fetch(self, query: str) -> dict | None:
        """Run the query against Overpass, falling back across instances.

        Public instances fail often (504s, resets) and, when overloaded,
        may answer 200 with no elements even over well-mapped areas — so
        an empty answer is cross-checked against the next instance before
        it is believed. Returns the first response with elements, else
        the first well-formed empty one, else None (all failed).
        """
        order = [b for b in self._bases if b != self._preferred]
        if self._preferred is not None:
            order.insert(0, self._preferred)
        empty: dict | None = None
        for base in order:
            try:
                response = await self._client.post(
                    base,
                    data={"data": query},
                    headers={"User-Agent": "guide-prayer-travel/1.0 (backend)"},
                )
                response.raise_for_status()
                payload = response.json()
            except (httpx.HTTPError, ValueError):
                continue
            if payload.get("elements"):
                # Remembered so the rest of this plan (and the next one)
                # skips the failing instances.
                self._preferred = base
                return payload
            empty = empty or payload
        return empty

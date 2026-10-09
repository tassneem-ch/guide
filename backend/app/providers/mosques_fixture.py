"""Development mosque fixture — deterministic synthetic candidates.

Names are explicitly "… (fixture)" and every candidate carries source="fixture"
so no fixture can ever be mistaken for a real mosque.
"""
from __future__ import annotations

import math
from datetime import datetime, timezone

from ..domain.geo import GeoPoint, haversine_m
from ..domain.mosque import DataQuality, MosqueCandidate, MosqueSearchResult, Verification

WARNING = (
    "DEVELOPMENT FIXTURE: synthetic mosque data for testing only. "
    "Set MOSQUE_PROVIDER=osm (keyless) or google (key required) for real places."
)


class FixtureMosqueProvider:
    name = "fixture"
    live = False

    def __init__(self, count: int = 5) -> None:
        self._count = count

    async def search_near(
        self, center: GeoPoint, radius_m: int, query: str | None = None
    ) -> MosqueSearchResult:
        # Deterministic ring around the centre; offsets derived from coordinates
        # so the same place always yields the same fixtures.
        seed = int(abs(center.lat * 1000 + center.lon * 1000)) % 360
        fetched_at = datetime.now(timezone.utc)
        candidates: list[MosqueCandidate] = []
        for i in range(self._count):
            angle = math.radians((seed + i * (360 // self._count)) % 360)
            distance = radius_m * (0.25 + 0.13 * i)
            dlat = (distance * math.sin(angle)) / 111_320.0
            dlon = (distance * math.cos(angle)) / (
                111_320.0 * max(abs(math.cos(math.radians(center.lat))), 1e-6)
            )
            candidates.append(
                MosqueCandidate(
                    id=f"fixture-{center.lat:.3f}-{center.lon:.3f}-{i}",
                    name=f"Dev Mosque {i + 1} (fixture)",
                    location=GeoPoint(
                        lat=center.lat + dlat, lon=center.lon + dlon, tz=center.tz
                    ),
                    quality=DataQuality(
                        provider=self.name,
                        source="fixture",
                        fetched_at=fetched_at,
                        notes=[WARNING],
                    ),
                    # Fixture hours are fabricated too — clearly marked.
                    opening_hours="Mo-Su 05:00-22:00 (fixture)",
                    opening_hours_verification=Verification.UNVERIFIED,
                )
            )
        return MosqueSearchResult(
            candidates=candidates,
            status="fixture",
            message=WARNING,
        )

    async def close(self) -> None:  # pragma: no cover
        return None

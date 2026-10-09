"""Mosque / place-candidate domain types.

Honesty rules encoded here:
* every field carries a verification status;
* absence of data (`no_data`) is distinct from verified absence (`none_found`);
* nothing (names, hours, facilities, iqama) is ever invented — unknown stays None.
"""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum

from pydantic import BaseModel, Field

from .geo import GeoPoint


class Verification(str, Enum):
    VERIFIED = "verified"        # confirmed by the provider response
    UNVERIFIED = "unverified"    # present but provider-supplied / possibly stale
    UNKNOWN = "unknown"          # field not provided by the provider
    ABSENT = "absent"            # provider explicitly reports nothing


class DataQuality(BaseModel):
    provider: str
    source: str                  # "live" | "fixture"
    fetched_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    staleness_seconds: int = 0
    location_accuracy_m: float | None = None
    notes: list[str] = Field(default_factory=list)


class MosqueCandidate(BaseModel):
    id: str
    name: str | None = None
    location: GeoPoint
    quality: DataQuality

    opening_hours: str | None = None
    opening_hours_verification: Verification = Verification.UNKNOWN
    phone: str | None = None
    website: str | None = None
    wheelchair_accessible: bool | None = None
    female_facilities: bool | None = None

    # Filled by the scheduling engine (routed, not straight-line):
    assigned_route_index: int | None = None      # index of the route vertex this stop hangs off
    detour_seconds: int | None = None            # extra road time caused by this stop
    detour_distance_m: int | None = None
    detour_method: str | None = None             # "routed" | "great_circle_estimate"

    # Only populated when a congregation schedule was explicitly provided:
    congregation_utc: datetime | None = None
    congregation_verified: bool = False

    alternatives: list[str] = Field(default_factory=list)  # nearby candidate ids

    @property
    def label(self) -> str:
        return self.name or f"Unnamed mosque ({self.location.lat:.4f}, {self.location.lon:.4f})"


class MosqueSearchResult(BaseModel):
    candidates: list[MosqueCandidate]
    queried_bbox: tuple[float, float, float, float] | None = None
    # Distinguishes "we could not reach the provider" from "provider says none exist".
    status: str = "ok"           # ok | no_data | provider_error | fixture
    message: str | None = None

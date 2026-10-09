"""Prayer-time endpoints."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from ..core.ratelimit import default_limit, limiter
from ..domain.prayer import DayPrayers, PrayerCapabilities
from ..providers.google_common import ProviderError
from ..providers.registry import get_providers
from .schemas import PrayerTimesRequest

router = APIRouter(prefix="/v1/prayer-times", tags=["prayer"])


@router.get("/capabilities", response_model=PrayerCapabilities)
async def capabilities() -> PrayerCapabilities:
    """What the active prayer provider actually supports — the app only
    offers these options in Settings."""
    return get_providers().prayer.capabilities()


@router.post("", response_model=DayPrayers)
@limiter.limit(default_limit())
async def prayer_times(req: PrayerTimesRequest, request: Request) -> DayPrayers:
    provider = get_providers().prayer
    try:
        return await provider.day_prayers(req.point, req.date, req.config)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

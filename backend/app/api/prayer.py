"""Prayer-time endpoints."""
from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from fastapi import APIRouter, HTTPException, Request

from ..core.ratelimit import default_limit, limiter
from ..core.timeutil import resolve_tz
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


def _local_date(point, value: date | datetime) -> date:
    """Calendar date *at the location*, never at the caller's device.

    A plain date is taken as already local; a datetime is treated as an
    instant (naive values assumed UTC) and converted through the point's
    IANA zone, so day boundaries follow the destination, not the phone.
    """
    if isinstance(value, datetime):
        instant = value
        if instant.tzinfo is None:
            instant = instant.replace(tzinfo=timezone.utc)
        tz_name = resolve_tz(point)
        return instant.astimezone(ZoneInfo(tz_name)).date()
    return value


@router.post("", response_model=DayPrayers)
@limiter.limit(default_limit())
async def prayer_times(req: PrayerTimesRequest, request: Request) -> DayPrayers:
    provider = get_providers().prayer
    local_date = _local_date(req.point, req.date)
    try:
        return await provider.day_prayers(req.point, local_date, req.config)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

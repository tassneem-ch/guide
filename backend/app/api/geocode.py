"""Geocoding endpoints (international address search + reverse)."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from ..core.ratelimit import default_limit, limiter
from ..domain.geo import GeoPoint
from ..providers.registry import get_providers
from .schemas import GeocodeRequest, ReverseGeocodeRequest

router = APIRouter(prefix="/v1/geocode", tags=["geocode"])


class GeocodeResult(BaseModel):
    results: list[GeoPoint]
    provider: str
    live: bool


@router.post("", response_model=GeocodeResult)
@limiter.limit(default_limit())
async def geocode(req: GeocodeRequest, request: Request) -> GeocodeResult:
    provider = get_providers().geocoding
    results = await provider.geocode(req.query, req.language, req.limit)
    return GeocodeResult(results=results, provider=provider.name, live=provider.live)


@router.post("/reverse", response_model=GeocodeResult)
async def reverse(req: ReverseGeocodeRequest) -> GeocodeResult:
    provider = get_providers().geocoding
    label = await provider.reverse(req.point, req.language)
    point = req.point.model_copy(update={"name": label})
    return GeocodeResult(
        results=[point] if label else [],
        provider=provider.name,
        live=provider.live,
    )

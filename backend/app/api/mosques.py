"""Mosque discovery endpoints (point + optional route corridor)."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from ..core.ratelimit import default_limit, limiter
from ..domain.geo import GeoPoint, haversine_m
from ..domain.mosque import MosqueSearchResult
from ..providers.registry import get_providers
from .schemas import MosqueSearchRequest

router = APIRouter(prefix="/v1/mosques", tags=["mosques"])


@router.post("/search", response_model=MosqueSearchResult)
@limiter.limit(default_limit())
async def search_mosques(req: MosqueSearchRequest, request: Request) -> MosqueSearchResult:
    provider = get_providers().mosques
    result = await provider.search_near(req.center, req.radius_m, req.query)

    if not req.corridor_points:
        return result

    # Corridor search: additional anchors along the given polyline, merged.
    merged = {c.id: c for c in result.candidates}
    statuses = {result.status}
    messages = [result.message] if result.message else []
    step = max(1, len(req.corridor_points) // 8)
    for point in req.corridor_points[::step]:
        extra = await provider.search_near(point, req.radius_m)
        statuses.add(extra.status)
        if extra.message:
            messages.append(extra.message)
        for candidate in extra.candidates:
            merged.setdefault(candidate.id, candidate)

    status = "ok" if merged else ("no_data" if "ok" not in statuses else "no_data")
    if not merged:
        status = "provider_error" if "provider_error" in statuses else "no_data"
    return MosqueSearchResult(
        candidates=list(merged.values()),
        status=status,
        message=None if merged else (" ".join(messages) or None),
    )

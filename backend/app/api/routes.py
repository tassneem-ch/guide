"""Route alternatives + re-optimization endpoints."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from ..core.ratelimit import default_limit, limiter
from ..domain.route import RouteRequest, RouteResponse
from ..providers.google_common import ProviderError
from ..providers.registry import get_providers
from ..services.route_planner import RoutePlanner

router = APIRouter(prefix="/v1/routes", tags=["routes"])


def _planner() -> RoutePlanner:
    bundle = get_providers()
    return RoutePlanner(bundle.routing, bundle.prayer, bundle.mosques)


@router.post("/alternatives", response_model=RouteResponse)
@limiter.limit(default_limit())
async def route_alternatives(req: RouteRequest, request: Request) -> RouteResponse:
    """Fastest / prayer-friendly / balanced plans for a journey."""
    try:
        return await _planner().plan(req)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.post("/optimize", response_model=RouteResponse)
@limiter.limit(default_limit())
async def reoptimize(req: RouteRequest, request: Request) -> RouteResponse:
    """Re-run planning after a departure-time, stop or preference change.

    Semantically identical to /alternatives; kept separate so clients can
    express rescheduling intent and so it can be rate-limited independently.
    """
    try:
        return await _planner().plan(req)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

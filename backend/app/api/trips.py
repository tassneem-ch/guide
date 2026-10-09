"""Trip planning (multi-day) + saved itineraries."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session

from ..core.ratelimit import default_limit, limiter
from ..db.models import Itinerary
from ..db.session import get_db
from ..domain.route import TripPlan, TripRequest
from ..providers.google_common import ProviderError
from ..providers.registry import get_providers
from ..security import require_user
from ..services.route_planner import RoutePlanner
from ..services.trip_planner import TripPlanner
from .schemas import ItinerarySummary, SaveItineraryRequest

router = APIRouter(prefix="/v1/trips", tags=["trips"])


@router.post("/plan", response_model=TripPlan)
@limiter.limit(default_limit())
async def plan_trip(req: TripRequest, request: Request) -> TripPlan:
    bundle = get_providers()
    planner = TripPlanner(RoutePlanner(bundle.routing, bundle.prayer, bundle.mosques))
    try:
        return await planner.plan(req)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.post("/save", response_model=ItinerarySummary)
async def save_trip(
    req: SaveItineraryRequest,
    user_id: str = Depends(require_user),
    db: Session = Depends(get_db),
) -> ItinerarySummary:
    owner = None if user_id == "anonymous" else user_id
    row = Itinerary(
        user_id=owner, title=req.title, kind=req.kind, data=req.data
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return ItinerarySummary(
        id=row.id, title=row.title, kind=row.kind,
        created_at=row.created_at, updated_at=row.updated_at,
    )


@router.get("/saved", response_model=list[ItinerarySummary])
async def list_saved(
    user_id: str = Depends(require_user),
    db: Session = Depends(get_db),
) -> list[ItinerarySummary]:
    query = db.query(Itinerary)
    if user_id != "anonymous":
        query = query.filter(
            (Itinerary.user_id == user_id) | (Itinerary.user_id.is_(None))
        )
    rows = query.order_by(Itinerary.updated_at.desc()).limit(100).all()
    return [
        ItinerarySummary(
            id=r.id, title=r.title, kind=r.kind,
            created_at=r.created_at, updated_at=r.updated_at,
        )
        for r in rows
    ]


@router.get("/{trip_id}")
async def get_saved(
    trip_id: str,
    user_id: str = Depends(require_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Itinerary, trip_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    if user_id != "anonymous" and row.user_id not in (None, user_id):
        raise HTTPException(status_code=403, detail="Not yours")
    return {
        "id": row.id,
        "title": row.title,
        "kind": row.kind,
        "data": row.data,
        "created_at": row.created_at,
        "updated_at": row.updated_at,
    }


@router.delete("/{trip_id}")
async def delete_saved(
    trip_id: str,
    user_id: str = Depends(require_user),
    db: Session = Depends(get_db),
) -> dict:
    row = db.get(Itinerary, trip_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Itinerary not found")
    if user_id != "anonymous" and row.user_id not in (None, user_id):
        raise HTTPException(status_code=403, detail="Not yours")
    db.delete(row)
    db.commit()
    return {"deleted": trip_id}

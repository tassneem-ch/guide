"""Auth + user preferences + health."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from ..config import get_settings
from ..db.models import Preferences, User
from ..db.session import get_db
from ..providers.registry import get_providers
from ..security import (
    create_token,
    hash_password,
    require_user,
    verify_password,
)
from .schemas import (
    LoginRequest,
    PreferencesRequest,
    RegisterRequest,
    TokenResponse,
)

auth_router = APIRouter(prefix="/v1/auth", tags=["auth"])
me_router = APIRouter(prefix="/v1/me", tags=["me"])
health_router = APIRouter(tags=["health"])


@auth_router.post("/register", response_model=TokenResponse)
async def register(req: RegisterRequest, db: Session = Depends(get_db)) -> TokenResponse:
    existing = db.query(User).filter(User.email == req.email.lower()).first()
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(
        email=req.email.lower(),
        password_hash=hash_password(req.password),
        display_name=req.display_name,
    )
    db.add(user)
    db.flush()  # assign the generated user id before linking preferences
    db.add(Preferences(user_id=user.id, data={}))
    db.commit()
    db.refresh(user)
    return TokenResponse(access_token=create_token(user.id), user_id=user.id)


@auth_router.post("/login", response_model=TokenResponse)
async def login(req: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    user = db.query(User).filter(User.email == req.email.lower()).first()
    if user is None or not verify_password(req.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return TokenResponse(access_token=create_token(user.id), user_id=user.id)


@me_router.get("/preferences")
async def get_preferences(
    user_id: str = Depends(require_user), db: Session = Depends(get_db)
) -> dict:
    if user_id == "anonymous":
        return {"data": {}, "anonymous": True}
    row = db.get(Preferences, user_id)
    return {"data": (row.data if row else {}), "anonymous": False}


@me_router.put("/preferences")
async def put_preferences(
    req: PreferencesRequest,
    user_id: str = Depends(require_user),
    db: Session = Depends(get_db),
) -> dict:
    if user_id == "anonymous":
        # Anonymous mode: preferences are stored client-side; acknowledge.
        return {"data": req.data, "stored": False, "anonymous": True}
    row = db.get(Preferences, user_id)
    if row is None:
        row = Preferences(user_id=user_id, data=req.data)
        db.add(row)
    else:
        row.data = req.data
    db.commit()
    return {"data": req.data, "stored": True, "anonymous": False}


# `/health` is a conventional alias for container/orchestrator probes;
# the canonical, documented path remains `/v1/health`.
@health_router.get("/health", include_in_schema=False)
@health_router.get("/v1/health")
async def health() -> dict:
    settings = get_settings()
    return {
        "status": "ok",
        "env": settings.app_env,
        "auth_required": settings.auth_required,
        "providers": get_providers().report(),
    }

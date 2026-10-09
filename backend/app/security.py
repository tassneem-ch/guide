"""Auth: bcrypt password hashing, JWT issuing/verification, FastAPI deps.

Auth is optional — with AUTH_REQUIRED=false, endpoints accept anonymous users
and saved trips are stored without an owner (device-local semantics).
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import Depends, HTTPException, Request
from sqlalchemy.orm import Session

from .config import get_settings
from .db.session import get_db

ALGORITHM = "HS256"


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode(), hashed.encode())
    except ValueError:
        return False


def create_token(user_id: str) -> str:
    settings = get_settings()
    payload = {
        "sub": user_id,
        "iat": datetime.now(timezone.utc),
        "exp": datetime.now(timezone.utc)
        + timedelta(minutes=settings.jwt_expires_min),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def decode_token(token: str) -> str | None:
    settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        return None
    sub = payload.get("sub")
    return str(sub) if sub else None


def _extract_token(request: Request) -> str | None:
    auth = request.headers.get("Authorization", "")
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return None


def current_user_optional(
    request: Request, db: Session = Depends(get_db)
) -> str | None:
    """Return the user id when a valid token is presented, else None."""
    token = _extract_token(request)
    if not token:
        return None
    user_id = decode_token(token)
    if user_id is None:
        return None
    from .db.models import User

    return user_id if db.get(User, user_id) else None


def require_user(user_id: str | None = Depends(current_user_optional)) -> str:
    settings = get_settings()
    if settings.auth_required and user_id is None:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user_id or "anonymous"

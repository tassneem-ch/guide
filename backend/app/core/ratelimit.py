"""Shared API rate limiter (slowapi)."""
from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address

from ..config import get_settings

limiter = Limiter(key_func=get_remote_address)


def default_limit() -> str:
    return f"{get_settings().rate_limit_per_minute} per minute"

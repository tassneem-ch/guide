"""Shared helpers for live providers: errors, time parsing, HTTP policy."""
from __future__ import annotations

from datetime import datetime

import httpx


class ProviderError(RuntimeError):
    """A live provider failed or returned garbage.

    Callers surface this to the API layer — the engine never fabricates data
    to hide a provider failure.
    """


def parse_duration_seconds(value: str | int | float | None) -> int | None:
    """Parse '3600s' (Routes API), '3600' or numeric seconds."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value).strip()
    if text.endswith("s"):
        text = text[:-1]
    try:
        return int(float(text))
    except ValueError:
        return None


def parse_rfc3339(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def google_headers(api_key: str, field_mask: str) -> dict[str, str]:
    if not api_key:
        raise ProviderError(
            "GOOGLE_MAPS_API_KEY is not configured for this provider"
        )
    return {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": field_mask,
    }


def make_client(timeout: float = 20.0) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        timeout=httpx.Timeout(timeout, connect=5.0),
        limits=httpx.Limits(max_connections=20, max_keepalive_connections=10),
    )

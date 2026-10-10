"""Place suggestions (autocomplete) + place details.

Two backends behind one contract:
- Google Places API (New) when GOOGLE_MAPS_API_KEY is set (key stays
  server-side; session tokens pass through for correct session billing);
- the configured geocoding provider otherwise (keyless Nominatim in live
  mode), which resolves coordinates immediately, so no details call exists.

The response never fabricates a location: results either carry real
coordinates (Nominatim path) or a real place id for later resolution
(Google path).
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel

from ..config import get_settings
from ..core.ratelimit import default_limit, limiter
from ..domain.geo import GeoPoint
from ..providers.base import GeocodingProvider
from ..providers.google_common import ProviderError
from ..providers.places_google import GooglePlacesProvider
from ..providers.registry import get_providers

router = APIRouter(prefix="/v1/places", tags=["places"])


class PlaceSuggestion(BaseModel):
    # Google path: id set, lat/lon absent (details required on selection).
    # Keyless path: id None, lat/lon/tz set from the geocoding provider.
    id: str | None = None
    label: str
    lat: float | None = None
    lon: float | None = None
    tz: str | None = None


class PlaceSuggestionsResult(BaseModel):
    results: list[PlaceSuggestion]
    provider: str
    live: bool
    # True when the client must call /v1/places/details after selection.
    requires_details: bool


class PlaceDetailsResult(BaseModel):
    result: GeoPoint
    provider: str
    live: bool


def _google_places() -> GooglePlacesProvider | None:
    """The Google Places provider when a key is configured, else None."""
    settings = get_settings()
    if not settings.google_maps_api_key or settings.places_provider == "nominatim":
        return None
    # Built lazily per call when no bundle slot exists; reuse the registry
    # instance when the registry provides one (avoids connection churn).
    bundle = get_providers()
    existing = getattr(bundle, "places", None)
    return existing if existing is not None else GooglePlacesProvider()


@router.get("/autocomplete")
@limiter.limit(default_limit())
async def autocomplete(
    request: Request,
    q: str = Query(min_length=1, max_length=200),
    language: str = "en",
    session: str | None = None,
    bias_lat: float | None = None,
    bias_lon: float | None = None,
    limit: int = Query(default=5, ge=1, le=10),
) -> PlaceSuggestionsResult:
    google = _google_places()
    bias = (
        GeoPoint(lat=bias_lat, lon=bias_lon)
        if bias_lat is not None and bias_lon is not None
        else None
    )
    if google is not None:
        try:
            rows = await google.autocomplete(
                q, language=language, session=session, bias=bias, limit=limit
            )
        except ProviderError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        return PlaceSuggestionsResult(
            results=[PlaceSuggestion(id=r["id"], label=r["label"]) for r in rows],
            provider=google.name,
            live=google.live,
            requires_details=True,
        )

    # Keyless path: the geocoding provider answers with resolved points.
    provider: GeocodingProvider = get_providers().geocoding
    points = await provider.geocode(q, language, limit)
    return PlaceSuggestionsResult(
        results=[
            PlaceSuggestion(
                id=None,
                label=p.name or f"{p.lat:.5f}, {p.lon:.5f}",
                lat=p.lat,
                lon=p.lon,
                tz=p.tz,
            )
            for p in points
        ],
        provider=provider.name,
        live=provider.live,
        requires_details=False,
    )


@router.get("/details")
@limiter.limit(default_limit())
async def details(
    request: Request,
    id: str = Query(min_length=1, max_length=128),
    language: str = "en",
    session: str | None = None,
) -> PlaceDetailsResult:
    google = _google_places()
    if google is None:
        raise HTTPException(
            status_code=409,
            detail=(
                "Place details require the Google Places provider "
                "(set GOOGLE_MAPS_API_KEY); the keyless provider returns "
                "coordinates with each suggestion."
            ),
        )
    try:
        point = await google.details(id, language=language, session=session)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    if point is None:
        raise HTTPException(
            status_code=404, detail="Place has no resolvable location"
        )
    return PlaceDetailsResult(result=point, provider=google.name, live=google.live)

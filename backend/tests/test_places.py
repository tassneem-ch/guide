"""Places autocomplete + prayer datetime contract tests.

Google-backed paths are exercised with stubbed HTTP responses (no network);
the API-level tests run against the keyless fixture stack like the rest of
tests/test_api.py.
"""
from __future__ import annotations

import httpx
import pytest

from app.domain.prayer import PrayerMethod
from app.providers.places_google import GooglePlacesProvider
from app.providers.prayer_aladhan import ALADHAN_METHOD_IDS, METHOD_LABELS


class _StubResponse:
    def __init__(self, payload, status_code=200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise httpx.HTTPError("stub http error")

    def json(self):
        return self._payload


class _StubClient:
    """Captures requests; returns queued responses."""

    def __init__(self, responses):
        self._responses = list(responses)
        self.requests = []

    async def post(self, url, json=None, headers=None, params=None):
        self.requests.append(("POST", url, json, headers, params))
        return self._responses.pop(0)

    async def get(self, url, headers=None, params=None):
        self.requests.append(("GET", url, None, headers, params))
        return self._responses.pop(0)

    async def aclose(self):
        pass


def _google_provider(client) -> GooglePlacesProvider:
    provider = GooglePlacesProvider.__new__(GooglePlacesProvider)
    provider._key = "test-key"
    provider._client = client
    return provider


_AUTOCOMPLETE_PAYLOAD = {
    "suggestions": [
        {
            "placePrediction": {
                "placeId": "ChIJabc123",
                "text": {"text": "Paris, France"},
                "structuredFormat": {
                    "mainText": {"text": "Paris"},
                    "secondaryText": {"text": "France"},
                },
            }
        },
        {"queryPrediction": {"text": {"text": "paris bag"}}},  # ignored
        {
            "placePrediction": {
                "placeId": "ChIJdef456",
                "text": {"text": "Paris 18e, France"},
            }
        },
    ]
}


async def test_google_autocomplete_passes_session_token_and_bias():
    from app.domain.geo import GeoPoint

    client = _StubClient([_StubResponse(_AUTOCOMPLETE_PAYLOAD)])
    provider = _google_provider(client)
    rows = await provider.autocomplete(
        "par",
        language="fr",
        session="sess-123",
        bias=GeoPoint(lat=48.85, lon=2.35),
    )
    assert [r["id"] for r in rows] == ["ChIJabc123", "ChIJdef456"]
    assert rows[0]["label"] == "Paris, France"

    method, url, body, headers, _ = client.requests[0]
    assert method == "POST"
    assert url.endswith("/v1/places:autocomplete")
    assert body["input"] == "par"
    assert body["languageCode"] == "fr"
    assert body["sessionToken"] == "sess-123"
    assert body["locationBias"]["circle"]["center"]["latitude"] == 48.85
    assert headers["X-Goog-Api-Key"] == "test-key"
    assert "suggestions.placePrediction.placeId" in headers["X-Goog-FieldMask"]


async def test_google_autocomplete_http_error_raises_provider_error():
    from app.providers.google_common import ProviderError

    client = _StubClient([_StubResponse({}, status_code=403)])
    provider = _google_provider(client)
    with pytest.raises(ProviderError):
        await provider.autocomplete("par")


async def test_google_details_resolves_coordinates():
    client = _StubClient([
        _StubResponse({
            "id": "places/ChIJabc123",
            "formattedAddress": "Paris, France",
            "location": {"latitude": 48.8566, "longitude": 2.3522},
        })
    ])
    provider = _google_provider(client)
    point = await provider.details("ChIJabc123", session="sess-123")
    assert point is not None
    assert point.lat == pytest.approx(48.8566)
    assert point.lon == pytest.approx(2.3522)
    assert point.name == "Paris, France"
    _, url, _, headers, params = client.requests[0]
    assert url.endswith("/places/ChIJabc123")
    assert params["sessionToken"] == "sess-123"
    assert "places.location" in headers["X-Goog-FieldMask"]


def test_autocomplete_endpoint_keyless_path(client):
    response = client.get("/v1/places/autocomplete", params={"q": "Paris"})
    assert response.status_code == 200
    body = response.json()
    assert body["results"], "keyless provider must return suggestions"
    assert body["requires_details"] is False
    first = body["results"][0]
    assert first["lat"] is not None and first["lon"] is not None
    assert "fixture" in first["label"].lower()
    assert body["live"] is False


def test_autocomplete_endpoint_rejects_empty_query(client):
    assert client.get("/v1/places/autocomplete", params={"q": ""}).status_code == 422


def test_details_endpoint_keyless_is_an_explicit_error(client):
    response = client.get("/v1/places/details", params={"id": "anything"})
    assert response.status_code == 409  # not silently faked


def test_prayer_times_accepts_utc_instant_and_converts_to_local_date(client):
    response = client.post(
        "/v1/prayer-times",
        json={
            "point": {"lat": 48.8566, "lon": 2.3522, "tz": "Europe/Paris"},
            # 23:30 UTC is already the next calendar day in Paris.
            "date": "2025-06-15T23:30:00Z",
            "config": {"method": "mwl", "school": "standard"},
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert body["local_date"] == "2025-06-16"


def test_prayer_times_still_accepts_plain_date(client):
    response = client.post(
        "/v1/prayer-times",
        json={
            "point": {"lat": 48.8566, "lon": 2.3522, "tz": "Europe/Paris"},
            "date": "2025-06-15",
        },
    )
    assert response.status_code == 200
    assert response.json()["local_date"] == "2025-06-15"


def test_aladhan_method_table_is_consistent():
    ids = list(ALADHAN_METHOD_IDS.values())
    assert len(ids) == len(set(ids)), "AlAdhan numeric ids must be unique"
    for method, numeric_id in ALADHAN_METHOD_IDS.items():
        assert isinstance(numeric_id, int)
        assert method in METHOD_LABELS
    # The worldwide set advertised to users must not be one region only.
    for method in (PrayerMethod.TUNISIA, PrayerMethod.FRANCE,
                   PrayerMethod.DUBAI, PrayerMethod.EGYPTIAN,
                   PrayerMethod.ISNA, PrayerMethod.MWL):
        assert method in ALADHAN_METHOD_IDS

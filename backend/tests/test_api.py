"""API contract tests with fixture providers (no network)."""
from __future__ import annotations


def test_health_reports_provider_modes(client):
    response = client.get("/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    providers = body["providers"]
    for slot in ("prayer", "routing", "mosques", "geocoding"):
        assert "FIXTURE" in providers[slot], f"{slot} must be visibly in fixture mode"


def test_prayer_times_endpoint(client):
    response = client.post(
        "/v1/prayer-times",
        json={
            "point": {"lat": 48.8566, "lon": 2.3522, "tz": "Europe/Paris"},
            "date": "2025-06-15",
            "config": {"method": "mwl", "school": "standard"},
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["events"]) == 5
    assert body["live"] is False            # fixture honesty
    assert body["source"] == "fixture"
    names = {e["name"] for e in body["events"]}
    assert names == {"fajr", "dhuhr", "asr", "maghrib", "isha"}
    for event in body["events"]:
        assert event["congregation_utc"] is None
        assert event["congregation_verified"] is False


def test_prayer_capabilities_reflect_provider(client):
    response = client.get("/v1/prayer-times/capabilities")
    assert response.status_code == 200
    body = response.json()
    assert body["methods"], "supported methods must be advertised"
    assert body["live"] is False
    assert any("FIXTURE" in note for note in body["notes"])


def test_route_alternatives_endpoint(client):
    response = client.post(
        "/v1/routes/alternatives",
        json={
            "origin": {"lat": 48.8566, "lon": 2.3522, "tz": "Europe/Paris"},
            "destination": {"lat": 45.7640, "lon": 4.8357, "tz": "Europe/Paris"},
            "depart_at": "2025-06-15T11:50:00+02:00",
            "mode": "driving",
            "options": {"preference": "balanced"},
            "prayer": {"method": "mwl", "school": "standard"},
        },
    )
    assert response.status_code == 200
    body = response.json()
    kinds = {a["preference"] for a in body["alternatives"]}
    assert {"fastest", "prayer_friendly", "balanced"} <= kinds
    assert body["notes"], "fixture/uncertainty notes must be surfaced"
    for alt in body["alternatives"]:
        assert alt["explanation"]
        assert alt["legs"]
        assert alt["stops"][0]["kind"] == "origin"


def test_route_rejects_invalid_payload(client):
    response = client.post("/v1/routes/alternatives", json={"origin": {}})
    assert response.status_code == 422


def test_mosque_search_endpoint(client):
    response = client.post(
        "/v1/mosques/search",
        json={"center": {"lat": 48.8566, "lon": 2.3522}, "radius_m": 2000},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["candidates"]
    assert all("fixture" in c["name"].lower() for c in body["candidates"])
    assert all(c["quality"]["source"] == "fixture" for c in body["candidates"])


def test_geocode_endpoint(client):
    response = client.post(
        "/v1/geocode", json={"query": "Paris, France", "language": "en"}
    )
    assert response.status_code == 200
    body = response.json()
    assert body["results"]
    assert "fixture" in body["results"][0]["name"].lower()
    assert body["live"] is False


def test_trip_plan_endpoint(client):
    response = client.post(
        "/v1/trips/plan",
        json={
            "title": "Tunis to Paris",
            "origin": {"lat": 36.8065, "lon": 10.1815, "tz": "Africa/Tunis",
                       "name": "Tunis"},
            "destination": {"lat": 48.8566, "lon": 2.3522, "tz": "Europe/Paris",
                            "name": "Paris"},
            "depart_utc": "2025-06-15T08:00:00Z",
            "days": 2,
            "options": {"preference": "balanced"},
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["days"]) == 2
    for day in body["days"]:
        assert day["local_date"]
        assert day["tz"]
        assert day["prayer_events"], "each day must show local prayers"
    assert body["providers"]["prayer"]


def test_auth_and_saved_itineraries(client):
    # register
    r = client.post(
        "/v1/auth/register",
        json={"email": "traveler@example.com", "password": "s3cret-pass"},
    )
    assert r.status_code == 200
    token = r.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    # duplicate rejected
    r2 = client.post(
        "/v1/auth/register",
        json={"email": "traveler@example.com", "password": "s3cret-pass"},
    )
    assert r2.status_code == 409

    # bad login
    r3 = client.post(
        "/v1/auth/login",
        json={"email": "traveler@example.com", "password": "wrong-password"},
    )
    assert r3.status_code == 401

    # preferences round-trip
    put = client.put(
        "/v1/me/preferences",
        json={"data": {"max_detour_min": 20, "language": "ar"}},
        headers=headers,
    )
    assert put.status_code == 200
    assert put.json()["stored"] is True
    got = client.get("/v1/me/preferences", headers=headers)
    assert got.json()["data"]["language"] == "ar"

    # save + list + fetch + delete itinerary
    saved = client.post(
        "/v1/trips/save",
        json={"title": "Weekend in Paris", "kind": "trip",
              "data": {"days": []}},
        headers=headers,
    )
    assert saved.status_code == 200
    trip_id = saved.json()["id"]

    listing = client.get("/v1/trips/saved", headers=headers)
    assert listing.status_code == 200
    assert any(t["id"] == trip_id for t in listing.json())

    fetched = client.get(f"/v1/trips/{trip_id}", headers=headers)
    assert fetched.status_code == 200
    assert fetched.json()["data"] == {"days": []}

    deleted = client.delete(f"/v1/trips/{trip_id}", headers=headers)
    assert deleted.status_code == 200
    gone = client.get(f"/v1/trips/{trip_id}", headers=headers)
    assert gone.status_code == 404


def test_anonymous_access_allowed_when_auth_disabled(client):
    listing = client.get("/v1/trips/saved")
    assert listing.status_code == 200
    prefs = client.get("/v1/me/preferences")
    assert prefs.status_code == 200
    assert prefs.json()["anonymous"] is True

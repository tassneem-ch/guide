"""Test configuration.

All tests run against clearly-labelled development fixtures — no network
calls. Environment is set BEFORE the app is imported.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

os.environ.update(
    {
        "PRAYER_PROVIDER": "fixture",
        "ROUTING_PROVIDER": "fixture",
        "MOSQUE_PROVIDER": "fixture",
        "GEOCODING_PROVIDER": "fixture",
        "OPTIMIZATION_PROVIDER": "internal",
        "DATABASE_URL": "sqlite:///./guide_test.db",
        "AUTH_REQUIRED": "false",
        "RATE_LIMIT_PER_MINUTE": "100000",
        "APP_ENV": "test",
    }
)

# Remove any singletons cached before env was set.
from app.config import get_settings  # noqa: E402

get_settings.cache_clear()

from app.providers.registry import reset_providers  # noqa: E402

reset_providers()

import pytest  # noqa: E402

from app.providers.geocoding_fixture import FixtureGeocodingProvider  # noqa: E402
from app.providers.mosques_fixture import FixtureMosqueProvider  # noqa: E402
from app.providers.prayer_fixture import FixturePrayerProvider  # noqa: E402
from app.providers.routing_fixture import FixtureRoutingProvider  # noqa: E402
from app.services.route_planner import RoutePlanner  # noqa: E402


@pytest.fixture
def prayer_provider() -> FixturePrayerProvider:
    return FixturePrayerProvider()


@pytest.fixture
def routing_provider() -> FixtureRoutingProvider:
    return FixtureRoutingProvider()


@pytest.fixture
def mosque_provider() -> FixtureMosqueProvider:
    return FixtureMosqueProvider()


@pytest.fixture
def planner(routing_provider, prayer_provider, mosque_provider) -> RoutePlanner:
    return RoutePlanner(routing_provider, prayer_provider, mosque_provider)


@pytest.fixture
def client():
    from fastapi.testclient import TestClient

    from app.main import app

    with TestClient(app) as test_client:
        yield test_client

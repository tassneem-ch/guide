"""FastAPI application factory."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from .api import auth as auth_api
from .api import geocode, mosques, prayer, routes, trips
from .config import get_settings
from .core.ratelimit import limiter
from .db.session import init_db
from .providers.registry import get_providers

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    get_providers()  # construct provider bundle eagerly
    yield
    await get_providers().close()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Guide — Prayer-Aware Travel Planner API",
        description=(
            "Route planning around Islamic prayer times with mosque "
            "discovery and multi-day itinerary scheduling. Provider modes "
            "(live vs development fixtures) are reported at /v1/health."
        ),
        version="1.0.0",
        lifespan=lifespan,
    )
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(prayer.router)
    app.include_router(routes.router)
    app.include_router(mosques.router)
    app.include_router(geocode.router)
    app.include_router(trips.router)
    app.include_router(auth_api.auth_router)
    app.include_router(auth_api.me_router)
    app.include_router(auth_api.health_router)
    return app


app = create_app()

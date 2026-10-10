"""Environment-driven application settings."""
from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # App
    app_env: str = "development"
    app_debug: bool = True
    app_host: str = "0.0.0.0"
    app_port: int = 8000
    public_base_url: str = "http://localhost:8000"

    # Database
    database_url: str = "sqlite:///./guide.db"
    postgis_enabled: bool = False

    # Auth
    auth_required: bool = False
    jwt_secret: str = "change-me-to-a-long-random-string"
    jwt_expires_min: int = 60 * 24 * 7

    # Providers
    prayer_provider: str = "aladhan"
    routing_provider: str = "osrm"
    mosque_provider: str = "osm"
    geocoding_provider: str = "nominatim"
    # "auto" (default): Google Places API (New) when a key is configured,
    # keyless geocoding-based suggestions otherwise. "google" | "nominatim"
    # pins a backend explicitly.
    places_provider: str = "auto"
    optimization_provider: str = "internal"

    # Credentials
    google_maps_api_key: str = ""
    google_route_optimization_key: str = ""
    aladhan_api_base: str = "https://api.aladhan.com/v1"
    osrm_api_base: str = "https://router.project-osrm.org"
    overpass_api_base: str = "https://overpass-api.de/api"
    nominatim_api_base: str = "https://nominatim.openstreetmap.org"

    # Engine tuning
    route_cache_ttl_seconds: int = 900
    prayer_cache_ttl_seconds: int = 21600
    max_matrix_elements: int = 300
    default_max_detour_min: int = 25
    default_stop_duration_min: int = 15
    default_planning_window_min: int = 30
    default_prayer_buffer_min: int = 10

    # Security / limits
    rate_limit_per_minute: int = 60
    cors_origins: str = "http://localhost:3000,http://localhost:5000"

    log_level: str = "INFO"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()

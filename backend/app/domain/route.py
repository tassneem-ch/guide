"""Route, stop and itinerary domain types."""
from __future__ import annotations

from datetime import datetime, timedelta
from enum import Enum

from pydantic import BaseModel, Field, model_validator

from .geo import GeoPoint
from .mosque import MosqueCandidate
from .prayer import PrayerConfig, PrayerEvent


class TravelMode(str, Enum):
    DRIVING = "driving"
    WALKING = "walking"
    CYCLING = "cycling"


class Preference(str, Enum):
    FASTEST = "fastest"
    BALANCED = "balanced"
    PRAYER_FRIENDLY = "prayer_friendly"


class StopKind(str, Enum):
    ORIGIN = "origin"
    WAYPOINT = "waypoint"
    DESTINATION = "destination"
    MOSQUE = "mosque"
    PRAYER_BREAK = "prayer_break"
    ATTRACTION = "attraction"
    MEAL = "meal"
    REST = "rest"
    OVERNIGHT = "overnight"


class PlanningOptions(BaseModel):
    """User knobs for the prayer-aware planner (all minutes)."""

    preference: Preference = Preference.BALANCED
    max_detour_min: int = Field(default=25, ge=0, le=600)
    stop_duration_min: int = Field(default=15, ge=1, le=240)
    planning_window_min: int = Field(default=30, ge=0, le=360,
        description="How early the user is willing to arrive and wait before a prayer.")
    prayer_buffer_min: int = Field(default=10, ge=0, le=180,
        description="Latest acceptable arrival after the prayer starts.")
    prayer_stops: str = Field(default="optional", pattern="^(mandatory|optional|none)$")
    # Objective weights (relative). The engine documents their effect.
    weight_detour: float = Field(default=1.0, ge=0, le=100)
    weight_waiting: float = Field(default=0.4, ge=0, le=100)
    weight_missing_prayer: float = Field(default=20.0, ge=0, le=100_000)


class RouteRequest(BaseModel):
    origin: GeoPoint
    destination: GeoPoint
    waypoints: list[GeoPoint] = Field(default_factory=list,
        description="Ordered intermediate destinations (mandatory stops).")
    depart_at: datetime
    mode: TravelMode = TravelMode.DRIVING
    options: PlanningOptions = Field(default_factory=PlanningOptions)
    prayer: PrayerConfig = Field(default_factory=PrayerConfig)
    locale: str = "en"
    max_alternatives: int = Field(default=3, ge=1, le=5)


class TravelLeg(BaseModel):
    from_point: GeoPoint
    to_point: GeoPoint
    departure_utc: datetime
    arrival_utc: datetime
    distance_m: int
    duration_s: int
    from_label: str = "Origin"
    to_label: str = "Destination"


class ScheduledStop(BaseModel):
    kind: StopKind
    name: str
    location: GeoPoint
    arrival_utc: datetime
    departure_utc: datetime
    locked: bool = False
    prayer: PrayerEvent | None = None
    mosque_id: str | None = None
    mosque: MosqueCandidate | None = None
    notes: list[str] = Field(default_factory=list)
    uncertainties: list[str] = Field(default_factory=list)
    # For prayer stops: why this mosque was chosen / what the trade-off was.
    rationale: str | None = None
    detour_seconds: int = 0
    detour_distance_m: int = 0

    @property
    def duration_s(self) -> int:
        return int((self.departure_utc - self.arrival_utc).total_seconds())


class RouteMetrics(BaseModel):
    total_distance_m: int
    total_duration_s: int                 # wheels-moving + planned stops + waiting
    driving_duration_s: int
    waiting_duration_s: int = 0
    detour_duration_s: int = 0            # extra vs. the fastest plan
    detour_distance_m: int = 0
    arrival_utc: datetime
    arrival_local: str = ""
    arrival_tz: str = ""
    mosque_stop_count: int = 0
    prayers_served: list[str] = Field(default_factory=list)
    prayers_missed: list[str] = Field(default_factory=list)


class RoutePlan(BaseModel):
    preference: Preference
    legs: list[TravelLeg] = Field(default_factory=list)
    stops: list[ScheduledStop] = Field(default_factory=list)
    metrics: RouteMetrics
    prayer_events: list[PrayerEvent] = Field(default_factory=list)
    explanation: list[str] = Field(default_factory=list)
    uncertainties: list[str] = Field(default_factory=list)
    route_provider: str
    route_live: bool
    geometry: list[GeoPoint] = Field(default_factory=list,
        description="Route polyline for map rendering.")
    feasible: bool = True
    infeasibility_reason: str | None = None


class RouteResponse(BaseModel):
    alternatives: list[RoutePlan]
    requested_at: datetime
    notes: list[str] = Field(default_factory=list)
    providers: dict[str, str] = Field(default_factory=dict)


# ---------------------------------------------------------------------------
# Multi-day trips
# ---------------------------------------------------------------------------

class ActivityItem(BaseModel):
    """A user-entered thing to do at a city, with an optional time window."""
    id: str
    name: str
    location: GeoPoint | None = None
    planned_duration_min: int = Field(default=90, ge=5, le=1440)
    earliest_start_local: str | None = None   # "HH:MM" local
    latest_start_local: str | None = None     # "HH:MM" local
    locked: bool = False                      # fixed order / fixed time
    day_index: int = 0


class OvernightPreference(str, Enum):
    NONE = "none"
    PREFER = "prefer"
    REQUIRED = "required"


class TripRequest(BaseModel):
    title: str = "My trip"
    origin: GeoPoint
    destination: GeoPoint
    depart_utc: datetime
    return_utc: datetime | None = None
    mode: TravelMode = TravelMode.DRIVING
    days: int = Field(default=3, ge=1, le=60)
    activities: list[ActivityItem] = Field(default_factory=list)
    overnight: OvernightPreference = OvernightPreference.PREFER
    pace_min_per_day: int = Field(default=480, ge=60, le=900,
        description="Planned minutes of activity per day before travel.")
    options: PlanningOptions = Field(default_factory=PlanningOptions)
    prayer: PrayerConfig = Field(default_factory=PrayerConfig)
    locale: str = "en"


class ScheduledActivity(BaseModel):
    activity: ActivityItem
    start_utc: datetime
    end_utc: datetime
    start_local: str
    notes: list[str] = Field(default_factory=list)
    conflicts: list[str] = Field(default_factory=list)


class DaySchedule(BaseModel):
    index: int
    local_date: str
    city: str
    tz: str
    legs: list[TravelLeg] = Field(default_factory=list)
    stops: list[ScheduledStop] = Field(default_factory=list)
    activities: list[ScheduledActivity] = Field(default_factory=list)
    overnight: ScheduledStop | None = None
    prayer_events: list[PrayerEvent] = Field(default_factory=list)
    explanation: list[str] = Field(default_factory=list)
    uncertainties: list[str] = Field(default_factory=list)


class TripPlan(BaseModel):
    title: str
    days: list[DaySchedule]
    created_at: datetime
    route_provider: str
    providers: dict[str, str] = Field(default_factory=dict)
    notes: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _non_empty(self) -> "TripPlan":
        if not self.days:
            raise ValueError("trip must contain at least one day")
        return self


def add_minutes(dt: datetime, minutes: int) -> datetime:
    return dt + timedelta(minutes=minutes)

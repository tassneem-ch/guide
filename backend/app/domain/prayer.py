"""Prayer-time domain types.

Convention: every prayer instant is carried as an aware UTC datetime plus the
IANA time zone of the location it was computed for. Display always uses the
local zone; comparisons always use UTC.
"""
from __future__ import annotations

from datetime import date, datetime, time, timezone
from enum import Enum

from pydantic import BaseModel, Field

from .geo import GeoPoint


class PrayerName(str, Enum):
    FAJR = "fajr"
    DHUHR = "dhuhr"
    ASR = "asr"
    MAGHRIB = "maghrib"
    ISHA = "isha"


ALL_PRAYERS: tuple[PrayerName, ...] = (
    PrayerName.FAJR,
    PrayerName.DHUHR,
    PrayerName.ASR,
    PrayerName.MAGHRIB,
    PrayerName.ISHA,
)


class AsrSchool(str, Enum):
    STANDARD = "standard"   # Shafi'i, Maliki, Hanbali (shadow ×1)
    HANAFI = "hanafi"       # Hanafi (shadow ×2)


class HighLatitudeRule(str, Enum):
    """Rule used when the sun does not set normally (high latitudes)."""
    MIDDLE_OF_THE_NIGHT = "middle_of_the_night"
    SEVENTH_OF_THE_NIGHT = "seventh_of_the_night"
    ANGLE_BASED = "angle_based"
    NEAREST_VALID = "nearest_valid"


class PrayerMethod(str, Enum):
    """Calculation methods supported by the active provider (see capabilities)."""
    MWL = "mwl"                          # Muslim World League
    ISNA = "isna"                        # Islamic Society of North America
    EGYPTIAN = "egyptian"                # Egyptian General Authority of Survey
    UMM_AL_QURA = "umm_al_qura"          # Umm al-Qura University, Makkah
    KARACHI = "karachi"                  # University of Islamic Sciences, Karachi
    TEHRAN = "tehran"                    # Institute of Geophysics, University of Tehran
    GULF = "gulf"                        # Gulf region
    KUWAIT = "kuwait"
    QATAR = "qatar"
    SINGAPORE = "singapore"
    TURKEY = "turkey"
    FRANCE = "france"
    RUSSIA = "russia"
    MOON_SIGHTING_COMMITTEE = "moon_sighting"
    DUBAI = "dubai"
    JAKIM = "jakim"                 # Malaysia
    TUNISIA = "tunisia"
    ALGERIA = "algeria"
    KEMENAG = "kemenag"             # Indonesia
    MOROCCO = "morocco"
    PORTUGAL = "portugal"
    JORDAN = "jordan"
    CUSTOM = "custom"                    # provider-independent: user angle/tune overrides


class PrayerConfig(BaseModel):
    """User/region prayer configuration — passed through to the provider."""

    method: PrayerMethod = PrayerMethod.MWL
    school: AsrSchool = AsrSchool.STANDARD
    high_latitude_rule: HighLatitudeRule = HighLatitudeRule.MIDDLE_OF_THE_NIGHT
    # Manual per-prayer minute corrections (provider `tune`), in local minutes.
    adjustments: dict[PrayerName, int] = Field(default_factory=dict)
    midnight_mode: str = "standard"     # "standard" | "umm_al_qura" (isha midpoint)


class PrayerEvent(BaseModel):
    """One prayer for one local date at one location."""

    name: PrayerName
    utc: datetime                        # always tz-aware UTC
    local: datetime                      # naive local wall time at `tz`
    tz: str
    local_date: date
    location: GeoPoint
    method: PrayerMethod
    school: AsrSchool
    source: str                          # e.g. "aladhan", "fixture"
    live: bool = True                    # False => development fixture data
    # Congregation/iqama: NEVER inferred from calculation. Only set when a
    # mosque published a verified schedule.
    congregation_utc: datetime | None = None
    congregation_verified: bool = False
    notes: list[str] = Field(default_factory=list)

    @classmethod
    def from_local(
        cls,
        *,
        name: PrayerName,
        local_dt: datetime,
        tz: str,
        location: GeoPoint,
        method: PrayerMethod,
        school: AsrSchool,
        source: str,
        live: bool,
        notes: list[str] | None = None,
    ) -> "PrayerEvent":
        from zoneinfo import ZoneInfo

        tz_obj = ZoneInfo(tz)
        aware_local = local_dt.replace(tzinfo=tz_obj)
        return cls(
            name=name,
            utc=aware_local.astimezone(timezone.utc),
            local=local_dt.replace(tzinfo=None),
            tz=tz,
            local_date=local_dt.date(),
            location=location,
            method=method,
            school=school,
            source=source,
            live=live,
            notes=notes or [],
        )


class DayPrayers(BaseModel):
    """All prayers for a single local date at a single location."""

    location: GeoPoint
    local_date: date
    tz: str
    events: list[PrayerEvent]
    source: str
    live: bool = True
    fetched_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    def by_name(self) -> dict[PrayerName, PrayerEvent]:
        return {e.name: e for e in self.events}


class PrayerCapabilities(BaseModel):
    """What the *active* provider actually supports — the app only offers these."""

    provider: str
    live: bool
    methods: list[dict[str, str]]
    schools: list[AsrSchool]
    high_latitude_rules: list[HighLatitudeRule]
    manual_adjustments: bool
    supports_future_dates: bool
    notes: list[str] = Field(default_factory=list)

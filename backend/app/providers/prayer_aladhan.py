"""Live prayer times via the AlAdhan API.

Docs: https://aladhan.com/prayer-times-api
Only options the API actually accepts are exposed (see capabilities()):
method, Asr school, per-prayer `tune` adjustments, midnight mode.
High-latitude *rule selection* is not offered by this provider — the app hides
that control based on capabilities() rather than silently ignoring it.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

import httpx

from ..config import get_settings
from ..core.cache import TTLCache
from ..domain.geo import GeoPoint
from ..domain.prayer import (
    ALL_PRAYERS,
    AsrSchool,
    DayPrayers,
    PrayerCapabilities,
    PrayerConfig,
    PrayerEvent,
    PrayerMethod,
    PrayerName,
)

# Our method enum -> AlAdhan numeric method id (only documented ids).
ALADHAN_METHOD_IDS: dict[PrayerMethod, int] = {
    PrayerMethod.MWL: 3,
    PrayerMethod.ISNA: 2,
    PrayerMethod.EGYPTIAN: 5,
    PrayerMethod.UMM_AL_QURA: 4,
    PrayerMethod.KARACHI: 1,
    PrayerMethod.TEHRAN: 7,
    PrayerMethod.GULF: 8,
    PrayerMethod.KUWAIT: 9,
    PrayerMethod.QATAR: 10,
    PrayerMethod.SINGAPORE: 11,
    PrayerMethod.TURKEY: 13,
    PrayerMethod.RUSSIA: 14,
    PrayerMethod.MOON_SIGHTING_COMMITTEE: 15,
}

METHOD_LABELS: dict[PrayerMethod, str] = {
    PrayerMethod.MWL: "Muslim World League",
    PrayerMethod.ISNA: "ISNA (North America)",
    PrayerMethod.EGYPTIAN: "Egyptian General Authority of Survey",
    PrayerMethod.UMM_AL_QURA: "Umm al-Qura University, Makkah",
    PrayerMethod.KARACHI: "University of Islamic Sciences, Karachi",
    PrayerMethod.TEHRAN: "Institute of Geophysics, University of Tehran",
    PrayerMethod.GULF: "Gulf region",
    PrayerMethod.KUWAIT: "Kuwait",
    PrayerMethod.QATAR: "Qatar",
    PrayerMethod.SINGAPORE: "Majlis Ugama Islam Singapura",
    PrayerMethod.TURKEY: "Diyanet Isleri Baskanligi, Turkey",
    PrayerMethod.RUSSIA: "Spiritual Administration of Muslims of Russia",
    PrayerMethod.MOON_SIGHTING_COMMITTEE: "Moonsighting Committee Worldwide",
    PrayerMethod.FRANCE: "Comite Islam de France",
    PrayerMethod.CUSTOM: "Custom (manual adjustments)",
}

_TIMING_KEYS: dict[PrayerName, str] = {
    PrayerName.FAJR: "Fajr",
    PrayerName.DHUHR: "Dhuhr",
    PrayerName.ASR: "Asr",
    PrayerName.MAGHRIB: "Maghrib",
    PrayerName.ISHA: "Isha",
}


class ProviderError(RuntimeError):
    """Raised when a live provider fails — callers must surface it, never mask it."""


class AladhanPrayerProvider:
    name = "aladhan"
    live = True

    def __init__(self) -> None:
        settings = get_settings()
        self._base = settings.aladhan_api_base.rstrip("/")
        self._client = httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=5.0))
        self._cache = TTLCache(settings.prayer_cache_ttl_seconds)

    def capabilities(self) -> PrayerCapabilities:
        return PrayerCapabilities(
            provider=self.name,
            live=True,
            methods=[
                {
                    "id": m.value,
                    "label": METHOD_LABELS[m],
                    "description": METHOD_LABELS[m],
                }
                for m in ALADHAN_METHOD_IDS
            ],
            schools=[AsrSchool.STANDARD, AsrSchool.HANAFI],
            # The AlAdhan API accepts no high-latitude rule selector.
            high_latitude_rules=[],
            manual_adjustments=True,
            supports_future_dates=True,
            notes=[
                "Prayer times are calculated by the provider for the given "
                "coordinates and local date; congregation (iqama) times are never "
                "inferred — they appear only when a mosque publishes a schedule.",
                "High-latitude rule selection is not supported by this provider; "
                "use manual per-prayer adjustments in polar regions.",
            ],
        )

    def _method_id(self, config: PrayerConfig) -> int:
        return ALADHAN_METHOD_IDS.get(config.method, 3)

    async def day_prayers(
        self, point: GeoPoint, local_date: date, config: PrayerConfig
    ) -> DayPrayers:
        cache_key = (
            self.name,
            round(point.lat, 5),
            round(point.lon, 5),
            local_date.isoformat(),
            config.model_dump_json(),
        )
        return await self._cache.get_or_fetch(
            cache_key, lambda: self._fetch(point, local_date, config)
        )

    async def _fetch(
        self, point: GeoPoint, local_date: date, config: PrayerConfig
    ) -> DayPrayers:
        params: dict[str, str | int] = {
            "latitude": f"{point.lat:.6f}",
            "longitude": f"{point.lon:.6f}",
            "method": self._method_id(config),
            "school": 1 if config.school == AsrSchool.HANAFI else 0,
        }
        if config.midnight_mode in ("standard", "umm_al_qura"):
            params["midnightMode"] = config.midnight_mode
        if config.adjustments:
            tune = {
                PrayerName.FAJR: config.adjustments.get(PrayerName.FAJR, 0),
                PrayerName.DHUHR: config.adjustments.get(PrayerName.DHUHR, 0),
                PrayerName.ASR: config.adjustments.get(PrayerName.ASR, 0),
                PrayerName.MAGHRIB: config.adjustments.get(PrayerName.MAGHRIB, 0),
                PrayerName.ISHA: config.adjustments.get(PrayerName.ISHA, 0),
            }
            # AlAdhan tune order: Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha
            params["tune"] = f"{tune[PrayerName.FAJR]},0,{tune[PrayerName.DHUHR]},{tune[PrayerName.ASR]},{tune[PrayerName.MAGHRIB]},{tune[PrayerName.ISHA]}"

        url = f"{self._base}/timings/{local_date.strftime('%d-%m-%Y')}"
        try:
            response = await self._client.get(url, params=params)
            response.raise_for_status()
            payload = response.json()
        except httpx.HTTPError as exc:
            raise ProviderError(f"AlAdhan request failed: {exc}") from exc
        if payload.get("code") != 200 or "data" not in payload:
            raise ProviderError(f"AlAdhan returned an error payload: {payload!r}")

        data = payload["data"]
        meta = data.get("meta", {})
        tz_name = meta.get("timezone") or point.tz or "UTC"
        try:
            tz_obj = ZoneInfo(tz_name)
        except Exception as exc:
            raise ProviderError(f"Provider returned unknown time zone {tz_name!r}") from exc

        timings = data.get("timings", {})
        events: list[PrayerEvent] = []
        for name in ALL_PRAYERS:
            raw = timings.get(_TIMING_KEYS[name])
            if not raw:
                raise ProviderError(f"AlAdhan response missing timing for {name.value}")
            local_dt = _parse_local(raw.strip(), local_date, tz_obj)
            events.append(
                PrayerEvent.from_local(
                    name=name,
                    local_dt=local_dt,
                    tz=tz_name,
                    location=point,
                    method=config.method,
                    school=config.school,
                    source=self.name,
                    live=True,
                )
            )
        return DayPrayers(
            location=point,
            local_date=local_date,
            tz=tz_name,
            events=events,
            source=self.name,
            live=True,
        )

    async def close(self) -> None:
        await self._client.aclose()


def _parse_local(hhmm: str, local_date: date, tz: ZoneInfo) -> datetime:
    """Parse 'HH:MM' (optionally 'HH:MM:SS') as wall time on the local date."""
    hhmm = hhmm.split(" (")[0].strip()
    parts = hhmm.split(":")
    hour, minute = int(parts[0]), int(parts[1])
    second = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
    return datetime(
        local_date.year, local_date.month, local_date.day,
        hour, minute, second, tzinfo=tz,
    )

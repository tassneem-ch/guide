"""Development/test prayer-time fixture.

Clearly labelled: every event carries source="fixture" and live=False so the UI
can render it as development data. Times are deterministic local wall times so
tests can assert scheduling behaviour across time zones and date boundaries.
"""
from __future__ import annotations

from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo

from ..core.timeutil import resolve_tz
from ..domain.geo import GeoPoint
from ..domain.prayer import (
    ALL_PRAYERS,
    AsrSchool,
    DayPrayers,
    HighLatitudeRule,
    PrayerCapabilities,
    PrayerConfig,
    PrayerEvent,
    PrayerMethod,
    PrayerName,
)

# Fixed local wall times — deliberately simple so tests can reason about them.
FIXTURE_LOCAL_TIMES: dict[PrayerName, tuple[int, int]] = {
    PrayerName.FAJR: (5, 10),
    PrayerName.DHUHR: (12, 20),
    PrayerName.ASR: (15, 45),
    PrayerName.MAGHRIB: (18, 5),
    PrayerName.ISHA: (19, 30),
}


class FixturePrayerProvider:
    name = "fixture"
    live = False

    def capabilities(self) -> PrayerCapabilities:
        from ..providers.registry import ALL_METHOD_LABELS

        return PrayerCapabilities(
            provider=self.name,
            live=False,
            methods=[
                {"id": m.value, "label": label, "description": label}
                for m, label in ALL_METHOD_LABELS.items()
            ],
            schools=[AsrSchool.STANDARD, AsrSchool.HANAFI],
            high_latitude_rules=list(HighLatitudeRule),
            manual_adjustments=True,
            supports_future_dates=True,
            notes=[
                "DEVELOPMENT FIXTURE: deterministic placeholder times, not real "
                "prayer times. Set PRAYER_PROVIDER=aladhan for live data."
            ],
        )

    async def day_prayers(
        self, point: GeoPoint, local_date: date, config: PrayerConfig
    ) -> DayPrayers:
        tz_name = resolve_tz(point)
        tz_obj = ZoneInfo(tz_name)
        events: list[PrayerEvent] = []
        for name in ALL_PRAYERS:
            hour, minute = FIXTURE_LOCAL_TIMES[name]
            adjust = config.adjustments.get(name, 0)
            local_dt = datetime(
                local_date.year, local_date.month, local_date.day, hour, minute,
                tzinfo=tz_obj,
            )
            if adjust:
                from datetime import timedelta

                local_dt = local_dt + timedelta(minutes=adjust)
            events.append(
                PrayerEvent.from_local(
                    name=name,
                    local_dt=local_dt.replace(tzinfo=None),
                    tz=tz_name,
                    location=point,
                    method=config.method,
                    school=config.school,
                    source="fixture",
                    live=False,
                    notes=["Development fixture — not a real calculation."],
                )
            )
        return DayPrayers(
            location=point,
            local_date=local_date,
            tz=tz_name,
            events=events,
            source="fixture",
            live=False,
        )

    async def close(self) -> None:  # pragma: no cover
        return None

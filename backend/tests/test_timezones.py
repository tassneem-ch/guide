"""Time zones, date boundaries and DST behaviour of the prayer engine."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from app.domain.geo import GeoPoint
from app.domain.prayer import PrayerConfig, PrayerName
from app.providers.prayer_fixture import FixturePrayerProvider
from app.services.prayer_sampling import sample_journey_prayers
from app.providers.base import RouteResult

PARIS = GeoPoint(lat=48.8566, lon=2.3522, tz="Europe/Paris", name="Paris")
TUNIS = GeoPoint(lat=36.8065, lon=10.1815, tz="Africa/Tunis", name="Tunis")
KIRITIMATI = GeoPoint(lat=1.87, lon=-157.43, tz="Pacific/Kiritimati", name="Kiritimati")


@pytest.mark.asyncio
async def test_prayer_times_use_the_points_own_timezone(prayer_provider):
    day = await prayer_provider.day_prayers(PARIS, date(2025, 6, 15), PrayerConfig())
    assert day.tz == "Europe/Paris"
    for event in day.events:
        assert event.tz == "Europe/Paris"
        assert event.local.hour in range(24)
        # UTC instant must equal the local wall time in that zone.
        round_trip = event.utc.astimezone(ZoneInfo("Europe/Paris"))
        assert round_trip.strftime("%H:%M") == event.local.strftime("%H:%M")


@pytest.mark.asyncio
async def test_same_city_different_zones_give_different_instants(prayer_provider):
    # Identical fixture wall times, different zones => different UTC instants.
    paris = await prayer_provider.day_prayers(PARIS, date(2025, 6, 15), PrayerConfig())
    tunis = await prayer_provider.day_prayers(TUNIS, date(2025, 6, 15), PrayerConfig())
    paris_dhuhr = paris.by_name()[PrayerName.DHUHR]
    tunis_dhuhr = tunis.by_name()[PrayerName.DHUHR]
    assert paris_dhuhr.local == tunis_dhuhr.local          # same wall clock
    assert paris_dhuhr.utc != tunis_dhuhr.utc              # different instants
    # Paris (UTC+2 in summer) is one hour ahead of Tunis (UTC+1).
    assert (tunis_dhuhr.utc - paris_dhuhr.utc) == timedelta(hours=1)


@pytest.mark.asyncio
async def test_dst_transition_changes_utc_offset(prayer_provider):
    winter = await prayer_provider.day_prayers(PARIS, date(2025, 1, 15), PrayerConfig())
    # Paris springs forward on 2025-03-30.
    after = await prayer_provider.day_prayers(PARIS, date(2025, 4, 1), PrayerConfig())
    w = winter.by_name()[PrayerName.FAJR]
    a = after.by_name()[PrayerName.FAJR]
    assert w.local.strftime("%H:%M") == a.local.strftime("%H:%M")
    # 76 calendar days apart, but UTC gap is one hour shorter after the
    # spring-forward (01:00 -> 02:00 on 30 March 2025).
    assert (a.utc - w.utc) == timedelta(days=76) - timedelta(hours=1)


@pytest.mark.asyncio
async def test_date_line_location_keeps_local_date(prayer_provider):
    day = await prayer_provider.day_prayers(KIRITIMATI, date(2025, 6, 15), PrayerConfig())
    fajr = day.by_name()[PrayerName.FAJR]
    # UTC+14: local 05:10 is still the previous day in UTC.
    assert fajr.utc.date() == date(2025, 6, 14)
    assert fajr.local_date == date(2025, 6, 15)


@pytest.mark.asyncio
async def test_journey_crossing_midnight_includes_next_day_fajr(prayer_provider):
    """Depart late evening; the next local Fajr inside the journey is sampled."""
    point = PARIS
    depart = datetime(2025, 6, 15, 22, 0, tzinfo=ZoneInfo("Europe/Paris")).astimezone(
        timezone.utc
    )
    route = RouteResult(
        geometry=[point, GeoPoint(lat=49.2, lon=2.4, tz="Europe/Paris")],
        distance_m=400_000,
        duration_s=8 * 3600,       # arrives ~06:00 local next day
        provider="test",
        live=False,
    )
    events, notes = await sample_journey_prayers(
        prayer_provider, route, depart, PrayerConfig()
    )
    fajrs = [e for e in events if e.name == PrayerName.FAJR]
    assert fajrs, "next-day Fajr must appear for a journey crossing midnight"
    assert all(e.utc >= depart for e in events)
    assert all(e.utc <= depart + timedelta(seconds=route.duration_s) for e in events)
    # The Fajr found must be the one on 16 June local.
    assert any(e.local_date == date(2025, 6, 16) for e in fajrs)


@pytest.mark.asyncio
async def test_departure_city_times_are_not_reused_along_the_route(prayer_provider):
    """Sampling must request prayer times per location, not copy the origin's."""
    depart = datetime(2025, 6, 15, 6, 0, tzinfo=timezone.utc)
    route = RouteResult(
        geometry=[TUNIS, PARIS],
        distance_m=2_200_000,
        duration_s=60 * 3600,
        provider="test",
        live=False,
    )
    events, _ = await sample_journey_prayers(
        prayer_provider, route, depart, PrayerConfig()
    )
    zones = {e.tz for e in events}
    assert "Africa/Tunis" in zones        # departure region
    assert "Europe/Paris" in zones        # destination region gets its own times

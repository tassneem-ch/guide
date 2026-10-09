"""Journey-wide prayer sampling.

Prayer times are computed for representative locations along the route (each
with its own IANA zone and local date) — never copied from the departure city.
Events are then filtered to the journey window and de-duplicated per
city/date/prayer so downstream scheduling stays cheap.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from ..domain.geo import GeoPoint, haversine_m
from ..domain.prayer import PrayerConfig, PrayerEvent
from ..providers.base import RouteResult
from ..providers.base import PrayerTimeProvider
from ..core.timeutil import resolve_tz

# Sampling: at most this many geometry points, roughly every ~40 km.
DEFAULT_MAX_SAMPLES = 12
SAMPLE_SPACING_M = 40_000
DEDUP_BUCKET_MINUTES = 15
MAX_JOURNEY_EVENTS = 40


def cumulative_distances(geometry: list[GeoPoint]) -> list[float]:
    cum = [0.0]
    for a, b in zip(geometry, geometry[1:]):
        cum.append(cum[-1] + haversine_m(a, b))
    return cum


def select_sample_indices(geometry: list[GeoPoint]) -> list[int]:
    """Pick up to DEFAULT_MAX_SAMPLES vertices spread along the route."""
    if not geometry:
        return []
    if len(geometry) <= DEFAULT_MAX_SAMPLES:
        return list(range(len(geometry)))
    total = haversine_m(geometry[0], geometry[-1]) if len(geometry) == 2 else None
    cum = cumulative_distances(geometry)
    route_len = cum[-1]
    if route_len <= 0:
        return [0, len(geometry) - 1]

    wanted = max(2, min(DEFAULT_MAX_SAMPLES, int(route_len / SAMPLE_SPACING_M) + 1))
    step = route_len / (wanted - 1)
    targets = [i * step for i in range(wanted)]
    indices: list[int] = []
    t = 0
    for target in targets:
        while t < len(cum) - 1 and cum[t] < target:
            t += 1
        if not indices or indices[-1] != t:
            indices.append(t)
    if len(indices) < 2:
        indices = [0, len(geometry) - 1]
    return indices


def eta_seconds_at_vertex(cum: list[float], index: int, route: RouteResult) -> int:
    """Interpolated ETA (seconds after departure) at a route vertex."""
    if route.distance_m <= 0:
        return 0
    fraction = min(max(cum[index] / route.distance_m, 0.0), 1.0)
    return int(route.duration_s * fraction)


async def sample_journey_prayers(
    provider: PrayerTimeProvider,
    route: RouteResult,
    depart_utc: datetime,
    config: PrayerConfig,
    waypoints: list[GeoPoint] | None = None,
    max_samples: int = DEFAULT_MAX_SAMPLES,
) -> tuple[list[PrayerEvent], list[str]]:
    """Return (journey prayer events, uncertainty notes).

    Every prayer is computed for the local date and time zone of the sample
    location at its ETA, which handles time-zone changes, DST and midnight
    crossings naturally. Events outside the journey window are dropped; the
    scheduler later decides which are actually reachable.
    """
    notes: list[str] = []
    if not route.geometry:
        return [], notes

    geometry = route.geometry
    cum = cumulative_distances(geometry)
    indices = select_sample_indices(geometry)[:max_samples]
    # Always sample waypoints and the destination so their local prayers exist.
    anchor_points: list[tuple[int, GeoPoint]] = []
    for i in indices:
        anchor_points.append((i, geometry[i]))
    for wp in waypoints or []:
        nearest = _nearest_vertex(geometry, wp)
        anchor_points.append((nearest, geometry[nearest]))

    # Deduplicate by vertex index (keep first occurrence).
    seen_vertices: set[int] = set()
    unique_points: list[tuple[int, GeoPoint]] = []
    for idx, point in sorted(anchor_points, key=lambda t: t[0]):
        if idx not in seen_vertices:
            seen_vertices.add(idx)
            unique_points.append((idx, point))

    journey_end = depart_utc + timedelta(seconds=route.duration_s)
    events: list[PrayerEvent] = []
    for idx, point in unique_points:
        eta = depart_utc + timedelta(seconds=eta_seconds_at_vertex(cum, idx, route))
        tz_name = resolve_tz(point)
        local_date = eta.astimezone(__import__("zoneinfo").ZoneInfo(tz_name)).date()
        try:
            day = await provider.day_prayers(point, local_date, config)
        except Exception as exc:  # provider failure must be visible, not silent
            notes.append(
                f"Prayer times unavailable for a route section near "
                f"({point.lat:.3f}, {point.lon:.3f}): {exc}"
            )
            continue
        # Include prayers from the local date that fall inside the journey.
        for event in day.events:
            if depart_utc - timedelta(minutes=5) <= event.utc <= journey_end:
                events.append(event)
        # Midnight crossing: also consider the next local day if the ETA is
        # late in the day and the journey continues past local midnight.
        next_local = local_date.replace(day=local_date.day + 1) if local_date.day < 28 \
            else None
        if next_local and eta.hour >= 20:
            try:
                next_day = await provider.day_prayers(point, next_local, config)
                for event in next_day.events:
                    if depart_utc <= event.utc <= journey_end:
                        events.append(event)
            except Exception:
                pass

    deduped = _dedupe(events)
    if len(deduped) >= MAX_JOURNEY_EVENTS:
        deduped = deduped[:MAX_JOURNEY_EVENTS]
        notes.append("Prayer-event list truncated for long journey.")
    if not deduped and route.duration_s > 3600:
        notes.append(
            "No prayer times could be determined for this journey window — "
            "check provider availability."
        )
    return deduped, notes


def _nearest_vertex(geometry: list[GeoPoint], point: GeoPoint) -> int:
    best_i, best_d = 0, float("inf")
    for i, v in enumerate(geometry):
        d = haversine_m(v, point)
        if d < best_d:
            best_i, best_d = i, d
    return best_i


def _dedupe(events: list[PrayerEvent]) -> list[PrayerEvent]:
    """Keep the first event per (name, tz, local date, 15-min bucket)."""
    seen: set[tuple] = set()
    unique: list[PrayerEvent] = []
    for event in sorted(events, key=lambda e: e.utc):
        bucket = int(event.utc.timestamp() // (DEDUP_BUCKET_MINUTES * 60))
        key = (event.name, event.tz, event.local_date, bucket)
        if key in seen:
            continue
        seen.add(key)
        unique.append(event)
    return unique

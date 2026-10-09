"""Multi-day trip planner.

Composes per-day prayer-aware route legs (via RoutePlanner) with city
activities, mosque anchors for non-travel days, and overnight stays. Feasibility
is enforced with the same leg/stop model: impossible schedules are flagged, not
silently dropped, and edits reschedule the affected day.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from ..core.timeutil import resolve_tz
from ..domain.geo import GeoPoint, haversine_m
from ..domain.prayer import PrayerEvent, PrayerName
from ..domain.route import (
    ActivityItem,
    DaySchedule,
    PlanningOptions,
    RouteRequest,
    ScheduledActivity,
    ScheduledStop,
    StopKind,
    TravelLeg,
    TripPlan,
    TripRequest,
)
from ..providers.google_common import ProviderError
from . import prayer_sampling as sampling
from .candidate_eval import discover_mosques_along_route, evaluate_detours
from .route_planner import RoutePlanner

MAX_HOURS_PER_DAY = 8.0
DEFAULT_DAY_START_LOCAL = (9, 0)


class TripPlanner:
    def __init__(self, route_planner: RoutePlanner) -> None:
        self.route_planner = route_planner
        self.prayer = route_planner.prayer
        self.mosques = route_planner.mosques
        self.routing = route_planner.routing

    async def plan(self, req: TripRequest) -> TripPlan:
        notes: list[str] = []
        days: list[DaySchedule] = []

        # 1) Route the whole journey once to learn geometry/total duration.
        depart = _as_utc(req.depart_utc)
        routes = await self.routing.route(
            origin=req.origin,
            destination=req.destination,
            waypoints=[],
            mode=req.mode,
            depart_at=depart,
            alternatives=1,
        )
        if not routes:
            raise ProviderError("Routing provider returned no route for this trip")
        main_route = routes[0]
        total_h = main_route.duration_s / 3600.0
        n_days = req.days

        # Split the journey into per-day segments when travel itself spans days.
        split_points: list[GeoPoint] = [req.origin]
        if total_h > MAX_HOURS_PER_DAY and n_days > 1:
            geometry = main_route.geometry or [req.origin, req.destination]
            cumulative = sampling.cumulative_distances(geometry)
            total_len = cumulative[-1] or 1.0
            travel_days = min(n_days, max(2, int(total_h / MAX_HOURS_PER_DAY) + 1))
            for i in range(1, travel_days):
                target = total_len * (i / travel_days)
                split_points.append(_interpolate(cumulative, geometry, target))
        split_points.append(req.destination)

        if len(split_points) - 1 >= n_days and n_days < len(split_points) - 1:
            split_points = split_points[: n_days - 1] + [req.destination]

        # Travel days: one leg per segment; remaining days stay in the last city.
        segments: list[tuple[GeoPoint, GeoPoint]] = []
        for i in range(len(split_points) - 1):
            segments.append((split_points[i], split_points[i + 1]))

        activities_by_day: dict[int, list[ActivityItem]] = {}
        for activity in req.activities:
            activities_by_day.setdefault(activity.day_index, []).append(activity)

        day_start_utc = depart
        for day_index in range(n_days):
            if day_index < len(segments):
                seg_from, seg_to = segments[day_index]
                schedule = await self._travel_day(
                    req, day_index, seg_from, seg_to, day_start_utc, notes
                )
                # Next day starts at the overnight location, 09:00 local.
                next_tz = resolve_tz(seg_to)
                next_date = (
                    schedule.local_date and date.fromisoformat(schedule.local_date)
                ) or depart.astimezone(ZoneInfo(next_tz)).date()
                next_date = next_date + timedelta(days=1)
                day_start_utc = _local_wall_to_utc(
                    next_date, DEFAULT_DAY_START_LOCAL, next_tz
                )
            else:
                city = segments[-1][1] if segments else req.destination
                schedule = await self._stay_day(
                    req, day_index, city, day_start_utc, notes
                )
                next_tz = resolve_tz(city)
                cur = date.fromisoformat(schedule.local_date)
                day_start_utc = _local_wall_to_utc(
                    cur + timedelta(days=1), DEFAULT_DAY_START_LOCAL, next_tz
                )

            # Attach user activities for this day.
            await self._attach_activities(
                schedule, activities_by_day.get(day_index, []), req, notes
            )

            # Overnight marker (except final day).
            if day_index < n_days - 1:
                overnight_city = (
                    segments[day_index][1]
                    if day_index < len(segments)
                    else (segments[-1][1] if segments else req.destination)
                )
                tz_name = resolve_tz(overnight_city)
                day_end = _local_wall_to_utc(
                    date.fromisoformat(schedule.local_date) + timedelta(days=1),
                    (7, 0), tz_name,
                )
                if req.overnight.value == "none":
                    schedule.uncertainties.append(
                        "Overnight stay not requested, but this journey requires "
                        "one — an overnight is shown at the end of the day."
                    )
                schedule.overnight = ScheduledStop(
                    kind=StopKind.OVERNIGHT,
                    name=f"Overnight — {overnight_city.name or 'stopover city'}",
                    location=overnight_city,
                    arrival_utc=day_end,
                    departure_utc=day_start_utc,
                    locked=True,
                    notes=["Accommodation not booked — plan only."],
                )

            days.append(schedule)

        return TripPlan(
            title=req.title,
            days=days,
            created_at=datetime.now(timezone.utc),
            route_provider=main_route.provider,
            providers={
                "routing": f"{main_route.provider} ({'live' if main_route.live else 'FIXTURE'})",
                "prayer": f"{self.prayer.name} ({'live' if self.prayer.live else 'FIXTURE'})",
                "mosques": f"{self.mosques.name} ({'live' if self.mosques.live else 'FIXTURE'})",
            },
            notes=notes,
        )

    # ------------------------------------------------------------------

    async def _travel_day(
        self, req: TripRequest, day_index: int,
        seg_from: GeoPoint, seg_to: GeoPoint,
        depart_utc: datetime, notes: list[str],
    ) -> DaySchedule:
        leg_request = RouteRequest(
            origin=seg_from,
            destination=seg_to,
            depart_at=depart_utc,
            mode=req.mode,
            options=req.options,
            prayer=req.prayer,
            locale=req.locale,
        )
        try:
            response = await self.route_planner.plan(leg_request)
        except ProviderError as exc:
            notes.append(f"Day {day_index + 1}: routing failed ({exc}).")
            return DaySchedule(
                index=day_index,
                local_date=depart_utc.strftime("%Y-%m-%d"),
                city=seg_from.name or "Unknown",
                tz=resolve_tz(seg_from),
                uncertainties=[f"Leg could not be routed: {exc}"],
            )
        # Prefer the user's preferred variant, else balanced, else fastest.
        order = {
            "prayer_friendly": ["prayer_friendly", "balanced", "fastest"],
            "balanced": ["balanced", "prayer_friendly", "fastest"],
            "fastest": ["fastest", "balanced", "prayer_friendly"],
        }[req.options.preference.value]
        chosen = response.alternatives[0]
        for pref in order:
            match = next(
                (p for p in response.alternatives
                 if p.preference.value == pref),
                None,
            )
            if match is not None:
                chosen = match
                break

        tz_name = resolve_tz(seg_to)
        arrival_local = chosen.metrics.arrival_utc.astimezone(ZoneInfo(tz_name))
        prayer_events = list(chosen.prayer_events)
        if not prayer_events:
            # Short legs can contain no in-journey prayers — show the
            # destination city's prayers for that local date instead.
            try:
                city_day = await self.prayer.day_prayers(
                    seg_to, arrival_local.date(), req.prayer
                )
                prayer_events = list(city_day.events)
            except ProviderError as exc:
                notes.append(
                    f"Day {day_index + 1}: local prayer times unavailable ({exc})."
                )
        if chosen.stops:
            city_label = seg_to.name or chosen.stops[-1].name
        else:
            city_label = seg_to.name or "Stop"
        return DaySchedule(
            index=day_index,
            local_date=arrival_local.strftime("%Y-%m-%d"),
            city=city_label,
            tz=tz_name,
            legs=chosen.legs,
            stops=chosen.stops,
            prayer_events=prayer_events,
            explanation=chosen.explanation,
            uncertainties=list(chosen.uncertainties) + list(response.notes),
        )

    async def _stay_day(
        self, req: TripRequest, day_index: int, city: GeoPoint,
        day_start_utc: datetime, notes: list[str],
    ) -> DaySchedule:
        """A day without a long leg: city prayers + optional mosque anchor."""
        tz_name = resolve_tz(city)
        local_date = day_start_utc.astimezone(ZoneInfo(tz_name)).date()
        day = await self.prayer.day_prayers(city, local_date, req.prayer)

        stops: list[ScheduledStop] = []
        if req.options.prayer_stops != "none":
            search = await discover_mosques_along_route(
                self.mosques, [city], [0], corridor_radius_m=3000
            )
            if search.candidates:
                cands, _ = await evaluate_detours(
                    self.routing, [city], {0: 0},
                    search.candidates, req.mode, day_start_utc,
                )
                # Anchor to Dhuhr: arrive just before, pray, continue.
                dhuhr = next(
                    (e for e in day.events if e.name == PrayerName.DHUHR), None
                )
                if dhuhr is not None and cands:
                    best = min(cands, key=lambda c: c.detour_seconds)
                    arrival = dhuhr.utc - timedelta(
                        seconds=min(300, req.options.planning_window_min * 60)
                    )
                    depart_mosque = dhuhr.utc + timedelta(
                        seconds=req.options.stop_duration_min * 60
                    )
                    stops.append(
                        ScheduledStop(
                            kind=StopKind.MOSQUE,
                            name=best.mosque.label,
                            location=best.mosque.location,
                            arrival_utc=arrival,
                            departure_utc=depart_mosque,
                            prayer=dhuhr,
                            mosque_id=best.mosque.id,
                            mosque=best.mosque,
                            rationale=(
                                f"City stop anchored to local Dhuhr "
                                f"({dhuhr.local.strftime('%H:%M')} {tz_name})."
                            ),
                            detour_seconds=best.detour_seconds,
                            detour_distance_m=best.detour_distance_m,
                            uncertainties=[
                                "Travel time inside the city is not routed; "
                                "arrival assumes you start from your base."
                            ],
                        )
                    )
            else:
                notes.append(
                    f"Day {day_index + 1}: no mosque data near "
                    f"{city.name or 'the city'} — no mosque stop scheduled."
                )

        return DaySchedule(
            index=day_index,
            local_date=local_date.isoformat(),
            city=city.name or "Current city",
            tz=tz_name,
            stops=stops,
            prayer_events=day.events,
            explanation=[
                f"Stay day in {city.name or 'the city'} — activities plus local "
                "prayer times."
            ],
            uncertainties=([] if day.live else
                           ["Prayer times are development fixtures."]),
        )

    async def _attach_activities(
        self,
        schedule: DaySchedule,
        activities: list[ActivityItem],
        req: TripRequest,
        notes: list[str],
    ) -> None:
        if not activities:
            return
        tz_name = schedule.tz
        tz = ZoneInfo(tz_name)
        local_date = date.fromisoformat(schedule.local_date)

        # Busy intervals already scheduled on this day.
        busy: list[tuple[datetime, datetime]] = []
        for leg in schedule.legs:
            busy.append((leg.departure_utc, leg.arrival_utc))
        for stop in schedule.stops:
            busy.append((stop.arrival_utc, stop.departure_utc))
        for act in schedule.activities:
            busy.append((act.start_utc, act.end_utc))

        # Start after travel + any morning stop.
        cursor = max(
            (b[1] for b in busy),
            default=_local_wall_to_utc(local_date, (8, 0), tz_name),
        )

        for activity in activities:
            duration = timedelta(minutes=activity.planned_duration_min)
            earliest = _parse_hhmm_local(
                activity.earliest_start_local, local_date, tz_name
            )
            latest = _parse_hhmm_local(
                activity.latest_start_local, local_date, tz_name
            )
            start = max(cursor, earliest) if earliest else cursor
            # Avoid overlap with busy intervals.
            for b_start, b_end in busy:
                if start < b_end and start + duration > b_start:
                    start = b_end
            end = start + duration
            conflicts: list[str] = []
            if latest and start > latest:
                conflicts.append(
                    f"Cannot start by {activity.latest_start_local} "
                    "(earlier items run over) — scheduled anyway; adjust the "
                    "order if this must be met."
                )
            elif latest and end > latest + timedelta(hours=1):
                conflicts.append(
                    f"Finishes after your latest start window "
                    f"({activity.latest_start_local})."
                )
            local_start = start.astimezone(tz).strftime("%H:%M")
            schedule.activities.append(
                ScheduledActivity(
                    activity=activity,
                    start_utc=start,
                    end_utc=end,
                    start_local=local_start,
                    conflicts=conflicts,
                    notes=[] if not conflicts else ["Rescheduled automatically "
                                                    "to avoid a conflict."],
                )
            )
            busy.append((start, end))
            cursor = end


# helpers ------------------------------------------------------------------


def _as_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _local_wall_to_utc(
    local_date: date, hhmm: tuple[int, int], tz_name: str
) -> datetime:
    tz = ZoneInfo(tz_name)
    return datetime(
        local_date.year, local_date.month, local_date.day,
        hhmm[0], hhmm[1], tzinfo=tz,
    ).astimezone(timezone.utc)


def _parse_hhmm_local(
    value: str | None, local_date: date, tz_name: str
) -> datetime | None:
    if not value:
        return None
    try:
        hour, minute = (int(p) for p in value.split(":"))
    except (ValueError, AttributeError):
        return None
    return _local_wall_to_utc(local_date, (hour, minute), tz_name)


def _interpolate(
    cum: list[float], geometry: list[GeoPoint], target: float
) -> GeoPoint:
    """Point at `target` distance along the polyline (by great-circle length)."""
    if not geometry:
        raise ValueError("empty geometry")
    if len(geometry) == 1:
        return geometry[0]
    for i in range(1, len(cum)):
        if cum[i] >= target:
            seg = cum[i] - cum[i - 1]
            frac = (target - cum[i - 1]) / seg if seg > 0 else 0.0
            a, b = geometry[i - 1], geometry[i]
            return GeoPoint(
                lat=a.lat + (b.lat - a.lat) * frac,
                lon=a.lon + (b.lon - a.lon) * frac,
                name=f"Stopover ({abs(a.lat + (b.lat - a.lat) * frac):.2f},"
                     f"{abs(a.lon + (b.lon - a.lon) * frac):.2f})",
            )
    return geometry[-1]

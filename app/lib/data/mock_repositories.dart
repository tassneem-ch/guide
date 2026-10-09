import 'dart:math';

import '../domain/models.dart';
import '../domain/repositories.dart';

/// In-app demo data used only when demo mode is enabled in Settings.
///
/// Everything here is obviously synthetic: provider names start with
/// "FIXTURE", `live` is always false, and mosque names carry a "Demo" tag.
/// This exists so the app is explorable without a backend — it must never be
/// confused with real data (the UI shows the fixture banner in this mode).
class MockGeocodeRepository implements GeocodeRepository {
  static const _cities = <GeoPoint>[
    GeoPoint(lat: 36.8065, lon: 10.1815, tz: 'Africa/Tunis', name: 'Tunis, Tunisia'),
    GeoPoint(lat: 36.8625, lon: 10.1956, tz: 'Africa/Tunis', name: 'Carthage, Tunisia'),
    GeoPoint(lat: 36.7538, lon: 10.0911, tz: 'Africa/Tunis', name: 'Sidi Bou Said, Tunisia'),
    GeoPoint(lat: 48.8566, lon: 2.3522, tz: 'Europe/Paris', name: 'Paris, France'),
    GeoPoint(lat: 48.8924, lon: 2.3494, tz: 'Europe/Paris', name: 'Paris 18e, France'),
    GeoPoint(lat: 51.5074, lon: -0.1278, tz: 'Europe/London', name: 'London, UK'),
    GeoPoint(lat: 21.4225, lon: 39.8262, tz: 'Asia/Riyadh', name: 'Mecca, Saudi Arabia'),
    GeoPoint(lat: 24.4672, lon: 39.6111, tz: 'Asia/Riyadh', name: 'Madinah, Saudi Arabia'),
    GeoPoint(lat: 30.0444, lon: 31.2357, tz: 'Africa/Cairo', name: 'Cairo, Egypt'),
    GeoPoint(lat: 41.0082, lon: 28.9784, tz: 'Europe/Istanbul', name: 'Istanbul, Türkiye'),
  ];

  @override
  Future<List<GeoPoint>> geocode(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _cities
        .where((c) => (c.name ?? '').toLowerCase().contains(q))
        .toList();
  }
}

class MockPrayerRepository implements PrayerRepository {
  @override
  Future<DayPrayers> dayPrayers({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  }) async {
    final now = DateTime.now().toUtc();
    // Synthetic schedule: 5 evenly spaced events from 05:00 "local-ish".
    final base = DateTime.utc(now.year, now.month, now.day, 5, 0);
    const names = [PrayerName.fajr, PrayerName.dhuhr, PrayerName.asr, PrayerName.maghrib, PrayerName.isha];
    const offsets = [Duration.zero, Duration(hours: 7), Duration(hours: 10, minutes: 30), Duration(hours: 13), Duration(hours: 14, minutes: 30)];
    final events = <PrayerEvent>[];
    for (var i = 0; i < names.length; i++) {
      final utc = base.add(offsets[i]).add(Duration(days: dateUtc.toUtc().day - now.day));
      events.add(PrayerEvent(
        name: names[i],
        utc: utc,
        local: DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute),
        tz: point.tz ?? 'UTC',
        localDate: utc.toIso8601String().substring(0, 10),
        method: config.method,
        school: config.school,
        source: 'in-app demo data',
        live: false,
        notes: const ['Fixture time — not a real calculation'],
      ));
    }
    return DayPrayers(
      location: point,
      localDate: events.first.localDate,
      tz: point.tz ?? 'UTC',
      events: events,
      source: 'in-app demo data',
      live: false,
      fetchedAt: now,
    );
  }

  @override
  Future<PrayerCapabilities> capabilities() async => PrayerCapabilities(
        provider: 'FIXTURE (in-app demo)',
        live: false,
        methods: const [
          MethodOption(id: 'mwl', label: 'Muslim World League (demo)'),
          MethodOption(id: 'egyptian', label: 'Egyptian General Authority (demo)'),
          MethodOption(id: 'karachi', label: 'University of Karachi (demo)'),
          MethodOption(id: 'umm_al_qura', label: 'Umm al-Qura, Makkah (demo)'),
          MethodOption(id: 'isna', label: 'ISNA, North America (demo)'),
        ],
        schools: const ['standard', 'hanafi'],
        highLatitudeRules: const [
          'middle_of_the_night',
          'seventh_of_the_night',
          'twilight_angle',
          'nearest_night',
        ],
        manualAdjustments: true,
        supportsFutureDates: true,
        notes: const ['Demo capabilities — connect a backend for real methods'],
      );
}

class MockRouteRepository implements RouteRepository {
  @override
  Future<RouteResponse> plan({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> waypoints = const [],
    required DateTime departUtc,
    required TravelMode mode,
    required PlanningOptions options,
    required PrayerConfig prayer,
    String locale = 'en',
  }) async {
    final rng = Random(origin.lat.hashCode ^ destination.lon.hashCode);
    final dist = _haversine(origin, destination);
    final speed = mode == TravelMode.walking ? 1.4 : mode == TravelMode.cycling ? 4.5 : 16.0;
    final baseSeconds = (dist / speed).round().clamp(600, 20 * 3600);

    RoutePlan build(RoutePreference pref, int detourFactor, int waitFactor, String label) {
      final detourSeconds = pref == RoutePreference.fastest ? 0 : (baseSeconds * 0.12 * detourFactor).round();
      final waiting = pref == RoutePreference.fastest ? 0 : (420 * waitFactor);
      final metrics = RouteMetrics(
        totalDistanceM: (dist * (pref == RoutePreference.fastest ? 1.0 : 1.12)).round(),
        totalDurationS: baseSeconds + detourSeconds + waiting,
        drivingDurationS: baseSeconds + detourSeconds,
        waitingDurationS: waiting,
        detourDurationS: detourSeconds,
        detourDistanceM: pref == RoutePreference.fastest ? 0 : (dist * 0.08).round(),
        arrivalUtc: departUtc.toUtc().add(Duration(seconds: baseSeconds + detourSeconds + waiting)),
        arrivalLocal: '',
        arrivalTz: destination.tz ?? 'UTC',
        mosqueStopCount: pref == RoutePreference.fastest ? 0 : (rng.nextBool() ? 1 : 2),
        prayersServed: pref == RoutePreference.fastest ? const [] : const ['asr'],
        prayersMissed: pref == RoutePreference.fastest ? const ['asr'] : const [],
      );
      final geometry = <GeoPoint>[origin, destination];
      final stops = <ScheduledStop>[
        ScheduledStop(
          kind: StopKind.origin,
          name: origin.name ?? 'Origin',
          location: origin,
          arrivalUtc: departUtc.toUtc(),
          departureUtc: departUtc.toUtc(),
          locked: true,
        ),
        if (pref != RoutePreference.fastest)
          ScheduledStop(
            kind: StopKind.mosque,
            name: 'Demo Mosque (fixture)',
            location: GeoPoint(
              lat: (origin.lat + destination.lat) / 2 + 0.004,
              lon: (origin.lon + destination.lon) / 2 - 0.003,
              tz: destination.tz,
            ),
            arrivalUtc: departUtc.toUtc().add(Duration(seconds: (baseSeconds * 0.6).round())),
            departureUtc: departUtc.toUtc().add(Duration(seconds: (baseSeconds * 0.6).round() + 900)),
            locked: false,
            rationale: 'Demo detour toward a fixture mosque near the corridor.',
            uncertainties: const [
              'Demo mosque: no verified name, hours, or congregation times',
              'Detour is estimated, not routed',
            ],
            detourSeconds: detourSeconds,
            detourDistanceM: pref == RoutePreference.fastest ? 0 : (dist * 0.08).round(),
          ),
        ScheduledStop(
          kind: StopKind.destination,
          name: destination.name ?? 'Destination',
          location: destination,
          arrivalUtc: metrics.arrivalUtc,
          departureUtc: metrics.arrivalUtc,
          locked: true,
        ),
      ];
      return RoutePlan(
        preference: pref,
        legs: [
          TravelLeg(
            from: origin,
            to: destination,
            departureUtc: departUtc.toUtc(),
            arrivalUtc: metrics.arrivalUtc,
            distanceM: metrics.totalDistanceM,
            durationS: metrics.totalDurationS,
            fromLabel: origin.name ?? 'Origin',
            toLabel: destination.name ?? 'Destination',
          ),
        ],
        stops: stops,
        metrics: metrics,
        prayerEvents: const [],
        explanation: [label, 'Demo alternative — generated locally without a router'],
        uncertainties: const ['Fixture mode: no live routing, no mosque verification'],
        routeProvider: 'FIXTURE (in-app demo)',
        routeLive: false,
        geometry: geometry,
        feasible: true,
      );
    }

    return RouteResponse(
      alternatives: [
        build(RoutePreference.fastest, 0, 0, 'Fastest demo route: no prayer stops, straight corridor'),
        build(RoutePreference.balanced, 1, 1, 'Balanced demo route: one short mosque detour with modest waiting'),
        build(RoutePreference.prayerFriendly, 2, 0, 'Prayer-friendly demo route: longer detour, minimal waiting'),
      ],
      requestedAt: DateTime.now().toUtc(),
      notes: const ['Fixture response generated on-device for demo mode'],
      providers: const {
        'prayer': 'FIXTURE (in-app demo)',
        'routing': 'FIXTURE (in-app demo)',
        'mosques': 'FIXTURE (in-app demo)',
      },
    );
  }

  static double _haversine(GeoPoint a, GeoPoint b) {
    const r = 6371000.0;
    final dLat = _rad(b.lat - a.lat);
    final dLon = _rad(b.lon - a.lon);
    final h = pow(sin(dLat / 2), 2) +
        cos(_rad(a.lat)) * cos(_rad(b.lat)) * pow(sin(dLon / 2), 2);
    return 2 * r * asin(sqrt(h));
  }

  static double _rad(double deg) => deg * pi / 180;
}

class MockTripRepository implements TripRepository {
  @override
  Future<TripPlan> plan({
    required String title,
    required GeoPoint origin,
    required GeoPoint destination,
    required DateTime departUtc,
    required int days,
    required List<ActivityItem> activities,
    bool overnight = true,
    int paceMinPerDay = 240,
    required PlanningOptions options,
    required PrayerConfig prayer,
    String locale = 'en',
  }) async {
    final daySchedules = <DaySchedule>[];
    for (var i = 0; i < days; i++) {
      final date = DateTime.utc(departUtc.year, departUtc.month, departUtc.day).add(Duration(days: i));
      final dayActivities = activities.where((a) => a.dayIndex == i).toList();
      final scheduled = <ScheduledActivity>[];
      var cursor = DateTime.utc(date.year, date.month, date.day, 9, 0);
      for (final act in dayActivities) {
        final start = cursor;
        final end = start.add(Duration(minutes: act.plannedDurationMin));
        scheduled.add(ScheduledActivity(
          activity: act,
          startUtc: start,
          endUtc: end,
          startLocal: start.toIso8601String().substring(11, 16),
          conflicts: end.isAfter(DateTime.utc(date.year, date.month, date.day, 22))
              ? const ['Demo conflict: activity runs past 22:00']
              : const [],
        ));
        cursor = end.add(const Duration(minutes: 30));
      }
      daySchedules.add(DaySchedule(
        index: i,
        localDate: date.toIso8601String().substring(0, 10),
        city: (i == 0 ? origin.name : destination.name) ?? 'Demo city',
        tz: (i == 0 ? origin.tz : destination.tz) ?? 'UTC',
        activities: scheduled,
        overnight: overnight
            ? ScheduledStop(
                kind: StopKind.overnight,
                name: 'Demo overnight (fixture)',
                location: i == 0 ? origin : destination,
                arrivalUtc: DateTime.utc(date.year, date.month, date.day, 22),
                departureUtc: DateTime.utc(date.year, date.month, date.day).add(const Duration(days: 1, hours: 8)),
                locked: false,
                uncertainties: const ['Demo overnight: not verified with any lodging provider'],
              )
            : null,
        explanation: const ['Demo day generated locally in fixture mode'],
      ));
    }
    return TripPlan(
      title: title.isEmpty ? 'Demo trip' : title,
      days: daySchedules,
      createdAt: DateTime.now().toUtc(),
      routeProvider: 'FIXTURE (in-app demo)',
      providers: const {
        'prayer': 'FIXTURE (in-app demo)',
        'routing': 'FIXTURE (in-app demo)',
        'mosques': 'FIXTURE (in-app demo)',
      },
      notes: const ['Fixture trip: planning rules are simulated, not executed'],
    );
  }
}

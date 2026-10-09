import 'package:flutter_test/flutter_test.dart';

import 'package:guide/domain/models.dart';

/// Parsing tests against the backend JSON contract (see
/// backend/app/api/schemas.py). These guard the client against silent
/// contract drift.
void main() {
  const samplePlanJson = {
    'preference': 'prayer_friendly',
    'legs': [
      {
        'from_point': {'lat': 36.8065, 'lon': 10.1815, 'tz': 'Africa/Tunis'},
        'to_point': {'lat': 36.8625, 'lon': 10.1956, 'tz': 'Africa/Tunis'},
        'departure_utc': '2026-06-15T08:00:00Z',
        'arrival_utc': '2026-06-15T09:30:00Z',
        'distance_m': 21000,
        'duration_s': 5400,
        'from_label': 'Tunis',
        'to_label': 'Carthage',
      },
    ],
    'stops': [
      {
        'kind': 'mosque',
        'name': 'Demo Mosque',
        'location': {'lat': 36.84, 'lon': 10.19, 'tz': 'Africa/Tunis'},
        'arrival_utc': '2026-06-15T08:50:00Z',
        'departure_utc': '2026-06-15T09:05:00Z',
        'locked': false,
        'rationale': 'Short detour to a mosque near the corridor',
        'uncertainties': ['Congregation time not provided'],
        'detour_seconds': 420,
        'detour_distance_m': 1500,
        'detour_method': 'routed',
      },
    ],
    'metrics': {
      'total_distance_m': 22500,
      'total_duration_s': 5820,
      'driving_duration_s': 5400,
      'waiting_duration_s': 0,
      'detour_duration_s': 420,
      'detour_distance_m': 1500,
      'arrival_utc': '2026-06-15T09:37:00Z',
      'arrival_local': '2026-06-15 10:37',
      'arrival_tz': 'Africa/Tunis',
      'mosque_stop_count': 1,
      'prayers_served': ['dhuhr'],
      'prayers_missed': [],
    },
    'prayer_events': [
      {
        'name': 'dhuhr',
        'utc': '2026-06-15T11:20:00Z',
        'local': '2026-06-15T12:20:00',
        'tz': 'Africa/Tunis',
        'local_date': '2026-06-15',
        'method': 'mwl',
        'school': 'standard',
        'source': 'aladhan',
        'live': true,
        'congregation_utc': null,
        'congregation_verified': false,
        'notes': [],
      },
    ],
    'explanation': ['Serves dhuhr with a small detour'],
    'uncertainties': ['Traffic data not available for cycling'],
    'route_provider': 'osrm',
    'route_live': true,
    'geometry': [
      {'lat': 36.8065, 'lon': 10.1815},
      {'lat': 36.84, 'lon': 10.19},
      {'lat': 36.8625, 'lon': 10.1956},
    ],
    'feasible': true,
  };

  const sampleResponseJson = {
    'alternatives': [samplePlanJson],
    'requested_at': '2026-06-15T07:00:00Z',
    'notes': [],
    'providers': {
      'prayer': 'aladhan',
      'routing': 'osrm',
      'mosques': 'osm',
    },
  };

  test('parses a full route response', () {
    final response = RouteResponse.fromJson(sampleResponseJson);
    expect(response.alternatives, hasLength(1));
    expect(response.providers['routing'], 'osrm');
    expect(response.stale, isFalse);

    final plan = response.alternatives.first;
    expect(plan.preference, RoutePreference.prayerFriendly);
    expect(plan.routeProvider, 'osrm');
    expect(plan.routeLive, isTrue);
    expect(plan.isFixture, isFalse);
    expect(plan.geometry, hasLength(3));
    expect(plan.metrics.prayersServed, ['dhuhr']);
    expect(plan.metrics.arrivalUtc.isUtc, isTrue);
  });

  test('parses mosque stops with honesty metadata', () {
    final plan = RouteResponse.fromJson(sampleResponseJson).alternatives.first;
    final stop = plan.stops.single;
    expect(stop.kind, StopKind.mosque);
    expect(stop.detourSeconds, 420);
    expect(stop.uncertainties, contains('Congregation time not provided'));
    expect(stop.rationale, isNotNull);
    // duration of the stop = arrival..departure = 15 min
    expect(stop.durationS, 15 * 60);
  });

  test('parses prayer events without inventing congregation times', () {
    final plan = RouteResponse.fromJson(sampleResponseJson).alternatives.first;
    final event = plan.prayerEvents.single;
    expect(event.name, PrayerName.dhuhr);
    expect(event.congregationUtc, isNull);
    expect(event.congregationVerified, isFalse);
    expect(event.live, isTrue);
    // naive local time keeps wall clock without zone math
    expect(event.local.hour, 12);
  });

  test('marks stale cache responses honestly', () {
    final cachedAt = DateTime.utc(2026, 6, 15, 6, 0);
    final response = RouteResponse.fromJson(sampleResponseJson,
        stale: true, staleAt: cachedAt);
    expect(response.stale, isTrue);
    expect(response.staleAt, cachedAt);
    expect(response.alternatives.first.routeLive, isTrue);
  });

  test('demo route options serialize to the backend contract', () {
    const options = PlanningOptions(
      preference: RoutePreference.prayerFriendly,
      maxDetourMin: 20,
      prayerStops: 'mandatory',
    );
    final json = options.toJson();
    expect(json['preference'], 'prayer_friendly');
    expect(json['max_detour_min'], 20);
    expect(json['prayer_stops'], 'mandatory');
    expect(json.containsKey('weight_detour'), isTrue);
  });
}

import 'dart:convert';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'api_client.dart';
import 'local_store.dart';

/// Repositories talking to the Guide backend.
///
/// Caching policy: successful responses are cached per request shape. If the
/// backend is unreachable, the last cached response is served with
/// `stale = true` and its fetch time — the UI must display the stale banner.
/// We never invent data to cover a failure.
class ApiGeocodeRepository implements GeocodeRepository {
  ApiGeocodeRepository(this._api, this._store);

  final GuideApi _api;
  final LocalStore _store;

  @override
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    String? sessionToken,
    GeoPoint? bias,
  }) async {
    final key = cacheKey('suggest', {'q': query});
    try {
      final queryParameters = <String, dynamic>{'q': query};
      if (sessionToken != null) queryParameters['session'] = sessionToken;
      if (bias != null) {
        queryParameters['bias_lat'] = bias.lat.toString();
        queryParameters['bias_lon'] = bias.lon.toString();
      }
      final json = await _api
          .getJson('/v1/places/autocomplete', query: queryParameters);
      await _store.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': json
          }));
      return _parseSuggestions(json);
    } on Failure catch (e) {
      if (e.isNetwork) {
        final cached = CacheEnvelope.tryParse(await _store.read(key) ?? '');
        if (cached != null) return _parseSuggestions(cached.body);
      }
      rethrow;
    }
  }

  static List<PlaceSuggestion> _parseSuggestions(Map<String, dynamic> json) {
    final results = json['results'] as List? ?? const [];
    return [
      for (final row in results.cast<Map<String, dynamic>>())
        if ((row['label'] as String? ?? '').isNotEmpty)
          PlaceSuggestion(
            id: row['id'] as String?,
            label: row['label'] as String,
            point: row['lat'] == null
                ? null
                : GeoPoint.fromJson(row),
          ),
    ];
  }

  @override
  Future<GeoPoint> resolveSuggestion(
    PlaceSuggestion suggestion, {
    String? sessionToken,
  }) async {
    final existing = suggestion.point;
    if (existing != null) return existing;
    final id = suggestion.id;
    if (id == null) {
      throw Failure('Suggestion has no resolvable place id',
          kind: FailureKind.validation);
    }
    final detailsQuery = <String, dynamic>{'id': id};
    if (sessionToken != null) detailsQuery['session'] = sessionToken;
    final json =
        await _api.getJson('/v1/places/details', query: detailsQuery);
    final result = json['result'];
    if (result is! Map<String, dynamic>) {
      throw const Failure('Place details response missing location',
          kind: FailureKind.server);
    }
    return GeoPoint.fromJson(result);
  }

  @override
  Future<List<GeoPoint>> geocode(String query) async {
    final suggestions = await suggest(query);
    final points = <GeoPoint>[];
    for (final suggestion in suggestions) {
      points.add(await resolveSuggestion(suggestion));
      if (points.length >= 5) break;
    }
    return points;
  }
}

class ApiPrayerRepository implements PrayerRepository {
  ApiPrayerRepository(this._api, this._store);

  final GuideApi _api;
  final LocalStore _store;

  @override
  Future<DayPrayers> dayPrayers({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  }) async {
    final key = cacheKey('prayers', {
      'lat': point.lat,
      'lon': point.lon,
      'date': dateUtc.toUtc().toIso8601String(),
      'config': config.toJson(),
    });
    // The backend receives an instant and resolves the *location's* local
    // calendar day server-side (IANA zone via timezonefinder) — the phone's
    // timezone never decides what day it is elsewhere.
    final body = {
      'point': point.toJson(),
      'date': dateUtc.toUtc().toIso8601String(),
      'config': config.toJson(),
    };
    try {
      final json = await _api.postJson('/v1/prayer-times', body: body);
      await _store.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': json
          }));
      return DayPrayers.fromJson(json);
    } on Failure catch (e) {
      if (e.isNetwork) {
        final cached = CacheEnvelope.tryParse(await _store.read(key) ?? '');
        if (cached != null) return DayPrayers.fromJson(cached.body);
      }
      rethrow;
    }
  }

  @override
  Future<PrayerCapabilities> capabilities() async {
    const key = 'prayer:capabilities';
    try {
      final json = await _api.getJson('/v1/prayer-times/capabilities');
      await _store.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': json
          }));
      return PrayerCapabilities.fromJson(json);
    } on Failure catch (e) {
      if (e.isNetwork) {
        final cached = CacheEnvelope.tryParse(await _store.read(key) ?? '');
        if (cached != null) {
          return PrayerCapabilities.fromJson(cached.body);
        }
      }
      rethrow;
    }
  }
}

class ApiRouteRepository implements RouteRepository {
  ApiRouteRepository(this._api, this._store);

  final GuideApi _api;
  final LocalStore _store;

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
    final body = {
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      if (waypoints.isNotEmpty)
        'waypoints': waypoints.map((w) => w.toJson()).toList(),
      'depart_utc': departUtc.toUtc().toIso8601String(),
      'mode': mode.name,
      'options': options.toJson(),
      'prayer': prayer.toJson(),
      'locale': locale,
    };
    final key = cacheKey('route', body);
    try {
      final json = await _api.postJson('/v1/routes/alternatives', body: body);
      await _store.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': json
          }));
      return RouteResponse.fromJson(json);
    } on Failure catch (e) {
      if (e.isNetwork) {
        final cached = CacheEnvelope.tryParse(await _store.read(key) ?? '');
        if (cached != null) {
          return RouteResponse.fromJson(cached.body,
              stale: true, staleAt: cached.fetchedAt);
        }
      }
      rethrow;
    }
  }
}

class ApiTripRepository implements TripRepository {
  ApiTripRepository(this._api, this._store);

  final GuideApi _api;
  final LocalStore _store;

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
    final body = {
      'title': title,
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      'depart_utc': departUtc.toUtc().toIso8601String(),
      'days': days,
      'activities': activities.map((a) => a.toJson()).toList(),
      'overnight': overnight,
      'pace_min_per_day': paceMinPerDay,
      'options': options.toJson(),
      'prayer': prayer.toJson(),
      'locale': locale,
    };
    final key = cacheKey('trip', body);
    try {
      final json = await _api.postJson('/v1/trips/plan', body: body);
      await _store.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': json
          }));
      return TripPlan.fromJson(json);
    } on Failure catch (e) {
      if (e.isNetwork) {
        final cached = CacheEnvelope.tryParse(await _store.read(key) ?? '');
        if (cached != null) return TripPlan.fromJson(cached.body, stale: true);
      }
      rethrow;
    }
  }
}

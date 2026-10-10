import 'models.dart';

/// Typed failure surfaced to the UI. Never silently swallowed.
class Failure {
  const Failure(
    this.message, {
    this.kind = FailureKind.unknown,
    this.statusCode,
    this.detail,
  });

  final String message;
  final FailureKind kind;
  final int? statusCode;
  final String? detail;

  bool get isNetwork => kind == FailureKind.network;
  bool get isServerError => kind == FailureKind.server;

  @override
  String toString() => 'Failure($kind: $message)';
}

enum FailureKind { network, server, cache, validation, unknown }

/// Geocoding: resolve free text to coordinates (no invented results).
abstract interface class GeocodeRepository {
  /// Compat path: full text → resolved coordinates.
  Future<List<GeoPoint>> geocode(String query);

  /// Autocomplete suggestions for [query]. [sessionToken] groups one typing
  /// session (passed through for Google session billing); [bias] is a soft
  /// location preference, never a restriction.
  Future<List<PlaceSuggestion>> suggest(
    String query, {
    String? sessionToken,
    GeoPoint? bias,
  });

  /// Resolve a selected suggestion to real coordinates + formatted address.
  Future<GeoPoint> resolveSuggestion(
    PlaceSuggestion suggestion, {
    String? sessionToken,
  });
}

/// Prayer times for a given day at a given point.
abstract interface class PrayerRepository {
  Future<DayPrayers> dayPrayers({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  });

  /// What the active provider actually supports (methods, school, ...).
  Future<PrayerCapabilities> capabilities();
}

/// Routing: alternatives + optional mosque stops baked into the itinerary.
abstract interface class RouteRepository {
  Future<RouteResponse> plan({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> waypoints = const [],
    required DateTime departUtc,
    required TravelMode mode,
    required PlanningOptions options,
    required PrayerConfig prayer,
    String locale = 'en',
  });
}

/// Multi-day trips.
abstract interface class TripRepository {
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
  });
}

/// Local persistence: settings + last responses (offline honesty).
abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

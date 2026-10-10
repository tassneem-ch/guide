import 'dart:convert';

import '../domain/models.dart';
import '../domain/repositories.dart';
import 'aladhan_service.dart';
import 'local_store.dart';

/// Prayer repository talking to AlAdhan directly from the app.
///
/// AlAdhan requires no API key, so calling it from the client ships no
/// credentials. Used as the app's fallback when the backend is unreachable
/// (or forced via Settings → prayer source).
///
/// Caching mirrors the backend repository: successful responses are cached
/// per request shape (date + coordinates + calculation preferences). When
/// the network fails, the last cached day is served with its original
/// `fetched_at` so the UI can show the "saved copy" indicator — we never
/// fabricate times to cover a failure.
class AladhanPrayerRepository implements PrayerRepository {
  AladhanPrayerRepository(this._service, [this._store]);

  final AladhanService _service;
  final LocalStore? _store;

  String _cacheKey(GeoPoint point, DateTime dateUtc, PrayerConfig config) =>
      cacheKey('aladhan_prayers', {
        'lat': point.lat,
        'lon': point.lon,
        'date': dateUtc.toUtc().toIso8601String(),
        'config': config.toJson(),
      });

  @override
  Future<DayPrayers> dayPrayers({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  }) async {
    final key = _cacheKey(point, dateUtc, config);
    final DayPrayers day;
    try {
      day = await _service.fetchDay(
          point: point, dateUtc: dateUtc, config: config);
      await _store?.write(
          key,
          jsonEncode({
            'fetched_at': DateTime.now().toUtc().toIso8601String(),
            'body': day.toJson(),
          }));
    } on Failure catch (e) {
      if (e.isNetwork && _store != null) {
        final raw = await _store.read(key);
        final cached = raw == null ? null : CacheEnvelope.tryParse(raw);
        if (cached != null) return DayPrayers.fromJson(cached.body);
      }
      rethrow;
    }
    try {
      return await _rolloverIfPassed(day, point, dateUtc, config);
    } on Failure {
      // Today's times above are still real and freshly fetched; if looking
      // up tomorrow fails we keep them rather than hiding good data.
      return day;
    }
  }

  /// If every prayer of the local day already passed, the next upcoming
  /// prayer lives on the following day: fetch it so the countdown shows a
  /// real future instant instead of nothing. Only relevant for "now"-style
  /// queries, never for future journey dates.
  Future<DayPrayers> _rolloverIfPassed(
    DayPrayers day,
    GeoPoint point,
    DateTime dateUtc,
    PrayerConfig config,
  ) async {
    final now = DateTime.now().toUtc();
    final instant = dateUtc.toUtc();
    final hasUpcoming = day.events.any((e) => e.utc.isAfter(now));
    final isNowish = !instant.isAfter(now.add(const Duration(hours: 1)));
    if (!hasUpcoming && isNowish) {
      return _service.fetchDay(
        point: point,
        dateUtc: instant.add(const Duration(days: 1)),
        config: config,
      );
    }
    return day;
  }

  @override
  Future<PrayerCapabilities> capabilities() => _service.capabilities();
}

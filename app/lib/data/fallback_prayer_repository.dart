import '../../domain/models.dart';
import '../../domain/repositories.dart';

/// Prayer data source: backend proxy first, direct AlAdhan second.
///
/// Only *network* failures (backend unreachable) trigger the fallback — a
/// server or validation error is a real answer and must surface untouched.
/// The data itself always carries its own provenance (`source: 'aladhan'`),
/// so nothing here ever disguises where a time came from.
class FallbackPrayerRepository implements PrayerRepository {
  FallbackPrayerRepository({required this.primary, required this.fallback});

  final PrayerRepository primary;
  final PrayerRepository fallback;

  @override
  Future<DayPrayers> dayPrayers({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  }) async {
    try {
      return await primary.dayPrayers(
          point: point, dateUtc: dateUtc, config: config);
    } on Failure catch (e) {
      if (!e.isNetwork) rethrow;
      return fallback.dayPrayers(
          point: point, dateUtc: dateUtc, config: config);
    }
  }

  @override
  Future<PrayerCapabilities> capabilities() async {
    try {
      return await primary.capabilities();
    } on Failure catch (e) {
      if (!e.isNetwork) rethrow;
      return fallback.capabilities();
    }
  }
}

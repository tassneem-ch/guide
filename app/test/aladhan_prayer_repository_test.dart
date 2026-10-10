import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide/data/aladhan_prayer_repository.dart';
import 'package:guide/data/aladhan_service.dart';
import 'package:guide/data/local_store.dart';
import 'package:guide/domain/models.dart';
import 'package:guide/domain/repositories.dart';

/// In-memory [LocalStore] so cache behavior can be asserted without a device.
class FakeStore implements LocalStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

Map<String, dynamic> _payload(String isoDate) => {
      'code': 200,
      'data': {
        'timings': {
          'Fajr': '${isoDate}T04:56:00+00:00',
          'Sunrise': '${isoDate}T06:18:00+00:00',
          'Dhuhr': '${isoDate}T12:06:00+00:00',
          'Asr': '${isoDate}T15:31:00+00:00',
          'Maghrib': '${isoDate}T18:02:00+00:00',
          'Isha': '${isoDate}T19:27:00+00:00',
        },
        'meta': {
          'timezone': 'Europe/Paris',
          'method': {'id': 3, 'name': 'Muslim World League'},
        },
      },
    };

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  bool failWithNetwork = false;
  Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (failWithNetwork) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  const point = GeoPoint(lat: 48.8566, lon: 2.3522, tz: 'Europe/Paris');

  // A date in the future: no day-rollover ambiguity in these assertions.
  final future = DateTime.now().toUtc().add(const Duration(days: 1));
  final isoDate =
      '${future.year.toString().padLeft(4, '0')}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}';

  _FakeAdapter newAdapter() => _FakeAdapter(
        (options) async => _json(_payload(isoDate)),
      )..failWithNetwork = false;

  test('successful fetch is cached by date, coordinates and preferences',
      () async {
    final store = FakeStore();
    final adapter = newAdapter();
    final repo = AladhanPrayerRepository(
      AladhanService(dio: Dio()..httpClientAdapter = adapter),
      store,
    );

    final day = await repo.dayPrayers(
      point: point,
      dateUtc: future,
      config: const PrayerConfig(method: 'mwl', school: 'standard'),
    );

    expect(day.localDate, isoDate);
    expect(store.data, hasLength(1), reason: 'one cache entry written');
    final cached = CacheEnvelope.tryParse(store.data.values.single);
    expect(cached, isNotNull);
    expect(cached!.fetchedAt, isNotNull);
    final body = DayPrayers.fromJson(cached.body);
    expect(body.localDate, isoDate);
    expect(body.events, hasLength(5));
    expect(body.events.first.utc.isUtc, isTrue);
  });

  test('network failure serves the cached day with its original fetch time',
      () async {
    final store = FakeStore();
    final adapter = newAdapter();
    final repo = AladhanPrayerRepository(
      AladhanService(dio: Dio()..httpClientAdapter = adapter),
      store,
    );
    final request = (point: point, dateUtc: future,
        config: const PrayerConfig(method: 'mwl', school: 'standard'));

    final fresh = await repo.dayPrayers(
        point: request.point,
        dateUtc: request.dateUtc,
        config: request.config);
    final fetchedAt = fresh.fetchedAt;
    expect(fetchedAt, isNotNull);

    adapter.failWithNetwork = true; // backend/API now unreachable
    final served = await repo.dayPrayers(
        point: request.point,
        dateUtc: request.dateUtc,
        config: request.config);

    expect(served.localDate, isoDate, reason: 'cached truth, not a guess');
    expect(served.fetchedAt, fetchedAt,
        reason: 'original fetch time kept so the UI can flag "saved copy"');
  });

  test('network failure without cache rethrows the network Failure', () async {
    final store = FakeStore();
    final adapter = newAdapter()..failWithNetwork = true;
    final repo = AladhanPrayerRepository(
      AladhanService(dio: Dio()..httpClientAdapter = adapter),
      store,
    );

    await expectLater(
      repo.dayPrayers(
        point: point,
        dateUtc: future,
        config: const PrayerConfig(),
      ),
      throwsA(isA<Failure>()),
    );
  });

  test('different preferences or coordinates use different cache entries',
      () async {
    final store = FakeStore();
    final adapter = newAdapter();
    final repo = AladhanPrayerRepository(
      AladhanService(dio: Dio()..httpClientAdapter = adapter),
      store,
    );

    await repo.dayPrayers(
        point: point,
        dateUtc: future,
        config: const PrayerConfig(method: 'mwl'));
    await repo.dayPrayers(
        point: point,
        dateUtc: future,
        config: const PrayerConfig(method: 'isna'));
    await repo.dayPrayers(
        point: const GeoPoint(lat: 41.9, lon: 12.5),
        dateUtc: future,
        config: const PrayerConfig(method: 'mwl'));

    expect(store.data, hasLength(3),
        reason: 'cache is keyed by coords + date + config');
  });
}

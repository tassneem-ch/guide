import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guide/data/aladhan_service.dart';
import 'package:guide/domain/models.dart';
import 'package:guide/domain/repositories.dart';

/// Captured-shape AlAdhan response (code/meta/timings) with offset-bearing
/// ISO-8601 timings, exactly like the live API returns them.
Map<String, dynamic> _payload({
  required String date, // yyyy-MM-dd
  String offset = '+01:00',
  String tz = 'Africa/Tunis',
  String fajrSuffix = '04:56:00',
  String dhuhrSuffix = '12:06:00',
  String asrSuffix = '15:31:00',
  String maghribSuffix = '18:02:00',
  String ishaSuffix = '19:27:00',
  String fajrOverride = '',
}) =>
    {
      'code': 200,
      'data': {
        'timings': {
          'Fajr': fajrOverride.isNotEmpty
              ? fajrOverride
              : '${date}T$fajrSuffix$offset',
          'Sunrise': '${date}T06:18:00$offset',
          'Dhuhr': '${date}T$dhuhrSuffix$offset',
          'Asr': '${date}T$asrSuffix$offset',
          'Maghrib': '${date}T$maghribSuffix$offset',
          'Isha': '${date}T$ishaSuffix$offset',
        },
        'meta': {
          'timezone': tz,
          'method': {'id': 18, 'name': 'Tunisia'},
        },
      },
    };

void main() {
  const point = GeoPoint(lat: 36.8065, lon: 10.1815, tz: 'Africa/Tunis');

  group('parseDay', () {
    test('parses iso8601 timings into UTC instants + naive local wall time',
        () {
      final day = AladhanService.parseDay(
        _payload(date: '2026-10-10')['data'] as Map<String, dynamic>,
        requestedDate: DateTime.utc(2026, 10, 10),
        point: point,
        config: const PrayerConfig(method: 'tunisia'),
      );

      expect(day.prayers.events, hasLength(5));
      expect(day.prayers.localDate, '2026-10-10');
      expect(day.prayers.tz, 'Africa/Tunis');
      expect(day.prayers.source, 'aladhan');
      expect(day.prayers.live, isTrue);
      expect(day.offset, const Duration(hours: 1));

      final fajr = day.prayers.events.first;
      expect(fajr.name, PrayerName.fajr);
      expect(fajr.utc, DateTime.utc(2026, 10, 10, 3, 56)); // 04:56 +01:00
      expect(fajr.local, DateTime(2026, 10, 10, 4, 56)); // wall clock there
      expect(fajr.source, 'aladhan');
      expect(fajr.live, isTrue);
      expect(fajr.congregationUtc, isNull); // never invented
    });

    test('negative offsets parse to the right UTC instant', () {
      final day = AladhanService.parseDay(
        _payload(date: '2026-06-10', offset: '-04:00', tz: 'America/New_York')[
            'data'] as Map<String, dynamic>,
        requestedDate: DateTime.utc(2026, 6, 10),
        point: const GeoPoint(lat: 40.7, lon: -74.0),
        config: const PrayerConfig(),
      );
      final fajr = day.prayers.events.first;
      expect(fajr.utc, DateTime.utc(2026, 6, 10, 8, 56)); // 04:56 -04:00
      expect(day.offset, const Duration(hours: -4));
    });

    test('a missing timing ("-----") is a typed failure, never a skip', () {
      expect(
        () => AladhanService.parseDay(
          _payload(date: '2026-06-21', fajrOverride: '-----')[
              'data'] as Map<String, dynamic>,
          requestedDate: DateTime.utc(2026, 6, 21),
          point: const GeoPoint(lat: 69.6, lon: 18.9),
          config: const PrayerConfig(),
        ),
        throwsA(isA<Failure>()),
      );
    });

    test('a timing without a UTC offset is rejected (no device-tz lies)', () {
      expect(
        () => AladhanService.parseDay(
          _payload(date: '2026-10-10', fajrOverride: '2026-10-10T04:56:00')[
              'data'] as Map<String, dynamic>,
          requestedDate: DateTime.utc(2026, 10, 10),
          point: point,
          config: const PrayerConfig(),
        ),
        throwsA(isA<Failure>()),
      );
    });

    test('a payload without timings is a typed failure', () {
      expect(
        () => AladhanService.parseDay(
          const {'code': 200, 'data': {}},
          requestedDate: DateTime.utc(2026, 10, 10),
          point: point,
          config: const PrayerConfig(),
        ),
        throwsA(isA<Failure>()),
      );
    });
  });

  group('parameter mapping', () {
    test('method slugs map to verified numeric ids', () {
      expect(AladhanService.aladhanMethodId('tunisia'), 18);
      expect(AladhanService.aladhanMethodId('mwl'), 3);
      expect(AladhanService.aladhanMethodId('france'), 12);
      expect(AladhanService.aladhanMethodId('umm_al_qura'), 4);
      // Unknown ids fall back exactly like the backend provider does.
      expect(AladhanService.aladhanMethodId('something_else'), 3);
    });

    test('tune follows the documented Fajr,Sunrise,Dhuhr,Asr,Maghrib,Isha order',
        () {
      expect(
        AladhanService.aladhanTuneParam(const {'fajr': 5, 'isha': -10}),
        '5,0,0,0,0,-10',
      );
      expect(AladhanService.aladhanTuneParam(const {}), isNull);
    });
  });

  group('fetchDay (mocked transport)', () {
    Dio dioWith(Future<ResponseBody> Function(RequestOptions) handler) =>
        Dio()..httpClientAdapter = _FakeAdapter(handler);

    test('corrects the requested date when the location offset crosses midnight',
        () async {
      final paths = <String>[];
      final dio = dioWith((options) async {
        paths.add(options.uri.path);
        // Both days return Tunis (+01:00) times.
        final datePart = options.uri.pathSegments.last; // DD-MM-YYYY
        final parts = datePart.split('-');
        final iso = '${parts[2]}-${parts[1]}-${parts[0]}';
        return _json(_payload(date: iso));
      });

      final service = AladhanService(dio: dio);
      // 23:30 UTC = 00:30 next day in Tunis (+01:00).
      final day = await service.fetchDay(
        point: point,
        dateUtc: DateTime.utc(2026, 10, 10, 23, 30),
        config: const PrayerConfig(method: 'tunisia'),
      );

      expect(paths, ['/timings/10-10-2026', '/timings/11-10-2026']);
      expect(day.localDate, '2026-10-11');
      final fajr = day.events.first;
      expect(fajr.utc.isAfter(DateTime.utc(2026, 10, 10, 23, 30)), isTrue);
    });

    test('no correction when the UTC date already matches the local date',
        () async {
      final paths = <String>[];
      final dio = dioWith((options) async {
        paths.add(options.uri.path);
        return _json(_payload(date: '2026-10-10'));
      });

      final service = AladhanService(dio: dio);
      final day = await service.fetchDay(
        point: point,
        dateUtc: DateTime.utc(2026, 10, 10, 12, 0),
        config: const PrayerConfig(),
      );

      expect(paths, ['/timings/10-10-2026']);
      expect(day.localDate, '2026-10-10');
    });

    test('sends the documented query parameters (numeric method, school, tune)',
        () async {
      final captured = <String>[];
      final dio = dioWith((options) async {
        captured.add(options.uri.query);
        return _json(_payload(date: '2026-10-10'));
      });

      final service = AladhanService(dio: dio);
      await service.fetchDay(
        point: point,
        dateUtc: DateTime.utc(2026, 10, 10, 12, 0),
        config: const PrayerConfig(
          method: 'egyptian',
          school: 'hanafi',
          adjustments: {'asr': 20},
        ),
      );

      final query = captured.single;
      expect(query, contains('method=5')); // Egyptian = 5
      expect(query, contains('school=1')); // Hanafi
      expect(query, contains('iso8601=true'));
      expect(query, contains('latitude=36.806500'));
      expect(query, contains('longitude=10.181500'));
      expect(query, contains('tune=0%2C0%2C0%2C20%2C0%2C0')); // 0,0,0,20,0,0
    });

    test('a non-200 payload becomes a typed Failure, not fake times', () async {
      final dio = dioWith((options) async =>
          _json({'code': 400, 'status': 'BAD_REQUEST', 'data': null}));
      final service = AladhanService(dio: dio);
      expect(
        () => service.fetchDay(
          point: point,
          dateUtc: DateTime.utc(2026, 10, 10),
          config: const PrayerConfig(),
        ),
        throwsA(isA<Failure>()),
      );
    });

    test('a transport error maps to a network Failure', () async {
      final dio = dioWith((options) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ));
      final service = AladhanService(dio: dio);
      try {
        await service.fetchDay(
          point: point,
          dateUtc: DateTime.utc(2026, 10, 10),
          config: const PrayerConfig(),
        );
        fail('expected a Failure');
      } on Failure catch (e) {
        expect(e.isNetwork, isTrue);
      }
    });
  });

  test('capabilities advertise the worldwide method set and honest limits', () async {
    final caps = await AladhanService().capabilities();
    expect(caps.live, isTrue);
    final ids = caps.methods.map((m) => m.id).toSet();
    expect(ids.containsAll({'mwl', 'isna', 'egyptian', 'tunisia', 'france',
      'dubai', 'umm_al_qura'}), isTrue);
    expect(caps.highLatitudeRules, isEmpty); // API has no rule selector
    expect(caps.manualAdjustments, isTrue);
  });
}

ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

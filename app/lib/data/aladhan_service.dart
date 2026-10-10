import 'package:dio/dio.dart';

import '../../domain/models.dart';
import '../../domain/repositories.dart';

/// Numeric AlAdhan method ids, verified against the provider's own catalog
/// (`GET https://api.aladhan.com/v1/methods`). The API's *string* ids are
/// NOT usable in the timings endpoint — unknown values silently fall back to
/// ISNA — so only these numeric ids are ever sent.
const Map<String, int> kAladhanMethodIds = <String, int>{
  'mwl': 3,
  'isna': 2,
  'egyptian': 5,
  'umm_al_qura': 4,
  'karachi': 1,
  'tehran': 7,
  'gulf': 8,
  'kuwait': 9,
  'qatar': 10,
  'singapore': 11,
  'france': 12,
  'turkey': 13,
  'russia': 14,
  'moon_sighting': 15,
  'dubai': 16,
  'jakim': 17,
  'tunisia': 18,
  'algeria': 19,
  'kemenag': 20,
  'morocco': 21,
  'portugal': 22,
  'jordan': 23,
};

const Map<String, String> kAladhanMethodLabels = <String, String>{
  'mwl': 'Muslim World League',
  'isna': 'ISNA (North America)',
  'egyptian': 'Egyptian General Authority of Survey',
  'umm_al_qura': 'Umm al-Qura University, Makkah',
  'karachi': 'University of Islamic Sciences, Karachi',
  'tehran': 'Institute of Geophysics, University of Tehran',
  'gulf': 'Gulf region',
  'kuwait': 'Kuwait',
  'qatar': 'Qatar',
  'singapore': 'Majlis Ugama Islam Singapura',
  'france': 'Union des Organisations Islamiques de France',
  'turkey': 'Diyanet Isleri Baskanligi, Turkey',
  'russia': 'Spiritual Administration of Muslims of Russia',
  'moon_sighting': 'Moonsighting Committee Worldwide',
  'dubai': 'Dubai',
  'jakim': 'Jabatan Kemajuan Islam Malaysia (JAKIM)',
  'tunisia': 'Tunisia',
  'algeria': 'Algeria',
  'kemenag': 'Kementerian Agama Republik Indonesia',
  'morocco': 'Morocco',
  'portugal': 'Comunidade Islamica de Lisboa',
  'jordan': 'Ministry of Awqaf, Islamic Affairs and Holy Places, Jordan',
};

/// Prayer times parsed from one AlAdhan response, plus the location's UTC
/// offset (learned from the ISO-8601 timings — needed to decide which local
/// calendar day an instant falls on without any device timezone).
class AladhanDay {
  const AladhanDay({required this.prayers, required this.offset});

  final DayPrayers prayers;
  final Duration offset;
}

/// Direct client for the AlAdhan prayer-times API (no API key required).
///
/// Docs: https://aladhan.com/prayer-times-api
///
/// Contract used: `GET /timings/{DD-MM-YYYY}?latitude=&longitude=&method=`
/// (numeric id) `&school=&iso8601=true` (+ optional `tune`, `midnightMode`).
/// Times arrive as offset-aware ISO-8601 strings; the calendar-day question
/// ("which date is it *there*") is answered from the response's own offset,
/// never from the phone's timezone. Failures raise a typed [Failure] — a
/// missing timing (e.g. "-----" in polar regions) is an error, never a
/// silently skipped prayer.
class AladhanService {
  AladhanService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.aladhan.com/v1',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const {'Accept': 'application/json'},
            ));

  final Dio _dio;

  /// Fetch prayer times for the local calendar day that [dateUtc] falls on
  /// at [point]. One correction request is made when the location's offset
  /// crosses a day boundary relative to the naive UTC date.
  Future<DayPrayers> fetchDay({
    required GeoPoint point,
    required DateTime dateUtc,
    required PrayerConfig config,
  }) async {
    final instant = dateUtc.toUtc();
    var result = await _fetchFor(
      date: DateTime.utc(instant.year, instant.month, instant.day),
      point: point,
      config: config,
    );
    final localNow = instant.add(result.offset);
    if (_dayKey(localNow) != result.prayers.localDate) {
      result = await _fetchFor(
        date: DateTime.utc(localNow.year, localNow.month, localNow.day),
        point: point,
        config: config,
      );
    }
    return result.prayers;
  }

  Future<AladhanDay> _fetchFor({
    required DateTime date,
    required GeoPoint point,
    required PrayerConfig config,
  }) async {
    final params = <String, dynamic>{
      'latitude': point.lat.toStringAsFixed(6),
      'longitude': point.lon.toStringAsFixed(6),
      'method': aladhanMethodId(config.method),
      'school': config.school == 'hanafi' ? 1 : 0,
      'iso8601': 'true',
    };
    if (config.midnightMode == 'standard' ||
        config.midnightMode == 'umm_al_qura') {
      params['midnightMode'] = config.midnightMode;
    }
    final tune = aladhanTuneParam(config.adjustments);
    if (tune != null) params['tune'] = tune;

    final path = '/timings/${_two(date.day)}-${_two(date.month)}-${date.year}';
    Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(path, queryParameters: params);
    } on DioException catch (e) {
      throw mapDioFailure(e);
    }
    final body = response.data;
    if (body == null || body['code'] != 200 || body['data'] is! Map) {
      throw Failure(
        'AlAdhan returned an error payload',
        kind: FailureKind.server,
        detail: body?.toString(),
      );
    }
    return parseDay(
      body['data'] as Map<String, dynamic>,
      requestedDate: date,
      point: point,
      config: config,
    );
  }

  /// What the AlAdhan provider actually supports (mirrors the backend's
  /// capabilities for the same provider — the app offers exactly this).
  Future<PrayerCapabilities> capabilities() async => PrayerCapabilities(
        provider: 'aladhan (direct)',
        live: true,
        methods: [
          for (final entry in kAladhanMethodLabels.entries)
            MethodOption(id: entry.key, label: entry.value),
        ],
        schools: const ['standard', 'hanafi'],
        // The API exposes no high-latitude rule selector; manual per-prayer
        // adjustments are the supported escape hatch in polar regions.
        highLatitudeRules: const [],
        manualAdjustments: true,
        supportsFutureDates: true,
        notes: const [
          'Times are calculated by the provider for the given coordinates '
              'and local date; congregation (iqama) times are never inferred.',
          'Direct AlAdhan mode: requests bypass the Guide backend.',
        ],
      );

  /// Parse one AlAdhan `data` payload into our domain types.
  ///
  /// Exposed (static) so tests can feed captured responses without HTTP.
  static AladhanDay parseDay(
    Map<String, dynamic> data, {
    required DateTime requestedDate,
    required GeoPoint point,
    required PrayerConfig config,
  }) {
    final meta = data['meta'] is Map ? data['meta'] as Map : const {};
    final tzName =
        (meta['timezone'] as String?) ?? point.tz ?? 'UTC';
    final timings = data['timings'];
    if (timings is! Map) {
      throw const Failure('AlAdhan response missing timings',
          kind: FailureKind.server);
    }

    Duration? offset;
    final events = <PrayerEvent>[];
    for (final name in PrayerName.values) {
      final raw = timings[_timingKey(name)];
      if (raw is! String || raw.trim().isEmpty || raw.contains('-----')) {
        // High-latitude days genuinely have no Fajr/Isha — surface it.
        throw Failure(
          'AlAdhan returned no time for ${name.name} on this date '
          '(common near the polar circles — try manual adjustments)',
          kind: FailureKind.server,
          detail: raw?.toString(),
        );
      }
      final parsed = _parseIsoTiming(raw.trim());
      offset ??= parsed.offset;
      events.add(PrayerEvent(
        name: name,
        utc: parsed.utc,
        local: parsed.local,
        tz: tzName,
        localDate: _dayKey(parsed.local),
        method: config.method,
        school: config.school,
        source: 'aladhan',
        live: true,
      ));
    }

    return AladhanDay(
      prayers: DayPrayers(
        location: point,
        localDate: events.first.localDate,
        tz: tzName,
        events: events,
        source: 'aladhan',
        live: true,
        fetchedAt: DateTime.now().toUtc(),
      ),
      offset: offset ?? Duration.zero,
    );
  }

  /// Map a Dio transport problem to the app's typed [Failure].
  static Failure mapDioFailure(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return Failure('AlAdhan unreachable: ${e.message ?? 'network error'}',
            kind: FailureKind.network, statusCode: e.response?.statusCode);
      case DioExceptionType.badResponse:
        return Failure('AlAdhan error ${e.response?.statusCode ?? ''}',
            kind: FailureKind.server, statusCode: e.response?.statusCode);
      case DioExceptionType.cancel:
        return const Failure('Request cancelled', kind: FailureKind.network);
      case DioExceptionType.badCertificate:
        return const Failure('TLS certificate rejected',
            kind: FailureKind.network);
      case DioExceptionType.transformTimeout:
      case DioExceptionType.unknown:
        return Failure('AlAdhan request failed: ${e.message ?? 'unknown'}',
            kind: FailureKind.network);
    }
  }

  /// `method` query value: our slug → AlAdhan numeric id. Unknown slugs fall
  /// back to MWL exactly like the backend provider does.
  static int aladhanMethodId(String method) => kAladhanMethodIds[method] ?? 3;

  /// AlAdhan `tune` parameter: minutes per prayer in the order
  /// Fajr, Sunrise(0), Dhuhr, Asr, Maghrib, Isha. Null when nothing tuned.
  static String? aladhanTuneParam(Map<String, int> adjustments) {
    if (adjustments.isEmpty) return null;
    int minutes(PrayerName n) => adjustments[n.name] ?? 0;
    return '${minutes(PrayerName.fajr)},0,${minutes(PrayerName.dhuhr)},'
        '${minutes(PrayerName.asr)},${minutes(PrayerName.maghrib)},'
        '${minutes(PrayerName.isha)}';
  }

  static String _timingKey(PrayerName name) {
    switch (name) {
      case PrayerName.fajr:
        return 'Fajr';
      case PrayerName.dhuhr:
        return 'Dhuhr';
      case PrayerName.asr:
        return 'Asr';
      case PrayerName.maghrib:
        return 'Maghrib';
      case PrayerName.isha:
        return 'Isha';
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
}

class _ParsedTiming {
  const _ParsedTiming({required this.utc, required this.local, required this.offset});

  final DateTime utc;
  final DateTime local; // naive wall-clock at the location
  final Duration offset;
}

/// Parse an `iso8601=true` timing ("2026-10-10T04:56:00+01:00") into the
/// UTC instant + the location's wall-clock rendering.
///
/// The wall components and the UTC offset are read straight from the string.
/// Dart's `DateTime.parse` normalizes an offset-bearing string into the
/// *device's* zone (the instant stays right, but the wall components and
/// `timeZoneOffset` become the machine's) — exactly the timezone lie this
/// app must never make. A value without an explicit offset fails honestly.
_ParsedTiming _parseIsoTiming(String raw) {
  final withoutSuffix =
      raw.contains('(') ? raw.substring(0, raw.indexOf('(')).trim() : raw;
  final match = RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?'
          r'(?:\.\d+)?([+-])(\d{2}):?(\d{2})$')
      .firstMatch(withoutSuffix);
  if (match == null) {
    throw Failure('Unparseable prayer time from provider: $raw',
        kind: FailureKind.server, detail: raw);
  }
  final wall = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
  final sign = match.group(7) == '-' ? -1 : 1;
  final offset = Duration(
    hours: int.parse(match.group(8)!) * sign,
    minutes: int.parse(match.group(9)!) * sign,
  );
  // UTC instant = written wall time minus its offset; constructed on the
  // UTC timeline so the device's zone can never influence the result.
  final utc = DateTime.utc(
    wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second,
  ).subtract(offset);
  return _ParsedTiming(utc: utc, local: wall, offset: offset);
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/repositories.dart';

/// SharedPreferences-backed local store for settings and cached responses.
class PrefsLocalStore implements LocalStore {
  PrefsLocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsLocalStore> open() async =>
      PrefsLocalStore(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
}

/// Cached JSON envelope with fetch time — used to serve stale data honestly
/// when the backend is unreachable.
class CacheEnvelope {
  const CacheEnvelope({required this.fetchedAt, required this.body});

  final DateTime fetchedAt;
  final Map<String, dynamic> body;

  Map<String, dynamic> toJson() => {
        'fetched_at': fetchedAt.toUtc().toIso8601String(),
        'body': body,
      };

  static CacheEnvelope? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.tryParse(decoded['fetched_at'] as String? ?? '');
      final body = decoded['body'];
      if (fetchedAt == null || body is! Map<String, dynamic>) return null;
      return CacheEnvelope(fetchedAt: fetchedAt, body: body);
    } catch (_) {
      return null;
    }
  }
}

/// Key builder that keeps cache entries per request shape.
String cacheKey(String prefix, Map<String, dynamic> params) {
  final canonical = jsonEncode(
    params.map((k, v) => MapEntry(k, v is DateTime ? v.toIso8601String() : v))
      .entries
      .toList()
      ..sort((a, b) => a.key.compareTo(b.key)),
  );
  return '$prefix:${base64Url.encode(utf8.encode(canonical))}';
}

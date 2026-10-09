import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/api_repositories.dart';
import '../data/mock_repositories.dart';
import '../domain/models.dart';
import '../domain/repositories.dart';

/// Default backend base URL per platform. Overridable in Settings or via
/// `--dart-define=BACKEND_URL=...` at build time (never a secret — this is a
/// public endpoint address; provider API keys stay server-side only).
const String kDefaultBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://10.0.2.2:8000', // Android emulator loopback alias
);

class AppSettings {
  const AppSettings({
    this.localeCode = 'system',
    this.themeMode = 'system',
    this.use24h = true,
    this.metric = true,
    this.prayer = const PrayerConfig(),
    this.maxDetourMin = 25,
    this.stopDurationMin = 15,
    this.planningWindowMin = 30,
    this.prayerBufferMin = 10,
    this.prayerStops = 'optional',
    this.preference = RoutePreference.balanced,
    this.prayerStopReminders = false,
    this.backendUrl = kDefaultBackendUrl,
    this.demoMode = false,
  });

  final String localeCode; // system | en | ar | fr
  final String themeMode; // system | light | dark
  final bool use24h;
  final bool metric;
  final PrayerConfig prayer;
  final int maxDetourMin;
  final int stopDurationMin;
  final int planningWindowMin;
  final int prayerBufferMin;
  final String prayerStops;
  final RoutePreference preference;
  final bool prayerStopReminders;
  final String backendUrl;
  final bool demoMode;

  Locale? get locale => localeCode == 'system' ? null : Locale(localeCode);

  PlanningOptions toPlanningOptions() => PlanningOptions(
        preference: preference,
        maxDetourMin: maxDetourMin,
        stopDurationMin: stopDurationMin,
        planningWindowMin: planningWindowMin,
        prayerBufferMin: prayerBufferMin,
        prayerStops: prayerStops,
      );

  AppSettings copyWith({
    String? localeCode,
    String? themeMode,
    bool? use24h,
    bool? metric,
    PrayerConfig? prayer,
    int? maxDetourMin,
    int? stopDurationMin,
    int? planningWindowMin,
    int? prayerBufferMin,
    String? prayerStops,
    RoutePreference? preference,
    bool? prayerStopReminders,
    String? backendUrl,
    bool? demoMode,
  }) =>
      AppSettings(
        localeCode: localeCode ?? this.localeCode,
        themeMode: themeMode ?? this.themeMode,
        use24h: use24h ?? this.use24h,
        metric: metric ?? this.metric,
        prayer: prayer ?? this.prayer,
        maxDetourMin: maxDetourMin ?? this.maxDetourMin,
        stopDurationMin: stopDurationMin ?? this.stopDurationMin,
        planningWindowMin: planningWindowMin ?? this.planningWindowMin,
        prayerBufferMin: prayerBufferMin ?? this.prayerBufferMin,
        prayerStops: prayerStops ?? this.prayerStops,
        preference: preference ?? this.preference,
        prayerStopReminders: prayerStopReminders ?? this.prayerStopReminders,
        backendUrl: backendUrl ?? this.backendUrl,
        demoMode: demoMode ?? this.demoMode,
      );

  Map<String, dynamic> toJson() => {
        'localeCode': localeCode,
        'themeMode': themeMode,
        'use24h': use24h,
        'metric': metric,
        'prayer': prayer.toJson(),
        'maxDetourMin': maxDetourMin,
        'stopDurationMin': stopDurationMin,
        'planningWindowMin': planningWindowMin,
        'prayerBufferMin': prayerBufferMin,
        'prayerStops': prayerStops,
        'preference': routePreferenceTo(preference),
        'prayerStopReminders': prayerStopReminders,
        'backendUrl': backendUrl,
        'demoMode': demoMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final prayerJson = json['prayer'];
    return AppSettings(
      localeCode: json['localeCode'] as String? ?? 'system',
      themeMode: json['themeMode'] as String? ?? 'system',
      use24h: json['use24h'] as bool? ?? true,
      metric: json['metric'] as bool? ?? true,
      prayer: prayerJson is Map<String, dynamic>
          ? PrayerConfig(
              method: prayerJson['method'] as String? ?? 'mwl',
              school: prayerJson['school'] as String? ?? 'standard',
              highLatitudeRule: prayerJson['high_latitude_rule'] as String? ??
                  'middle_of_the_night',
              adjustments: (prayerJson['adjustments'] as Map?)
                      ?.map((k, v) =>
                          MapEntry(k.toString(), (v as num).toInt())) ??
                  const {},
              midnightMode:
                  prayerJson['midnight_mode'] as String? ?? 'standard',
            )
          : const PrayerConfig(),
      maxDetourMin: json['maxDetourMin'] as int? ?? 25,
      stopDurationMin: json['stopDurationMin'] as int? ?? 15,
      planningWindowMin: json['planningWindowMin'] as int? ?? 30,
      prayerBufferMin: json['prayerBufferMin'] as int? ?? 10,
      prayerStops: json['prayerStops'] as String? ?? 'optional',
      preference: routePreferenceFrom(json['preference'] as String? ?? 'balanced'),
      prayerStopReminders: json['prayerStopReminders'] as bool? ?? false,
      backendUrl: json['backendUrl'] as String? ?? kDefaultBackendUrl,
      demoMode: json['demoMode'] as bool? ?? false,
    );
  }
}

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final store = ref.read(localStoreProvider);
    final raw = store.read('settings');
    raw.then((value) {
      if (value != null) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map<String, dynamic>) {
            state = AppSettings.fromJson(decoded);
          }
        } catch (_) {
          // Corrupt settings: keep defaults rather than crash.
        }
      }
    });
    return const AppSettings();
  }

  Future<void> update(AppSettings Function(AppSettings) transform) async {
    state = transform(state);
    await ref
        .read(localStoreProvider)
        .write('settings', jsonEncode(state.toJson()));
  }

  void setLocale(String code) => update((s) => s.copyWith(localeCode: code));
  void setThemeMode(String mode) => update((s) => s.copyWith(themeMode: mode));
  void setUse24h(bool v) => update((s) => s.copyWith(use24h: v));
  void setMetric(bool v) => update((s) => s.copyWith(metric: v));
  void setDemoMode(bool v) => update((s) => s.copyWith(demoMode: v));
  void setBackendUrl(String url) => update((s) => s.copyWith(backendUrl: url));
  void setPrayerStopReminders(bool v) =>
      update((s) => s.copyWith(prayerStopReminders: v));

  void setPrayerMethod(String method, {bool? supportsAdjustments}) =>
      update((s) => s.copyWith(
            prayer: PrayerConfig(
              method: method,
              school: s.prayer.school,
              highLatitudeRule: s.prayer.highLatitudeRule,
              adjustments: supportsAdjustments == false
                  ? const {}
                  : s.prayer.adjustments,
              midnightMode: s.prayer.midnightMode,
            ),
          ));

  void setAsrSchool(String school) => update((s) => s.copyWith(
        prayer: PrayerConfig(
          method: s.prayer.method,
          school: school,
          highLatitudeRule: s.prayer.highLatitudeRule,
          adjustments: s.prayer.adjustments,
          midnightMode: s.prayer.midnightMode,
        ),
      ));

  void setHighLatitudeRule(String rule) => update((s) => s.copyWith(
        prayer: PrayerConfig(
          method: s.prayer.method,
          school: s.prayer.school,
          highLatitudeRule: rule,
          adjustments: s.prayer.adjustments,
          midnightMode: s.prayer.midnightMode,
        ),
      ));

  void setAdjustment(String prayerName, int minutes) =>
      update((s) => s.copyWith(
            prayer: PrayerConfig(
              method: s.prayer.method,
              school: s.prayer.school,
              highLatitudeRule: s.prayer.highLatitudeRule,
              adjustments: {
                ...s.prayer.adjustments,
                prayerName: minutes,
              }..removeWhere((_, v) => v == 0),
              midnightMode: s.prayer.midnightMode,
            ),
          ));

  void setPlanning({
    int? maxDetourMin,
    int? stopDurationMin,
    int? planningWindowMin,
    int? prayerBufferMin,
    String? prayerStops,
    RoutePreference? preference,
  }) =>
      update((s) => s.copyWith(
            maxDetourMin: maxDetourMin,
            stopDurationMin: stopDurationMin,
            planningWindowMin: planningWindowMin,
            prayerBufferMin: prayerBufferMin,
            prayerStops: prayerStops,
            preference: preference,
          ));
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider must be overridden in main()');
});

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

final guideApiProvider = Provider<GuideApi>((ref) {
  final url = ref.watch(settingsProvider.select((s) => s.backendUrl));
  return GuideApi(baseUrl: url);
});

/// The active repository set — demo fixtures when demo mode is on, otherwise
/// the real backend. This is the single switch point for data honesty.
final repositoriesProvider = Provider<Repositories>((ref) {
  final demo = ref.watch(settingsProvider.select((s) => s.demoMode));
  if (demo) {
    return Repositories(
      geocode: MockGeocodeRepository(),
      prayer: MockPrayerRepository(),
      route: MockRouteRepository(),
      trip: MockTripRepository(),
      fixtureMode: true,
    );
  }
  final api = ref.watch(guideApiProvider);
  final store = ref.watch(localStoreProvider);
  return Repositories(
    geocode: ApiGeocodeRepository(api, store),
    prayer: ApiPrayerRepository(api, store),
    route: ApiRouteRepository(api, store),
    trip: ApiTripRepository(api, store),
    fixtureMode: false,
  );
});

class Repositories {
  const Repositories({
    required this.geocode,
    required this.prayer,
    required this.route,
    required this.trip,
    required this.fixtureMode,
  });

  final GeocodeRepository geocode;
  final PrayerRepository prayer;
  final RouteRepository route;
  final TripRepository trip;
  final bool fixtureMode;
}

/// Prayer provider capabilities from the backend (capabilities-driven UI).
final prayerCapabilitiesProvider = FutureProvider<PrayerCapabilities>((ref) async {
  final repos = ref.watch(repositoriesProvider);
  return repos.prayer.capabilities();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'settings.dart';

// ---------------------------------------------------------------------------
// Home planner form state
// ---------------------------------------------------------------------------

class PlannerForm {
  const PlannerForm({
    this.origin,
    this.destination,
    this.waypoints = const [],
    this.departNow = true,
    this.departUtc,
    this.mode = TravelMode.driving,
  });

  final GeoPoint? origin;
  final GeoPoint? destination;
  final List<GeoPoint> waypoints;
  final bool departNow;
  final DateTime? departUtc;
  final TravelMode mode;

  PlannerForm copyWith({
    GeoPoint? origin,
    GeoPoint? destination,
    List<GeoPoint>? waypoints,
    bool? departNow,
    DateTime? departUtc,
    TravelMode? mode,
    bool clearOrigin = false,
    bool clearDestination = false,
  }) =>
      PlannerForm(
        origin: clearOrigin ? null : origin ?? this.origin,
        destination: clearDestination ? null : destination ?? this.destination,
        waypoints: waypoints ?? this.waypoints,
        departNow: departNow ?? this.departNow,
        departUtc: departUtc ?? this.departUtc,
        mode: mode ?? this.mode,
      );
}

class PlannerController extends Notifier<PlannerForm> {
  @override
  PlannerForm build() => const PlannerForm();

  void setOrigin(GeoPoint? point) =>
      state = state.copyWith(origin: point, clearOrigin: point == null);
  void setDestination(GeoPoint? point) =>
      state = state.copyWith(destination: point, clearDestination: point == null);
  void setMode(TravelMode mode) => state = state.copyWith(mode: mode);
  void setDepartNow(bool now) => state = state.copyWith(departNow: now);
  void setDepartUtc(DateTime time) =>
      state = state.copyWith(departNow: false, departUtc: time);

  void addWaypoint(GeoPoint point) =>
      state = state.copyWith(waypoints: [...state.waypoints, point]);
  void removeWaypoint(int index) {
    final wps = [...state.waypoints]..removeAt(index);
    state = state.copyWith(waypoints: wps);
  }

  void swap() {
    final o = state.origin;
    final d = state.destination;
    state = state.copyWith(origin: d, destination: o);
  }
}

final plannerProvider =
    NotifierProvider<PlannerController, PlannerForm>(PlannerController.new);

// ---------------------------------------------------------------------------
// Route planning result
// ---------------------------------------------------------------------------

class RouteController extends AsyncNotifier<RouteResponse?> {
  @override
  RouteResponse? build() => null;

  Future<void> plan({
    required GeoPoint origin,
    required GeoPoint destination,
    List<GeoPoint> waypoints = const [],
    DateTime? departUtc,
    required TravelMode mode,
  }) async {
    final settings = ref.read(settingsProvider);
    final repos = ref.read(repositoriesProvider);
    final depart = departUtc ?? DateTime.now().toUtc();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => repos.route.plan(
          origin: origin,
          destination: destination,
          waypoints: waypoints,
          departUtc: depart,
          mode: mode,
          options: settings.toPlanningOptions(),
          prayer: settings.prayer,
          locale: settings.localeCode,
        ));
  }

  void clear() => state = const AsyncData(null);
}

final routeProvider =
    AsyncNotifierProvider<RouteController, RouteResponse?>(RouteController.new);

// ---------------------------------------------------------------------------
// Geocoding is handled directly by PlaceField (debounced), no global query.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Prayer times for the home card
// ---------------------------------------------------------------------------

final prayerTimesProvider = FutureProvider<DayPrayers>((ref) async {
  final form = ref.watch(plannerProvider);
  final settings = ref.watch(settingsProvider);
  final point = form.origin ?? form.destination;
  if (point == null) {
    throw StateError('no_point_selected');
  }
  final repos = ref.watch(repositoriesProvider);
  return repos.prayer.dayPrayers(
    point: point,
    dateUtc: DateTime.now().toUtc(),
    config: settings.prayer,
  );
});

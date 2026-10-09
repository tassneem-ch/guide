import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import 'settings.dart';

/// Trip planner form + execution.
class TripForm {
  const TripForm({
    this.title = '',
    this.origin,
    this.destination,
    this.departUtc,
    this.days = 3,
    this.activities = const [],
    this.overnight = true,
    this.paceMinPerDay = 240,
  });

  final String title;
  final GeoPoint? origin;
  final GeoPoint? destination;
  final DateTime? departUtc;
  final int days;
  final List<ActivityItem> activities;
  final bool overnight;
  final int paceMinPerDay;

  TripForm copyWith({
    String? title,
    GeoPoint? origin,
    GeoPoint? destination,
    DateTime? departUtc,
    int? days,
    List<ActivityItem>? activities,
    bool? overnight,
    int? paceMinPerDay,
    bool clearOrigin = false,
    bool clearDestination = false,
    bool clearDepart = false,
  }) =>
      TripForm(
        title: title ?? this.title,
        origin: clearOrigin ? null : origin ?? this.origin,
        destination: clearDestination ? null : destination ?? this.destination,
        departUtc: clearDepart ? null : departUtc ?? this.departUtc,
        days: days ?? this.days,
        activities: activities ?? this.activities,
        overnight: overnight ?? this.overnight,
        paceMinPerDay: paceMinPerDay ?? this.paceMinPerDay,
      );
}

class TripController extends Notifier<TripForm> {
  @override
  TripForm build() => const TripForm();

  void setTitle(String v) => state = state.copyWith(title: v);
  void setOrigin(GeoPoint? p) =>
      state = state.copyWith(origin: p, clearOrigin: p == null);
  void setDestination(GeoPoint? p) =>
      state = state.copyWith(destination: p, clearDestination: p == null);
  void setDepart(DateTime? d) =>
      state = state.copyWith(departUtc: d, clearDepart: d == null);
  void setDays(int d) => state = state.copyWith(days: d.clamp(1, 21));
  void setOvernight(bool v) => state = state.copyWith(overnight: v);
  void setPace(int v) => state = state.copyWith(paceMinPerDay: v);

  void addActivity(ActivityItem item) =>
      state = state.copyWith(activities: [...state.activities, item]);
  void removeActivity(int index) {
    final acts = [...state.activities]..removeAt(index);
    state = state.copyWith(activities: acts);
  }

  void setActivityDay(int index, int dayIndex) {
    final acts = [...state.activities];
    final old = acts[index];
    acts[index] = ActivityItem(
      id: old.id,
      name: old.name,
      location: old.location,
      plannedDurationMin: old.plannedDurationMin,
      earliestStartLocal: old.earliestStartLocal,
      latestStartLocal: old.latestStartLocal,
      locked: old.locked,
      dayIndex: dayIndex,
    );
    state = state.copyWith(activities: acts);
  }
}

final tripProvider = NotifierProvider<TripController, TripForm>(TripController.new);

class TripResultController extends AsyncNotifier<TripPlan?> {
  @override
  TripPlan? build() => null;

  Future<bool> plan() async {
    final form = ref.read(tripProvider);
    final origin = form.origin;
    final destination = form.destination;
    if (origin == null || destination == null) return false;
    final settings = ref.read(settingsProvider);
    final repos = ref.read(repositoriesProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => repos.trip.plan(
          title: form.title,
          origin: origin,
          destination: destination,
          departUtc: form.departUtc ?? DateTime.now().toUtc(),
          days: form.days,
          activities: form.activities,
          overnight: form.overnight,
          paceMinPerDay: form.paceMinPerDay,
          options: settings.toPlanningOptions(),
          prayer: settings.prayer,
          locale: settings.localeCode,
        ));
    state = result;
    return !result.hasError;
  }

  void clear() => state = const AsyncData(null);
}

final tripResultProvider =
    AsyncNotifierProvider<TripResultController, TripPlan?>(
        TripResultController.new);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/planner.dart';
import '../../application/settings.dart';
import '../../core/format.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/common.dart';
import '../widgets/place_field.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _planning = false;

  Future<void> _plan() async {
    final form = ref.read(plannerProvider);
    final origin = form.origin;
    final destination = form.destination;
    final l10n = AppLocalizations.of(context);
    if (origin == null || destination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.requiredField)),
      );
      return;
    }
    setState(() => _planning = true);
    await ref.read(routeProvider.notifier).plan(
          origin: origin,
          destination: destination,
          waypoints: form.waypoints,
          departUtc: form.departNow ? null : form.departUtc,
          mode: form.mode,
        );
    if (!mounted) return;
    setState(() => _planning = false);
    final state = ref.read(routeProvider);
    if (state.hasError) {
      final err = state.error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err is Failure ? err.message : l10n.errorGeneric)),
      );
      return;
    }
    context.push('/route');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(plannerProvider);
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            tooltip: l10n.tripTitle,
            icon: const Icon(Icons.luggage_outlined),
            onPressed: () => context.push('/trip'),
          ),
          IconButton(
            tooltip: l10n.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FixtureBanner(),
          const SizedBox(height: 8),

          // --- planner form -------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PlaceField(
                    label: l10n.fromLabel,
                    icon: Icons.trip_origin_outlined,
                    initial: form.origin,
                    onSelected: (p) =>
                        ref.read(plannerProvider.notifier).setOrigin(p),
                  ),
                  Row(
                    children: [
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: l10n.swapButton,
                        icon: const Icon(Icons.swap_vert),
                        onPressed:
                            ref.read(plannerProvider.notifier).swap,
                      ),
                      const Spacer(),
                    ],
                  ),
                  PlaceField(
                    label: l10n.toLabel,
                    icon: Icons.place_outlined,
                    initial: form.destination,
                    onSelected: (p) =>
                        ref.read(plannerProvider.notifier).setDestination(p),
                  ),

                  // waypoints
                  for (var i = 0; i < form.waypoints.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l10n.waypoint(i + 1)}: '
                              '${form.waypoints[i].name ?? ''}',
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.delete,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => ref
                                .read(plannerProvider.notifier)
                                .removeWaypoint(i),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _showWaypointSheet(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.addWaypoint),
                    ),
                  ),

                  const Divider(height: 24),

                  // departure
                  Row(
                    children: [
                      Expanded(child: Text(l10n.departureTime)),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: true, label: Text(l10n.departNow)),
                          ButtonSegment(value: false, label: Text(l10n.chooseTime)),
                        ],
                        selected: {form.departNow},
                        onSelectionChanged: (sel) {
                          if (sel.first) {
                            ref
                                .read(plannerProvider.notifier)
                                .setDepartNow(true);
                          } else {
                            _pickDepartTime();
                          }
                        },
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _useMyLocation,
                      icon: const Icon(Icons.my_location, size: 16),
                      label: Text(l10n.useMyLocation),
                    ),
                  ),
                  if (!form.departNow && form.departUtc != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        formatDateTime(context, form.departUtc!.toLocal(),
                            use24h: settings.use24h),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),

                  const SizedBox(height: 12),

                  // travel mode
                  Text(l10n.travelMode,
                      style: Theme.of(context).textTheme.labelLarge),
                  SegmentedButton<TravelMode>(
                    segments: [
                      ButtonSegment(
                          value: TravelMode.driving,
                          icon: const Icon(Icons.directions_car, size: 18),
                          label: Text(l10n.modeDriving)),
                      ButtonSegment(
                          value: TravelMode.cycling,
                          icon: const Icon(Icons.directions_bike, size: 18),
                          label: Text(l10n.modeCycling)),
                      ButtonSegment(
                          value: TravelMode.walking,
                          icon: const Icon(Icons.directions_walk, size: 18),
                          label: Text(l10n.modeWalking)),
                    ],
                    selected: {form.mode},
                    onSelectionChanged: (sel) => ref
                        .read(plannerProvider.notifier)
                        .setMode(sel.first),
                  ),

                  const SizedBox(height: 12),

                  // preference + prayer stops
                  Text(l10n.preference,
                      style: Theme.of(context).textTheme.labelLarge),
                  SegmentedButton<RoutePreference>(
                    segments: [
                      ButtonSegment(
                          value: RoutePreference.fastest,
                          label: Text(l10n.prefFastest)),
                      ButtonSegment(
                          value: RoutePreference.balanced,
                          label: Text(l10n.prefBalanced)),
                      ButtonSegment(
                          value: RoutePreference.prayerFriendly,
                          label: Text(l10n.prefPrayerFriendly)),
                    ],
                    selected: {settings.preference},
                    onSelectionChanged: (sel) => ref
                        .read(settingsProvider.notifier)
                        .setPlanning(preference: sel.first),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.prayerStopsLabel,
                      style: Theme.of(context).textTheme.labelLarge),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                          value: 'mandatory', label: Text(l10n.stopsMandatory)),
                      ButtonSegment(
                          value: 'optional', label: Text(l10n.stopsOptional)),
                      ButtonSegment(value: 'none', label: Text(l10n.stopsNone)),
                    ],
                    selected: {settings.prayerStops},
                    onSelectionChanged: (sel) => ref
                        .read(settingsProvider.notifier)
                        .setPlanning(prayerStops: sel.first),
                  ),

                  // planning limits
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(l10n.advancedOptions,
                        style: Theme.of(context).textTheme.labelLarge),
                    children: [
                      _LimitSlider(
                        label: l10n.maxDetour,
                        value: settings.maxDetourMin,
                        min: 5,
                        max: 90,
                        unit: l10n.minutesShort(settings.maxDetourMin),
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setPlanning(maxDetourMin: v.round()),
                      ),
                      _LimitSlider(
                        label: l10n.stopDuration,
                        value: settings.stopDurationMin,
                        min: 5,
                        max: 60,
                        unit: l10n.minutesShort(settings.stopDurationMin),
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setPlanning(stopDurationMin: v.round()),
                      ),
                      _LimitSlider(
                        label: l10n.planningWindow,
                        value: settings.planningWindowMin,
                        min: 10,
                        max: 120,
                        unit: l10n.minutesShort(settings.planningWindowMin),
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setPlanning(planningWindowMin: v.round()),
                      ),
                      _LimitSlider(
                        label: l10n.prayerBuffer,
                        value: settings.prayerBufferMin,
                        min: 0,
                        max: 30,
                        unit: l10n.minutesShort(settings.prayerBufferMin),
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setPlanning(prayerBufferMin: v.round()),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _planning ? null : _plan,
                    icon: _planning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.route),
                    label: Text(l10n.planRoute),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          _PrayerCard(
            point: form.origin ?? form.destination,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _useMyLocation() async {
    final l10n = AppLocalizations.of(context);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.locationDenied)));
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      ref.read(plannerProvider.notifier).setOrigin(GeoPoint(
            lat: position.latitude,
            lon: position.longitude,
            name: l10n.useMyLocation,
          ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.locationDenied)));
      }
    }
  }

  Future<void> _pickDepartTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    final utc = DateTime(date.year, date.month, date.day, time.hour, time.minute).toUtc();
    ref.read(plannerProvider.notifier).setDepartUtc(utc);
  }

  void _showWaypointSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => UncontrolledProviderScope(
        container: ProviderScope.containerOf(context, listen: false),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PlaceField(
            label: AppLocalizations.of(sheetContext).addWaypoint,
            icon: Icons.add_location_alt_outlined,
            onSelected: (p) {
              ref.read(plannerProvider.notifier).addWaypoint(p);
              Navigator.of(sheetContext).pop();
            },
          ),
        ),
      ),
    );
  }
}

class _LimitSlider extends StatelessWidget {
  const _LimitSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final int value;
  final double min;
  final double max;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $unit', style: Theme.of(context).textTheme.bodySmall),
        Slider(
          value: value.toDouble().clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / 5).round().clamp(1, 24),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PrayerCard extends ConsumerWidget {
  const _PrayerCard({this.point});

  final GeoPoint? point;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final prayers = ref.watch(prayerTimesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.todayPrayers,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (prayers.hasValue && prayers.value != null)
                  SourceBadge(
                      live: prayers.value!.live, label: l10n.fixtureData),
              ],
            ),
            const SizedBox(height: 8),
            if (point == null)
              Text(l10n.searchFirst,
                  style: Theme.of(context).textTheme.bodyMedium),
            if (point != null)
              prayers.when(
                skipLoadingOnRefresh: true,
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (err, _) {
                  if (err is StateError) {
                    return Text(l10n.searchFirst);
                  }
                  return ErrorCard(
                    message: err is Failure
                        ? (err.isNetwork
                            ? l10n.errorNetwork
                            : l10n.errorProvider(err.message))
                        : l10n.errorGeneric,
                    onRetry: () => ref.invalidate(prayerTimesProvider),
                  );
                },
                data: (day) {
                  final now = DateTime.now().toUtc();
                  PrayerEvent? next;
                  for (final e in day.events) {
                    if (e.utc.isAfter(now)) {
                      next = e;
                      break;
                    }
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (next != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${l10n.nextPrayer}: '
                                '${prayerName(context, next.name.name)}',
                                style:
                                    Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatCountdown(context,
                                    next.utc.difference(now)),
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (next.notes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                InfoList(items: next.notes),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      for (final e in day.events)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(prayerName(context, e.name.name)),
                          subtitle: e.localDate.isEmpty
                              ? null
                              : Text(e.localDate),
                          trailing: Text(
                            formatTime(context, e.local, use24h: settings.use24h),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

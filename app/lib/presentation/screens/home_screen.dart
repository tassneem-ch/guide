import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../application/planner.dart';
import '../../application/settings.dart';
import '../../core/format.dart';
import '../../core/map_engine.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';
import '../widgets/place_field.dart';
import '../widgets/route_map.dart';

/// Screen 1 — map-first home.
///
/// Layout: a full-bleed map (Google Maps when configured, labeled OSM
/// fallback otherwise) with the selected points plotted on it; a floating
/// search card on top; and a draggable sheet containing the full planning
/// form plus today's prayer times.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _planning = false;

  /// Drives the map controls: they sit just above the sheet wherever the
  /// user has dragged it, so they are never buried underneath it.
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  double _sheetExtent = 0.42; // == initialChildSize

  /// How many From/To fields are focused (0 or 1 in practice; counted so a
  /// hand-off between fields never restores the sheet in between).
  int _focusedFields = 0;

  /// The user's sheet position before a field took focus, restored after.
  double? _extentBeforeFocus;

  /// A From/To field gained or lost focus. Typing opens an in-card
  /// suggestions list that on small screens (especially with the keyboard
  /// open) would be hidden behind the half-expanded sheet — so shrink the
  /// sheet to its minimum while a field is focused and put it back after.
  void _onPlaceFocusChanged(bool focused) {
    if (!mounted) return;
    final first = focused && _focusedFields == 0;
    final last = !focused && _focusedFields == 1;
    setState(() {
      _focusedFields += focused ? 1 : -1;
      if (_focusedFields < 0) _focusedFields = 0;
      if (first) _extentBeforeFocus ??= _sheetExtent;
    });
    const duration = Duration(milliseconds: 250);
    if (first) {
      _sheetController.animateTo(0.12,
          duration: duration, curve: Curves.easeInOut);
    } else if (last) {
      final restore = _extentBeforeFocus ?? 0.42;
      _extentBeforeFocus = null;
      _sheetController.animateTo(restore,
          duration: duration, curve: Curves.easeInOut);
    }
  }

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(() {
      if (!mounted || !_sheetController.isAttached) return;
      final size = _sheetController.size;
      if ((size - _sheetExtent).abs() > 0.01) {
        setState(() => _sheetExtent = size);
      }
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

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
        SnackBar(
            content:
                Text(err is Failure ? err.message : l10n.errorGeneric)),
      );
      return;
    }
    context.push('/route');
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

  Future<void> _onMapTap(GeoPoint point) async {
    final l10n = AppLocalizations.of(context);
    final label = '${point.lat.toStringAsFixed(5)}, '
        '${point.lon.toStringAsFixed(5)}';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.trip_origin_outlined),
              title: Text(l10n.fromLabel),
              onTap: () => Navigator.of(sheetContext).pop('from'),
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(l10n.toLabel),
              onTap: () => Navigator.of(sheetContext).pop('to'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final picked = point.copyWith(name: label);
    final planner = ref.read(plannerProvider.notifier);
    if (choice == 'from') {
      planner.setOrigin(picked);
    } else {
      planner.setDestination(picked);
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
    final utc =
        DateTime(date.year, date.month, date.day, time.hour, time.minute)
            .toUtc();
    ref.read(plannerProvider.notifier).setDepartUtc(utc);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(plannerProvider);
    final settings = ref.watch(settingsProvider);

    // Points to plot on the home map.
    final mapPoints = <GeoPoint>[
      if (form.origin != null) form.origin!,
      ...form.waypoints,
      if (form.destination != null) form.destination!,
    ];

    return Scaffold(
      body: Stack(
        children: [
          // --- full-bleed map -------------------------------------------
          Positioned.fill(
            child: AdaptiveMap(
              points: mapPoints,
              // Tapping the map (as opposed to dragging) picks a point.
              onMapTap: _onMapTap,
              // Keep the zoom/my-location controls above the sheet, no
              // matter where the user has dragged it.
              controlsBottomInset: (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom) *
                  _sheetExtent +
                  12,
            ),
          ),

          // --- floating search card --------------------------------------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FixtureBanner(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.travel_explore,
                                  color:
                                      Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.homeTitle,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
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
                          // The map's own engine label sits behind this
                          // card, so disclose it here as well.
                          if (!useGoogleMaps)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.map_outlined, size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      l10n.mapFallbackNote,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 4),
                          PlaceField(
                            label: l10n.fromLabel,
                            icon: Icons.trip_origin_outlined,
                            initial: form.origin,
                            onFocusChanged: _onPlaceFocusChanged,
                            onSelected: (p) => ref
                                .read(plannerProvider.notifier)
                                .setOrigin(p),
                            onCleared: () => ref
                                .read(plannerProvider.notifier)
                                .setOrigin(null),
                          ),
                          Row(
                            children: [
                              const Spacer(),
                              IconButton.filledTonal(
                                tooltip: l10n.swapButton,
                                icon: const Icon(Icons.swap_vert),
                                onPressed: ref
                                    .read(plannerProvider.notifier)
                                    .swap,
                              ),
                              const Spacer(),
                            ],
                          ),
                          PlaceField(
                            label: l10n.toLabel,
                            icon: Icons.place_outlined,
                            initial: form.destination,
                            onFocusChanged: _onPlaceFocusChanged,
                            onSelected: (p) => ref
                                .read(plannerProvider.notifier)
                                .setDestination(p),
                            onCleared: () => ref
                                .read(plannerProvider.notifier)
                                .setDestination(null),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _planning ? null : _plan,
                            icon: _planning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.route),
                            label: Text(l10n.planRoute),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- draggable details sheet ------------------------------------
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.42,
            minChildSize: 0.12,
            maxChildSize: 0.92,
            builder: (context, scrollController) => Material(
              elevation: 8,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              color: Theme.of(context).colorScheme.surface,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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
                          ButtonSegment(
                              value: true, label: Text(l10n.departNow)),
                          ButtonSegment(
                              value: false, label: Text(l10n.chooseTime)),
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
                  _PrayerCard(point: form.origin ?? form.destination),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

class _PrayerCard extends ConsumerStatefulWidget {
  const _PrayerCard({this.point});

  final GeoPoint? point;

  @override
  ConsumerState<_PrayerCard> createState() => _PrayerCardState();
}

class _PrayerCardState extends ConsumerState<_PrayerCard> {
  Timer? _ticker;
  int _rolloverAttempts = 0;
  String? _lastRolloverDate;

  @override
  void initState() {
    super.initState();
    // Local countdown tick only — the network is never polled from here.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            if (widget.point == null)
              Text(l10n.searchFirst,
                  style: Theme.of(context).textTheme.bodyMedium),
            if (widget.point != null)
              prayers.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: true,
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
                  if (next != null) {
                    _rolloverAttempts = 0;
                    _lastRolloverDate = null;
                  } else if (_lastRolloverDate != day.localDate &&
                      _rolloverAttempts < 2) {
                    // Every prayer of this local day already passed: ask
                    // once for the next day so "next prayer" shows a real
                    // upcoming instant instead of nothing.
                    _lastRolloverDate = day.localDate;
                    _rolloverAttempts++;
                    WidgetsBinding.instance.addPostFrameCallback(
                        (_) => ref.invalidate(prayerTimesProvider));
                  }
                  final cached = day.fetchedAt != null &&
                      now.difference(day.fetchedAt!.toUtc()).inMinutes > 5;
                  final locationLabel = day.location.name ??
                      '${day.location.lat.toStringAsFixed(4)}, '
                          '${day.location.lon.toStringAsFixed(4)}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Where + when + how these times were computed.
                      Text(
                        '$locationLabel · ${day.localDate}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l10n.prayerMethod}: ${settings.prayer.method}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (cached)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.history, size: 14),
                                const SizedBox(width: 4),
                                Text(l10n.cachedData,
                                    style:
                                        Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
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
                          subtitle:
                              e.localDate.isEmpty ? null : Text(e.localDate),
                          trailing: Text(
                            formatTime(context, e.local,
                                use24h: settings.use24h),
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

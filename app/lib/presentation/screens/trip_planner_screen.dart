import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings.dart';
import '../../application/trips.dart';
import '../../core/format.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';
import '../widgets/place_field.dart';

/// Screen 5: multi-day trip planner. Conflicts (overlaps, prayer conflicts,
/// missing overnights) are surfaced by the backend and shown — never hidden.
class TripPlannerScreen extends ConsumerStatefulWidget {
  const TripPlannerScreen({super.key});

  @override
  ConsumerState<TripPlannerScreen> createState() => _TripPlannerScreenState();
}

class _TripPlannerScreenState extends ConsumerState<TripPlannerScreen> {
  final _titleController = TextEditingController();
  bool _planning = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    final form = ref.read(tripProvider);
    final l10n = AppLocalizations.of(context);
    if (form.origin == null || form.destination == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.requiredField)));
      return;
    }
    setState(() => _planning = true);
    ref.read(tripProvider.notifier).setTitle(_titleController.text);
    final ok = await ref.read(tripResultProvider.notifier).plan();
    if (!mounted) return;
    setState(() => _planning = false);
    if (!ok) {
      final err = ref.read(tripResultProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err is Failure
            ? (err.isNetwork ? l10n.errorNetwork : l10n.errorProvider(err.message))
            : l10n.errorGeneric),
      ));
    }
  }

  Future<void> _addActivity() async {
    final l10n = AppLocalizations.of(context);
    final form = ref.read(tripProvider);
    final name = TextEditingController();
    final duration = TextEditingController(text: '90');
    var dayIndex = 0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(l10n.addActivity),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: l10n.activityName),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l10n.durationMin),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(l10n.dayIndex),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => setDialogState(
                        () => dayIndex = (dayIndex - 1).clamp(0, form.days - 1)),
                  ),
                  Text('${dayIndex + 1}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setDialogState(
                        () => dayIndex = (dayIndex + 1).clamp(0, form.days - 1)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                ref.read(tripProvider.notifier).addActivity(ActivityItem(
                      id: 'act-${DateTime.now().microsecondsSinceEpoch}',
                      name: name.text.trim(),
                      plannedDurationMin:
                          int.tryParse(duration.text) ?? 90,
                      dayIndex: dayIndex,
                    ));
                Navigator.of(dialogContext).pop();
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final form = ref.watch(tripProvider);
    final settings = ref.watch(settingsProvider);
    final result = ref.watch(tripResultProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tripTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FixtureBanner(),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(labelText: l10n.tripName),
                  ),
                  const SizedBox(height: 12),
                  PlaceField(
                    label: l10n.fromLabel,
                    icon: Icons.trip_origin_outlined,
                    initial: form.origin,
                    onSelected: (p) =>
                        ref.read(tripProvider.notifier).setOrigin(p),
                  ),
                  const SizedBox(height: 8),
                  PlaceField(
                    label: l10n.toLabel,
                    icon: Icons.place_outlined,
                    initial: form.destination,
                    onSelected: (p) =>
                        ref.read(tripProvider.notifier).setDestination(p),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(l10n.departureTime),
                    subtitle: Text(
                      form.departUtc == null
                          ? l10n.departNow
                          : formatDateTime(
                              context, form.departUtc!.toLocal(),
                              use24h: settings.use24h),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        firstDate: now,
                        lastDate: now.add(const Duration(days: 365)),
                      );
                      if (date != null && context.mounted) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: const TimeOfDay(hour: 9, minute: 0),
                        );
                        if (time != null) {
                          ref.read(tripProvider.notifier).setDepart(
                              DateTime(date.year, date.month, date.day,
                                      time.hour, time.minute)
                                  .toUtc());
                        }
                      }
                    },
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(l10n.days)),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () => ref
                            .read(tripProvider.notifier)
                            .setDays(form.days - 1),
                      ),
                      Text('${form.days}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => ref
                            .read(tripProvider.notifier)
                            .setDays(form.days + 1),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.overnight),
                    value: form.overnight,
                    onChanged: (v) =>
                        ref.read(tripProvider.notifier).setOvernight(v),
                  ),
                  Text('${l10n.paceLabel}: ${l10n.minutesShort(form.paceMinPerDay)}'),
                  Slider(
                    value: form.paceMinPerDay.toDouble(),
                    min: 60,
                    max: 600,
                    divisions: 9,
                    onChanged: (v) => ref
                        .read(tripProvider.notifier)
                        .setPace(v.round()),
                  ),
                ],
              ),
            ),
          ),

          const SectionHeader2(),
          for (var i = 0; i < form.activities.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.hiking_outlined),
                title: Text(form.activities[i].name),
                subtitle: Text(
                    '${l10n.minutesShort(form.activities[i].plannedDurationMin)} · ${l10n.dayIndex} ${form.activities[i].dayIndex + 1}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => ref
                      .read(tripProvider.notifier)
                      .removeActivity(i),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addActivity,
            icon: const Icon(Icons.add),
            label: Text(l10n.addActivity),
          ),

          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _planning ? null : _plan,
            icon: _planning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.map_outlined),
            label: Text(l10n.planTrip),
          ),

          const SizedBox(height: 16),
          result.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => ErrorCard(
              message: err is Failure
                  ? (err.isNetwork
                      ? l10n.errorNetwork
                      : l10n.errorProvider(err.message))
                  : l10n.errorGeneric,
              onRetry: () => ref.read(tripResultProvider.notifier).plan(),
            ),
            data: (plan) => plan == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FixtureBanner(providers: plan.providers),
                      const SizedBox(height: 8),
                      for (final day in plan.days) _DayCard(day: day),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _save(plan),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l10n.saveTrip),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _save(TripPlan plan) async {
    final l10n = AppLocalizations.of(context);
    final store = ref.read(localStoreProvider);
    final key = 'saved_trips:${DateTime.now().millisecondsSinceEpoch}';
    await store.write(
      key,
      jsonEncode({
        'id': key,
        'title': plan.title,
        'kind': 'trip',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'plan': {
          'title': plan.title,
          'route_provider': plan.routeProvider,
          'providers': plan.providers,
          'notes': plan.notes,
          'created_at': plan.createdAt.toIso8601String(),
          'days': [
            for (final d in plan.days)
              {
                'index': d.index,
                'local_date': d.localDate,
                'city': d.city,
                'tz': d.tz,
                'explanation': d.explanation,
                'uncertainties': d.uncertainties,
                'activities': [
                  for (final a in d.activities)
                    {
                      'activity': {
                        'id': a.activity.id,
                        'name': a.activity.name,
                        'planned_duration_min': a.activity.plannedDurationMin,
                        'day_index': a.activity.dayIndex,
                      },
                      'start_utc': a.startUtc.toIso8601String(),
                      'end_utc': a.endUtc.toIso8601String(),
                      'start_local': a.startLocal,
                      'notes': a.notes,
                      'conflicts': a.conflicts,
                    },
                ],
                if (d.overnight != null)
                  'overnight': {
                    'kind': 'overnight',
                    'name': d.overnight!.name,
                    'location': d.overnight!.location.toJson(),
                    'arrival_utc': d.overnight!.arrivalUtc.toIso8601String(),
                    'departure_utc':
                        d.overnight!.departureUtc.toIso8601String(),
                    'locked': d.overnight!.locked,
                    'uncertainties': d.overnight!.uncertainties,
                  },
              },
          ],
        },
      }),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.settingsSaved)));
  }
}

class SectionHeader2 extends ConsumerWidget {
  const SectionHeader2({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      SectionHeader(AppLocalizations.of(context).activities);
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});

  final DaySchedule day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasConflict = day.activities.any((a) => a.conflicts.isNotEmpty) ||
        day.uncertainties.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${l10n.dayIndex} ${day.index + 1} · ${day.city}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasConflict)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        Theme.of(context).colorScheme.errorContainer,
                    avatar: Icon(Icons.warning_amber_rounded,
                        size: 16,
                        color:
                            Theme.of(context).colorScheme.onErrorContainer),
                    label: Text(l10n.conflict),
                  ),
              ],
            ),
            Text(day.localDate,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (day.activities.isEmpty)
              Text(l10n.noResults,
                  style: Theme.of(context).textTheme.bodySmall),
            for (final a in day.activities)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined, size: 20),
                title: Text(a.activity.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${a.startLocal} · ${l10n.minutesShort(a.activity.plannedDurationMin)}'),
                    for (final c in a.conflicts)
                      Text(
                        c,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12),
                      ),
                  ],
                ),
              ),
            if (day.overnight != null) ...[
              const Divider(),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hotel_outlined, size: 20),
                title: Text('${l10n.overnight}: ${day.overnight!.name}'),
                subtitle: InfoList(items: day.overnight!.uncertainties, warning: true),
              ),
            ],
            if (day.uncertainties.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoList(items: day.uncertainties, warning: true),
            ],
            if (day.explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoList(items: day.explanation),
            ],
          ],
        ),
      ),
    );
  }
}

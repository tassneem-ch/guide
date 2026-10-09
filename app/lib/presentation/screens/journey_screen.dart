import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/planner.dart';
import '../../application/settings.dart';
import '../../core/format.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';
import '../widgets/route_map.dart';

/// Screen 3: full itinerary for the selected alternative — timeline of stops
/// with honest labels for everything unverified.
class JourneyScreen extends ConsumerWidget {
  const JourneyScreen({super.key, required this.planIndex});

  final int planIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final response = ref.watch(routeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.journeyTitle)),
      body: response.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(
            message: l10n.errorGeneric,
            onRetry: () => context.pop(),
          ),
        ),
        data: (data) {
          if (data == null || planIndex >= data.alternatives.length) {
            return Center(child: Text(l10n.noResults));
          }
          final plan = data.alternatives[planIndex];
          final m = plan.metrics;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.stale) ...[
                StaleBanner(fetchedAt: data.staleAt ?? data.requestedAt),
                const SizedBox(height: 8),
              ],
              FixtureBanner(providers: data.providers),
              const SizedBox(height: 8),
              if (plan.geometry.length >= 2)
                RouteMap(geometry: plan.geometry, stops: plan.stops),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              switch (plan.preference) {
                                RoutePreference.fastest => l10n.labelFastest,
                                RoutePreference.balanced => l10n.labelBalanced,
                                RoutePreference.prayerFriendly =>
                                  l10n.labelPrayerFriendly,
                              },
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (!plan.routeLive)
                            SourceBadge(live: false, label: l10n.fixtureData),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          MetricTile(
                            icon: Icons.straighten,
                            label: l10n.totalDistance,
                            value: formatDistance(context, m.totalDistanceM,
                                metric: settings.metric),
                          ),
                          const SizedBox(width: 8),
                          MetricTile(
                            icon: Icons.schedule,
                            label: l10n.totalDuration,
                            value: formatDuration(context, m.totalDurationS,
                                compact: true),
                          ),
                          const SizedBox(width: 8),
                          MetricTile(
                            icon: Icons.flag_outlined,
                            label: l10n.arrivalTime,
                            value: m.arrivalLocal.isEmpty
                                ? formatTime(context, m.arrivalUtc.toLocal(),
                                    use24h: settings.use24h)
                                : m.arrivalLocal,
                          ),
                        ],
                      ),
                      if (m.prayersServed.isNotEmpty || m.prayersMissed.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('${l10n.servedPrayers}: '
                            '${m.prayersServed.map((p) => prayerName(context, p)).join(', ')}'),
                        if (m.prayersMissed.isNotEmpty)
                          Text(
                            '${l10n.missedPrayers}: '
                            '${m.prayersMissed.map((p) => prayerName(context, p)).join(', ')}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error),
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              const SectionHeader2(),
              for (var i = 0; i < plan.stops.length; i++)
                _StopTile(stop: plan.stops[i], use24h: settings.use24h),

              if (plan.uncertainties.isNotEmpty) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.uncertainties,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer)),
                        const SizedBox(height: 8),
                        InfoList(items: plan.uncertainties, warning: true),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class SectionHeader2 extends StatelessWidget {
  const SectionHeader2({super.key});

  @override
  Widget build(BuildContext context) =>
      SectionHeader(AppLocalizations.of(context).stopsTimeline);
}

class _StopTile extends StatelessWidget {
  const _StopTile({required this.stop, required this.use24h});

  final ScheduledStop stop;
  final bool use24h;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final arrival = formatTime(context, stop.arrivalUtc.toLocal(),
        use24h: use24h);
    final departure = formatTime(context, stop.departureUtc.toLocal(),
        use24h: use24h);

    final (icon, title) = switch (stop.kind) {
      StopKind.origin => (Icons.trip_origin_outlined, l10n.origin),
      StopKind.destination => (Icons.place_outlined, l10n.destination),
      StopKind.mosque => (Icons.mosque, stop.name),
      StopKind.prayerBreak => (Icons.mosque, stop.name),
      _ => (Icons.circle_outlined, stop.name),
    };

    final canOpenMosque = stop.kind == StopKind.mosque && stop.mosque != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stop.kind == StopKind.origin
                ? l10n.departAt(arrival)
                : l10n.arriveAt(arrival)),
            if (stop.kind != StopKind.origin && stop.kind != StopKind.destination)
              Text(l10n.departAt(departure)),
            if (stop.prayer != null)
              Text(l10n.prayerAt(
                prayerName(context, stop.prayer!.name.name),
                formatTime(context, stop.prayer!.local, use24h: use24h),
              )),
            if (stop.rationale != null) ...[
              const SizedBox(height: 4),
              Text(stop.rationale!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12)),
            ],
            if (stop.uncertainties.isNotEmpty) ...[
              const SizedBox(height: 4),
              InfoList(items: stop.uncertainties, warning: true),
            ],
          ],
        ),
        trailing: canOpenMosque ? const Icon(Icons.chevron_right) : null,
        onTap: canOpenMosque
            ? () => context.push('/mosque', extra: stop.mosque)
            : null,
      ),
    );
  }
}

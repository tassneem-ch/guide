import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/planner.dart';
import '../../application/settings.dart';
import '../../core/format.dart';
import '../../domain/models.dart';
import '../../domain/repositories.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';

/// Screen 2: side-by-side comparison of the planned alternatives with
/// explanations and honest uncertainty labels.
class RouteComparisonScreen extends ConsumerWidget {
  const RouteComparisonScreen({super.key});

  String _planLabel(BuildContext context, RoutePreference pref) {
    final l10n = AppLocalizations.of(context);
    return switch (pref) {
      RoutePreference.fastest => l10n.labelFastest,
      RoutePreference.balanced => l10n.labelBalanced,
      RoutePreference.prayerFriendly => l10n.labelPrayerFriendly,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final response = ref.watch(routeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.routesTitle)),
      body: response.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(
            message: err is Failure
                ? (err.isNetwork
                    ? l10n.errorNetwork
                    : l10n.errorProvider(err.message))
                : l10n.errorGeneric,
            onRetry: () => ref.invalidate(routeProvider),
          ),
        ),
        data: (data) {
          if (data == null || data.alternatives.isEmpty) {
            return Center(child: Text(l10n.noResults));
          }
          final fastestDuration = data.alternatives
                  .map((a) => a.metrics.totalDurationS)
                  .reduce((a, b) => a < b ? a : b) ~/
              60;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.stale) ...[
                StaleBanner(fetchedAt: data.staleAt ?? data.requestedAt),
                const SizedBox(height: 8),
              ],
              FixtureBanner(providers: data.providers),
              const SizedBox(height: 8),
              for (var i = 0; i < data.alternatives.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _PlanCard(
                  plan: data.alternatives[i],
                  label: _planLabel(context, data.alternatives[i].preference),
                  fastestMinutes: fastestDuration,
                  use24h: settings.use24h,
                  metric: settings.metric,
                  onSelect: () =>
                      context.push('/route/journey?plan=$i'),
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.label,
    required this.fastestMinutes,
    required this.use24h,
    required this.metric,
    required this.onSelect,
  });

  final RoutePlan plan;
  final String label;
  final int fastestMinutes;
  final bool use24h;
  final bool metric;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final m = plan.metrics;
    final durationMin = m.totalDurationS ~/ 60;
    final detourMin = durationMin - fastestMinutes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (plan.preference) {
                    RoutePreference.fastest => Icons.speed,
                    RoutePreference.balanced => Icons.balance,
                    RoutePreference.prayerFriendly => Icons.mosque,
                  },
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (!plan.feasible)
                  Tooltip(
                    message: plan.infeasibilityReason ?? '',
                    child: Icon(Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                MetricTile(
                  icon: Icons.straighten,
                  label: l10n.totalDistance,
                  value: formatDistance(context, m.totalDistanceM,
                      metric: metric),
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
                          use24h: use24h)
                      : m.arrivalLocal,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.add_road, size: 16),
                  label: Text(detourMin <= 0
                      ? l10n.detourValue(0)
                      : l10n.detourValue(detourMin)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.mosque, size: 16),
                  label: Text('${m.mosqueStopCount}'),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                      m.prayersMissed.isEmpty
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 16,
                      color: m.prayersMissed.isEmpty
                          ? Colors.green
                          : Theme.of(context).colorScheme.error),
                  label: Text(
                      '${m.prayersServed.length}/${m.prayersServed.length + m.prayersMissed.length}'),
                ),
              ],
            ),
            if (m.prayersMissed.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${l10n.missedPrayers}: '
                '${m.prayersMissed.map((p) => prayerName(context, p)).join(', ')}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            SectionHeader(l10n.whyChosen, trailing: const SizedBox()),
            InfoList(items: plan.explanation),
            if (plan.uncertainties.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.help_outline,
                      size: 16, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 4),
                  Text(l10n.uncertainties,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                              color: Theme.of(context).colorScheme.error)),
                ],
              ),
              InfoList(items: plan.uncertainties, warning: true),
            ],
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: plan.feasible ? onSelect : null,
              icon: const Icon(Icons.timeline),
              label: Text(l10n.selectRoute),
            ),
          ],
        ),
      ),
    );
  }
}

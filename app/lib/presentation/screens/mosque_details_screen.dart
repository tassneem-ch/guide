import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';

/// Screen 4: mosque details as reported by the data provider.
///
/// Strict honesty rules:
/// - hours are shown exactly at their verification level (verified /
///   unverified / unknown) — never estimated;
/// - iqama/congregation time is shown only when the provider verified it,
///   otherwise an explicit note explains why it is missing;
/// - unnamed mosques stay unnamed.
class MosqueDetailsScreen extends ConsumerWidget {
  const MosqueDetailsScreen({super.key, required this.mosque});

  final MosqueCandidate? mosque;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final m = mosque;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mosqueDetails)),
      body: m == null
          ? Center(child: Text(l10n.noResults))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FixtureBanner(
                    providers: {'mosques': m.quality.source == 'live' ? 'LIVE' : 'FIXTURE'}),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.mosque,
                                color: Theme.of(context).colorScheme.primary,
                                size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                m.label,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            SourceBadge(
                                live: m.quality.isFixture == false,
                                label: l10n.fixtureData),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.storage, size: 14),
                              label: Text(m.quality.provider),
                            ),
                            if (m.detourSeconds != null)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: const Icon(Icons.add_road, size: 14),
                                label: Text(
                                    '${l10n.minutesShort(m.detourSeconds! ~/ 60)}'
                                    '${m.detourMethod == 'great_circle_estimate' ? ' ≈' : ''}'),
                              ),
                          ],
                        ),
                        if (m.quality.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          InfoList(items: m.quality.notes),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.openingHours,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        switch (m.openingHoursVerification) {
                          'verified' => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.verified_outlined,
                                  color: Colors.green.shade700),
                              title: Text(m.openingHours ?? ''),
                              subtitle: Text(l10n.hoursVerified),
                            ),
                          'unverified' => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.help_outline,
                                  color: Theme.of(context).colorScheme.error),
                              title: Text(m.openingHours ?? ''),
                              subtitle: Text(l10n.hoursUnverified),
                            ),
                          _ => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.hourglass_disabled_outlined),
                              title: Text(l10n.hoursUnknown),
                            ),
                        },
                        const Divider(),
                        // Congregation honesty: never infer iqama times.
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            m.congregationVerified
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            color: m.congregationVerified
                                ? Colors.green.shade700
                                : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            m.congregationUtc != null && m.congregationVerified
                                ? m.congregationUtc!
                                    .toLocal()
                                    .toIso8601String()
                                    .substring(11, 16)
                                : l10n.congregationUnknown,
                          ),
                        ),
                        if (m.phone != null) ...[
                          const Divider(),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.phone_outlined),
                            title: Text(m.phone!),
                            onTap: () => launchUrl(Uri.parse('tel:${m.phone}')),
                          ),
                        ],
                        if (m.website != null) ...[
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.language_outlined),
                            title: Text(m.website!),
                            onTap: () =>
                                launchUrl(Uri.parse(m.website!)),
                          ),
                        ],
                        if (m.wheelchairAccessible != null) ...[
                          const Divider(),
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.accessible_outlined),
                            title: Text(l10n.wheelchair),
                            trailing: Text(
                              m.wheelchairAccessible!
                                  ? l10n.yes
                                  : l10n.no,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(
                      'geo:${m.location.lat},${m.location.lon}?q=${Uri.encodeComponent(m.label)}')),
                  icon: const Icon(Icons.directions_outlined),
                  label: Text(l10n.openInMaps),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

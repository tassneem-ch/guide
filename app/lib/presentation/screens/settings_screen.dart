import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings.dart';
import '../../core/format.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../widgets/common.dart';

/// Screen 6: settings. Prayer controls are capabilities-driven: methods,
/// school, high-latitude rules and manual adjustments only appear when the
/// active provider supports them (checked live against the backend).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider);
    final settingsCtl = ref.read(settingsProvider.notifier);
    final caps = ref.watch(prayerCapabilitiesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const FixtureBanner(),
          const SizedBox(height: 8),

          // ---- appearance ---------------------------------------------------
          SectionHeader(l10n.appearance),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.translate_outlined),
                  title: Text(l10n.language),
                  trailing: DropdownButton<String>(
                    value: settings.localeCode,
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('System')),
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ar', child: Text('العربية')),
                      DropdownMenuItem(value: 'fr', child: Text('Français')),
                    ],
                    onChanged: (v) {
                      if (v != null) settingsCtl.setLocale(v);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dark_mode_outlined),
                  title: Text(l10n.darkMode),
                  trailing: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'system', label: Text('A')),
                      ButtonSegment(value: 'light', label: Text('☀')),
                      ButtonSegment(value: 'dark', label: Text('🌙')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (sel) =>
                        settingsCtl.setThemeMode(sel.first),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_outlined),
                  title: Text(l10n.timeFormat),
                  subtitle: Text(settings.use24h ? l10n.time24 : l10n.time12),
                  value: settings.use24h,
                  onChanged: settingsCtl.setUse24h,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.straighten_outlined),
                  title: Text(l10n.units),
                  subtitle:
                      Text(settings.metric ? l10n.unitsMetric : l10n.unitsImperial),
                  value: settings.metric,
                  onChanged: settingsCtl.setMetric,
                ),
              ],
            ),
          ),

          // ---- prayer data source ------------------------------------------
          SectionHeader(l10n.prayerSourceTitle),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: Text(l10n.prayerSourceTitle),
              subtitle: Text(switch (settings.prayerSource) {
                'backend' => l10n.prayerSourceBackend,
                'aladhan' => l10n.prayerSourceAladhan,
                _ => l10n.prayerSourceAuto,
              }),
              enabled: !settings.demoMode,
              onTap: () => _pickPrayerSource(context, ref, settings),
            ),
          ),

          // ---- prayer settings (capabilities-driven) -----------------------
          SectionHeader(l10n.prayerMethod),
          caps.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (err, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(settings.demoMode
                    ? l10n.demoModeNote
                    : l10n.errorNetwork),
              ),
            ),
            data: (caps) => Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calculate_outlined),
                    title: Text(l10n.prayerMethod),
                    subtitle: Text(
                      caps.methods
                          .firstWhere((m) => m.id == settings.prayer.method,
                              orElse: () => MethodOption(
                                  id: settings.prayer.method,
                                  label: settings.prayer.method))
                          .label,
                    ),
                    enabled: caps.methods.isNotEmpty,
                    onTap: () => _pickMethod(context, ref, caps, settings),
                  ),
                  if (caps.schools.length > 1)
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: Text(l10n.asrSchool),
                      subtitle: Text(settings.prayer.school == 'hanafi'
                          ? l10n.asrHanafi
                          : l10n.asrStandard),
                      onTap: () {
                        final next = settings.prayer.school == 'hanafi'
                            ? 'standard'
                            : 'hanafi';
                        if (caps.schools.contains(next)) {
                          settingsCtl.setAsrSchool(next);
                        }
                      },
                    ),
                  if (caps.highLatitudeRules.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.public_outlined),
                      title: Text(l10n.highLatitude),
                      subtitle: Text(settings.prayer.highLatitudeRule),
                      onTap: () => _pickHighLatitude(context, ref, caps, settings),
                    ),
                  if (caps.manualAdjustments)
                    ExpansionTile(
                      leading: const Icon(Icons.tune_outlined),
                      title: Text(l10n.manualAdjustments),
                      children: [
                        for (final p in ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'])
                          ListTile(
                            dense: true,
                            title: Text(prayerName(context, p)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove),
                                  onPressed: () => settingsCtl.setAdjustment(
                                    p,
                                    (settings.prayer.adjustments[p] ?? 0) - 1,
                                  ),
                                ),
                                Text('${settings.prayer.adjustments[p] ?? 0}'),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: () => settingsCtl.setAdjustment(
                                    p,
                                    (settings.prayer.adjustments[p] ?? 0) + 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  if (!caps.live || !caps.manualAdjustments ||
                      caps.methods.isEmpty ||
                      caps.highLatitudeRules.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: InfoList(items: [
                        for (final n in caps.notes) n,
                        if (!caps.live) l10n.fixtureBanner,
                      ]),
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.dns_outlined, size: 18),
                    title: Text(l10n.backendStatus),
                    subtitle: Text(
                        '${l10n.prayerProviderLabel}: ${caps.provider}'),
                  ),
                ],
              ),
            ),
          ),

          // ---- planning defaults --------------------------------------------
          SectionHeader(l10n.advancedOptions),
          Card(
            child: Column(
              children: [
                _SettingSlider(
                  label: l10n.maxDetour,
                  value: settings.maxDetourMin,
                  min: 5,
                  max: 90,
                  unitLabel: l10n.minutesShort(settings.maxDetourMin),
                  onChanged: (v) =>
                      settingsCtl.setPlanning(maxDetourMin: v.round()),
                ),
                _SettingSlider(
                  label: l10n.stopDuration,
                  value: settings.stopDurationMin,
                  min: 5,
                  max: 60,
                  unitLabel: l10n.minutesShort(settings.stopDurationMin),
                  onChanged: (v) =>
                      settingsCtl.setPlanning(stopDurationMin: v.round()),
                ),
                _SettingSlider(
                  label: l10n.planningWindow,
                  value: settings.planningWindowMin,
                  min: 10,
                  max: 120,
                  unitLabel: l10n.minutesShort(settings.planningWindowMin),
                  onChanged: (v) =>
                      settingsCtl.setPlanning(planningWindowMin: v.round()),
                ),
                _SettingSlider(
                  label: l10n.prayerBuffer,
                  value: settings.prayerBufferMin,
                  min: 0,
                  max: 30,
                  unitLabel: l10n.minutesShort(settings.prayerBufferMin),
                  onChanged: (v) =>
                      settingsCtl.setPlanning(prayerBufferMin: v.round()),
                ),
              ],
            ),
          ),

          // ---- notifications (honest limitation) ----------------------------
          SectionHeader(l10n.notifications),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.notifications),
                  subtitle: Text(l10n.notificationsNote),
                  value: settings.prayerStopReminders,
                  onChanged: settingsCtl.setPrayerStopReminders,
                ),
              ],
            ),
          ),

          // ---- backend / demo mode ------------------------------------------
          SectionHeader(l10n.backendStatus),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.science_outlined),
                  title: Text(l10n.demoMode),
                  subtitle: Text(l10n.demoModeNote),
                  value: settings.demoMode,
                  onChanged: settingsCtl.setDemoMode,
                ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(l10n.backendUrl),
                  subtitle: Text(settings.backendUrl),
                  enabled: !settings.demoMode,
                  onTap: () => _editBackendUrl(context, ref, settings),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _pickMethod(BuildContext context, WidgetRef ref,
      PrayerCapabilities caps, AppSettings settings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          for (final m in caps.methods)
            ListTile(
              title: Text(m.label),
              selected: m.id == settings.prayer.method,
              trailing: m.id == settings.prayer.method
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref
                    .read(settingsProvider.notifier)
                    .setPrayerMethod(m.id, supportsAdjustments: caps.manualAdjustments);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  void _pickPrayerSource(
      BuildContext context, WidgetRef ref, AppSettings settings) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          for (final (value, label) in [
            ('auto', l10n.prayerSourceAuto),
            ('backend', l10n.prayerSourceBackend),
            ('aladhan', l10n.prayerSourceAladhan),
          ])
            ListTile(
              title: Text(label),
              selected: value == settings.prayerSource,
              trailing: value == settings.prayerSource
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setPrayerSource(value);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  void _pickHighLatitude(BuildContext context, WidgetRef ref,
      PrayerCapabilities caps, AppSettings settings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          for (final r in caps.highLatitudeRules)
            ListTile(
              title: Text(r),
              selected: r == settings.prayer.highLatitudeRule,
              trailing: r == settings.prayer.highLatitudeRule
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setHighLatitudeRule(r);
                Navigator.of(sheetContext).pop();
              },
            ),
        ],
      ),
    );
  }

  Future<void> _editBackendUrl(
      BuildContext context, WidgetRef ref, AppSettings settings) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: settings.backendUrl);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.backendUrl),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l10n.backendUrlHint),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(settingsProvider.notifier)
                  .setBackendUrl(kDefaultBackendUrl);
              Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.resetToDefault),
          ),
          FilledButton(
            onPressed: () {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                ref.read(settingsProvider.notifier).setBackendUrl(url);
              }
              Navigator.of(dialogContext).pop();
            },
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unitLabel,
    required this.onChanged,
  });

  final String label;
  final int value;
  final double min;
  final double max;
  final String unitLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: $unitLabel', style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: value.toDouble().clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) / 5).round().clamp(1, 24),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

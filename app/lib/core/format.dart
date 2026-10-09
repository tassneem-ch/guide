import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';

/// Formatting helpers that respect the user's locale + settings.

String formatDistance(BuildContext context, int meters, {bool metric = true}) {
  final l10n = AppLocalizations.of(context);
  final loc = Localizations.localeOf(context).toString();
  if (!metric) {
    final miles = meters / 1609.344;
    return '${NumberFormat.decimalPattern(loc).format(miles)} mi';
  }
  if (meters < 1000) {
    return '${NumberFormat.decimalPattern(loc).format(meters)} m';
  }
  final km = meters / 1000;
  return l10n.unitsKmValue(
      NumberFormat.decimalPattern(loc).format(km));
}

/// Compact duration like "2 h 15 min" (or "45 min").
String formatDuration(BuildContext context, int seconds, {bool compact = false}) {
  final l10n = AppLocalizations.of(context);
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return l10n.countdownMinutes(m);
  if (compact) return l10n.countdownHours(h, m);
  return l10n.hoursMinutes(h, m);
}

/// Local time formatting honoring the 12/24h preference.
String formatTime(BuildContext context, DateTime time, {required bool use24h}) {
  final loc = Localizations.localeOf(context).toString();
  if (use24h) return DateFormat.Hm(loc).format(time);
  return DateFormat.jm(loc).format(time);
}

/// Full local date+time, e.g. "15 Jun 2025, 14:32".
String formatDateTime(BuildContext context, DateTime time, {required bool use24h}) {
  final loc = Localizations.localeOf(context).toString();
  final date = DateFormat.yMMMd(loc).format(time);
  return '$date, ${formatTime(context, time, use24h: use24h)}';
}

/// "in 2 h 15 min" / "in 4 d 3 h" / "in 12 min".
String formatCountdown(BuildContext context, Duration remaining) {
  final l10n = AppLocalizations.of(context);
  if (remaining.isNegative) return l10n.inTime('0');
  final d = remaining.inDays;
  final h = remaining.inHours % 24;
  final m = remaining.inMinutes % 60;
  if (d > 0) return l10n.inTime(l10n.countdownDays(d, h));
  if (h > 0) return l10n.inTime(l10n.countdownHours(h, m));
  return l10n.inTime(l10n.countdownMinutes(m));
}

/// Locale-aware prayer name.
String prayerName(BuildContext context, String enumName) {
  final l10n = AppLocalizations.of(context);
  return switch (enumName) {
    'fajr' => l10n.prayerFajr,
    'dhuhr' => l10n.prayerDhuhr,
    'asr' => l10n.prayerAsr,
    'maghrib' => l10n.prayerMaghrib,
    'isha' => l10n.prayerIsha,
    _ => enumName,
  };
}

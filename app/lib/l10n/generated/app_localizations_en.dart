// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Guide';

  @override
  String get homeTitle => 'Plan a journey';

  @override
  String get fromLabel => 'From';

  @override
  String get toLabel => 'To';

  @override
  String get searchHint => 'City, address or place';

  @override
  String get useMyLocation => 'Use my location';

  @override
  String get locationDenied =>
      'Location permission denied — enter a place manually.';

  @override
  String get swapButton => 'Swap';

  @override
  String get addWaypoint => 'Add stop';

  @override
  String waypoint(int n) {
    return 'Stop $n';
  }

  @override
  String get departureTime => 'Departure';

  @override
  String get departNow => 'Leave now';

  @override
  String get chooseTime => 'Choose time';

  @override
  String get travelMode => 'Travel mode';

  @override
  String get modeDriving => 'Driving';

  @override
  String get modeWalking => 'Walking';

  @override
  String get modeCycling => 'Cycling';

  @override
  String get preference => 'Priority';

  @override
  String get prefFastest => 'Fastest';

  @override
  String get prefBalanced => 'Balanced';

  @override
  String get prefPrayerFriendly => 'Prayer-friendly';

  @override
  String get prayerStopsLabel => 'Prayer stops';

  @override
  String get stopsOptional => 'Optional';

  @override
  String get stopsMandatory => 'Mandatory';

  @override
  String get stopsNone => 'None';

  @override
  String get advancedOptions => 'Planning limits';

  @override
  String get maxDetour => 'Maximum mosque detour';

  @override
  String get stopDuration => 'Stop duration';

  @override
  String get planningWindow => 'Planning window (arrive early)';

  @override
  String get prayerBuffer => 'Buffer after prayer start';

  @override
  String minutesShort(int n) {
    return '$n min';
  }

  @override
  String get planRoute => 'Plan route';

  @override
  String get nextPrayer => 'Next prayer';

  @override
  String get todayPrayers => 'Today\'s prayers';

  @override
  String get noPrayerData => 'Prayer times unavailable';

  @override
  String get prayerFajr => 'Fajr';

  @override
  String get prayerDhuhr => 'Dhuhr';

  @override
  String get prayerAsr => 'Asr';

  @override
  String get prayerMaghrib => 'Maghrib';

  @override
  String get prayerIsha => 'Isha';

  @override
  String get searchFirst => 'Choose a starting point to see prayer times.';

  @override
  String get routesTitle => 'Route comparison';

  @override
  String get journeyTitle => 'Journey details';

  @override
  String get tripTitle => 'Trip planner';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get labelFastest => 'Fastest route';

  @override
  String get labelBalanced => 'Balanced route';

  @override
  String get labelPrayerFriendly => 'Prayer-friendly route';

  @override
  String get totalDistance => 'Distance';

  @override
  String get totalDuration => 'Duration';

  @override
  String get arrivalTime => 'Arrival';

  @override
  String get detourVsFastest => 'Detour vs fastest';

  @override
  String get mosqueStops => 'Mosque stops';

  @override
  String get whyChosen => 'Why this route';

  @override
  String get uncertainties => 'Uncertain / unverified';

  @override
  String get servedPrayers => 'Prayers served';

  @override
  String get missedPrayers => 'Prayers not stopped for';

  @override
  String get selectRoute => 'View journey';

  @override
  String get stopsTimeline => 'Stops and legs';

  @override
  String get origin => 'Origin';

  @override
  String get destination => 'Destination';

  @override
  String arriveAt(String time) {
    return 'Arrive $time';
  }

  @override
  String departAt(String time) {
    return 'Depart $time';
  }

  @override
  String prayerAt(String prayer, String time) {
    return '$prayer at $time';
  }

  @override
  String get rationale => 'Why this stop';

  @override
  String alternativeMosques(int n) {
    return '$n alternative mosques nearby';
  }

  @override
  String get mosqueDetails => 'Mosque details';

  @override
  String get openingHours => 'Opening hours';

  @override
  String get hoursUnknown => 'Opening hours not published by the data source.';

  @override
  String get hoursUnverified =>
      'Hours are provider-supplied and not independently verified.';

  @override
  String get hoursVerified => 'Hours confirmed by the data source.';

  @override
  String get congregationUnknown =>
      'Congregation (iqama) time unknown — only the calculated prayer start is shown.';

  @override
  String get phone => 'Phone';

  @override
  String get website => 'Website';

  @override
  String get wheelchair => 'Wheelchair accessible';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get notSpecified => 'Not specified';

  @override
  String get dataFrom => 'Data source';

  @override
  String get liveData => 'Live data';

  @override
  String get fixtureData => 'Development data';

  @override
  String get openInMaps => 'Open directions in maps';

  @override
  String detourValue(Object n) {
    return 'Detour $n min';
  }

  @override
  String get tripName => 'Trip name';

  @override
  String get days => 'Days';

  @override
  String get activities => 'Sightseeing & activities';

  @override
  String get addActivity => 'Add activity';

  @override
  String get activityName => 'Activity name';

  @override
  String get durationMin => 'Duration (min)';

  @override
  String get dayIndex => 'Day (0-based starts at 1 in list)';

  @override
  String get planTrip => 'Plan trip';

  @override
  String get saveTrip => 'Save itinerary';

  @override
  String get savedTrips => 'Saved itineraries';

  @override
  String get resume => 'Resume';

  @override
  String get delete => 'Delete';

  @override
  String get conflict => 'Conflict';

  @override
  String get overnight => 'Overnight';

  @override
  String get paceLabel => 'Planned activity minutes per day';

  @override
  String get nothingPlanned => 'Nothing planned yet.';

  @override
  String get language => 'Language';

  @override
  String get prayerMethod => 'Prayer calculation method';

  @override
  String get asrSchool => 'Asr calculation';

  @override
  String get asrStandard => 'Standard (Shafi\'i, Maliki, Hanbali)';

  @override
  String get asrHanafi => 'Hanafi';

  @override
  String get highLatitude => 'High-latitude rule';

  @override
  String get unsupportedByProvider => 'Not supported by the active provider';

  @override
  String get manualAdjustments => 'Manual adjustments (minutes)';

  @override
  String get timeFormat => 'Time format';

  @override
  String get time24 => '24-hour';

  @override
  String get time12 => '12-hour';

  @override
  String get units => 'Units';

  @override
  String get unitsMetric => 'Metric (km)';

  @override
  String get unitsImperial => 'Imperial (mi)';

  @override
  String get notifications => 'Prayer stop reminders';

  @override
  String get notificationsNote =>
      'Preference is saved; on-device reminder scheduling is not yet available in this build.';

  @override
  String get appearance => 'Appearance';

  @override
  String get darkMode => 'Dark theme';

  @override
  String get backendStatus => 'Backend provider status';

  @override
  String get prayerProviderLabel => 'Prayer provider';

  @override
  String get demoMode => 'Demo data (offline preview)';

  @override
  String get demoModeNote =>
      'Shows clearly-marked sample journeys without a backend.';

  @override
  String get loading => 'Loading…';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get errorNetwork =>
      'Cannot reach the server — check the backend address in Settings.';

  @override
  String errorProvider(String message) {
    return 'A data provider failed: $message';
  }

  @override
  String get retry => 'Retry';

  @override
  String offlineBanner(Object time) {
    return 'Offline — showing saved data from $time.';
  }

  @override
  String get fixtureBanner =>
      'Development fixtures active — data is simulated, not live.';

  @override
  String get noResults => 'No results';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get done => 'Done';

  @override
  String get requiredField => 'Required';

  @override
  String get unknown => 'Unknown';

  @override
  String unitsKmValue(String n) {
    return '$n km';
  }

  @override
  String hoursMinutes(int h, int m) {
    return '$h h $m min';
  }

  @override
  String inTime(String time) {
    return 'in $time';
  }

  @override
  String countdownDays(int d, int h) {
    return '${d}d ${h}h';
  }

  @override
  String countdownHours(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String countdownMinutes(int m) {
    return '${m}m';
  }

  @override
  String get backendUrl => 'Backend address';

  @override
  String get backendUrlHint => 'e.g. http://10.0.2.2:8000 (Android emulator)';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String providerReport(String prayer, String routing, String mosques) {
    return 'Prayer: $prayer · Routing: $routing · Mosques: $mosques';
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Guide'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan a journey'**
  String get homeTitle;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toLabel;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'City, address or place'**
  String get searchHint;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get useMyLocation;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied — enter a place manually.'**
  String get locationDenied;

  /// No description provided for @swapButton.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get swapButton;

  /// No description provided for @addWaypoint.
  ///
  /// In en, this message translates to:
  /// **'Add stop'**
  String get addWaypoint;

  /// No description provided for @waypoint.
  ///
  /// In en, this message translates to:
  /// **'Stop {n}'**
  String waypoint(int n);

  /// No description provided for @departureTime.
  ///
  /// In en, this message translates to:
  /// **'Departure'**
  String get departureTime;

  /// No description provided for @departNow.
  ///
  /// In en, this message translates to:
  /// **'Leave now'**
  String get departNow;

  /// No description provided for @chooseTime.
  ///
  /// In en, this message translates to:
  /// **'Choose time'**
  String get chooseTime;

  /// No description provided for @travelMode.
  ///
  /// In en, this message translates to:
  /// **'Travel mode'**
  String get travelMode;

  /// No description provided for @modeDriving.
  ///
  /// In en, this message translates to:
  /// **'Driving'**
  String get modeDriving;

  /// No description provided for @modeWalking.
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get modeWalking;

  /// No description provided for @modeCycling.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get modeCycling;

  /// No description provided for @preference.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get preference;

  /// No description provided for @prefFastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get prefFastest;

  /// No description provided for @prefBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get prefBalanced;

  /// No description provided for @prefPrayerFriendly.
  ///
  /// In en, this message translates to:
  /// **'Prayer-friendly'**
  String get prefPrayerFriendly;

  /// No description provided for @prayerStopsLabel.
  ///
  /// In en, this message translates to:
  /// **'Prayer stops'**
  String get prayerStopsLabel;

  /// No description provided for @stopsOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get stopsOptional;

  /// No description provided for @stopsMandatory.
  ///
  /// In en, this message translates to:
  /// **'Mandatory'**
  String get stopsMandatory;

  /// No description provided for @stopsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get stopsNone;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Planning limits'**
  String get advancedOptions;

  /// No description provided for @maxDetour.
  ///
  /// In en, this message translates to:
  /// **'Maximum mosque detour'**
  String get maxDetour;

  /// No description provided for @stopDuration.
  ///
  /// In en, this message translates to:
  /// **'Stop duration'**
  String get stopDuration;

  /// No description provided for @planningWindow.
  ///
  /// In en, this message translates to:
  /// **'Planning window (arrive early)'**
  String get planningWindow;

  /// No description provided for @prayerBuffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer after prayer start'**
  String get prayerBuffer;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String minutesShort(int n);

  /// No description provided for @planRoute.
  ///
  /// In en, this message translates to:
  /// **'Plan route'**
  String get planRoute;

  /// No description provided for @nextPrayer.
  ///
  /// In en, this message translates to:
  /// **'Next prayer'**
  String get nextPrayer;

  /// No description provided for @todayPrayers.
  ///
  /// In en, this message translates to:
  /// **'Today\'s prayers'**
  String get todayPrayers;

  /// No description provided for @noPrayerData.
  ///
  /// In en, this message translates to:
  /// **'Prayer times unavailable'**
  String get noPrayerData;

  /// No description provided for @prayerFajr.
  ///
  /// In en, this message translates to:
  /// **'Fajr'**
  String get prayerFajr;

  /// No description provided for @prayerDhuhr.
  ///
  /// In en, this message translates to:
  /// **'Dhuhr'**
  String get prayerDhuhr;

  /// No description provided for @prayerAsr.
  ///
  /// In en, this message translates to:
  /// **'Asr'**
  String get prayerAsr;

  /// No description provided for @prayerMaghrib.
  ///
  /// In en, this message translates to:
  /// **'Maghrib'**
  String get prayerMaghrib;

  /// No description provided for @prayerIsha.
  ///
  /// In en, this message translates to:
  /// **'Isha'**
  String get prayerIsha;

  /// No description provided for @searchFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a starting point to see prayer times.'**
  String get searchFirst;

  /// No description provided for @routesTitle.
  ///
  /// In en, this message translates to:
  /// **'Route comparison'**
  String get routesTitle;

  /// No description provided for @journeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Journey details'**
  String get journeyTitle;

  /// No description provided for @tripTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip planner'**
  String get tripTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @labelFastest.
  ///
  /// In en, this message translates to:
  /// **'Fastest route'**
  String get labelFastest;

  /// No description provided for @labelBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced route'**
  String get labelBalanced;

  /// No description provided for @labelPrayerFriendly.
  ///
  /// In en, this message translates to:
  /// **'Prayer-friendly route'**
  String get labelPrayerFriendly;

  /// No description provided for @totalDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get totalDistance;

  /// No description provided for @totalDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get totalDuration;

  /// No description provided for @arrivalTime.
  ///
  /// In en, this message translates to:
  /// **'Arrival'**
  String get arrivalTime;

  /// No description provided for @detourVsFastest.
  ///
  /// In en, this message translates to:
  /// **'Detour vs fastest'**
  String get detourVsFastest;

  /// No description provided for @mosqueStops.
  ///
  /// In en, this message translates to:
  /// **'Mosque stops'**
  String get mosqueStops;

  /// No description provided for @whyChosen.
  ///
  /// In en, this message translates to:
  /// **'Why this route'**
  String get whyChosen;

  /// No description provided for @uncertainties.
  ///
  /// In en, this message translates to:
  /// **'Uncertain / unverified'**
  String get uncertainties;

  /// No description provided for @servedPrayers.
  ///
  /// In en, this message translates to:
  /// **'Prayers served'**
  String get servedPrayers;

  /// No description provided for @missedPrayers.
  ///
  /// In en, this message translates to:
  /// **'Prayers not stopped for'**
  String get missedPrayers;

  /// No description provided for @selectRoute.
  ///
  /// In en, this message translates to:
  /// **'View journey'**
  String get selectRoute;

  /// No description provided for @stopsTimeline.
  ///
  /// In en, this message translates to:
  /// **'Stops and legs'**
  String get stopsTimeline;

  /// No description provided for @origin.
  ///
  /// In en, this message translates to:
  /// **'Origin'**
  String get origin;

  /// No description provided for @destination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destination;

  /// No description provided for @arriveAt.
  ///
  /// In en, this message translates to:
  /// **'Arrive {time}'**
  String arriveAt(String time);

  /// No description provided for @departAt.
  ///
  /// In en, this message translates to:
  /// **'Depart {time}'**
  String departAt(String time);

  /// No description provided for @prayerAt.
  ///
  /// In en, this message translates to:
  /// **'{prayer} at {time}'**
  String prayerAt(String prayer, String time);

  /// No description provided for @rationale.
  ///
  /// In en, this message translates to:
  /// **'Why this stop'**
  String get rationale;

  /// No description provided for @alternativeMosques.
  ///
  /// In en, this message translates to:
  /// **'{n} alternative mosques nearby'**
  String alternativeMosques(int n);

  /// No description provided for @mosqueDetails.
  ///
  /// In en, this message translates to:
  /// **'Mosque details'**
  String get mosqueDetails;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening hours'**
  String get openingHours;

  /// No description provided for @hoursUnknown.
  ///
  /// In en, this message translates to:
  /// **'Opening hours not published by the data source.'**
  String get hoursUnknown;

  /// No description provided for @hoursUnverified.
  ///
  /// In en, this message translates to:
  /// **'Hours are provider-supplied and not independently verified.'**
  String get hoursUnverified;

  /// No description provided for @hoursVerified.
  ///
  /// In en, this message translates to:
  /// **'Hours confirmed by the data source.'**
  String get hoursVerified;

  /// No description provided for @congregationUnknown.
  ///
  /// In en, this message translates to:
  /// **'Congregation (iqama) time unknown — only the calculated prayer start is shown.'**
  String get congregationUnknown;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @wheelchair.
  ///
  /// In en, this message translates to:
  /// **'Wheelchair accessible'**
  String get wheelchair;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @notSpecified.
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get notSpecified;

  /// No description provided for @dataFrom.
  ///
  /// In en, this message translates to:
  /// **'Data source'**
  String get dataFrom;

  /// No description provided for @liveData.
  ///
  /// In en, this message translates to:
  /// **'Live data'**
  String get liveData;

  /// No description provided for @fixtureData.
  ///
  /// In en, this message translates to:
  /// **'Development data'**
  String get fixtureData;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open directions in maps'**
  String get openInMaps;

  /// No description provided for @detourValue.
  ///
  /// In en, this message translates to:
  /// **'Detour {n} min'**
  String detourValue(Object n);

  /// No description provided for @tripName.
  ///
  /// In en, this message translates to:
  /// **'Trip name'**
  String get tripName;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get days;

  /// No description provided for @activities.
  ///
  /// In en, this message translates to:
  /// **'Sightseeing & activities'**
  String get activities;

  /// No description provided for @addActivity.
  ///
  /// In en, this message translates to:
  /// **'Add activity'**
  String get addActivity;

  /// No description provided for @activityName.
  ///
  /// In en, this message translates to:
  /// **'Activity name'**
  String get activityName;

  /// No description provided for @durationMin.
  ///
  /// In en, this message translates to:
  /// **'Duration (min)'**
  String get durationMin;

  /// No description provided for @dayIndex.
  ///
  /// In en, this message translates to:
  /// **'Day (0-based starts at 1 in list)'**
  String get dayIndex;

  /// No description provided for @planTrip.
  ///
  /// In en, this message translates to:
  /// **'Plan trip'**
  String get planTrip;

  /// No description provided for @saveTrip.
  ///
  /// In en, this message translates to:
  /// **'Save itinerary'**
  String get saveTrip;

  /// No description provided for @savedTrips.
  ///
  /// In en, this message translates to:
  /// **'Saved itineraries'**
  String get savedTrips;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @conflict.
  ///
  /// In en, this message translates to:
  /// **'Conflict'**
  String get conflict;

  /// No description provided for @overnight.
  ///
  /// In en, this message translates to:
  /// **'Overnight'**
  String get overnight;

  /// No description provided for @paceLabel.
  ///
  /// In en, this message translates to:
  /// **'Planned activity minutes per day'**
  String get paceLabel;

  /// No description provided for @nothingPlanned.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned yet.'**
  String get nothingPlanned;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @prayerMethod.
  ///
  /// In en, this message translates to:
  /// **'Prayer calculation method'**
  String get prayerMethod;

  /// No description provided for @asrSchool.
  ///
  /// In en, this message translates to:
  /// **'Asr calculation'**
  String get asrSchool;

  /// No description provided for @asrStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard (Shafi\'i, Maliki, Hanbali)'**
  String get asrStandard;

  /// No description provided for @asrHanafi.
  ///
  /// In en, this message translates to:
  /// **'Hanafi'**
  String get asrHanafi;

  /// No description provided for @highLatitude.
  ///
  /// In en, this message translates to:
  /// **'High-latitude rule'**
  String get highLatitude;

  /// No description provided for @unsupportedByProvider.
  ///
  /// In en, this message translates to:
  /// **'Not supported by the active provider'**
  String get unsupportedByProvider;

  /// No description provided for @manualAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Manual adjustments (minutes)'**
  String get manualAdjustments;

  /// No description provided for @timeFormat.
  ///
  /// In en, this message translates to:
  /// **'Time format'**
  String get timeFormat;

  /// No description provided for @time24.
  ///
  /// In en, this message translates to:
  /// **'24-hour'**
  String get time24;

  /// No description provided for @time12.
  ///
  /// In en, this message translates to:
  /// **'12-hour'**
  String get time12;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get units;

  /// No description provided for @unitsMetric.
  ///
  /// In en, this message translates to:
  /// **'Metric (km)'**
  String get unitsMetric;

  /// No description provided for @unitsImperial.
  ///
  /// In en, this message translates to:
  /// **'Imperial (mi)'**
  String get unitsImperial;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Prayer stop reminders'**
  String get notifications;

  /// No description provided for @notificationsNote.
  ///
  /// In en, this message translates to:
  /// **'Preference is saved; on-device reminder scheduling is not yet available in this build.'**
  String get notificationsNote;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get darkMode;

  /// No description provided for @backendStatus.
  ///
  /// In en, this message translates to:
  /// **'Backend provider status'**
  String get backendStatus;

  /// No description provided for @mapFallbackNote.
  ///
  /// In en, this message translates to:
  /// **'OpenStreetMap preview — set the Google Maps key to use Google Maps'**
  String get mapFallbackNote;

  /// No description provided for @prayerProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Prayer provider'**
  String get prayerProviderLabel;

  /// No description provided for @demoMode.
  ///
  /// In en, this message translates to:
  /// **'Demo data (offline preview)'**
  String get demoMode;

  /// No description provided for @demoModeNote.
  ///
  /// In en, this message translates to:
  /// **'Shows clearly-marked sample journeys without a backend.'**
  String get demoModeNote;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the server — check the backend address in Settings.'**
  String get errorNetwork;

  /// No description provided for @errorProvider.
  ///
  /// In en, this message translates to:
  /// **'A data provider failed: {message}'**
  String errorProvider(String message);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved data from {time}.'**
  String offlineBanner(Object time);

  /// No description provided for @fixtureBanner.
  ///
  /// In en, this message translates to:
  /// **'Development fixtures active — data is simulated, not live.'**
  String get fixtureBanner;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @unitsKmValue.
  ///
  /// In en, this message translates to:
  /// **'{n} km'**
  String unitsKmValue(String n);

  /// No description provided for @hoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} min'**
  String hoursMinutes(int h, int m);

  /// No description provided for @inTime.
  ///
  /// In en, this message translates to:
  /// **'in {time}'**
  String inTime(String time);

  /// No description provided for @countdownDays.
  ///
  /// In en, this message translates to:
  /// **'{d}d {h}h'**
  String countdownDays(int d, int h);

  /// No description provided for @countdownHours.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String countdownHours(int h, int m);

  /// No description provided for @countdownMinutes.
  ///
  /// In en, this message translates to:
  /// **'{m}m'**
  String countdownMinutes(int m);

  /// No description provided for @backendUrl.
  ///
  /// In en, this message translates to:
  /// **'Backend address'**
  String get backendUrl;

  /// No description provided for @backendUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. http://10.0.2.2:8000 (Android emulator)'**
  String get backendUrlHint;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @providerReport.
  ///
  /// In en, this message translates to:
  /// **'Prayer: {prayer} · Routing: {routing} · Mosques: {mosques}'**
  String providerReport(String prayer, String routing, String mosques);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

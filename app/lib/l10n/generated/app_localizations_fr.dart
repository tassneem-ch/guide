// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Guide';

  @override
  String get homeTitle => 'Planifier un voyage';

  @override
  String get fromLabel => 'Départ';

  @override
  String get toLabel => 'Arrivée';

  @override
  String get searchHint => 'Ville, adresse ou lieu';

  @override
  String get useMyLocation => 'Utiliser ma position';

  @override
  String get locationDenied =>
      'Permission de localisation refusée — saisissez un lieu manuellement.';

  @override
  String get swapButton => 'Inverser';

  @override
  String get addWaypoint => 'Ajouter une étape';

  @override
  String waypoint(int n) {
    return 'Étape $n';
  }

  @override
  String get departureTime => 'Départ';

  @override
  String get departNow => 'Partir maintenant';

  @override
  String get chooseTime => 'Choisir l\'heure';

  @override
  String get travelMode => 'Mode de transport';

  @override
  String get modeDriving => 'Voiture';

  @override
  String get modeWalking => 'À pied';

  @override
  String get modeCycling => 'Vélo';

  @override
  String get preference => 'Priorité';

  @override
  String get prefFastest => 'Le plus rapide';

  @override
  String get prefBalanced => 'Équilibré';

  @override
  String get prefPrayerFriendly => 'Adapté à la prière';

  @override
  String get prayerStopsLabel => 'Arrêts prière';

  @override
  String get stopsOptional => 'Facultatif';

  @override
  String get stopsMandatory => 'Obligatoire';

  @override
  String get stopsNone => 'Aucun';

  @override
  String get advancedOptions => 'Limites de planification';

  @override
  String get maxDetour => 'Détour maximal vers une mosquée';

  @override
  String get stopDuration => 'Durée de l\'arrêt';

  @override
  String get planningWindow => 'Fenêtre d\'attente (arriver en avance)';

  @override
  String get prayerBuffer => 'Marge après le début de la prière';

  @override
  String minutesShort(int n) {
    return '$n min';
  }

  @override
  String get planRoute => 'Planifier l\'itinéraire';

  @override
  String get nextPrayer => 'Prochaine prière';

  @override
  String get todayPrayers => 'Prière d\'aujourd\'hui';

  @override
  String get noPrayerData => 'Horaires de prière indisponibles';

  @override
  String get prayerFajr => 'Fajr';

  @override
  String get prayerDhuhr => 'Dhouhr';

  @override
  String get prayerAsr => 'Asr';

  @override
  String get prayerMaghrib => 'Maghrib';

  @override
  String get prayerIsha => 'Isha';

  @override
  String get searchFirst =>
      'Choisissez un point de départ pour voir les horaires de prière.';

  @override
  String get routesTitle => 'Comparaison des itinéraires';

  @override
  String get journeyTitle => 'Détails du voyage';

  @override
  String get tripTitle => 'Planificateur de voyage';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get labelFastest => 'Itinéraire le plus rapide';

  @override
  String get labelBalanced => 'Itinéraire équilibré';

  @override
  String get labelPrayerFriendly => 'Itinéraire adapté à la prière';

  @override
  String get totalDistance => 'Distance';

  @override
  String get totalDuration => 'Durée';

  @override
  String get arrivalTime => 'Arrivée';

  @override
  String get detourVsFastest => 'Détour vs le plus rapide';

  @override
  String get mosqueStops => 'Arrêts mosquée';

  @override
  String get whyChosen => 'Pourquoi cet itinéraire';

  @override
  String get uncertainties => 'Incertain / non vérifié';

  @override
  String get servedPrayers => 'Prières desservies';

  @override
  String get missedPrayers => 'Prières sans arrêt';

  @override
  String get selectRoute => 'Voir le voyage';

  @override
  String get stopsTimeline => 'Étapes et trajets';

  @override
  String get origin => 'Départ';

  @override
  String get destination => 'Arrivée';

  @override
  String arriveAt(String time) {
    return 'Arrivée $time';
  }

  @override
  String departAt(String time) {
    return 'Départ $time';
  }

  @override
  String prayerAt(String prayer, String time) {
    return '$prayer à $time';
  }

  @override
  String get rationale => 'Pourquoi cet arrêt';

  @override
  String alternativeMosques(int n) {
    return '$n mosquées alternatives à proximité';
  }

  @override
  String get mosqueDetails => 'Détails de la mosquée';

  @override
  String get openingHours => 'Horaires d\'ouverture';

  @override
  String get hoursUnknown =>
      'Le fournisseur de données ne publie pas les horaires.';

  @override
  String get hoursUnverified =>
      'Horaires fournis par la source, non vérifiés indépendamment.';

  @override
  String get hoursVerified => 'Horaires confirmés par la source de données.';

  @override
  String get congregationUnknown =>
      'Heure d\'iqama inconnue — seul le début calculé de la prière est affiché.';

  @override
  String get phone => 'Téléphone';

  @override
  String get website => 'Site web';

  @override
  String get wheelchair => 'Accessible en fauteuil roulant';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get notSpecified => 'Non précisé';

  @override
  String get dataFrom => 'Source des données';

  @override
  String get liveData => 'Données en direct';

  @override
  String get fixtureData => 'Données de développement';

  @override
  String get openInMaps => 'Ouvrir l\'itinéraire dans les cartes';

  @override
  String detourValue(Object n) {
    return 'Détour $n min';
  }

  @override
  String get tripName => 'Nom du voyage';

  @override
  String get days => 'Jours';

  @override
  String get activities => 'Visites et activités';

  @override
  String get addActivity => 'Ajouter une activité';

  @override
  String get activityName => 'Nom de l\'activité';

  @override
  String get durationMin => 'Durée (min)';

  @override
  String get dayIndex => 'Jour (numérotation à partir de 1)';

  @override
  String get planTrip => 'Planifier le voyage';

  @override
  String get saveTrip => 'Enregistrer l\'itinéraire';

  @override
  String get savedTrips => 'Itinéraires enregistrés';

  @override
  String get resume => 'Reprendre';

  @override
  String get delete => 'Supprimer';

  @override
  String get conflict => 'Conflit';

  @override
  String get overnight => 'Nuit sur place';

  @override
  String get paceLabel => 'Minutes d\'activité planifiées par jour';

  @override
  String get nothingPlanned => 'Rien de planifié pour l\'instant.';

  @override
  String get language => 'Langue';

  @override
  String get prayerMethod => 'Méthode de calcul des prières';

  @override
  String get asrSchool => 'Calcul de Asr';

  @override
  String get asrStandard => 'Standard (chaféite, malikite, hanbalite)';

  @override
  String get asrHanafi => 'Hanafite';

  @override
  String get highLatitude => 'Règle des hautes latitudes';

  @override
  String get unsupportedByProvider =>
      'Non pris en charge par le fournisseur actif';

  @override
  String get manualAdjustments => 'Ajustements manuels (minutes)';

  @override
  String get timeFormat => 'Format horaire';

  @override
  String get time24 => '24 heures';

  @override
  String get time12 => '12 heures';

  @override
  String get units => 'Unités';

  @override
  String get unitsMetric => 'Métrique (km)';

  @override
  String get unitsImperial => 'Impérial (miles)';

  @override
  String get notifications => 'Rappels d\'arrêt de prière';

  @override
  String get notificationsNote =>
      'La préférence est enregistrée ; les rappels locaux ne sont pas encore disponibles dans cette version.';

  @override
  String get appearance => 'Apparence';

  @override
  String get darkMode => 'Thème sombre';

  @override
  String get backendStatus => 'État des fournisseurs du backend';

  @override
  String get prayerProviderLabel => 'Fournisseur de prière';

  @override
  String get demoMode => 'Données de démonstration (aperçu hors ligne)';

  @override
  String get demoModeNote =>
      'Affiche des trajets d\'exemple clairement marqués sans backend.';

  @override
  String get loading => 'Chargement…';

  @override
  String get errorGeneric => 'Une erreur est survenue';

  @override
  String get errorNetwork =>
      'Impossible de joindre le serveur — vérifiez l\'adresse du backend dans les paramètres.';

  @override
  String errorProvider(String message) {
    return 'Un fournisseur de données a échoué : $message';
  }

  @override
  String get retry => 'Réessayer';

  @override
  String offlineBanner(Object time) {
    return 'Hors ligne — données enregistrées du $time.';
  }

  @override
  String get fixtureBanner =>
      'Fixtures de développement actives — données simulées, pas en direct.';

  @override
  String get noResults => 'Aucun résultat';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get close => 'Fermer';

  @override
  String get done => 'Terminé';

  @override
  String get requiredField => 'Obligatoire';

  @override
  String get unknown => 'Inconnu';

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
    return 'dans $time';
  }

  @override
  String countdownDays(int d, int h) {
    return '$d j $h h';
  }

  @override
  String countdownHours(int h, int m) {
    return '$h h $m min';
  }

  @override
  String countdownMinutes(int m) {
    return '$m min';
  }

  @override
  String get backendUrl => 'Adresse du backend';

  @override
  String get backendUrlHint => 'ex. http://10.0.2.2:8000 (émulateur Android)';

  @override
  String get resetToDefault => 'Rétablir par défaut';

  @override
  String get settingsSaved => 'Paramètres enregistrés';

  @override
  String providerReport(String prayer, String routing, String mosques) {
    return 'Prière : $prayer · Itinéraire : $routing · Mosquées : $mosques';
  }
}

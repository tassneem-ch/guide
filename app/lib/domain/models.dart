/// Domain entities — pure Dart, mirroring the backend contract.
///
/// Every externally derived fact keeps its provenance: `live` flags whether
/// data came from a live provider, and verification enums mark what a source
/// actually confirmed. Nothing here invents data.
library;

// ---------------------------------------------------------------------------
// Geo
// ---------------------------------------------------------------------------

class GeoPoint {
  const GeoPoint({required this.lat, required this.lon, this.tz, this.name});

  final double lat;
  final double lon;
  final String? tz;
  final String? name;

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        tz: json['tz'] as String?,
        name: json['name'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lon': lon, if (tz != null) 'tz': tz, if (name != null) 'name': name};

  GeoPoint copyWith({String? name}) =>
      GeoPoint(lat: lat, lon: lon, tz: tz, name: name ?? this.name);

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

/// One autocomplete suggestion.
///
/// Either [point] is already resolved (keyless provider path), or only [id]
/// is present and the suggestion must be resolved through
/// `GeocodeRepository.resolveSuggestion` before its coordinates can be used.
/// A suggestion without [point] is never treated as a location.
class PlaceSuggestion {
  const PlaceSuggestion({required this.label, this.id, this.point});

  final String? id;
  final String label;
  final GeoPoint? point;
}

// ---------------------------------------------------------------------------
// Prayer
// ---------------------------------------------------------------------------

enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

class PrayerEvent {
  const PrayerEvent({
    required this.name,
    required this.utc,
    required this.local,
    required this.tz,
    required this.localDate,
    required this.method,
    required this.school,
    required this.source,
    required this.live,
    this.congregationUtc,
    this.congregationVerified = false,
    this.notes = const [],
  });

  final PrayerName name;
  final DateTime utc; // parsed as UTC
  final DateTime local; // naive wall-clock date/time
  final String tz;
  final String localDate; // yyyy-MM-dd
  final String method;
  final String school;
  final String source;
  final bool live;
  final DateTime? congregationUtc;
  final bool congregationVerified;
  final List<String> notes;

  factory PrayerEvent.fromJson(Map<String, dynamic> json) => PrayerEvent(
        name: PrayerName.values.byName(json['name'] as String),
        utc: DateTime.parse(json['utc'] as String).toUtc(),
        local: _naive(json['local'] as String),
        tz: json['tz'] as String,
        localDate: json['local_date'] as String,
        method: json['method'] as String,
        school: json['school'] as String,
        source: json['source'] as String,
        live: json['live'] as bool? ?? false,
        congregationUtc: json['congregation_utc'] == null
            ? null
            : DateTime.parse(json['congregation_utc'] as String).toUtc(),
        congregationVerified: json['congregation_verified'] as bool? ?? false,
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
      );

  /// Wire format matching [PrayerEvent.fromJson] (used for response caching).
  Map<String, dynamic> toJson() => {
        'name': name.name,
        'utc': utc.toUtc().toIso8601String(),
        'local': local.toIso8601String(),
        'tz': tz,
        'local_date': localDate,
        'method': method,
        'school': school,
        'source': source,
        'live': live,
        'congregation_utc': congregationUtc?.toUtc().toIso8601String(),
        'congregation_verified': congregationVerified,
        'notes': notes,
      };
}

class DayPrayers {
  const DayPrayers({
    required this.location,
    required this.localDate,
    required this.tz,
    required this.events,
    required this.source,
    required this.live,
    this.fetchedAt,
  });

  final GeoPoint location;
  final String localDate;
  final String tz;
  final List<PrayerEvent> events;
  final String source;
  final bool live;
  final DateTime? fetchedAt;

  factory DayPrayers.fromJson(Map<String, dynamic> json) => DayPrayers(
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        localDate: json['local_date'] as String,
        tz: json['tz'] as String,
        events: (json['events'] as List)
            .map((e) => PrayerEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: json['source'] as String,
        live: json['live'] as bool? ?? false,
        fetchedAt: json['fetched_at'] == null
            ? null
            : DateTime.tryParse(json['fetched_at'] as String),
      );

  /// Wire format matching [DayPrayers.fromJson] (used for response caching).
  Map<String, dynamic> toJson() => {
        'location': location.toJson(),
        'local_date': localDate,
        'tz': tz,
        'events': events.map((e) => e.toJson()).toList(),
        'source': source,
        'live': live,
        'fetched_at': fetchedAt?.toUtc().toIso8601String(),
      };
}

class MethodOption {
  const MethodOption({required this.id, required this.label});

  final String id;
  final String label;

  factory MethodOption.fromJson(Map<String, dynamic> json) =>
      MethodOption(id: json['id'] as String, label: json['label'] as String);
}

class PrayerCapabilities {
  const PrayerCapabilities({
    required this.provider,
    required this.live,
    required this.methods,
    required this.schools,
    required this.highLatitudeRules,
    required this.manualAdjustments,
    required this.supportsFutureDates,
    this.notes = const [],
  });

  final String provider;
  final bool live;
  final List<MethodOption> methods;
  final List<String> schools;
  final List<String> highLatitudeRules;
  final bool manualAdjustments;
  final bool supportsFutureDates;
  final List<String> notes;

  factory PrayerCapabilities.fromJson(Map<String, dynamic> json) =>
      PrayerCapabilities(
        provider: json['provider'] as String,
        live: json['live'] as bool? ?? false,
        methods: (json['methods'] as List)
            .map((m) => MethodOption.fromJson(m as Map<String, dynamic>))
            .toList(),
        schools: (json['schools'] as List).cast<String>(),
        highLatitudeRules: (json['high_latitude_rules'] as List).cast<String>(),
        manualAdjustments: json['manual_adjustments'] as bool? ?? false,
        supportsFutureDates: json['supports_future_dates'] as bool? ?? true,
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
      );
}

// ---------------------------------------------------------------------------
// Prayer configuration (sent to the backend)
// ---------------------------------------------------------------------------

class PrayerConfig {
  const PrayerConfig({
    this.method = 'mwl',
    this.school = 'standard',
    this.highLatitudeRule = 'middle_of_the_night',
    this.adjustments = const {},
    this.midnightMode = 'standard',
  });

  final String method;
  final String school;
  final String highLatitudeRule;
  final Map<String, int> adjustments;
  final String midnightMode;

  Map<String, dynamic> toJson() => {
        'method': method,
        'school': school,
        'high_latitude_rule': highLatitudeRule,
        'adjustments': adjustments,
        'midnight_mode': midnightMode,
      };
}

// ---------------------------------------------------------------------------
// Mosques
// ---------------------------------------------------------------------------

class DataQuality {
  const DataQuality({
    required this.provider,
    required this.source,
    this.fetchedAt,
    this.stalenessSeconds = 0,
    this.locationAccuracyM,
    this.notes = const [],
  });

  final String provider;
  final String source; // "live" | "fixture"
  final DateTime? fetchedAt;
  final int stalenessSeconds;
  final double? locationAccuracyM;
  final List<String> notes;

  factory DataQuality.fromJson(Map<String, dynamic> json) => DataQuality(
        provider: json['provider'] as String,
        source: json['source'] as String,
        fetchedAt: json['fetched_at'] == null
            ? null
            : DateTime.tryParse(json['fetched_at'] as String),
        stalenessSeconds: json['staleness_seconds'] as int? ?? 0,
        locationAccuracyM: (json['location_accuracy_m'] as num?)?.toDouble(),
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
      );

  bool get isFixture => source != 'live';
}

class MosqueCandidate {
  const MosqueCandidate({
    required this.id,
    required this.name,
    required this.location,
    required this.quality,
    this.openingHours,
    this.openingHoursVerification = 'unknown',
    this.phone,
    this.website,
    this.wheelchairAccessible,
    this.detourSeconds,
    this.detourDistanceM,
    this.detourMethod,
    this.congregationUtc,
    this.congregationVerified = false,
    this.alternatives = const [],
  });

  final String id;
  final String? name;
  final GeoPoint location;
  final DataQuality quality;
  final String? openingHours;
  final String openingHoursVerification; // verified | unverified | unknown | absent
  final String? phone;
  final String? website;
  final bool? wheelchairAccessible;
  final int? detourSeconds;
  final int? detourDistanceM;
  final String? detourMethod; // routed | great_circle_estimate
  final DateTime? congregationUtc;
  final bool congregationVerified;
  final List<String> alternatives;

  String get label => name ?? 'Unnamed mosque';

  factory MosqueCandidate.fromJson(Map<String, dynamic> json) =>
      MosqueCandidate(
        id: json['id'] as String,
        name: json['name'] as String?,
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        quality: DataQuality.fromJson(json['quality'] as Map<String, dynamic>),
        openingHours: json['opening_hours'] as String?,
        openingHoursVerification:
            json['opening_hours_verification'] as String? ?? 'unknown',
        phone: json['phone'] as String?,
        website: json['website'] as String?,
        wheelchairAccessible: json['wheelchair_accessible'] as bool?,
        detourSeconds: json['detour_seconds'] as int?,
        detourDistanceM: json['detour_distance_m'] as int?,
        detourMethod: json['detour_method'] as String?,
        congregationUtc: json['congregation_utc'] == null
            ? null
            : DateTime.parse(json['congregation_utc'] as String).toUtc(),
        congregationVerified: json['congregation_verified'] as bool? ?? false,
        alternatives:
            (json['alternatives'] as List?)?.cast<String>() ?? const [],
      );
}

// ---------------------------------------------------------------------------
// Routes / itinerary
// ---------------------------------------------------------------------------

enum TravelMode { driving, walking, cycling }

enum RoutePreference { fastest, balanced, prayerFriendly }

RoutePreference routePreferenceFrom(String value) => switch (value) {
      'fastest' => RoutePreference.fastest,
      'prayer_friendly' => RoutePreference.prayerFriendly,
      _ => RoutePreference.balanced,
    };

String routePreferenceTo(RoutePreference p) => switch (p) {
      RoutePreference.fastest => 'fastest',
      RoutePreference.prayerFriendly => 'prayer_friendly',
      RoutePreference.balanced => 'balanced',
    };

enum StopKind { origin, waypoint, destination, mosque, prayerBreak, attraction, meal, rest, overnight }

StopKind stopKindFrom(String value) => switch (value) {
      'origin' => StopKind.origin,
      'waypoint' => StopKind.waypoint,
      'destination' => StopKind.destination,
      'mosque' => StopKind.mosque,
      'prayer_break' => StopKind.prayerBreak,
      'attraction' => StopKind.attraction,
      'meal' => StopKind.meal,
      'rest' => StopKind.rest,
      'overnight' => StopKind.overnight,
      _ => StopKind.waypoint,
    };

class PlanningOptions {
  const PlanningOptions({
    this.preference = RoutePreference.balanced,
    this.maxDetourMin = 25,
    this.stopDurationMin = 15,
    this.planningWindowMin = 30,
    this.prayerBufferMin = 10,
    this.prayerStops = 'optional',
    this.weightDetour = 1.0,
    this.weightWaiting = 0.4,
    this.weightMissingPrayer = 20.0,
  });

  final RoutePreference preference;
  final int maxDetourMin;
  final int stopDurationMin;
  final int planningWindowMin;
  final int prayerBufferMin;
  final String prayerStops; // mandatory | optional | none
  final double weightDetour;
  final double weightWaiting;
  final double weightMissingPrayer;

  PlanningOptions copyWith({
    RoutePreference? preference,
    int? maxDetourMin,
    int? stopDurationMin,
    int? planningWindowMin,
    int? prayerBufferMin,
    String? prayerStops,
  }) =>
      PlanningOptions(
        preference: preference ?? this.preference,
        maxDetourMin: maxDetourMin ?? this.maxDetourMin,
        stopDurationMin: stopDurationMin ?? this.stopDurationMin,
        planningWindowMin: planningWindowMin ?? this.planningWindowMin,
        prayerBufferMin: prayerBufferMin ?? this.prayerBufferMin,
        prayerStops: prayerStops ?? this.prayerStops,
        weightDetour: weightDetour,
        weightWaiting: weightWaiting,
        weightMissingPrayer: weightMissingPrayer,
      );

  Map<String, dynamic> toJson() => {
        'preference': routePreferenceTo(preference),
        'max_detour_min': maxDetourMin,
        'stop_duration_min': stopDurationMin,
        'planning_window_min': planningWindowMin,
        'prayer_buffer_min': prayerBufferMin,
        'prayer_stops': prayerStops,
        'weight_detour': weightDetour,
        'weight_waiting': weightWaiting,
        'weight_missing_prayer': weightMissingPrayer,
      };
}

class TravelLeg {
  const TravelLeg({
    required this.from,
    required this.to,
    required this.departureUtc,
    required this.arrivalUtc,
    required this.distanceM,
    required this.durationS,
    required this.fromLabel,
    required this.toLabel,
  });

  final GeoPoint from;
  final GeoPoint to;
  final DateTime departureUtc;
  final DateTime arrivalUtc;
  final int distanceM;
  final int durationS;
  final String fromLabel;
  final String toLabel;

  factory TravelLeg.fromJson(Map<String, dynamic> json) => TravelLeg(
        from: GeoPoint.fromJson(json['from_point'] as Map<String, dynamic>),
        to: GeoPoint.fromJson(json['to_point'] as Map<String, dynamic>),
        departureUtc:
            DateTime.parse(json['departure_utc'] as String).toUtc(),
        arrivalUtc: DateTime.parse(json['arrival_utc'] as String).toUtc(),
        distanceM: json['distance_m'] as int,
        durationS: json['duration_s'] as int,
        fromLabel: json['from_label'] as String? ?? 'From',
        toLabel: json['to_label'] as String? ?? 'To',
      );
}

class ScheduledStop {
  const ScheduledStop({
    required this.kind,
    required this.name,
    required this.location,
    required this.arrivalUtc,
    required this.departureUtc,
    required this.locked,
    this.prayer,
    this.mosqueId,
    this.mosque,
    this.notes = const [],
    this.uncertainties = const [],
    this.rationale,
    this.detourSeconds = 0,
    this.detourDistanceM = 0,
  });

  final StopKind kind;
  final String name;
  final GeoPoint location;
  final DateTime arrivalUtc;
  final DateTime departureUtc;
  final bool locked;
  final PrayerEvent? prayer;
  final String? mosqueId;
  final MosqueCandidate? mosque;
  final List<String> notes;
  final List<String> uncertainties;
  final String? rationale;
  final int detourSeconds;
  final int detourDistanceM;

  int get durationS => departureUtc.difference(arrivalUtc).inSeconds;

  factory ScheduledStop.fromJson(Map<String, dynamic> json) => ScheduledStop(
        kind: stopKindFrom(json['kind'] as String),
        name: json['name'] as String,
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        arrivalUtc: DateTime.parse(json['arrival_utc'] as String).toUtc(),
        departureUtc: DateTime.parse(json['departure_utc'] as String).toUtc(),
        locked: json['locked'] as bool? ?? false,
        prayer: json['prayer'] == null
            ? null
            : PrayerEvent.fromJson(json['prayer'] as Map<String, dynamic>),
        mosqueId: json['mosque_id'] as String?,
        mosque: json['mosque'] == null
            ? null
            : MosqueCandidate.fromJson(json['mosque'] as Map<String, dynamic>),
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
        uncertainties:
            (json['uncertainties'] as List?)?.cast<String>() ?? const [],
        rationale: json['rationale'] as String?,
        detourSeconds: json['detour_seconds'] as int? ?? 0,
        detourDistanceM: json['detour_distance_m'] as int? ?? 0,
      );
}

class RouteMetrics {
  const RouteMetrics({
    required this.totalDistanceM,
    required this.totalDurationS,
    required this.drivingDurationS,
    required this.waitingDurationS,
    required this.detourDurationS,
    required this.detourDistanceM,
    required this.arrivalUtc,
    required this.arrivalLocal,
    required this.arrivalTz,
    required this.mosqueStopCount,
    required this.prayersServed,
    required this.prayersMissed,
  });

  final int totalDistanceM;
  final int totalDurationS;
  final int drivingDurationS;
  final int waitingDurationS;
  final int detourDurationS;
  final int detourDistanceM;
  final DateTime arrivalUtc;
  final String arrivalLocal;
  final String arrivalTz;
  final int mosqueStopCount;
  final List<String> prayersServed;
  final List<String> prayersMissed;

  factory RouteMetrics.fromJson(Map<String, dynamic> json) => RouteMetrics(
        totalDistanceM: json['total_distance_m'] as int,
        totalDurationS: json['total_duration_s'] as int,
        drivingDurationS: json['driving_duration_s'] as int,
        waitingDurationS: json['waiting_duration_s'] as int? ?? 0,
        detourDurationS: json['detour_duration_s'] as int? ?? 0,
        detourDistanceM: json['detour_distance_m'] as int? ?? 0,
        arrivalUtc: DateTime.parse(json['arrival_utc'] as String).toUtc(),
        arrivalLocal: json['arrival_local'] as String? ?? '',
        arrivalTz: json['arrival_tz'] as String? ?? '',
        mosqueStopCount: json['mosque_stop_count'] as int? ?? 0,
        prayersServed: (json['prayers_served'] as List?)?.cast<String>() ??
            const [],
        prayersMissed: (json['prayers_missed'] as List?)?.cast<String>() ??
            const [],
      );
}

class RoutePlan {
  const RoutePlan({
    required this.preference,
    required this.legs,
    required this.stops,
    required this.metrics,
    required this.prayerEvents,
    required this.explanation,
    required this.uncertainties,
    required this.routeProvider,
    required this.routeLive,
    required this.geometry,
    required this.feasible,
    this.infeasibilityReason,
  });

  final RoutePreference preference;
  final List<TravelLeg> legs;
  final List<ScheduledStop> stops;
  final RouteMetrics metrics;
  final List<PrayerEvent> prayerEvents;
  final List<String> explanation;
  final List<String> uncertainties;
  final String routeProvider;
  final bool routeLive;
  final List<GeoPoint> geometry;
  final bool feasible;
  final String? infeasibilityReason;

  bool get isFixture => !routeLive;

  factory RoutePlan.fromJson(Map<String, dynamic> json) => RoutePlan(
        preference: routePreferenceFrom(json['preference'] as String),
        legs: (json['legs'] as List)
            .map((l) => TravelLeg.fromJson(l as Map<String, dynamic>))
            .toList(),
        stops: (json['stops'] as List)
            .map((s) => ScheduledStop.fromJson(s as Map<String, dynamic>))
            .toList(),
        metrics:
            RouteMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
        prayerEvents: (json['prayer_events'] as List?)
                ?.map((e) => PrayerEvent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        explanation: (json['explanation'] as List?)?.cast<String>() ?? const [],
        uncertainties:
            (json['uncertainties'] as List?)?.cast<String>() ?? const [],
        routeProvider: json['route_provider'] as String,
        routeLive: json['route_live'] as bool? ?? false,
        geometry: (json['geometry'] as List?)
                ?.map((p) => GeoPoint.fromJson(p as Map<String, dynamic>))
                .toList() ??
            const [],
        feasible: json['feasible'] as bool? ?? true,
        infeasibilityReason: json['infeasibility_reason'] as String?,
      );
}

class RouteResponse {
  const RouteResponse({
    required this.alternatives,
    required this.requestedAt,
    this.notes = const [],
    this.providers = const {},
    this.stale = false,
    this.staleAt,
  });

  final List<RoutePlan> alternatives;
  final DateTime requestedAt;
  final List<String> notes;
  final Map<String, String> providers;
  /// True when served from the local cache (offline / server unreachable).
  final bool stale;
  final DateTime? staleAt;

  factory RouteResponse.fromJson(Map<String, dynamic> json,
          {bool stale = false, DateTime? staleAt}) =>
      RouteResponse(
        alternatives: (json['alternatives'] as List)
            .map((a) => RoutePlan.fromJson(a as Map<String, dynamic>))
            .toList(),
        requestedAt:
            DateTime.parse(json['requested_at'] as String).toUtc(),
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
        providers: (json['providers'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        stale: stale,
        staleAt: staleAt,
      );
}

// ---------------------------------------------------------------------------
// Trips
// ---------------------------------------------------------------------------

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.name,
    this.location,
    this.plannedDurationMin = 90,
    this.earliestStartLocal,
    this.latestStartLocal,
    this.locked = false,
    this.dayIndex = 0,
  });

  final String id;
  final String name;
  final GeoPoint? location;
  final int plannedDurationMin;
  final String? earliestStartLocal;
  final String? latestStartLocal;
  final bool locked;
  final int dayIndex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (location != null) 'location': location!.toJson(),
        'planned_duration_min': plannedDurationMin,
        if (earliestStartLocal != null)
          'earliest_start_local': earliestStartLocal,
        if (latestStartLocal != null) 'latest_start_local': latestStartLocal,
        'locked': locked,
        'day_index': dayIndex,
      };

  factory ActivityItem.fromJson(Map<String, dynamic> json) => ActivityItem(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] == null
            ? null
            : GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        plannedDurationMin: json['planned_duration_min'] as int? ?? 90,
        earliestStartLocal: json['earliest_start_local'] as String?,
        latestStartLocal: json['latest_start_local'] as String?,
        locked: json['locked'] as bool? ?? false,
        dayIndex: json['day_index'] as int? ?? 0,
      );
}

class ScheduledActivity {
  const ScheduledActivity({
    required this.activity,
    required this.startUtc,
    required this.endUtc,
    required this.startLocal,
    this.notes = const [],
    this.conflicts = const [],
  });

  final ActivityItem activity;
  final DateTime startUtc;
  final DateTime endUtc;
  final String startLocal;
  final List<String> notes;
  final List<String> conflicts;

  factory ScheduledActivity.fromJson(Map<String, dynamic> json) =>
      ScheduledActivity(
        activity:
            ActivityItem.fromJson(json['activity'] as Map<String, dynamic>),
        startUtc: DateTime.parse(json['start_utc'] as String).toUtc(),
        endUtc: DateTime.parse(json['end_utc'] as String).toUtc(),
        startLocal: json['start_local'] as String,
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
        conflicts: (json['conflicts'] as List?)?.cast<String>() ?? const [],
      );
}

class DaySchedule {
  const DaySchedule({
    required this.index,
    required this.localDate,
    required this.city,
    required this.tz,
    this.legs = const [],
    this.stops = const [],
    this.activities = const [],
    this.overnight,
    this.prayerEvents = const [],
    this.explanation = const [],
    this.uncertainties = const [],
  });

  final int index;
  final String localDate;
  final String city;
  final String tz;
  final List<TravelLeg> legs;
  final List<ScheduledStop> stops;
  final List<ScheduledActivity> activities;
  final ScheduledStop? overnight;
  final List<PrayerEvent> prayerEvents;
  final List<String> explanation;
  final List<String> uncertainties;

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        index: json['index'] as int,
        localDate: json['local_date'] as String,
        city: json['city'] as String? ?? '',
        tz: json['tz'] as String? ?? 'UTC',
        legs: (json['legs'] as List?)
                ?.map((l) => TravelLeg.fromJson(l as Map<String, dynamic>))
                .toList() ??
            const [],
        stops: (json['stops'] as List?)
                ?.map((s) => ScheduledStop.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        activities: (json['activities'] as List?)
                ?.map((a) =>
                    ScheduledActivity.fromJson(a as Map<String, dynamic>))
                .toList() ??
            const [],
        overnight: json['overnight'] == null
            ? null
            : ScheduledStop.fromJson(
                json['overnight'] as Map<String, dynamic>),
        prayerEvents: (json['prayer_events'] as List?)
                ?.map((e) => PrayerEvent.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        explanation: (json['explanation'] as List?)?.cast<String>() ?? const [],
        uncertainties:
            (json['uncertainties'] as List?)?.cast<String>() ?? const [],
      );
}

class TripPlan {
  const TripPlan({
    required this.title,
    required this.days,
    required this.createdAt,
    required this.routeProvider,
    this.providers = const {},
    this.notes = const [],
    this.stale = false,
  });

  final String title;
  final List<DaySchedule> days;
  final DateTime createdAt;
  final String routeProvider;
  final Map<String, String> providers;
  final List<String> notes;
  final bool stale;

  factory TripPlan.fromJson(Map<String, dynamic> json, {bool stale = false}) =>
      TripPlan(
        title: json['title'] as String,
        days: (json['days'] as List)
            .map((d) => DaySchedule.fromJson(d as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        routeProvider: json['route_provider'] as String,
        providers: (json['providers'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        notes: (json['notes'] as List?)?.cast<String>() ?? const [],
        stale: stale,
      );
}

class SavedItinerary {
  const SavedItinerary({
    required this.id,
    required this.title,
    required this.kind,
    required this.updatedAt,
    this.data = const {},
  });

  final String id;
  final String title;
  final String kind;
  final DateTime updatedAt;
  final Map<String, dynamic> data;

  factory SavedItinerary.fromJson(Map<String, dynamic> json) =>
      SavedItinerary(
        id: json['id'] as String,
        title: json['title'] as String,
        kind: json['kind'] as String? ?? 'trip',
        updatedAt: (json['updated_at'] == null
                ? DateTime.now()
                : DateTime.tryParse(json['updated_at'] as String)) ??
            DateTime.now(),
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Parse a naive local ISO datetime (no zone) — keeps the wall-clock fields.
DateTime _naive(String iso) {
  final parsed = DateTime.parse(iso);
  return DateTime(
      parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute);
}

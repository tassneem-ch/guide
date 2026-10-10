import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart' as lm;

import '../../core/map_engine.dart';
import '../../domain/models.dart';
import '../../l10n/generated/app_localizations.dart';

/// The map surface used across the app (home preview + journey detail).
///
/// Engine selection happens here and only here:
/// - Google Maps (`google_maps_flutter`) when built with
///   `--dart-define=USE_GOOGLE_MAPS=true` and a Maps SDK key configured;
/// - OpenStreetMap (`flutter_map`, keyless) otherwise - visibly labeled, so
///   the user always knows which map engine produced what they see.
///
/// Both engines are fully interactive (pan, pinch zoom, double-tap zoom,
/// rotate), carry engine-agnostic zoom + my-location controls, refit the
/// camera when the plotted points change, and report taps through
/// [onMapTap] so a point on the map can become an origin or destination.
class AdaptiveMap extends StatelessWidget {
  const AdaptiveMap({
    super.key,
    required this.points,
    this.stops = const [],
    this.height,
    this.onMapTap,
  });

  /// Ordered points forming the polyline (a line is drawn from 2+ points).
  final List<GeoPoint> points;

  /// Extra markers (e.g. mosque stops).
  final List<ScheduledStop> stops;

  /// Fixed height; when null the map fills its parent.
  final double? height;

  /// Tap on the map (not drag) → coordinates picked by the user.
  final ValueChanged<GeoPoint>? onMapTap;

  @override
  Widget build(BuildContext context) {
    Widget map;
    if (useGoogleMaps) {
      map = _GoogleMapSurface(points: points, stops: stops, onMapTap: onMapTap);
    } else {
      map = _OsmMapSurface(points: points, stops: stops, onMapTap: onMapTap);
    }
    if (height != null) {
      map = SizedBox(height: height, child: map);
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Shared overlay controls + permission-aware "my location"
// ---------------------------------------------------------------------------

/// Resolve the device position, asking for permission only on demand.
/// Returns null when denied or unavailable (callers show the denial hint).
Future<GeoPoint?> _devicePosition(BuildContext context) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return GeoPoint(lat: position.latitude, lon: position.longitude);
  } catch (_) {
    return null;
  }
}

/// Zoom in / zoom out / my-location controls that sit above either engine.
class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onMyLocation,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onMyLocation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(String tooltip, IconData icon, VoidCallback onPressed) =>
        Material(
          color: Theme.of(context)
              .colorScheme
              .surface
              .withValues(alpha: 0.92),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: IconButton(
            tooltip: tooltip,
            iconSize: 20,
            icon: Icon(icon),
            onPressed: onPressed,
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(l10n.zoomIn, Icons.add, onZoomIn),
        const SizedBox(height: 6),
        button(l10n.zoomOut, Icons.remove, onZoomOut),
        const SizedBox(height: 10),
        button(l10n.useMyLocation, Icons.my_location, onMyLocation),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Google Maps engine
// ---------------------------------------------------------------------------

class _GoogleMapSurface extends StatefulWidget {
  const _GoogleMapSurface({
    required this.points,
    required this.stops,
    this.onMapTap,
  });

  final List<GeoPoint> points;
  final List<ScheduledStop> stops;
  final ValueChanged<GeoPoint>? onMapTap;

  @override
  State<_GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<_GoogleMapSurface> {
  gm.GoogleMapController? _controller;

  static gm.LatLng _ll(GeoPoint p) => gm.LatLng(p.lat, p.lon);

  static bool _samePoints(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lon != b[i].lon) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _GoogleMapSurface old) {
    super.didUpdateWidget(old);
    if (!_samePoints(old.points, widget.points)) {
      // Only an actual point change moves the camera — marker updates or
      // unrelated rebuilds never yank the view around.
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToPoints());
    }
  }

  Future<void> _fitToPoints() async {
    final controller = _controller;
    if (controller == null) return;
    final points = widget.points.map(_ll).toList();
    if (points.isEmpty) return;
    try {
      if (points.length >= 2) {
        final mosqueStops =
            widget.stops.where((s) => s.kind == StopKind.mosque).toList();
        await controller.animateCamera(
          gm.CameraUpdate.newLatLngBounds(_bounds(points, mosqueStops), 72),
        );
      } else {
        await controller.animateCamera(
            gm.CameraUpdate.newLatLngZoom(points.first, 12));
      }
    } catch (_) {
      // Bounds animation unsupported on some platforms - camera stays put.
    }
  }

  Future<void> _goToMyLocation() async {
    final position = await _devicePosition(context);
    if (position == null || !mounted) {
      _showDeniedHint();
      return;
    }
    await _controller?.animateCamera(gm.CameraUpdate.newLatLngZoom(
      gm.LatLng(position.lat, position.lon),
      13,
    ));
  }

  void _showDeniedHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text(AppLocalizations.of(context).locationDeniedShort)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points.map(_ll).toList();
    final mosqueStops =
        widget.stops.where((s) => s.kind == StopKind.mosque).toList();

    final markers = <gm.Marker>{
      if (points.isNotEmpty)
        gm.Marker(
          markerId: const gm.MarkerId('origin'),
          position: points.first,
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(
              gm.BitmapDescriptor.hueGreen),
        ),
      if (points.length > 1)
        gm.Marker(
          markerId: const gm.MarkerId('destination'),
          position: points.last,
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(
              gm.BitmapDescriptor.hueRed),
        ),
      for (final s in mosqueStops)
        gm.Marker(
          markerId: gm.MarkerId('mosque-${s.mosqueId ?? s.name}'),
          position: _ll(s.location),
          infoWindow: gm.InfoWindow(title: s.name),
          icon: gm.BitmapDescriptor.defaultMarkerWithHue(
              gm.BitmapDescriptor.hueAzure),
        ),
    };

    return Stack(
      children: [
        gm.GoogleMap(
          initialCameraPosition: _initialCamera(points),
          polylines: points.length >= 2
              ? {
                  gm.Polyline(
                    polylineId: const gm.PolylineId('route'),
                    points: points,
                    width: 5,
                    color: Colors.teal,
                  ),
                }
              : const {},
          markers: markers,
          // Explicit interactive-map configuration (never Lite/static mode).
          scrollGesturesEnabled: true,
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          zoomControlsEnabled: false, // replaced by engine-agnostic controls
          mapToolbarEnabled: false,
          myLocationEnabled: true,
          myLocationButtonEnabled: false, // replaced by engine-agnostic control
          // Claim gestures inside the platform view even while a draggable
          // sheet or card floats over parts of the map.
          gestureRecognizers: const {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          onMapCreated: (controller) {
            _controller = controller;
            if (points.length >= 2) {
              _fitToPoints();
            }
          },
          onTap: (latLng) => widget.onMapTap
              ?.call(GeoPoint(lat: latLng.latitude, lon: latLng.longitude)),
        ),
        Positioned(
          right: 12,
          bottom: 96,
          child: SafeArea(
            child: _MapControls(
              onZoomIn: () => _controller?.animateCamera(gm.CameraUpdate.zoomIn()),
              onZoomOut: () =>
                  _controller?.animateCamera(gm.CameraUpdate.zoomOut()),
              onMyLocation: _goToMyLocation,
            ),
          ),
        ),
      ],
    );
  }

  gm.CameraPosition _initialCamera(List<gm.LatLng> points) {
    if (points.isEmpty) {
      return const gm.CameraPosition(target: gm.LatLng(0, 0), zoom: 2);
    }
    if (points.length == 1) {
      return gm.CameraPosition(target: points.first, zoom: 12);
    }
    final bounds = _bounds(points, const []);
    final center = gm.LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    return gm.CameraPosition(target: center, zoom: 9);
  }

  gm.LatLngBounds _bounds(
      List<gm.LatLng> points, List<ScheduledStop> stops) {
    var south = points.first.latitude, north = south;
    var west = points.first.longitude, east = west;
    void grow(gm.LatLng p) {
      south = south < p.latitude ? south : p.latitude;
      north = north > p.latitude ? north : p.latitude;
      west = west < p.longitude ? west : p.longitude;
      east = east > p.longitude ? east : p.longitude;
    }

    for (final p in points.skip(1)) {
      grow(p);
    }
    for (final s in stops) {
      grow(_ll(s.location));
    }
    return gm.LatLngBounds(
        southwest: gm.LatLng(south, west),
        northeast: gm.LatLng(north, east));
  }
}

// ---------------------------------------------------------------------------
// OpenStreetMap fallback engine (keyless)
// ---------------------------------------------------------------------------

class _OsmMapSurface extends StatefulWidget {
  const _OsmMapSurface({
    required this.points,
    required this.stops,
    this.onMapTap,
  });

  final List<GeoPoint> points;
  final List<ScheduledStop> stops;
  final ValueChanged<GeoPoint>? onMapTap;

  @override
  State<_OsmMapSurface> createState() => _OsmMapSurfaceState();
}

class _OsmMapSurfaceState extends State<_OsmMapSurface> {
  final MapController _mapController = MapController();

  static bool _samePoints(List<GeoPoint> a, List<GeoPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].lat != b[i].lat || a[i].lon != b[i].lon) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant _OsmMapSurface old) {
    super.didUpdateWidget(old);
    if (!_samePoints(old.points, widget.points)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitToPoints());
    }
  }

  void _fitToPoints() {
    final lmPoints = widget.points.map(_toLm).toList();
    if (lmPoints.isEmpty) return;
    try {
      if (lmPoints.length >= 2) {
        final mosqueStops = widget.stops
            .where((s) => s.kind == StopKind.mosque)
            .map((s) => _toLm(s.location))
            .toList();
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([...lmPoints, ...mosqueStops]),
          padding: const EdgeInsets.all(56),
        ));
      } else {
        _mapController.move(lmPoints.first, 12);
      }
    } catch (_) {
      // Map not attached yet — the initial camera fit still applies.
    }
  }

  static lm.LatLng _toLm(GeoPoint p) => lm.LatLng(p.lat, p.lon);

  void _zoom(double delta) {
    try {
      final camera = _mapController.camera;
      _mapController.move(
          camera.center, (camera.zoom + delta).clamp(2.0, 19.0));
    } catch (_) {
      // Map not ready — ignore.
    }
  }

  Future<void> _goToMyLocation() async {
    final position = await _devicePosition(context);
    if (position == null || !mounted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context).locationDeniedShort)),
      );
      return;
    }
    try {
      final zoom = _mapController.camera.zoom;
      _mapController.move(_toLm(position), zoom < 13 ? 13 : zoom);
    } catch (_) {
      // Map not ready — ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lmPoints = widget.points.map(_toLm).toList();
    final mosqueStops =
        widget.stops.where((s) => s.kind == StopKind.mosque).toList();

    lm.LatLng center;
    double zoom;
    if (lmPoints.isEmpty) {
      center = const lm.LatLng(0, 0);
      zoom = 2;
    } else if (lmPoints.length == 1) {
      center = lmPoints.first;
      zoom = 12;
    } else {
      center = lm.LatLng(
        (lmPoints.first.latitude + lmPoints.last.latitude) / 2,
        (lmPoints.first.longitude + lmPoints.last.longitude) / 2,
      );
      zoom = 9;
    }

    final hasBounds = lmPoints.length >= 2 || mosqueStops.isNotEmpty;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            initialCameraFit: hasBounds && lmPoints.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      ...lmPoints,
                      for (final s in mosqueStops) _toLm(s.location),
                    ]),
                    padding: const EdgeInsets.all(56),
                  )
                : null,
            // Fully interactive: pan, pinch, rotate, double-tap, wheel.
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.all),
            onTap: (tapPosition, point) => widget.onMapTap?.call(
                GeoPoint(lat: point.latitude, lon: point.longitude)),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.guide.app',
            ),
            if (lmPoints.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                      points: lmPoints, strokeWidth: 5, color: Colors.teal),
                ],
              ),
            MarkerLayer(
              markers: [
                if (lmPoints.isNotEmpty)
                  Marker(
                    point: lmPoints.first,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.trip_origin,
                        color: Colors.green, size: 28),
                  ),
                if (lmPoints.length > 1)
                  Marker(
                    point: lmPoints.last,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.place, color: Colors.red, size: 30),
                  ),
                for (final s in mosqueStops)
                  Marker(
                    point: _toLm(s.location),
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message: s.name,
                      child: const Icon(Icons.mosque,
                          color: Colors.teal, size: 26),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ]),
          ],
        ),
        // Honest label: this is not Google Maps.
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 14),
                  const SizedBox(width: 6),
                  Text(l10n.mapFallbackNote,
                      style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 72,
          child: SafeArea(
            child: _MapControls(
              onZoomIn: () => _zoom(1),
              onZoomOut: () => _zoom(-1),
              onMyLocation: _goToMyLocation,
            ),
          ),
        ),
      ],
    );
  }
}

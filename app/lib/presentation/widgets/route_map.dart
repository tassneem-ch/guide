import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
/// A vendor swap in the future touches this widget only, not the screens.
class AdaptiveMap extends StatelessWidget {
  const AdaptiveMap({
    super.key,
    required this.points,
    this.stops = const [],
    this.height,
  });

  /// Ordered points forming the polyline (a line is drawn from 2+ points).
  final List<GeoPoint> points;

  /// Extra markers (e.g. mosque stops).
  final List<ScheduledStop> stops;

  /// Fixed height; when null the map fills its parent.
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget map;
    if (useGoogleMaps) {
      map = _GoogleMapSurface(points: points, stops: stops);
    } else {
      map = _OsmMapSurface(points: points, stops: stops);
    }
    if (height != null) {
      map = SizedBox(height: height, child: map);
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Google Maps engine
// ---------------------------------------------------------------------------

class _GoogleMapSurface extends StatefulWidget {
  const _GoogleMapSurface({required this.points, required this.stops});

  final List<GeoPoint> points;
  final List<ScheduledStop> stops;

  @override
  State<_GoogleMapSurface> createState() => _GoogleMapSurfaceState();
}

class _GoogleMapSurfaceState extends State<_GoogleMapSurface> {
  gm.GoogleMapController? _controller;

  static gm.LatLng _ll(GeoPoint p) => gm.LatLng(p.lat, p.lon);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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

    return gm.GoogleMap(
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
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      onMapCreated: (controller) {
        _controller = controller;
        if (points.length >= 2) {
          _fitBounds(controller, points, mosqueStops);
        }
      },
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

  Future<void> _fitBounds(gm.GoogleMapController controller,
      List<gm.LatLng> points, List<ScheduledStop> stops) async {
    try {
      await controller.animateCamera(
        gm.CameraUpdate.newLatLngBounds(_bounds(points, stops), 72),
      );
    } catch (_) {
      // Bounds animation unsupported on some platforms - initial camera stays.
    }
  }
}

// ---------------------------------------------------------------------------
// OpenStreetMap fallback engine (keyless)
// ---------------------------------------------------------------------------

class _OsmMapSurface extends StatelessWidget {
  const _OsmMapSurface({required this.points, required this.stops});

  final List<GeoPoint> points;
  final List<ScheduledStop> stops;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lmPoints = points.map((p) => lm.LatLng(p.lat, p.lon)).toList();
    final mosqueStops = stops.where((s) => s.kind == StopKind.mosque).toList();

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
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            initialCameraFit: hasBounds && lmPoints.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      ...lmPoints,
                      for (final s in mosqueStops)
                        lm.LatLng(s.location.lat, s.location.lon),
                    ]),
                    padding: const EdgeInsets.all(56),
                  )
                : null,
            interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom),
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
                    point: lm.LatLng(s.location.lat, s.location.lon),
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
      ],
    );
  }
}

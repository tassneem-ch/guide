import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/models.dart';

/// Map widget isolated from the rest of the app: today it's flutter_map with
/// OpenStreetMap tiles (keyless, no vendor account). A vendor SDK can replace
/// this single widget without touching screens.
///
/// Shows: route polyline, origin/destination and mosque stop markers.
/// Deliberately simple — no invented POIs, no fabricated map content.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.geometry,
    required this.stops,
  });

  final List<GeoPoint> geometry;
  final List<ScheduledStop> stops;

  @override
  Widget build(BuildContext context) {
    final points = geometry.map((p) => LatLng(p.lat, p.lon)).toList();
    final mosqueStops = stops.where((s) => s.kind == StopKind.mosque).toList();

    // flutter_map needs at least two points to fit bounds.
    if (points.length < 2) {
      return const SizedBox(
          height: 180, child: ColoredBox(color: Colors.black12));
    }

    final bounds = LatLngBounds.fromPoints(points);
    for (final s in mosqueStops) {
      bounds.extend(LatLng(s.location.lat, s.location.lon));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(36),
            ),
            interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.guide.app',
            ),
            PolylineLayer(
              polylines: [
                Polyline(points: points, strokeWidth: 4, color: Colors.teal),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: LatLng(points.first.latitude, points.first.longitude),
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.trip_origin,
                      color: Colors.green, size: 28),
                ),
                Marker(
                  point: LatLng(points.last.latitude, points.last.longitude),
                  width: 36,
                  height: 36,
                  child:
                      const Icon(Icons.place, color: Colors.red, size: 30),
                ),
                for (final s in mosqueStops)
                  Marker(
                    point: LatLng(s.location.lat, s.location.lon),
                    width: 36,
                    height: 36,
                    child: Tooltip(
                      message: s.name,
                      child:
                          const Icon(Icons.mosque, color: Colors.teal, size: 26),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ]),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapMarker {
  const MapMarker({required this.point, required this.child, this.size = 44});
  final LatLng point;
  final Widget child;
  final double size;
}

/// Map abstraction so OpenStreetMap can be swapped for Google Maps / Mapbox
/// later without touching the ride screens.
abstract interface class MapProvider {
  Widget buildMap({
    required List<LatLng> fitPoints,
    List<LatLng> polyline,
    List<MapMarker> markers,
    Color polylineColor,
  });
}

/// flutter_map + OpenStreetMap tiles.
/// NOTE: tile.openstreetmap.org is for development only. Production must use
/// a commercial tile provider or a self-hosted tile server (set TILE_URL).
class OsmMapProvider implements MapProvider {
  const OsmMapProvider({String? tileUrl}) : _tileUrl = tileUrl;

  static const _envTileUrl = String.fromEnvironment('TILE_URL');
  static const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  final String? _tileUrl;

  String get tileUrl => _tileUrl ?? (_envTileUrl.isEmpty ? _osmTileUrl : _envTileUrl);

  @override
  Widget buildMap({
    required List<LatLng> fitPoints,
    List<LatLng> polyline = const [],
    List<MapMarker> markers = const [],
    Color polylineColor = const Color(0xFF16A34A),
  }) {
    // Points on top of each other (a trip inside one spot) have no extent to fit: fitting them would zoom forever.
    final spread = fitPoints.length >= 2 &&
        fitPoints.any((p) => (p.latitude - fitPoints.first.latitude).abs() > 0.001 || (p.longitude - fitPoints.first.longitude).abs() > 0.001);
    final fit = spread
        ? CameraFit.coordinates(coordinates: fitPoints, padding: const EdgeInsets.all(56), maxZoom: 17)
        : null;
    return FlutterMap(
      options: MapOptions(
        initialCenter: fitPoints.isEmpty ? const LatLng(30.75, 72.5) : fitPoints.first,
        initialZoom: spread || fitPoints.isEmpty ? 11 : 15,
        initialCameraFit: fit,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
      ),
      children: [
        TileLayer(
          urlTemplate: tileUrl,
          // OSM tile policy requires an identifying User-Agent.
          userAgentPackageName: 'pk.kamgo.kamgo_app',
          maxNativeZoom: 18,
        ),
        if (polyline.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: polyline, strokeWidth: 5, color: polylineColor),
          ]),
        MarkerLayer(
          markers: [
            for (final m in markers)
              Marker(point: m.point, width: m.size, height: m.size, child: m.child),
          ],
        ),
        const SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
      ],
    );
  }
}

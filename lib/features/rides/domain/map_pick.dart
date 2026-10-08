import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../../core/services/routing_service.dart';
import 'ride_models.dart';

/// Farthest a pin may be from the nearest town centre. Mirrors the server's
/// `max_service_km` setting (default 40).
const maxServiceKm = 40.0;

/// A place the passenger chose on the map (or a town centre shortcut).
class MapPick {
  const MapPick({required this.point, required this.nearestName, this.isTownCentre = false, this.label});

  final GeoPoint point;

  /// Name of the closest town — shown to drivers as context.
  final String nearestName;
  final bool isTownCentre;

  /// The place name or address the passenger typed or picked from the search (a village, a stop, a muhalla...).
  final String? label;

  /// What the booking card shows: exactly what the passenger typed or chose, nothing added.
  String get title => label ?? (isTownCentre ? '$nearestName (town centre)' : 'Pinned location');

  /// Sent to the server as the pickup / drop-off label: exactly what the card shows,
  /// so the driver sees the same words the passenger does.
  String get serverLabel => title;
}

/// Two pins closer than this are the same place (the server refuses such a trip).
bool pinsOverlap(GeoPoint a, GeoPoint b) =>
    haversineKm(LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)) < 0.3;

/// Pin-to-pin trip distance: straight line × 1.3 road factor, one decimal,
/// at least 1 km. The server (`create_ride_request_geo`) uses the same rule.
double tripDistanceKm(GeoPoint a, GeoPoint b) {
  final km = haversineKm(LatLng(a.lat, a.lng), LatLng(b.lat, b.lng)) * roadFactor;
  return math.max(1, (km * 10).round() / 10);
}

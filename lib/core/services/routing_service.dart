import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Road distance / ETA / polyline between points.
abstract interface class RoutingService {
  Future<RouteEstimate> route(List<LatLng> waypoints);
}

class RouteEstimate {
  const RouteEstimate({required this.points, required this.distanceKm, required this.minutes});

  final List<LatLng> points;
  final double distanceKm;
  final int minutes;
}

const roadFactor = 1.3;
const avgSpeedKmh = 40.0;

double haversineKm(LatLng a, LatLng b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLng = rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Default: works fully offline. Straight segments through the waypoints,
/// distance × 1.3 road factor.
class HaversineRoutingService implements RoutingService {
  const HaversineRoutingService();

  @override
  Future<RouteEstimate> route(List<LatLng> waypoints) async {
    var km = 0.0;
    for (var i = 1; i < waypoints.length; i++) {
      km += haversineKm(waypoints[i - 1], waypoints[i]);
    }
    km *= roadFactor;
    return RouteEstimate(
      points: waypoints,
      distanceKm: km,
      minutes: math.max(1, (km / avgSpeedKmh * 60).round()),
    );
  }
}

/// Optional: OSRM (demo server or self-hosted) for real road geometry.
/// Any failure falls back to Haversine — never mandatory.
class OsrmRoutingService implements RoutingService {
  OsrmRoutingService(this.baseUrl, {this.fallback = const HaversineRoutingService()});

  final String baseUrl;
  final RoutingService fallback;

  @override
  Future<RouteEstimate> route(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return fallback.route(waypoints);
    try {
      final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final res = await http
          .get(Uri.parse('$baseUrl/route/v1/driving/$coords?overview=simplified&geometries=geojson'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return await fallback.route(waypoints);
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final r = (j['routes'] as List).first as Map<String, dynamic>;
      final line = ((r['geometry'] as Map)['coordinates'] as List)
          .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return RouteEstimate(
        points: line,
        distanceKm: (r['distance'] as num) / 1000,
        minutes: ((r['duration'] as num) / 60).round(),
      );
    } catch (_) {
      return fallback.route(waypoints);
    }
  }
}

/// Position along a polyline at fraction [t] (0..1), for the moving-car effect.
LatLng pointAlong(List<LatLng> line, double t) {
  if (line.isEmpty) return const LatLng(0, 0);
  if (line.length == 1 || t <= 0) return line.first;
  if (t >= 1) return line.last;
  final seg = <double>[];
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    final d = haversineKm(line[i - 1], line[i]);
    seg.add(d);
    total += d;
  }
  if (total == 0) return line.first;
  var target = total * t;
  for (var i = 0; i < seg.length; i++) {
    if (target <= seg[i]) {
      final f = seg[i] == 0 ? 0.0 : target / seg[i];
      final a = line[i];
      final b = line[i + 1];
      return LatLng(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f);
    }
    target -= seg[i];
  }
  return line.last;
}

/// Fraction (0..1) of the polyline closest to [p].
double fractionAlong(List<LatLng> line, LatLng p) {
  if (line.length < 2) return 0;
  var best = double.infinity;
  var bestT = 0.0;
  const steps = 100;
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final d = haversineKm(pointAlong(line, t), p);
    if (d < best) {
      best = d;
      bestT = t;
    }
  }
  return bestT;
}

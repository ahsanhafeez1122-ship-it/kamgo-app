import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/map_provider.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/kamgo_logo.dart';
import '../domain/ride_models.dart';
import '../domain/ride_status.dart';
import 'ride_flow_providers.dart';

final _routeLineProvider = FutureProvider.autoDispose.family<RouteEstimate, String>((ref, key) {
  final pts = key.split(';').map((p) {
    final ll = p.split(',');
    return LatLng(double.parse(ll[0]), double.parse(ll[1]));
  }).toList();
  return ref.watch(routingServiceProvider).route(pts);
});

/// Pickup / destination / driver markers, the route polyline, and a car
/// that glides along the route while the ride is in progress.
class LiveRideMap extends ConsumerStatefulWidget {
  const LiveRideMap({super.key, required this.ride});
  final RideDetails ride;

  @override
  ConsumerState<LiveRideMap> createState() => _LiveRideMapState();
}

class _LiveRideMapState extends ConsumerState<LiveRideMap> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Re-estimate progress periodically when there is no live GPS.
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && widget.ride.status == RideStatus.rideStarted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<LatLng> get _waypoints => [
        if (widget.ride.origin.point != null) _ll(widget.ride.origin.point!),
        for (final s in widget.ride.stops)
          if (s.point != null) _ll(s.point!),
        if (widget.ride.destination.point != null) _ll(widget.ride.destination.point!),
      ];

  static LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

  /// 0..1 along the route.
  double _progress(List<LatLng> line, RouteEstimate est) {
    final r = widget.ride;
    if (r.status == RideStatus.completed) return 1;
    if (r.status != RideStatus.rideStarted) return 0;
    if (r.lastLocation != null) return fractionAlong(line, _ll(r.lastLocation!));
    final started = r.startedAt;
    if (started == null) return 0;
    final total = (r.estMinutes ?? est.minutes).clamp(1, 600);
    final elapsed = DateTime.now().difference(started).inSeconds / 60;
    return (elapsed / total).clamp(0.0, 0.95);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _waypoints;
    if (pts.length < 2) return const ColoredBox(color: AppColors.borderSoft);
    final key = pts.map((p) => '${p.latitude},${p.longitude}').join(';');
    final est = ref.watch(_routeLineProvider(key)).valueOrNull;
    final line = est?.points ?? pts;
    final map = ref.watch(mapProviderProvider);
    final target = est == null ? 0.0 : _progress(line, est);
    final r = widget.ride;
    final showCar = r.isActive || r.status == RideStatus.completed;

    Widget build(double t) {
      final car = r.status != RideStatus.rideStarted && r.lastLocation != null
          ? _ll(r.lastLocation!)
          : pointAlong(line, t);
      return map.buildMap(
        fitPoints: pts,
        polyline: line,
        markers: [
          MapMarker(point: pts.first, size: 22, child: const _Dot(color: AppColors.green, round: true)),
          MapMarker(point: pts.last, size: 22, child: const _Dot(color: AppColors.navy, round: false)),
          if (showCar) MapMarker(point: car, size: 40, child: const _CarMarker()),
        ],
      );
    }

    if (reduceMotion(context)) return build(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (_, t, __) => build(t),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.round});
  final Color color;
  final bool round;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: round ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: round ? null : BorderRadius.circular(4),
            border: Border.all(color: AppColors.white, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
          ),
        ),
      );
}

class _CarMarker extends StatelessWidget {
  const _CarMarker();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.navy,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.all(7),
        child: const CustomPaint(painter: CarLinePainter(fill: AppColors.navy)),
      );
}

/// Remaining minutes, from route estimate and progress.
int etaMinutes(RideDetails r) {
  final total = r.estMinutes ?? math.max(1, (r.distanceKm / 40 * 60).round());
  if (r.status != RideStatus.rideStarted || r.startedAt == null) return total;
  final left = total - DateTime.now().difference(r.startedAt!).inMinutes;
  return math.max(1, left);
}

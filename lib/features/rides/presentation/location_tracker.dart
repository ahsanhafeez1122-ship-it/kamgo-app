import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../../core/services/location_service.dart';
import '../../driver/domain/driver_models.dart';

/// Sends the driver's position every ~12 s, and only while a ride is active.
class RideLocationTracker {
  RideLocationTracker(this._location, this._drivers);

  final LocationService _location;
  final DriverRepository _drivers;

  StreamSubscription<Position>? _sub;
  String? _rideId;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _sub != null;

  Future<void> start(String rideId) async {
    if (_rideId == rideId && _sub != null) return;
    await stop();
    if (!await _location.ensurePermission()) return;
    _rideId = rideId;
    _sub = _location.rideStream().listen((p) {
      final now = DateTime.now();
      if (now.difference(_lastSent) < const Duration(seconds: 10)) return;
      _lastSent = now;
      _drivers
          .sendLocation(rideId, p.latitude, p.longitude, heading: p.heading, speedKmh: p.speed * 3.6)
          .catchError((_) {}); // Next tick retries; never crash a ride over GPS.
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _rideId = null;
  }
}

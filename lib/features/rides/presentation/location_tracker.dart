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

  /// Distance driven since the ride started (hourly trips are billed on it). Starts from what the
  /// server already knows, so reopening the app mid-trip does not lose the km.
  double _km = 0;
  Position? _prev;
  bool _counting = false;

  double get km => _km;

  /// Count km only while the ride is in progress.
  void setCounting(bool value) {
    _counting = value;
    if (!value) _prev = null;
  }

  /// Raise the counter to what the server has (never lowers it).
  void syncKm(double serverKm) {
    if (serverKm > _km) _km = serverKm;
  }

  Future<void> start(String rideId) async {
    if (_rideId == rideId && _sub != null) return;
    await stop();
    if (!await _location.ensurePermission()) return;
    _rideId = rideId;
    _km = 0;
    _prev = null;
    _sub = _location.rideStream().listen((p) {
      if (_counting) {
        final prev = _prev;
        if (prev != null) {
          final d = Geolocator.distanceBetween(prev.latitude, prev.longitude, p.latitude, p.longitude) / 1000;
          // Ignore GPS jitter (a few metres) and impossible jumps.
          if (d >= 0.01 && d < 2) _km += d;
        }
        _prev = p;
      }
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
    _prev = null;
    _counting = false;
  }
}

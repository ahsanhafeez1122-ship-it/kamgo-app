import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/rides/domain/ride_models.dart';

/// Thin wrapper over geolocator. Every call degrades gracefully: when
/// permission is refused or GPS is off, callers simply get null.
class LocationService {
  const LocationService();

  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  Future<GeoPoint?> current({Duration timeout = const Duration(seconds: 8)}) async {
    try {
      if (!await ensurePermission()) return null;
      final last = await Geolocator.getLastKnownPosition();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(timeout, onTimeout: () => last ?? (throw TimeoutException('gps')));
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Battery-friendly stream used only during an active ride. On Android a
  /// foreground-service notification keeps it alive with the screen off.
  Stream<Position> rideStream() {
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final settings = isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 25,
            intervalDuration: const Duration(seconds: 12),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'KAM GO ride in progress',
              notificationText: 'Sharing your location with the passenger',
              enableWakeLock: false,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25);
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_service.dart';

/// Emergency alert on an active ride: tells the KAM GO team (with the
/// caller's location when GPS is available).
abstract interface class SosService {
  bool get isAvailable;
  Future<void> trigger({required String rideId});
}

class NoopSosService implements SosService {
  const NoopSosService();

  @override
  bool get isAvailable => false;

  @override
  Future<void> trigger({required String rideId}) async {}
}

class SupabaseSosService implements SosService {
  const SupabaseSosService(this._client, this._location);

  final SupabaseClient _client;
  final LocationService _location;

  @override
  bool get isAvailable => true;

  @override
  Future<void> trigger({required String rideId}) async {
    final here = await _location.current(timeout: const Duration(seconds: 5));
    await _client.rpc('trigger_sos', params: {
      'p_ride_id': rideId,
      'p_lat': here?.lat,
      'p_lng': here?.lng,
    });
  }
}

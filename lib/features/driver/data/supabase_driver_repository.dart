import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/driver_models.dart';

class SupabaseDriverRepository implements DriverRepository {
  SupabaseDriverRepository(this._client);

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  @override
  Future<DriverDashboard?> dashboard() async {
    final j = await _client.rpc('get_driver_dashboard');
    return j == null ? null : DriverDashboard.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<List<FeedRequest>> feed() async {
    final rows = await _client.rpc('get_driver_feed') as List;
    return rows.cast<Map<String, dynamic>>().map(FeedRequest.fromJson).toList();
  }

  @override
  Stream<void> feedChanges(String cityId, String driverId) {
    late final RealtimeChannel ch;
    final controller = StreamController<void>.broadcast(onCancel: () => _client.removeChannel(ch));
    void tick(_) => controller.add(null);
    ch = _client
        .channel('feed:$cityId:$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_requests',
          callback: tick,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ride_offers',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'driver_id', value: driverId),
          callback: tick,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'driver_id', value: driverId),
          callback: tick,
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) controller.add(null);
        });
    return controller.stream;
  }

  @override
  Future<void> submitOffer(String requestId,
          {required bool accept, int? fare, double? lat, double? lng, int? etaMin}) =>
      _client.rpc('submit_offer', params: {
        'p_request_id': requestId,
        'p_offer_type': accept ? 'ACCEPT' : 'COUNTER',
        'p_fare': fare,
        'p_driver_lat': lat,
        'p_driver_lng': lng,
        'p_eta_min': etaMin,
      });

  @override
  Future<void> dismiss(String requestId) =>
      _client.rpc('dismiss_request', params: {'p_request_id': requestId});

  @override
  Future<void> setOnline(bool online, {String? cityId}) =>
      _client.rpc('set_driver_online', params: {'p_online': online, 'p_city_id': cityId});

  @override
  Future<void> updateLocation(double lat, double lng) =>
      _client.rpc('update_driver_location', params: {'p_lat': lat, 'p_lng': lng});

  @override
  Future<void> saveApplication(DriverApplication a) => _client.rpc('save_driver_application', params: {
        'p_cnic': a.cnic,
        'p_city_id': a.cityId,
        'p_vehicle_make': a.make,
        'p_vehicle_model': a.model,
        'p_vehicle_color': a.color,
        'p_plate_number': a.plate,
        'p_seats': a.seats,
        'p_vehicle_year': a.year,
        'p_ac_available': a.acAvailable,
      });

  @override
  Future<void> setRoutes(List<String> routeIds) =>
      _client.rpc('set_driver_routes', params: {'p_route_ids': routeIds});

  @override
  Future<void> uploadDocument(DriverDocType type, List<int> jpegBytes) async {
    final path = '$_uid/${type.code}-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('driver-documents').uploadBinary(
          path,
          Uint8List.fromList(jpegBytes),
          fileOptions: const FileOptions(contentType: 'image/jpeg'),
        );
    await _client.from('driver_documents').insert({
      'driver_id': _uid,
      'doc_type': type.code,
      'storage_path': path,
    });
  }

  @override
  Future<void> sendLocation(String rideId, double lat, double lng, {double? heading, double? speedKmh}) =>
      _client.from('ride_locations').insert({
        'ride_id': rideId,
        'driver_id': _uid,
        'lat': lat,
        'lng': lng,
        'heading': heading,
        'speed_kmh': speedKmh,
      });
}

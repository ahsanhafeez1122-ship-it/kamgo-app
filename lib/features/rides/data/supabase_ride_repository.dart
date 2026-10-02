import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ride_models.dart';
import '../domain/ride_repository.dart';
import '../domain/ride_status.dart';

class SupabaseRideRepository implements RideRepository {
  SupabaseRideRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<RideRequest> createRequest({
    required String routeId,
    required int passengers,
    required int fare,
    String? pickupLabel,
    GeoPoint? pickup,
  }) async {
    final row = await _client.rpc('create_ride_request', params: {
      'p_route_id': routeId,
      'p_passenger_count': passengers,
      'p_offered_fare': fare,
      'p_pickup_label': pickupLabel,
      'p_pickup_lat': pickup?.lat,
      'p_pickup_lng': pickup?.lng,
    });
    return RideRequest.fromJson(row as Map<String, dynamic>);
  }

  @override
  Future<RideRequest?> request(String requestId) async {
    final row = await _client.from('ride_requests').select().eq('id', requestId).maybeSingle();
    return row == null ? null : RideRequest.fromJson(row);
  }

  @override
  Future<void> cancelRequest(String requestId) =>
      _client.rpc('cancel_request', params: {'p_request_id': requestId});

  @override
  Future<List<DriverOffer>> offers(String requestId) async {
    final rows = await _client.rpc('get_request_offers', params: {'p_request_id': requestId}) as List;
    return rows.cast<Map<String, dynamic>>().map(DriverOffer.fromJson).toList();
  }

  /// Realtime → a tick stream. Screens refetch through the RPC on each tick,
  /// so the server stays the single source of truth.
  Stream<void> _changes(String channel, String table, String column, String value) {
    late final RealtimeChannel ch;
    final controller = StreamController<void>.broadcast(
      onCancel: () => _client.removeChannel(ch),
    );
    ch = _client
        .channel('$channel:$value')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: column, value: value),
          callback: (_) => controller.add(null),
        )
        .subscribe((status, _) {
          // Refetch after (re)connecting so nothing missed while offline is lost.
          if (status == RealtimeSubscribeStatus.subscribed) controller.add(null);
        });
    return controller.stream;
  }

  @override
  Stream<void> offerChanges(String requestId) =>
      _changes('offers', 'ride_offers', 'request_id', requestId);

  @override
  Stream<void> requestChanges(String requestId) =>
      _changes('request', 'ride_requests', 'id', requestId);

  @override
  Future<void> rejectOffer(String offerId) =>
      _client.rpc('reject_offer', params: {'p_offer_id': offerId});

  @override
  Future<String> selectOffer(String offerId) async {
    final row = await _client.rpc('select_offer', params: {'p_offer_id': offerId});
    return (row as Map<String, dynamic>)['id'] as String;
  }

  @override
  Future<RideDetails> ride(String rideId) async {
    final j = await _client.rpc('get_ride_details', params: {'p_ride_id': rideId});
    return RideDetails.fromJson(j as Map<String, dynamic>);
  }

  @override
  Stream<void> rideChanges(String rideId) {
    final a = _changes('ride', 'rides', 'id', rideId);
    final b = _changes('ride-loc', 'ride_locations', 'ride_id', rideId);
    final out = StreamController<void>.broadcast();
    late StreamSubscription<void> sa;
    late StreamSubscription<void> sb;
    out.onListen = () {
      sa = a.listen(out.add);
      sb = b.listen(out.add);
    };
    out.onCancel = () async {
      await sa.cancel();
      await sb.cancel();
    };
    return out.stream;
  }

  @override
  Future<void> updateStatus(String rideId, RideStatus status) => _client.rpc(
        'update_ride_status',
        params: {'p_ride_id': rideId, 'p_new_status': status.code},
      );

  @override
  Future<void> completeRide(String rideId) =>
      _client.rpc('complete_ride', params: {'p_ride_id': rideId});

  @override
  Future<void> cancelRide(String rideId, CancelReason reason, {String? note}) => _client.rpc(
        'cancel_ride',
        params: {'p_ride_id': rideId, 'p_reason': reason.code, 'p_note': note},
      );

  @override
  Future<void> rate(String rideId, int stars, {String? comment}) => _client.rpc(
        'rate_ride',
        params: {'p_ride_id': rideId, 'p_stars': stars, 'p_comment': comment},
      );

  @override
  Future<ActiveState> myActive() async {
    final j = await _client.rpc('get_my_active');
    return ActiveState.fromJson(j as Map<String, dynamic>);
  }

  @override
  Future<List<RideHistoryItem>> history({int page = 0, int pageSize = 20}) async {
    final rows = await _client.rpc('get_my_rides', params: {
      'p_limit': pageSize,
      'p_offset': page * pageSize,
    }) as List;
    return rows.cast<Map<String, dynamic>>().map(RideHistoryItem.fromJson).toList();
  }
}

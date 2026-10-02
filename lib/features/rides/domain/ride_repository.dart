import 'ride_models.dart';
import 'ride_status.dart';

enum CancelReason {
  passengerCancelled('PASSENGER_CANCELLED'),
  driverCancelled('DRIVER_CANCELLED'),
  driverNoShow('DRIVER_NO_SHOW'),
  passengerNoShow('PASSENGER_NO_SHOW');

  const CancelReason(this.code);
  final String code;
}

/// Passenger + shared ride operations. Every write is a server RPC; the app
/// never sets a status or an amount itself.
abstract interface class RideRepository {
  Future<RideRequest> createRequest({
    required String routeId,
    required int passengers,
    required int fare,
    String? pickupLabel,
    GeoPoint? pickup,
  });

  Future<RideRequest?> request(String requestId);

  Future<void> cancelRequest(String requestId);

  Future<List<DriverOffer>> offers(String requestId);

  /// Emits whenever an offer on [requestId] is created or changes.
  Stream<void> offerChanges(String requestId);

  /// Emits whenever the request row changes (status / expiry).
  Stream<void> requestChanges(String requestId);

  Future<void> rejectOffer(String offerId);

  /// Returns the new ride id.
  Future<String> selectOffer(String offerId);

  Future<RideDetails> ride(String rideId);

  /// Emits on ride status changes and new driver locations.
  Stream<void> rideChanges(String rideId);

  Future<void> updateStatus(String rideId, RideStatus status);

  Future<void> completeRide(String rideId);

  Future<void> cancelRide(String rideId, CancelReason reason, {String? note});

  Future<void> rate(String rideId, int stars, {String? comment});

  Future<ActiveState> myActive();

  Future<List<RideHistoryItem>> history({int page = 0, int pageSize = 20});
}

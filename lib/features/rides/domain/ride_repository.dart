import 'fare_service.dart';
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
  /// A request between two map pins; the server derives distance, checks the
  /// fare guardrails and finds the nearest towns.
  Future<RideRequest> createRequest({
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int passengers,
    required int fare,
    String? pickupLabel,
    String? dropoffLabel,
    String category = 'car_mini',
    bool loading = false,
    BookingType bookingType = BookingType.oneWay,
    String? packageId,
    int expectedWaitMin = 0,
    DateTime? scheduledAt,
    double? distanceKm,
  });

  Future<RideRequest?> request(String requestId);

  /// Passenger offers more while nobody has taken the request.
  Future<void> raiseFare(String requestId, int fare);

  /// Driver taps arrived at the pickup (starts the waiting clock). Where the driver is, if known,
  /// teaches KAM GO the exact spot of the pickup address.
  Future<void> driverArrived(String rideId, {double? lat, double? lng});

  /// Hourly trips: the driver app reports the km travelled so far (it only grows).
  Future<void> updateProgress(String rideId, double km);

  /// Round trip: the driver reached the destination / starts the way back.
  Future<void> reachedDestination(String rideId);
  Future<void> returnStarted(String rideId);

  /// Sends the reminder for scheduled bookings that are about to start (also run by the server).
  Future<void> remindScheduled();

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

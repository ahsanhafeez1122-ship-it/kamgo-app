import 'ride_status.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int? _i(Object? v) => (v as num?)?.toInt();
DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

enum OfferType { accept, counter }

enum OfferStatus { pending, selected, unavailable, rejected, withdrawn, expired }

OfferStatus _offerStatus(String s) => OfferStatus.values.byName(s.toLowerCase());

class RideRequest {
  const RideRequest({
    required this.id,
    required this.routeId,
    required this.originCityId,
    required this.destinationCityId,
    required this.passengerCount,
    required this.offeredFare,
    required this.status,
    required this.expiresAt,
  });

  factory RideRequest.fromJson(Map<String, dynamic> j) => RideRequest(
        id: j['id'] as String,
        routeId: j['route_id'] as String,
        originCityId: j['origin_city_id'] as String,
        destinationCityId: j['destination_city_id'] as String,
        passengerCount: _i(j['passenger_count']) ?? 1,
        offeredFare: _d(j['offered_fare']),
        status: RideStatus.fromCode(j['status'] as String),
        expiresAt: _t(j['expires_at'])!,
      );

  final String id;
  final String routeId;
  final String originCityId;
  final String destinationCityId;
  final int passengerCount;
  final double offeredFare;
  final RideStatus status;
  final DateTime expiresAt;
}

/// A driver's response, as the passenger sees it.
class DriverOffer {
  const DriverOffer({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.rating,
    required this.vehicle,
    required this.type,
    required this.fare,
    required this.status,
    required this.expiresAt,
    this.plate,
    this.vehicleType,
    this.etaMin,
    this.distanceKm,
  });

  factory DriverOffer.fromJson(Map<String, dynamic> j) => DriverOffer(
        id: j['offer_id'] as String,
        driverId: j['driver_id'] as String,
        driverName: j['driver_name'] as String? ?? 'Driver',
        rating: _d(j['rating']),
        vehicle: j['vehicle'] as String? ?? '',
        vehicleType: j['vehicle_type'] as String?,
        plate: j['plate'] as String?,
        type: j['offer_type'] == 'ACCEPT' ? OfferType.accept : OfferType.counter,
        fare: _d(j['fare']),
        status: _offerStatus(j['status'] as String),
        etaMin: _i(j['eta_min']),
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        expiresAt: _t(j['expires_at'])!,
      );

  final String id;
  final String driverId;
  final String driverName;
  final double rating;
  final String vehicle;
  final String? vehicleType;
  final String? plate;
  final OfferType type;
  final double fare;
  final OfferStatus status;
  final int? etaMin;
  final double? distanceKm;
  final DateTime expiresAt;

  bool get isLive => status == OfferStatus.pending && expiresAt.isAfter(DateTime.now());
}

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

class Place {
  const Place({required this.id, required this.name, this.point, this.label});

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        label: j['label'] as String?,
        point: j['lat'] == null || j['lng'] == null ? null : GeoPoint(_d(j['lat']), _d(j['lng'])),
      );

  final String id;
  final String name;
  final String? label;
  final GeoPoint? point;

  String get display => label == null || label!.isEmpty ? name : '$label, $name';
}

class RideParty {
  const RideParty({required this.id, required this.name, this.phone, this.rating});

  factory RideParty.fromJson(Map<String, dynamic> j) => RideParty(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        rating: (j['rating'] as num?)?.toDouble(),
      );

  final String id;
  final String name;
  final String? phone;
  final double? rating;
}

class VehicleInfo {
  const VehicleInfo({this.type, this.make, this.model, this.color, this.plate});

  factory VehicleInfo.fromJson(Map<String, dynamic>? j) => VehicleInfo(
        type: j?['type'] as String?,
        make: j?['make'] as String?,
        model: j?['model'] as String?,
        color: j?['color'] as String?,
        plate: j?['plate'] as String?,
      );

  final String? type;
  final String? make;
  final String? model;
  final String? color;
  final String? plate;

  String get title => [make, model].whereType<String>().where((s) => s.isNotEmpty).join(' ');
}

/// Everything shown on the ride screens for both passenger and driver.
class RideDetails {
  const RideDetails({
    required this.id,
    required this.status,
    required this.finalFare,
    required this.passengerCount,
    required this.origin,
    required this.destination,
    required this.stops,
    required this.driver,
    required this.passenger,
    required this.vehicle,
    required this.distanceKm,
    this.estMinutes,
    this.startedAt,
    this.completedAt,
    this.myRating,
    this.commission,
    this.driverEarning,
    this.lastLocation,
  });

  factory RideDetails.fromJson(Map<String, dynamic> j) {
    final driver = j['driver'] as Map<String, dynamic>;
    final c = j['commission'] as Map<String, dynamic>?;
    final loc = j['last_location'] as Map<String, dynamic>?;
    return RideDetails(
      id: j['id'] as String,
      status: RideStatus.fromCode(j['status'] as String),
      finalFare: _d(j['final_fare']),
      passengerCount: _i(j['passenger_count']) ?? 1,
      origin: Place.fromJson(j['origin'] as Map<String, dynamic>),
      destination: Place.fromJson(j['destination'] as Map<String, dynamic>),
      stops: ((j['stops'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((s) => Place.fromJson({'id': '', ...s}))
          .toList(),
      driver: RideParty.fromJson(driver),
      passenger: RideParty.fromJson(j['passenger'] as Map<String, dynamic>),
      vehicle: VehicleInfo.fromJson(driver['vehicle'] as Map<String, dynamic>?),
      distanceKm: _d(j['distance_km']),
      estMinutes: _i(j['est_duration_min']),
      startedAt: _t(j['started_at']),
      completedAt: _t(j['completed_at']),
      myRating: _i(j['my_rating']),
      commission: c == null ? null : _d(c['amount']),
      driverEarning: c == null ? null : _d(c['driver_earning']),
      lastLocation: loc == null ? null : GeoPoint(_d(loc['lat']), _d(loc['lng'])),
    );
  }

  final String id;
  final RideStatus status;
  final double finalFare;
  final int passengerCount;
  final Place origin;
  final Place destination;
  final List<Place> stops;
  final RideParty driver;
  final RideParty passenger;
  final VehicleInfo vehicle;
  final double distanceKm;
  final int? estMinutes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int? myRating;
  final double? commission;
  final double? driverEarning;
  final GeoPoint? lastLocation;

  String get routeName => '${origin.name} → ${destination.name}';

  bool get isActive =>
      status == RideStatus.confirmed ||
      status == RideStatus.driverArriving ||
      status == RideStatus.rideStarted;
}

/// What the app should resume after a restart.
class ActiveState {
  const ActiveState({this.rideId, this.requestId, this.unratedRideId});

  factory ActiveState.fromJson(Map<String, dynamic> j) => ActiveState(
        rideId: j['ride_id'] as String?,
        requestId: j['request_id'] as String?,
        unratedRideId: j['unrated_ride_id'] as String?,
      );

  final String? rideId;
  final String? requestId;
  final String? unratedRideId;
}

/// Row in "My Rides" for either role.
class RideHistoryItem {
  const RideHistoryItem({
    required this.rideId,
    required this.originName,
    required this.destinationName,
    required this.fare,
    required this.status,
    required this.createdAt,
    required this.otherName,
    required this.isDriver,
    this.driverEarning,
    this.commission,
    this.myRating,
  });

  factory RideHistoryItem.fromJson(Map<String, dynamic> j) => RideHistoryItem(
        rideId: j['ride_id'] as String,
        originName: j['origin_name'] as String,
        destinationName: j['destination_name'] as String,
        fare: _d(j['final_fare']),
        status: RideStatus.fromCode(j['status'] as String),
        createdAt: _t(j['created_at'])!,
        otherName: j['other_name'] as String? ?? '',
        isDriver: j['my_role'] == 'DRIVER',
        driverEarning: (j['driver_earning'] as num?)?.toDouble(),
        commission: (j['commission_amount'] as num?)?.toDouble(),
        myRating: _i(j['my_rating']),
      );

  final String rideId;
  final String originName;
  final String destinationName;
  final double fare;
  final RideStatus status;
  final DateTime createdAt;
  final String otherName;
  final bool isDriver;
  final double? driverEarning;
  final double? commission;
  final int? myRating;
}

import '../../profile/domain/profile.dart';

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;

/// An open request in the driver's feed.
class FeedRequest {
  const FeedRequest({
    required this.requestId,
    required this.routeId,
    required this.originName,
    required this.destinationName,
    required this.passengerName,
    required this.passengerCount,
    required this.offeredFare,
    required this.distanceKm,
    required this.createdAt,
    required this.expiresAt,
    required this.isReturn,
    this.pickupLabel,
    this.passengerRating,
    this.myOfferFare,
    this.myOfferIsCounter = false,
  });

  factory FeedRequest.fromJson(Map<String, dynamic> j) => FeedRequest(
        requestId: j['request_id'] as String,
        routeId: j['route_id'] as String,
        originName: j['origin_name'] as String,
        destinationName: j['destination_name'] as String,
        pickupLabel: j['pickup_label'] as String?,
        passengerName: j['passenger_first_name'] as String? ?? 'Passenger',
        passengerRating: (j['passenger_rating'] as num?)?.toDouble(),
        passengerCount: (j['passenger_count'] as num).toInt(),
        offeredFare: _d(j['offered_fare']),
        distanceKm: _d(j['distance_km']),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
        myOfferFare: (j['my_offer_fare'] as num?)?.toDouble(),
        myOfferIsCounter: j['my_offer_type'] == 'COUNTER',
        isReturn: j['is_return'] as bool? ?? false,
      );

  final String requestId;
  final String routeId;
  final String originName;
  final String destinationName;
  final String? pickupLabel;
  final String passengerName;
  final double? passengerRating;
  final int passengerCount;
  final double offeredFare;
  final double distanceKm;
  final DateTime createdAt;
  final DateTime expiresAt;
  final double? myOfferFare;
  final bool myOfferIsCounter;
  final bool isReturn;

  bool get hasMyOffer => myOfferFare != null;
}

class DriverEarnings {
  const DriverEarnings({
    this.today = 0,
    this.week = 0,
    this.month = 0,
    this.ridesToday = 0,
    this.commissionDue = 0,
  });

  factory DriverEarnings.fromJson(Map<String, dynamic>? j) => DriverEarnings(
        today: _d(j?['today']),
        week: _d(j?['week']),
        month: _d(j?['month']),
        ridesToday: (j?['rides_today'] as num?)?.toInt() ?? 0,
        commissionDue: _d(j?['commission_due']),
      );

  final double today;
  final double week;
  final double month;
  final int ridesToday;
  final double commissionDue;
}

class DriverRatingItem {
  const DriverRatingItem({required this.stars, this.comment});
  final int stars;
  final String? comment;
}

class DriverDashboard {
  const DriverDashboard({
    required this.status,
    required this.isOnline,
    required this.rating,
    required this.ratingCount,
    required this.totalRides,
    required this.earnings,
    required this.routeIds,
    required this.documentTypes,
    required this.recentRatings,
    this.cityId,
    this.cityName,
    this.rejectionReason,
    this.cnic,
    this.vehicleTitle,
    this.vehiclePlate,
    this.vehicleType,
    this.vehicleColor,
    this.vehicleSeats,
    this.vehicleYear,
    this.vehicleMake,
    this.vehicleModel,
    this.addaOnline = 0,
    this.addaOpenRequests = 0,
  });

  factory DriverDashboard.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'] as Map<String, dynamic>?;
    final adda = j['adda'] as Map<String, dynamic>?;
    return DriverDashboard(
      status: DriverStatus.fromCode(j['status'] as String?),
      isOnline: j['is_online'] as bool? ?? false,
      rejectionReason: j['rejection_reason'] as String?,
      cityId: j['city_id'] as String?,
      cityName: j['city_name'] as String?,
      rating: _d(j['rating']),
      ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      totalRides: (j['total_rides'] as num?)?.toInt() ?? 0,
      cnic: j['cnic'] as String?,
      vehicleTitle: v == null ? null : [v['make'], v['model']].whereType<String>().join(' '),
      vehicleMake: v?['make'] as String?,
      vehicleModel: v?['model'] as String?,
      vehiclePlate: v?['plate'] as String?,
      vehicleType: v?['type'] as String?,
      vehicleColor: v?['color'] as String?,
      vehicleSeats: (v?['seats'] as num?)?.toInt(),
      vehicleYear: (v?['year'] as num?)?.toInt(),
      routeIds: ((j['route_ids'] as List?) ?? const []).cast<String>(),
      documentTypes: ((j['documents'] as List?) ?? const [])
          .map((d) => (d as Map)['type'] as String)
          .toSet(),
      earnings: DriverEarnings.fromJson(j['earnings'] as Map<String, dynamic>?),
      addaOnline: (adda?['online_drivers'] as num?)?.toInt() ?? 0,
      addaOpenRequests: (adda?['open_requests'] as num?)?.toInt() ?? 0,
      recentRatings: ((j['recent_ratings'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((r) => DriverRatingItem(stars: (r['stars'] as num).toInt(), comment: r['comment'] as String?))
          .toList(),
    );
  }

  final DriverStatus status;
  final bool isOnline;
  final String? rejectionReason;
  final String? cityId;
  final String? cityName;
  final double rating;
  final int ratingCount;
  final int totalRides;
  final String? cnic;
  final String? vehicleTitle;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehiclePlate;
  final String? vehicleType;
  final String? vehicleColor;
  final int? vehicleSeats;
  final int? vehicleYear;
  final List<String> routeIds;
  final Set<String> documentTypes;
  final DriverEarnings earnings;
  final int addaOnline;
  final int addaOpenRequests;
  final List<DriverRatingItem> recentRatings;

  bool get hasApplication => vehiclePlate != null && cnic != null;
}

/// Documents a driver must upload.
enum DriverDocType {
  cnicFront('CNIC_FRONT', 'CNIC front'),
  cnicBack('CNIC_BACK', 'CNIC back'),
  license('LICENSE', 'Driving licence'),
  registration('VEHICLE_REGISTRATION', 'Vehicle registration'),
  selfie('SELFIE', 'Selfie'),
  vehiclePhoto('VEHICLE_PHOTO', 'Vehicle photo');

  const DriverDocType(this.code, this.label);
  final String code;
  final String label;
}

class DriverApplication {
  const DriverApplication({
    required this.cnic,
    required this.cityId,
    required this.vehicleType,
    required this.make,
    required this.model,
    required this.color,
    required this.plate,
    required this.seats,
    required this.year,
    required this.routeIds,
  });

  final String cnic;
  final String cityId;
  final String vehicleType;
  final String make;
  final String model;
  final String color;
  final String plate;
  final int seats;
  final int? year;
  final List<String> routeIds;
}

abstract interface class DriverRepository {
  Future<DriverDashboard?> dashboard();

  Future<List<FeedRequest>> feed();

  /// Ticks when requests in [cityId] or the driver's own offers change.
  Stream<void> feedChanges(String cityId, String driverId);

  Future<void> submitOffer(String requestId, {required bool accept, int? fare, double? lat, double? lng});

  Future<void> dismiss(String requestId);

  Future<void> setOnline(bool online, {String? cityId});

  Future<void> saveApplication(DriverApplication app);

  Future<void> setRoutes(List<String> routeIds);

  /// Uploads an already-compressed JPEG and records it for review.
  Future<void> uploadDocument(DriverDocType type, List<int> jpegBytes);

  Future<void> sendLocation(String rideId, double lat, double lng, {double? heading, double? speedKmh});
}

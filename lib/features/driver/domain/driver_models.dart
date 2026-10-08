import '../../profile/domain/profile.dart';
import '../../rides/domain/fare_service.dart';

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
    this.category = 'car_mini',
    this.pickupKm,
    this.recommendedFare,
    this.minOffer,
    this.maxOffer,
    this.commission = 0,
    this.driverGets = 0,
    this.isNight = false,
    this.loadingSelected = false,
    this.bookingType = BookingType.oneWay,
    this.packageHours,
    this.packageKm,
    this.expectedWaitMin = 0,
    this.scheduledAt,
    this.intercity = false,
    this.pickupLabel,
    this.dropoffLabel,
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
        dropoffLabel: j['dropoff_label'] as String?,
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
        category: j['category'] as String? ?? 'car_mini',
        pickupKm: (j['pickup_km'] as num?)?.toDouble(),
        recommendedFare: (j['recommended_fare'] as num?)?.toDouble(),
        minOffer: (j['min_offer'] as num?)?.toDouble(),
        maxOffer: (j['max_offer'] as num?)?.toDouble(),
        commission: _d(j['commission']),
        driverGets: _d(j['driver_gets']),
        isNight: j['is_night'] as bool? ?? false,
        loadingSelected: j['loading_selected'] as bool? ?? false,
        bookingType: BookingType.fromCode(j['booking_type'] as String?),
        packageHours: (j['package_hours'] as num?)?.toInt(),
        packageKm: (j['package_km'] as num?)?.toDouble(),
        expectedWaitMin: (j['expected_wait_min'] as num?)?.toInt() ?? 0,
        scheduledAt: j['scheduled_at'] == null ? null : DateTime.parse(j['scheduled_at'] as String).toLocal(),
        intercity: j['origin_city_id'] != null && j['origin_city_id'] != j['destination_city_id'],
      );

  final String requestId;
  final String routeId;
  final String originName;
  final String destinationName;
  final String? pickupLabel;
  final String? dropoffLabel;
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

  /// Ride type of the request (BIKE, RICKSHAW, MINI, PREMIUM, COURIER).
  final String category;

  /// How far the driver is from the pickup, when the driver's location is known.
  final double? pickupKm;

  /// The fare engine's numbers for this request, and the money split of the passenger's offer.
  final double? recommendedFare;
  final double? minOffer;
  final double? maxOffer;
  final double commission;
  final double driverGets;
  final bool isNight;
  final bool loadingSelected;

  /// One way / hourly (package hours and km) / round trip (expected waiting at the destination).
  final BookingType bookingType;
  final int? packageHours;
  final double? packageKm;
  final int expectedWaitMin;

  /// Pickup time of a scheduled booking (null = now).
  final DateTime? scheduledAt;

  /// City to City trip (the destination is in another city).
  final bool intercity;

  /// Badge on the request card: Hourly 4h / Round Trip (nothing for one way).
  String? get badge => switch (bookingType) {
        BookingType.hourly => 'Hourly ${packageHours ?? ''}h',
        BookingType.roundTrip => intercity ? 'City to City · Round Trip' : 'Round Trip',
        BookingType.oneWay => intercity ? 'City to City' : null,
      };

  /// The band a counter-offer must stay inside (null for old requests without one).
  FareQuote? get quote => minOffer == null || maxOffer == null
      ? null
      : FareQuote(
          recommended: (recommendedFare ?? offeredFare).round(),
          minOffer: minOffer!.round(),
          maxOffer: maxOffer!.round(),
          commission: commission.round(),
          driverGets: driverGets.round(),
        );

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
    this.vehicleCategory,
    this.vehicleAc = false,
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
      vehicleCategory: v?['category'] as String?,
      vehicleAc: v?['ac'] as bool? ?? false,
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
  final String? vehicleCategory;
  final bool vehicleAc;
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
    required this.make,
    required this.model,
    required this.color,
    required this.plate,
    required this.seats,
    required this.year,
    this.acAvailable = false,
  });

  final String cnic;
  final String cityId;
  final String make;
  final String model;
  final String color;
  final String plate;
  final int seats;
  final int? year;
  final bool acAvailable;
}

abstract interface class DriverRepository {
  Future<DriverDashboard?> dashboard();

  Future<List<FeedRequest>> feed();

  /// Ticks when requests in [cityId] or the driver's own offers change.
  Stream<void> feedChanges(String cityId, String driverId);

  /// [etaMin]: how many minutes the driver needs to reach the pickup.
  Future<void> submitOffer(String requestId, {required bool accept, int? fare, double? lat, double? lng, int? etaMin});

  Future<void> dismiss(String requestId);

  Future<void> setOnline(bool online, {String? cityId});

  /// Tells the server where the driver is, so requests near them reach them first.
  Future<void> updateLocation(double lat, double lng);

  Future<void> saveApplication(DriverApplication app);

  Future<void> setRoutes(List<String> routeIds);

  /// Uploads an already-compressed JPEG and records it for review.
  Future<void> uploadDocument(DriverDocType type, List<int> jpegBytes);

  Future<void> sendLocation(String rideId, double lat, double lng, {double? heading, double? speedKmh});
}

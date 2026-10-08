import 'package:latlong2/latlong.dart';

import '../../../core/services/routing_service.dart';
import 'fare_service.dart';

class City {
  const City({
    required this.id,
    required this.name,
    this.nameUr,
    this.lat,
    this.lng,
    this.serviceRadiusKm = 25,
  });

  factory City.fromJson(Map<String, dynamic> j) => City(
        id: j['id'] as String,
        name: j['name'] as String,
        nameUr: j['name_ur'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        serviceRadiusKm: (j['service_radius_km'] as num?)?.toDouble() ?? 25,
      );

  final String id;
  final String name;
  final String? nameUr;
  final double? lat;
  final double? lng;

  /// Rides starting within this many km of the centre belong to this city.
  final double serviceRadiusKm;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_ur': nameUr,
        'lat': lat,
        'lng': lng,
        'service_radius_km': serviceRadiusKm,
      };
}

class RouteInfo {
  const RouteInfo({
    required this.id,
    required this.originCityId,
    required this.destinationCityId,
    required this.distanceKm,
    this.estMinutes,
  });

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
        id: j['id'] as String,
        originCityId: j['origin_city_id'] as String,
        destinationCityId: j['destination_city_id'] as String,
        distanceKm: (j['distance_km'] as num).toDouble(),
        estMinutes: j['est_duration_min'] as int?,
      );

  final String id;
  final String originCityId;
  final String destinationCityId;
  final double distanceKm;
  final int? estMinutes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'origin_city_id': originCityId,
        'destination_city_id': destinationCityId,
        'distance_km': distanceKm,
        'est_duration_min': estMinutes,
      };
}

/// A ride type (Car Mini, Car Comfort, Car XL, Bike, Rickshaw, Loader): its fare configuration,
/// seats and display order. All of it is editable in the admin panel (`ride_categories`).
class RideCategory {
  const RideCategory({
    required this.code,
    required this.name,
    required this.maxPassengers,
    required this.fare,
    this.sortOrder = 0,
    this.isCar = false,
    this.nameUr,
    this.vehicleType = 'CAR',
  });

  factory RideCategory.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num).toDouble();
    return RideCategory(
      code: j['code'] as String,
      name: j['name'] as String,
      nameUr: j['name_ur'] as String?,
      vehicleType: j['vehicle_type'] as String? ?? 'CAR',
      maxPassengers: (j['max_passengers'] as num).toInt(),
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      isCar: j['is_car'] as bool? ?? false,
      fare: FareConfig(
        cityMileage: d('city_mileage'),
        highwayMileage: d('highway_mileage'),
        cityMaint: d('city_maint'),
        highwayMaint: d('highway_maint'),
        minFare: d('min_fare'),
        waitingPerMin: d('waiting_per_min'),
        maxKm: (j['max_km'] as num?)?.toDouble(),
        loadingCharge: (j['loading_charge'] as num?)?.toDouble() ?? 0,
        roundTripWaitPerHour: (j['round_trip_wait_per_hour'] as num?)?.toDouble() ?? 0,
        hourProfit: (j['hour_profit'] as num?)?.toDouble() ?? 0,
        extraKmRate: (j['extra_km_rate'] as num?)?.toDouble() ?? 0,
        extraHourRate: (j['extra_hour_rate'] as num?)?.toDouble() ?? 0,
        profitPoints: [
          for (final p in (j['profit_points'] as List? ?? const []))
            [for (final n in (p as List)) (n as num).toDouble()],
        ],
      ),
    );
  }

  final String code;
  final String name;
  final String? nameUr;
  final String vehicleType;
  final int maxPassengers;
  final int sortOrder;
  final bool isCar;
  final FareConfig fare;

  double? get maxKm => fare.maxKm;

  /// Bike and Loader carry one person (or one load): there is no passenger count to pick.
  bool get isSingle => maxPassengers <= 1;

  /// Cars can also be booked by the hour or for a round trip.
  bool get allowsHourlyAndRoundTrip => isCar;

  /// Does this ride type have a loading-help option (Loader)?
  bool get hasLoading => fare.loadingCharge > 0;

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'name_ur': nameUr,
        'vehicle_type': vehicleType,
        'max_passengers': maxPassengers,
        'sort_order': sortOrder,
        'is_car': isCar,
        'city_mileage': fare.cityMileage,
        'highway_mileage': fare.highwayMileage,
        'city_maint': fare.cityMaint,
        'highway_maint': fare.highwayMaint,
        'min_fare': fare.minFare,
        'waiting_per_min': fare.waitingPerMin,
        'max_km': fare.maxKm,
        'loading_charge': fare.loadingCharge,
        'round_trip_wait_per_hour': fare.roundTripWaitPerHour,
        'hour_profit': fare.hourProfit,
        'extra_km_rate': fare.extraKmRate,
        'extra_hour_rate': fare.extraHourRate,
        'profit_points': fare.profitPoints,
      };
}
/// A car a driver can register for a ride type (e.g. Mini: Suzuki Alto, Mehran, Wagon R, Cultus).
class VehicleModel {
  const VehicleModel({required this.category, required this.make, required this.model});

  factory VehicleModel.fromJson(Map<String, dynamic> j) => VehicleModel(
        category: j['category'] as String,
        make: j['make'] as String,
        model: j['model'] as String,
      );

  final String category;
  final String make;
  final String model;

  String get title => '$make $model';

  bool matches(String? make, String? model) =>
      this.make.toLowerCase() == (make ?? '').trim().toLowerCase() &&
      this.model.toLowerCase() == (model ?? '').trim().toLowerCase();

  Map<String, dynamic> toJson() => {'category': category, 'make': make, 'model': model};
}

/// KAM GO helpline, used until the `settings` table answers (WhatsApp without +, phone with +).
const defaultSupportWhatsapp = '923126865361';
const defaultSupportPhone = '+923126865361';

/// Public, admin-editable settings (the `settings` table).
class AppSettings {
  const AppSettings({
    this.commissionPercent = 10,
    this.offerExpiryMinutes = 3,
    this.maxPassengers = 6,
    this.minFarePerKm = 20,
    this.maxFarePerKm = 100,
    this.noDriverNotifyMinutes = 3,
    this.scheduledReminderMinutes = 30,
    this.sameAreaKm = 3,
    this.showCategoryPrices = false,
    this.fare = const FareSettings(),
    this.supportWhatsapp = defaultSupportWhatsapp,
    this.supportPhone = defaultSupportPhone,
  });

  factory AppSettings.fromRows(List<Map<String, dynamic>> rows) {
    final m = {for (final r in rows) r['key'] as String: r['value']};
    num n(String k, num d) => (m[k] is num) ? m[k] as num : num.tryParse('${m[k]}') ?? d;
    final commission = n('commission_percent', 10).toDouble();
    return AppSettings(
      commissionPercent: commission,
      offerExpiryMinutes: n('offer_expiry_minutes', 3).toInt(),
      maxPassengers: n('max_passengers', 6).toInt(),
      minFarePerKm: n('min_fare_per_km', 20).toDouble(),
      maxFarePerKm: n('max_fare_per_km', 100).toDouble(),
      noDriverNotifyMinutes: n('no_driver_notify_minutes', 3).toInt(),
      showCategoryPrices: m['show_category_prices'] == true,
      fare: FareSettings(
        petrolPrice: n('petrol_price', 400).toDouble(),
        commissionPercent: commission,
        slabKm: n('slab_km', 8).toDouble(),
        returnFactor: n('return_factor', 0.5).toDouble(),
        minOfferPercent: n('min_offer_percent', 85).toDouble(),
        maxOfferPercent: n('max_offer_percent', 200).toDouble(),
        nightSurchargePercent: n('night_surcharge_percent', 20).toDouble(),
        nightStartHour: n('night_start_hour', 23).toInt(),
        nightEndHour: n('night_end_hour', 6).toInt(),
        waitingFreeMinutes: n('waiting_free_minutes', 5).toInt(),
        roundTripCostFactor: n('round_trip_cost_factor', 2).toDouble(),
        roundTripProfitFactor: n('round_trip_profit_factor', 1.5).toDouble(),
        roundTripFreeWaitMinutes: n('round_trip_free_wait_minutes', 30).toInt(),
      ),
      scheduledReminderMinutes: n('scheduled_reminder_minutes', 30).toInt(),
      sameAreaKm: n('same_area_default_km', 3).toDouble(),
      supportWhatsapp: _text(m['support_whatsapp']) ?? defaultSupportWhatsapp,
      supportPhone: _text(m['support_phone']) ?? defaultSupportPhone,
    );
  }

  static String? _text(Object? v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

  final double commissionPercent;
  final int offerExpiryMinutes;
  final int maxPassengers;
  final double minFarePerKm;
  final double maxFarePerKm;

  /// After this many minutes without a driver, the passenger is asked to raise the offer.
  final int noDriverNotifyMinutes;

  /// Reminder before a scheduled booking.
  final int scheduledReminderMinutes;

  /// Distance assumed when both addresses are in the same area and cannot be told apart.
  final double sameAreaKm;

  /// Show each ride type's recommended fare on its card (off by default).
  final bool showCategoryPrices;
  final FareSettings fare;
  final String? supportWhatsapp;
  final String? supportPhone;

  List<Map<String, dynamic>> toRows() => [
        {'key': 'commission_percent', 'value': commissionPercent},
        {'key': 'offer_expiry_minutes', 'value': offerExpiryMinutes},
        {'key': 'max_passengers', 'value': maxPassengers},
        {'key': 'min_fare_per_km', 'value': minFarePerKm},
        {'key': 'max_fare_per_km', 'value': maxFarePerKm},
        {'key': 'no_driver_notify_minutes', 'value': noDriverNotifyMinutes},
        {'key': 'show_category_prices', 'value': showCategoryPrices},
        {'key': 'petrol_price', 'value': fare.petrolPrice},
        {'key': 'slab_km', 'value': fare.slabKm},
        {'key': 'return_factor', 'value': fare.returnFactor},
        {'key': 'min_offer_percent', 'value': fare.minOfferPercent},
        {'key': 'max_offer_percent', 'value': fare.maxOfferPercent},
        {'key': 'night_surcharge_percent', 'value': fare.nightSurchargePercent},
        {'key': 'night_start_hour', 'value': fare.nightStartHour},
        {'key': 'night_end_hour', 'value': fare.nightEndHour},
        {'key': 'waiting_free_minutes', 'value': fare.waitingFreeMinutes},
        {'key': 'round_trip_cost_factor', 'value': fare.roundTripCostFactor},
        {'key': 'round_trip_profit_factor', 'value': fare.roundTripProfitFactor},
        {'key': 'round_trip_free_wait_minutes', 'value': fare.roundTripFreeWaitMinutes},
        {'key': 'scheduled_reminder_minutes', 'value': scheduledReminderMinutes},
        {'key': 'same_area_default_km', 'value': sameAreaKm},
        {'key': 'support_whatsapp', 'value': supportWhatsapp},
        {'key': 'support_phone', 'value': supportPhone},
      ];
}
/// Everything the booking UI needs that changes rarely: cities, routes and
/// fare settings. Loaded once and cached on the device.
class Catalog {
  Catalog({
    required this.cities,
    required this.routes,
    required this.settings,
    this.categories = const [],
    this.vehicleModels = const [],
    this.hourlyPackages = const [],
  }) : _cityById = {for (final c in cities) c.id: c};

  final List<City> cities;
  final List<RouteInfo> routes;
  final AppSettings settings;
  final List<RideCategory> categories;
  final List<VehicleModel> vehicleModels;
  final List<HourlyPackage> hourlyPackages;
  final Map<String, City> _cityById;

  /// The cars allowed for a ride type; empty means any car (type it in).
  List<VehicleModel> modelsFor(String? code) => [for (final m in vehicleModels) if (m.category == code) m];

  RideCategory? category(String? code) {
    for (final c in categories) {
      if (c.code == code) return c;
    }
    return null;
  }

  /// The one fare service, set up from the admin-editable settings.
  FareService get fareService => FareService(settings.fare);

  /// Fare quote for a trip in ride type [code]; null if the type is unknown.
  FareQuote? quoteFor(String? code, double distanceKm, {bool night = false, bool loading = false, double toll = 0}) {
    final c = category(code);
    return c == null
        ? null
        : fareService.quote(c.fare, distanceKm, night: night, loading: loading && c.hasLoading, toll: toll);
  }

  HourlyPackage? package(String? id) {
    for (final p in hourlyPackages) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Quote for a trip of any booking type; null if it cannot be priced (unknown type, bike hourly...).
  FareQuote? quoteBooking(
    String? code,
    BookingType type, {
    double distanceKm = 0,
    HourlyPackage? package,
    int expectedWaitMinutes = 0,
    bool night = false,
    bool loading = false,
    double toll = 0,
  }) {
    final c = category(code);
    if (c == null) return null;
    switch (type) {
      case BookingType.oneWay:
        return fareService.quote(c.fare, distanceKm, night: night, loading: loading && c.hasLoading, toll: toll);
      case BookingType.hourly:
        return c.isCar && package != null && c.fare.hourProfit > 0 ? fareService.hourlyQuote(c.fare, package) : null;
      case BookingType.roundTrip:
        return c.isCar
            ? fareService.roundTripQuote(c.fare, distanceKm, expectedWaitMinutes: expectedWaitMinutes)
            : null;
    }
  }

  /// Ride types in the order passengers see them, without the ones too short-ranged for [distanceKm].
  List<RideCategory> categoriesFor(double? distanceKm) => [
        for (final c in categories)
          if (distanceKm == null || FareService.availableFor(c.fare, distanceKm)) c,
      ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// The city a ride starting at [lat],[lng] belongs to: the nearest city centre, if the pickup is
  /// inside its service radius; otherwise null ("service not available here yet").
  City? serviceCity(double lat, double lng) {
    final n = nearestCity(lat, lng);
    return n != null && n.km <= n.city.serviceRadiusKm ? n.city : null;
  }
  /// Most people the ride type can take.
  int maxPassengersFor(String? code) {
    final cap = category(code)?.maxPassengers;
    return cap == null ? settings.maxPassengers : (cap < settings.maxPassengers ? cap : settings.maxPassengers);
  }

  City? city(String? id) => id == null ? null : _cityById[id];

  /// The town whose centre is closest to [lat],[lng], with the distance.
  ({City city, double km})? nearestCity(double lat, double lng) {
    ({City city, double km})? best;
    for (final c in cities) {
      if (c.lat == null || c.lng == null) continue;
      final km = haversineKm(LatLng(lat, lng), LatLng(c.lat!, c.lng!));
      if (best == null || km < best.km) best = (city: c, km: km);
    }
    return best;
  }

  List<RouteInfo> routesFrom(String cityId) =>
      routes.where((r) => r.originCityId == cityId).toList();

  RouteInfo? routeBetween(String? originId, String? destinationId) {
    if (originId == null || destinationId == null) return null;
    for (final r in routes) {
      if (r.originCityId == originId && r.destinationCityId == destinationId) return r;
    }
    return null;
  }

  String routeName(RouteInfo r) =>
      '${city(r.originCityId)?.name ?? '?'} → ${city(r.destinationCityId)?.name ?? '?'}';
}

abstract interface class CatalogRepository {
  /// Returns fresh data when online; falls back to the device cache.
  Future<Catalog> load();
}

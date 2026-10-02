import 'fare_policy.dart';

class City {
  const City({required this.id, required this.name, this.nameUr, this.lat, this.lng});

  factory City.fromJson(Map<String, dynamic> j) => City(
        id: j['id'] as String,
        name: j['name'] as String,
        nameUr: j['name_ur'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
      );

  final String id;
  final String name;
  final String? nameUr;
  final double? lat;
  final double? lng;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'name_ur': nameUr, 'lat': lat, 'lng': lng};
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

/// Public, admin-editable settings (the `settings` table).
class AppSettings {
  const AppSettings({
    this.commissionPercent = 10,
    this.offerExpiryMinutes = 3,
    this.minFarePerKm = 20,
    this.maxFarePerKm = 100,
    this.maxPassengers = 6,
    this.supportWhatsapp,
    this.supportPhone,
  });

  factory AppSettings.fromRows(List<Map<String, dynamic>> rows) {
    final m = {for (final r in rows) r['key'] as String: r['value']};
    num n(String k, num d) => (m[k] is num) ? m[k] as num : num.tryParse('${m[k]}') ?? d;
    return AppSettings(
      commissionPercent: n('commission_percent', 10).toDouble(),
      offerExpiryMinutes: n('offer_expiry_minutes', 3).toInt(),
      minFarePerKm: n('min_fare_per_km', 20).toDouble(),
      maxFarePerKm: n('max_fare_per_km', 100).toDouble(),
      maxPassengers: n('max_passengers', 6).toInt(),
      supportWhatsapp: m['support_whatsapp'] as String?,
      supportPhone: m['support_phone'] as String?,
    );
  }

  final double commissionPercent;
  final int offerExpiryMinutes;
  final double minFarePerKm;
  final double maxFarePerKm;
  final int maxPassengers;
  final String? supportWhatsapp;
  final String? supportPhone;

  FarePolicy get farePolicy => FarePolicy(minPerKm: minFarePerKm, maxPerKm: maxFarePerKm);

  List<Map<String, dynamic>> toRows() => [
        {'key': 'commission_percent', 'value': commissionPercent},
        {'key': 'offer_expiry_minutes', 'value': offerExpiryMinutes},
        {'key': 'min_fare_per_km', 'value': minFarePerKm},
        {'key': 'max_fare_per_km', 'value': maxFarePerKm},
        {'key': 'max_passengers', 'value': maxPassengers},
        {'key': 'support_whatsapp', 'value': supportWhatsapp},
        {'key': 'support_phone', 'value': supportPhone},
      ];
}

/// Everything the booking UI needs that changes rarely: cities, routes and
/// fare settings. Loaded once and cached on the device.
class Catalog {
  Catalog({required this.cities, required this.routes, required this.settings})
      : _cityById = {for (final c in cities) c.id: c};

  final List<City> cities;
  final List<RouteInfo> routes;
  final AppSettings settings;
  final Map<String, City> _cityById;

  City? city(String? id) => id == null ? null : _cityById[id];

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

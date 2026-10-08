import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/catalog.dart';
import '../domain/fare_service.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client, this._prefs);

  static const _cacheKey = 'catalog_cache_v5';

  final SupabaseClient _client;
  final SharedPreferences _prefs;

  @override
  Future<Catalog> load() async {
    try {
      final results = await Future.wait([
        _client
            .from('cities')
            .select('id, name, name_ur, lat, lng, service_radius_km')
            .eq('is_active', true)
            .order('sort_order'),
        _client
            .from('routes')
            .select('id, origin_city_id, destination_city_id, distance_km, est_duration_min')
            .eq('is_active', true)
            .order('distance_km'),
        _client.from('settings').select('key, value'),
        _client
            .from('ride_categories')
            .select(
                'code, name, name_ur, vehicle_type, is_car, max_passengers, sort_order, city_mileage, highway_mileage, '
                'city_maint, highway_maint, min_fare, waiting_per_min, max_km, loading_charge, round_trip_wait_per_hour, profit_points, hour_profit, extra_km_rate, extra_hour_rate')
            .eq('is_active', true)
            .order('sort_order'),
        _client.from('vehicle_models').select('category, make, model').eq('is_active', true).order('make').order('model'),
        _client
            .from('hourly_packages')
            .select('id, hours, included_km, profit_multiplier, sort_order')
            .eq('is_active', true)
            .order('sort_order'),
      ]);
      final catalog = Catalog(
        cities: results[0].map(City.fromJson).toList(),
        routes: results[1].map(RouteInfo.fromJson).toList(),
        settings: AppSettings.fromRows(results[2]),
        categories: results[3].map(RideCategory.fromJson).toList(),
        vehicleModels: results[4].map(VehicleModel.fromJson).toList(),
        hourlyPackages: results[5].map(HourlyPackage.fromJson).toList(),
      );
      await _save(catalog);
      return catalog;
    } catch (_) {
      final cached = _read();
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<void> _save(Catalog c) => _prefs.setString(
        _cacheKey,
        jsonEncode({
          'cities': c.cities.map((e) => e.toJson()).toList(),
          'routes': c.routes.map((e) => e.toJson()).toList(),
          'settings': c.settings.toRows(),
          'categories': c.categories.map((e) => e.toJson()).toList(),
          'vehicle_models': c.vehicleModels.map((e) => e.toJson()).toList(),
          'hourly_packages': c.hourlyPackages.map((e) => e.toJson()).toList(),
        }),
      );

  Catalog? _read() {
    final raw = _prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      List<Map<String, dynamic>> list(String k) =>
          (j[k] as List).cast<Map<String, dynamic>>();
      return Catalog(
        cities: list('cities').map(City.fromJson).toList(),
        routes: list('routes').map(RouteInfo.fromJson).toList(),
        settings: AppSettings.fromRows(list('settings')),
        categories: list('categories').map(RideCategory.fromJson).toList(),
        vehicleModels: list('vehicle_models').map(VehicleModel.fromJson).toList(),
        hourlyPackages: j['hourly_packages'] == null ? const [] : list('hourly_packages').map(HourlyPackage.fromJson).toList(),
      );
    } catch (_) {
      return null;
    }
  }
}

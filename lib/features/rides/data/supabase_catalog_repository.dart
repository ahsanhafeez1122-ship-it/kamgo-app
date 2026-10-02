import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/catalog.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client, this._prefs);

  static const _cacheKey = 'catalog_cache_v1';

  final SupabaseClient _client;
  final SharedPreferences _prefs;

  @override
  Future<Catalog> load() async {
    try {
      final results = await Future.wait([
        _client
            .from('cities')
            .select('id, name, name_ur, lat, lng')
            .eq('is_active', true)
            .order('sort_order'),
        _client
            .from('routes')
            .select('id, origin_city_id, destination_city_id, distance_km, est_duration_min')
            .eq('is_active', true)
            .order('distance_km'),
        _client.from('settings').select('key, value'),
      ]);
      final catalog = Catalog(
        cities: results[0].map(City.fromJson).toList(),
        routes: results[1].map(RouteInfo.fromJson).toList(),
        settings: AppSettings.fromRows(results[2]),
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
      );
    } catch (_) {
      return null;
    }
  }
}

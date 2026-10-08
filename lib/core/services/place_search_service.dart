import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lng,
    this.saved = false,
  });

  /// True for places KAM GO keeps itself (villages, stops, landmarks), false for map-search results.
  final bool saved;

  final String title;
  final String subtitle;
  final double lat;
  final double lng;
}

/// Type-ahead place search for the map picker.
abstract interface class PlaceSearch {
  /// Places matching [query], biased towards the box
  /// ([minLat], [minLng]) – ([maxLat], [maxLng]).
  Future<List<PlaceSuggestion>> search(
    String query, {
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  });

  /// A short name for the spot at [lat],[lng] (street and area), or null if none is known.
  Future<String?> reverse(double lat, double lng);
}

/// OpenStreetMap Nominatim.
/// NOTE: nominatim.openstreetmap.org is for development / light use only
/// (about one request per second). Production should use a paid geocoder or a
/// self-hosted Nominatim: set NOMINATIM_URL at build time.
class NominatimPlaceSearch implements PlaceSearch {
  NominatimPlaceSearch({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? (_envUrl.isEmpty ? _publicUrl : _envUrl);

  static const _envUrl = String.fromEnvironment('NOMINATIM_URL');
  static const _publicUrl = 'https://nominatim.openstreetmap.org';

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {
      'format': 'jsonv2',
      'q': q,
      'countrycodes': 'pk',
      'limit': '8',
      'addressdetails': '0',
      'accept-language': 'en',
      // Prefer results inside the service area; the app also filters by distance.
      'viewbox': '$minLng,$maxLat,$maxLng,$minLat',
    });
    final res = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return const [];
    final list = jsonDecode(res.body) as List<dynamic>;
    return [
      for (final raw in list)
        if (_parse(raw as Map<String, dynamic>) case final s?) s,
    ];
  }

  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  /// Named places (stations, schools, hospitals, shops, mosques...) by map cell of about 2 km,
  /// fetched once per cell and kept for the session: the first pin in an area waits for them,
  /// every later pin there is instant.
  final _poiCells = <String, Future<List<({String name, double lat, double lng})>>>{};

  Future<List<({String name, double lat, double lng})>> _poisAround(double lat, double lng) {
    const cell = 0.02;
    final s = (lat / cell).floor() * cell, w = (lng / cell).floor() * cell;
    final key = '${s.toStringAsFixed(2)},${w.toStringAsFixed(2)}';
    return _poiCells.putIfAbsent(key, () async {
      // A little margin so a pin near the cell's edge still finds what is across it.
      final bbox = '${s - 0.003},${w - 0.003},${s + cell + 0.003},${w + cell + 0.003}';
      const keys = 'amenity|railway|shop|tourism|office|healthcare|leisure|public_transport|building|historic|man_made';
      final q = '[out:json][timeout:20];('
          'node($bbox)[name][~"^($keys)\$"~"."];'
          'way($bbox)[name][~"^($keys)\$"~"."];'
          ');out center tags;';
      try {
        final res = await _client.post(Uri.parse(_overpassUrl), body: {'data': q}).timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw StateError('overpass ${res.statusCode}');
        final els = ((jsonDecode(res.body) as Map<String, dynamic>)['elements'] as List?) ?? const [];
        return [
          for (final e in els.cast<Map<String, dynamic>>())
            if (_poi(e) case final p?) p,
        ];
      } catch (_) {
        _poiCells.remove(key); // try again next time
        return const [];
      }
    });
  }

  static ({String name, double lat, double lng})? _poi(Map<String, dynamic> e) {
    final c = (e['center'] as Map<String, dynamic>?) ?? e;
    final lat = (c['lat'] as num?)?.toDouble(), lng = (c['lon'] as num?)?.toDouble();
    final tags = (e['tags'] as Map<String, dynamic>?) ?? const {};
    final name = ('${tags['name:en'] ?? tags['name'] ?? ''}').trim();
    // Railway lines and similar long features are not a place to stand.
    if (lat == null || lng == null || name.isEmpty || tags['railway'] == 'rail' || tags.containsKey('electrified')) {
      return null;
    }
    return (name: name, lat: lat, lng: lng);
  }

  /// The named place closest to the pin, within about 120 m.
  Future<String?> _nearbyPoi(double lat, double lng) async {
    final pois = await _poisAround(lat, lng);
    String? best;
    var bestKm = 0.12;
    for (final p in pois) {
      final dLat = (p.lat - lat) * 111.0, dLng = (p.lng - lng) * 111.0 * 0.857; // cos(31°)
      final km = math.sqrt(dLat * dLat + dLng * dLng);
      if (km < bestKm) {
        bestKm = km;
        best = p.name;
      }
    }
    return best;
  }
  @override
  Future<String?> reverse(double lat, double lng) async {
    // Both lookups at once; the named place is a bonus on top of the road name.
    final poiFuture = _nearbyPoi(lat, lng).catchError((_) => null);
    String? poi;
    try {
      final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: {
        'format': 'jsonv2',
        'lat': '$lat',
        'lon': '$lng',
        'zoom': '17',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
      // The area's places may still be loading the first time; don't keep the passenger waiting.
      poi = await poiFuture.timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (res.statusCode != 200) return poi;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final a = (j['address'] as Map<String, dynamic>?) ?? const {};
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final parts = <String>[];
      void add(String? v) {
        if (v != null && !parts.contains(v)) parts.add(v);
      }

      add(poi);
      add(('${j['name'] ?? ''}').trim().isEmpty ? null : ('${j['name']}').trim());
      add(pick(['road', 'pedestrian', 'footway']));
      add(pick(['neighbourhood', 'suburb', 'quarter', 'hamlet', 'village']));
      add(pick(['town', 'city', 'county']));
      return parts.isEmpty ? null : parts.take(3).join(', ');
    } catch (_) {
      return poi ?? await poiFuture.timeout(const Duration(seconds: 6), onTimeout: () => null);
    }
  }

  PlaceSuggestion? _parse(Map<String, dynamic> j) {
    final lat = double.tryParse('${j['lat']}');
    final lng = double.tryParse('${j['lon']}');
    if (lat == null || lng == null) return null;
    final parts = ('${j['display_name'] ?? ''}').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final name = ('${j['name'] ?? ''}').trim();
    final title = name.isNotEmpty ? name : (parts.isEmpty ? 'Place' : parts.first);
    final rest = parts.where((p) => p != title).take(3).join(', ');
    return PlaceSuggestion(title: title, subtitle: rest, lat: lat, lng: lng);
  }
}

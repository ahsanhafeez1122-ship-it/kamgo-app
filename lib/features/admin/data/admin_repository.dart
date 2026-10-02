import 'package:supabase_flutter/supabase_flutter.dart';

typedef DbRow = Map<String, dynamic>;

/// Admin operations. Every call is protected server-side (is_admin() in the
/// RPCs and RLS policies); the UI hiding things is only for convenience.
class AdminRepository {
  AdminRepository(this._c);
  final SupabaseClient _c;

  Future<bool> isAdmin() async => (await _c.rpc('is_admin')) == true;

  Future<DbRow> stats() async => (await _c.rpc('admin_dashboard_stats')) as DbRow;

  Future<List<DbRow>> drivers({String? status}) async =>
      ((await _c.rpc('admin_list_drivers', params: {'p_status': status})) as List).cast<DbRow>();

  Future<void> setDriverStatus(String driverId, String status, {String? reason}) =>
      _c.rpc('admin_set_driver_status', params: {'p_driver_id': driverId, 'p_status': status, 'p_reason': reason});

  Future<void> setAccountStatus(String userId, String status) =>
      _c.rpc('admin_set_account_status', params: {'p_user_id': userId, 'p_status': status});

  Future<void> recordPayment(String driverId, double amount, {String? note}) => _c.rpc(
        'admin_record_commission_payment',
        params: {'p_driver_id': driverId, 'p_amount': amount, 'p_note': note},
      );

  /// Documents with short-lived signed URLs (private bucket).
  Future<List<DbRow>> documents(String driverId) async {
    final rows = await _c
        .from('driver_documents')
        .select('id, doc_type, storage_path, status, created_at')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);
    final out = <DbRow>[];
    for (final r in rows) {
      String? url;
      try {
        url = await _c.storage.from('driver-documents').createSignedUrl(r['storage_path'] as String, 600);
      } catch (_) {}
      out.add({...r, 'url': url});
    }
    return out;
  }

  Future<List<DbRow>> passengers({String? search}) async => ((await _c.rpc(
        'admin_list_passengers',
        params: {'p_search': (search?.isEmpty ?? true) ? null : search},
      )) as List)
          .cast<DbRow>();

  Future<List<DbRow>> rides({String? status, String? cityId, String? search, int offset = 0}) async =>
      ((await _c.rpc('admin_list_rides', params: {
        'p_status': status,
        'p_city_id': cityId,
        'p_search': (search?.isEmpty ?? true) ? null : search,
        'p_limit': 50,
        'p_offset': offset,
      })) as List)
          .cast<DbRow>();

  Future<void> cancelRide(String rideId, String note) =>
      _c.rpc('cancel_ride', params: {'p_ride_id': rideId, 'p_reason': 'ADMIN_CANCELLED', 'p_note': note});

  Future<DbRow?> rideDetails(String rideId) async => (await _c.rpc('get_ride_details', params: {'p_ride_id': rideId})) as DbRow?;

  // Catalog -------------------------------------------------------------
  Future<List<DbRow>> cities() async => await _c.from('cities').select().order('sort_order').order('name');

  Future<void> saveCity(DbRow values, {String? id}) async {
    id == null ? await _c.from('cities').insert(values) : await _c.from('cities').update(values).eq('id', id);
  }

  Future<List<DbRow>> routes() async => await _c
      .from('routes')
      .select('*, origin:cities!routes_origin_city_id_fkey(name), destination:cities!routes_destination_city_id_fkey(name)')
      .order('created_at');

  Future<void> saveRoute(DbRow values, {String? id}) async {
    id == null ? await _c.from('routes').insert(values) : await _c.from('routes').update(values).eq('id', id);
  }

  Future<List<DbRow>> stops(String routeId) async =>
      await _c.from('route_stops').select().eq('route_id', routeId).order('stop_order');

  Future<void> addStop(String routeId, String name, int order, {double? lat, double? lng}) =>
      _c.from('route_stops').insert({'route_id': routeId, 'name': name, 'stop_order': order, 'lat': lat, 'lng': lng});

  Future<void> deleteStop(String id) => _c.from('route_stops').delete().eq('id', id);

  Future<List<DbRow>> settings() async => await _c.from('settings').select().order('key');

  Future<void> saveSetting(String key, Object? value) =>
      _c.from('settings').update({'value': value}).eq('key', key);

  Future<List<DbRow>> complaints() async => await _c
      .from('complaints')
      .select('*, reporter:profiles!complaints_reporter_id_fkey(full_name, phone)')
      .order('created_at', ascending: false)
      .limit(200);

  Future<void> updateComplaint(String id, String status, {String? note}) =>
      _c.from('complaints').update({'status': status, 'admin_note': note}).eq('id', id);
}

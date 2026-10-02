import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ride_summary.dart';

class SupabaseRideHistoryRepository implements RideHistoryRepository {
  SupabaseRideHistoryRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<List<RideSummary>> myRides({int page = 0, int pageSize = 20}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final from = page * pageSize;
    final rows = await _client
        .from('rides')
        .select(
          'id, final_fare, status, created_at, '
          'origin:cities!rides_origin_city_id_fkey(name), '
          'destination:cities!rides_destination_city_id_fkey(name)',
        )
        .eq('passenger_id', uid)
        .order('created_at', ascending: false)
        .range(from, from + pageSize - 1);
    return rows.map(RideSummary.fromJson).toList();
  }

  @override
  Future<List<String>> recentDestinationIds({int limit = 6}) async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from('ride_requests')
        .select('destination_city_id')
        .eq('passenger_id', uid)
        .order('created_at', ascending: false)
        .limit(30);
    final seen = <String>{};
    for (final r in rows) {
      seen.add(r['destination_city_id'] as String);
      if (seen.length >= limit) break;
    }
    return seen.toList();
  }
}

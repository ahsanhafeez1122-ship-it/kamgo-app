import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/adda.dart';

class SupabaseAddaRepository implements AddaRepository {
  SupabaseAddaRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AddaSummary>> summary() async {
    final rows = await _client.rpc('get_adda_summary') as List;
    return rows.cast<Map<String, dynamic>>().map(AddaSummary.fromJson).toList();
  }

  @override
  Future<PopularRoute?> popularRoute({String? originCityId}) async {
    final rows = await _client.rpc(
      'get_popular_route',
      params: {'p_origin_city_id': originCityId},
    ) as List;
    if (rows.isEmpty) return null;
    return PopularRoute.fromJson(rows.first as Map<String, dynamic>);
  }
}

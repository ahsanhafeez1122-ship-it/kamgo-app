import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile.dart';

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  @override
  Future<Profile?> fetchMine() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client.from('profiles').select().eq('id', uid).maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  @override
  Future<void> completeProfile({
    required String fullName,
    required UserRole role,
    String? cityId,
  }) async {
    await _client.rpc('complete_profile', params: {
      'p_full_name': fullName,
      'p_role': role.code,
      'p_city_id': cityId,
    });
  }

  @override
  Future<void> updateEmergencyContact({String? name, String? phone}) async {
    final uid = _uid;
    if (uid == null) return;
    await _client.from('profiles').update({
      'emergency_contact_name': name,
      'emergency_contact_phone': phone,
    }).eq('id', uid);
  }

  @override
  Future<DriverInfo?> fetchMyDriverInfo() async {
    final uid = _uid;
    if (uid == null) return null;
    final row = await _client
        .from('drivers')
        .select('status, is_online, rejection_reason')
        .eq('id', uid)
        .maybeSingle();
    return row == null ? null : DriverInfo.fromJson(row);
  }
}

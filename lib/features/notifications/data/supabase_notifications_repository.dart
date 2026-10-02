import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_notification.dart';

class SupabaseNotificationsRepository implements NotificationsRepository {
  SupabaseNotificationsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> latest({int limit = 30}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('notifications')
        .select('id, type, title, body, created_at, read_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromJson).toList();
  }

  @override
  Future<void> markAllRead() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', uid)
        .isFilter('read_at', null);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_notifications_repository.dart';
import '../domain/app_notification.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => SupabaseNotificationsRepository(ref.watch(supabaseClientProvider)),
);

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(notificationsRepositoryProvider).latest();
});

final hasUnreadProvider = Provider<bool>((ref) {
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.any((n) => n.isUnread);
});

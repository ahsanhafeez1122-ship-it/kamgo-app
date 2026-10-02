import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../data/supabase_auth_service.dart';
import '../domain/auth_service.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => SupabaseAuthService(ref.watch(supabaseClientProvider)),
);

/// Current signed-in user id (null when signed out). Rebuilds dependants on
/// sign-in / sign-out.
final authUserIdProvider = StreamProvider<String?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  yield auth.currentUserId;
  yield* auth.userIdChanges().distinct();
});

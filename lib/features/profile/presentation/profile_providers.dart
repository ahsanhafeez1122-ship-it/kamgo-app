import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(supabaseClientProvider)),
);

/// The signed-in user's profile; refetched whenever the user changes.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final uid = await ref.watch(authUserIdProvider.future);
  if (uid == null) return null;
  return ref.watch(profileRepositoryProvider).fetchMine();
});

final myDriverInfoProvider = FutureProvider<DriverInfo?>((ref) async {
  final uid = await ref.watch(authUserIdProvider.future);
  if (uid == null) return null;
  return ref.watch(profileRepositoryProvider).fetchMyDriverInfo();
});

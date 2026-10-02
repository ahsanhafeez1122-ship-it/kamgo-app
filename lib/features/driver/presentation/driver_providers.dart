import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../rides/presentation/location_tracker.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../data/supabase_driver_repository.dart';
import '../domain/driver_models.dart';

final driverRepositoryProvider = Provider<DriverRepository>(
  (ref) => SupabaseDriverRepository(ref.watch(supabaseClientProvider)),
);

final rideLocationTrackerProvider = Provider<RideLocationTracker>((ref) {
  final t = RideLocationTracker(ref.watch(locationServiceProvider), ref.watch(driverRepositoryProvider));
  ref.onDispose(t.stop);
  return t;
});

final driverDashboardProvider = FutureProvider<DriverDashboard?>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(driverRepositoryProvider).dashboard();
});

/// Open requests for the driver, live via Realtime + 15 s polling fallback.
final driverFeedProvider =
    AsyncNotifierProvider.autoDispose<DriverFeedNotifier, List<FeedRequest>>(DriverFeedNotifier.new);

class DriverFeedNotifier extends AutoDisposeAsyncNotifier<List<FeedRequest>> {
  @override
  Future<List<FeedRequest>> build() async {
    final uid = await ref.watch(authUserIdProvider.future);
    final dash = await ref.watch(driverDashboardProvider.future);
    final repo = ref.watch(driverRepositoryProvider);
    if (uid == null || dash == null || !dash.isOnline || dash.cityId == null) return const [];

    final sub = repo.feedChanges(dash.cityId!, uid).listen((_) {
      refresh();
      // A new ride row for me means a passenger picked my offer.
      ref.invalidate(activeStateProvider);
    });
    final poll = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    ref.onDispose(() {
      sub.cancel();
      poll.cancel();
    });
    return repo.feed();
  }

  bool _busy = false;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      state = AsyncData(await ref.read(driverRepositoryProvider).feed());
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}

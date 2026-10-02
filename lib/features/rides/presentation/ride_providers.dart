import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_adda_repository.dart';
import '../data/supabase_catalog_repository.dart';
import '../data/supabase_ride_history_repository.dart';
import '../domain/adda.dart';
import '../domain/catalog.dart';
import '../domain/ride_summary.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => SupabaseCatalogRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(sharedPrefsProvider),
  ),
);

final addaRepositoryProvider = Provider<AddaRepository>(
  (ref) => SupabaseAddaRepository(ref.watch(supabaseClientProvider)),
);

final rideHistoryRepositoryProvider = Provider<RideHistoryRepository>(
  (ref) => SupabaseRideHistoryRepository(ref.watch(supabaseClientProvider)),
);

final catalogProvider = FutureProvider<Catalog>(
  (ref) => ref.watch(catalogRepositoryProvider).load(),
);

final addaSummaryProvider = FutureProvider<List<AddaSummary>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(addaRepositoryProvider).summary();
});

final popularRouteProvider = FutureProvider.family<PopularRoute?, String?>(
  (ref, originCityId) =>
      ref.watch(addaRepositoryProvider).popularRoute(originCityId: originCityId),
);

final recentDestinationsProvider = FutureProvider<List<String>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideHistoryRepositoryProvider).recentDestinationIds();
});

final myRidesProvider = FutureProvider<List<RideSummary>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideHistoryRepositoryProvider).myRides();
});

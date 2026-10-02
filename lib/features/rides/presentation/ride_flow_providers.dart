import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/map_provider.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/services/sos_service.dart';
import '../../../core/services/supabase_providers.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/supabase_ride_repository.dart';
import '../domain/ride_models.dart';
import '../domain/ride_repository.dart';

final rideRepositoryProvider = Provider<RideRepository>(
  (ref) => SupabaseRideRepository(ref.watch(supabaseClientProvider)),
);

final locationServiceProvider = Provider<LocationService>((_) => const LocationService());

final mapProviderProvider = Provider<MapProvider>((_) => const OsmMapProvider());

final sosServiceProvider = Provider<SosService>((_) => const NoopSosService());

/// Haversine by default; set OSRM_URL at build time to use road geometry.
final routingServiceProvider = Provider<RoutingService>((_) {
  const osrm = String.fromEnvironment('OSRM_URL');
  return osrm.isEmpty ? const HaversineRoutingService() : OsrmRoutingService(osrm);
});

/// Current request/ride to resume, checked on Home / dashboard.
final activeStateProvider = FutureProvider<ActiveState>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideRepositoryProvider).myActive();
});

final rideHistoryProvider = FutureProvider<List<RideHistoryItem>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideRepositoryProvider).history();
});

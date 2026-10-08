import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/location_service.dart';
import '../../../core/services/map_provider.dart';
import '../../../core/services/place_search_service.dart';
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

/// Once a minute, asks the server to send reminders for scheduled bookings that are about to start.
/// (The server also does this itself on a schedule; this is the fallback when no scheduler runs.)
final scheduledReminderProvider = Provider<void>((ref) {
  final timer = Timer.periodic(const Duration(minutes: 1), (_) {
    ref.read(rideRepositoryProvider).remindScheduled().catchError((_) {});
  });
  ref.onDispose(timer.cancel);
});

final locationServiceProvider = Provider<LocationService>((_) => const LocationService());

final placeSearchProvider = Provider<PlaceSearch>((_) => NominatimPlaceSearch());

/// Villages, stops and landmarks kept by KAM GO (admin-editable). Searched first,
/// instantly and offline-friendly: the list is small.
final placesProvider = FutureProvider<List<PlaceSuggestion>>((ref) async {
  final rows = await ref
      .watch(supabaseClientProvider)
      .from('places')
      .select('name, kind, lat, lng')
      .eq('is_active', true)
      .order('name');
  String label(String kind) => switch (kind) {
        'town' => 'Town',
        'village' => 'Village',
        'hamlet' => 'Hamlet',
        'stop' => 'Stop',
        'landmark' => 'Landmark',
        _ => 'Place',
      };
  return [
    for (final r in rows)
      PlaceSuggestion(
        title: r['name'] as String,
        subtitle: label(r['kind'] as String),
        lat: (r['lat'] as num).toDouble(),
        lng: (r['lng'] as num).toDouble(),
        saved: true,
      ),
  ];
});

final mapProviderProvider = Provider<MapProvider>((_) => const OsmMapProvider());

final sosServiceProvider = Provider<SosService>(
  (ref) => SupabaseSosService(ref.watch(supabaseClientProvider), ref.watch(locationServiceProvider)),
);

/// Haversine by default; set OSRM_URL at build time to use road geometry.
final routingServiceProvider = Provider<RoutingService>((_) {
  const osrm = String.fromEnvironment('OSRM_URL');
  // Real road distance from the public OSRM server unless another one is configured; offline it falls back to
  // the straight line x 1.3.
  return OsrmRoutingService(osrm.isEmpty ? 'https://router.project-osrm.org' : osrm);
});

/// Current request/ride to resume, checked on Home / dashboard.
final activeStateProvider = FutureProvider<ActiveState>((ref) async {
  // Re-check every 10 s: the other side may have cancelled or finished.
  final timer = Timer(const Duration(seconds: 10), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideRepositoryProvider).myActive();
});

final rideHistoryProvider = FutureProvider<List<RideHistoryItem>>((ref) async {
  await ref.watch(authUserIdProvider.future);
  return ref.watch(rideRepositoryProvider).history();
});

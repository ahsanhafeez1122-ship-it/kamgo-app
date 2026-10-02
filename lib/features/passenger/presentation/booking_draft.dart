import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/supabase_providers.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/fare_policy.dart';
import '../../rides/presentation/ride_providers.dart';

/// What the passenger has filled in on the Home booking card.
class BookingDraft {
  const BookingDraft({
    this.pickupCityId,
    this.destinationCityId,
    this.passengers = 1,
    this.offer,
  });

  final String? pickupCityId;
  final String? destinationCityId;
  final int passengers;
  final int? offer;

  BookingDraft copyWith({
    String? pickupCityId,
    String? destinationCityId,
    int? passengers,
    int? offer,
    bool clearDestination = false,
    bool clearOffer = false,
  }) =>
      BookingDraft(
        pickupCityId: pickupCityId ?? this.pickupCityId,
        destinationCityId:
            clearDestination ? null : destinationCityId ?? this.destinationCityId,
        passengers: passengers ?? this.passengers,
        offer: clearOffer ? null : offer ?? this.offer,
      );
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftNotifier, BookingDraft>(BookingDraftNotifier.new);

class BookingDraftNotifier extends Notifier<BookingDraft> {
  static const _lastPickupKey = 'last_pickup_city_id';

  BookingDraft? _last;

  @override
  BookingDraft build() {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final prefs = ref.read(sharedPrefsProvider);
    final base = _last ?? BookingDraft(pickupCityId: prefs.getString(_lastPickupKey));
    if (catalog == null) return base;
    return _last = _reconcile(base, catalog);
  }

  Catalog? get _catalog => ref.read(catalogProvider).valueOrNull;

  void _set(BookingDraft d) {
    final catalog = _catalog;
    state = _last = catalog == null ? d : _reconcile(d, catalog);
  }

  void setPickup(String cityId) {
    ref.read(sharedPrefsProvider).setString(_lastPickupKey, cityId);
    final d = state;
    final destination = d.destinationCityId == cityId ? null : d.destinationCityId;
    _set(BookingDraft(
      pickupCityId: cityId,
      destinationCityId: destination,
      passengers: d.passengers,
      offer: d.offer,
    ));
  }

  void setDestination(String cityId) => _set(state.copyWith(destinationCityId: cityId));

  void setPassengers(int count) => _set(state.copyWith(passengers: count));

  void setOffer(int fare) => _set(state.copyWith(offer: fare));

  void swap() {
    final d = state;
    if (d.destinationCityId == null) return;
    _set(BookingDraft(
      pickupCityId: d.destinationCityId,
      destinationCityId: d.pickupCityId,
      passengers: d.passengers,
      offer: d.offer,
    ));
  }

  /// Keeps the draft valid against the current catalog: known cities, an
  /// existing active route, passengers within limits and a fare within the
  /// guardrails (falling back to a suggested fare).
  static BookingDraft _reconcile(BookingDraft d, Catalog c) {
    if (c.cities.isEmpty) return d;
    final pickup = c.city(d.pickupCityId) != null &&
            c.routesFrom(d.pickupCityId!).isNotEmpty
        ? d.pickupCityId!
        : c.cities
            .firstWhere((x) => c.routesFrom(x.id).isNotEmpty, orElse: () => c.cities.first)
            .id;

    final from = c.routesFrom(pickup);
    final route = c.routeBetween(pickup, d.destinationCityId) ??
        (from.isNotEmpty ? from.first : null);

    final passengers = d.passengers.clamp(1, c.settings.maxPassengers);

    int? offer = d.offer;
    if (route != null) {
      final policy = c.settings.farePolicy;
      if (offer == null || policy.check(offer, route.distanceKm) != FareCheck.ok) {
        offer = policy.suggestedFare(route.distanceKm);
      }
    }

    return BookingDraft(
      pickupCityId: pickup,
      destinationCityId: route?.destinationCityId,
      passengers: passengers,
      offer: offer,
    );
  }
}

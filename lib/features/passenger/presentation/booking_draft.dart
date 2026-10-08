import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../rides/domain/catalog.dart';
import '../../rides/domain/fare_service.dart';
import '../../rides/domain/map_pick.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';

/// What the passenger has filled in on the Home booking card.
class BookingDraft {
  const BookingDraft({
    this.pickup,
    this.destination,
    this.passengers = 1,
    this.offer,
    this.category = 'car_mini',
    this.loading = false,
    this.type = BookingType.oneWay,
    this.packageId,
    this.expectedWaitMin = 0,
    this.scheduledAt,
    this.manualKm,
    this.routeKm,
    this.estKm,
  });

  final MapPick? pickup;
  final MapPick? destination;
  final int passengers;
  final int? offer;

  /// Ride type code (a row of `ride_categories`), e.g. car_mini, bike, loader.
  final String category;

  /// Loader only: loading help wanted (adds the category's loading charge).
  final bool loading;

  /// One way, hourly or round trip (hourly and round trip: cars only).
  final BookingType type;

  /// Hourly: the chosen package (a row of `hourly_packages`).
  final String? packageId;

  /// Round trip: how long the passenger expects to wait at the destination.
  final int expectedWaitMin;

  /// Null = as soon as possible; otherwise the pickup time (requests are still sent right away).
  final DateTime? scheduledAt;

  /// Distance the passenger typed in (for addresses that are not on the map). Wins over the pins.
  final double? manualKm;

  /// Road distance between the two places (from the routing service), once it has answered.
  final double? routeKm;

  /// Both places resolved to the same area: the default local distance (a setting) stands in.
  final double? estKm;

  /// The distance is an estimate, not worked out from two different places.
  bool get isEstimate => estKm != null && manualKm == null && routeKm == null;

  /// Trip distance once both ends are chosen: what the passenger entered, else pin to pin.
  double? get distanceKm => pickup == null || destination == null
      ? null
      : manualKm ?? routeKm ?? estKm ?? tripDistanceKm(pickup!.point, destination!.point);

  /// Both ends chosen but on top of each other (and no distance entered by hand).
  bool get samePlace =>
      type != BookingType.hourly &&
      manualKm == null &&
      pickup != null &&
      destination != null &&
      pinsOverlap(pickup!.point, destination!.point);

  /// Is there enough to price and send this booking?
  bool get complete => pickup != null && (type == BookingType.hourly ? packageId != null : destination != null);

  /// The fare quote (recommended fare, offer band, commission) for this trip, from the shared fare service.
  FareQuote? quote(Catalog c, {DateTime? now}) {
    final night = c.fareService.isNight(scheduledAt ?? now ?? DateTime.now());
    switch (type) {
      case BookingType.hourly:
        return c.quoteBooking(category, type, package: c.package(packageId));
      case BookingType.roundTrip:
        final km = distanceKm;
        return km == null ? null : c.quoteBooking(category, type, distanceKm: km, expectedWaitMinutes: expectedWaitMin);
      case BookingType.oneWay:
        final km = distanceKm;
        return km == null ? null : c.quoteBooking(category, type, distanceKm: km, night: night, loading: loading);
    }
  }

  BookingDraft copyWith({
    MapPick? pickup,
    MapPick? destination,
    int? passengers,
    int? offer,
    String? category,
    bool? loading,
    BookingType? type,
    String? packageId,
    int? expectedWaitMin,
    DateTime? scheduledAt,
    double? manualKm,
    bool clearSchedule = false,
    bool clearManualKm = false,
    double? routeKm,
    bool clearRouteKm = false,
  }) =>
      BookingDraft(
        pickup: pickup ?? this.pickup,
        destination: destination ?? this.destination,
        passengers: passengers ?? this.passengers,
        offer: offer ?? this.offer,
        category: category ?? this.category,
        loading: loading ?? this.loading,
        type: type ?? this.type,
        packageId: packageId ?? this.packageId,
        expectedWaitMin: expectedWaitMin ?? this.expectedWaitMin,
        scheduledAt: clearSchedule ? null : scheduledAt ?? this.scheduledAt,
        manualKm: clearManualKm ? null : manualKm ?? this.manualKm,
        routeKm: clearRouteKm ? null : routeKm ?? this.routeKm,
        estKm: estKm,
      );

  /// Same booking with the offer cleared, so it goes back to the recommended fare.
  BookingDraft withoutOffer() => BookingDraft(
        pickup: pickup,
        destination: destination,
        passengers: passengers,
        category: category,
        loading: loading,
        type: type,
        packageId: packageId,
        expectedWaitMin: expectedWaitMin,
        scheduledAt: scheduledAt,
        manualKm: manualKm,
        routeKm: routeKm,
        estKm: estKm,
      );
}

final bookingDraftProvider =
    NotifierProvider<BookingDraftNotifier, BookingDraft>(BookingDraftNotifier.new);

class BookingDraftNotifier extends Notifier<BookingDraft> {
  BookingDraft? _last;

  @override
  BookingDraft build() {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    ref.onDispose(() => _disposed = true);
    final base = _last ?? const BookingDraft();
    if (catalog == null) return base;
    return _last = _reconcile(base, catalog);
  }

  Catalog? get _catalog => ref.read(catalogProvider).valueOrNull;

  void _set(BookingDraft d) {
    final catalog = _catalog;
    state = _last = catalog == null ? d : _reconcile(d, catalog);
  }

  // A new pin means a new trip: the distance typed for the old one no longer applies.
  void setPickup(MapPick pick) {
    _set(state.copyWith(pickup: pick, clearManualKm: true, clearRouteKm: true).withoutOffer());
    _fetchRoute();
  }

  void setDestination(MapPick pick) {
    _set(state.copyWith(destination: pick, clearManualKm: true, clearRouteKm: true).withoutOffer());
    _fetchRoute();
  }

  /// The trip changes: forget the destination (e.g. switching between City Ride and City to City).
  void clearDestination() {
    final d = state;
    _set(BookingDraft(
      pickup: d.pickup,
      passengers: d.passengers,
      category: d.category,
      loading: d.loading,
      type: d.type,
      packageId: d.packageId,
      expectedWaitMin: d.expectedWaitMin,
      scheduledAt: d.scheduledAt,
    ));
  }

  bool _disposed = false;

  /// Asks the routing service for the real road distance; until it answers (or if it cannot), the
  /// straight line x 1.3 is used.
  Future<void> _fetchRoute() async {
    final d = state;
    final from = d.pickup?.point, to = d.destination?.point;
    if (from == null || to == null || d.samePlace) return;
    try {
      final est = await ref
          .read(routingServiceProvider)
          .route([LatLng(from.lat, from.lng), LatLng(to.lat, to.lng)]);
      if (_disposed) return;
      final s = state;
      final f = s.pickup?.point, t = s.destination?.point;
      if (f == null || t == null || f.lat != from.lat || f.lng != from.lng || t.lat != to.lat || t.lng != to.lng) return;
      if (s.manualKm != null) return;
      final km = ((est.distanceKm * 10).round() / 10).clamp(1.0, 300.0);
      _set(s.copyWith(routeKm: km).withoutOffer());
    } catch (_) {
      // Keep the straight-line estimate.
    }
  }

  /// For addresses that are not on the map: the passenger says how far it is. Null goes back to the pins.
  void setManualKm(double? km) =>
      _set(km == null ? state.copyWith(clearManualKm: true).withoutOffer() : state.copyWith(manualKm: km).withoutOffer());

  void setPassengers(int count) => _set(state.copyWith(passengers: count));

  void setOffer(int fare) => _set(state.copyWith(offer: fare));

  /// Each ride type has its own fare, so the offer goes back to the recommended fare.
  void setCategory(String code) => _set(state.copyWith(category: code).withoutOffer());

  /// Loading help (Loader): the recommended fare changes with it.
  void setLoading(bool value) => _set(state.copyWith(loading: value).withoutOffer());

  /// One way / hourly / round trip. Bike, Rickshaw and Loader only do one way.
  void setType(BookingType type) => _set(state.copyWith(type: type).withoutOffer());

  void setPackage(String id) => _set(state.copyWith(packageId: id).withoutOffer());

  void setExpectedWait(int minutes) => _set(state.copyWith(expectedWaitMin: minutes.clamp(0, 1440)).withoutOffer());

  /// [at] null = as soon as possible.
  void setSchedule(DateTime? at) =>
      _set(at == null ? state.copyWith(clearSchedule: true).withoutOffer() : state.copyWith(scheduledAt: at).withoutOffer());

  void swap() {
    final d = state;
    if (d.pickup == null || d.destination == null) return;
    _set(BookingDraft(
      pickup: d.destination,
      destination: d.pickup,
      passengers: d.passengers,
      offer: d.offer,
      category: d.category,
      loading: d.loading,
      type: d.type,
      packageId: d.packageId,
      expectedWaitMin: d.expectedWaitMin,
      scheduledAt: d.scheduledAt,
      manualKm: d.manualKm,
      routeKm: d.routeKm,
    ));
  }

  /// Keeps the draft valid: a ride type that exists and can take this trip, a booking type that
  /// ride type allows, passengers within its seats, and an offer inside the allowed band
  /// (else the recommended fare).
  static BookingDraft _reconcile(BookingDraft d, Catalog c) {
    var type = d.type;
    final km = d.distanceKm;
    var available = c.categoriesFor(type == BookingType.hourly ? null : km);
    if (type != BookingType.oneWay) {
      available = [for (final x in available) if (x.isCar) x];
      if (available.isEmpty) {
        type = BookingType.oneWay;
        available = c.categoriesFor(km);
      }
    }
    var category = d.category;
    if (c.category(category) == null || !available.any((x) => x.code == category)) {
      category = available.isEmpty ? d.category : available.first.code;
    }
    final cat = c.category(category);
    final loading = type == BookingType.oneWay && d.loading && (cat?.hasLoading ?? false);
    final passengers = d.passengers.clamp(1, c.maxPassengersFor(category));
    var packageId = d.packageId;
    if (type == BookingType.hourly && c.package(packageId) == null) {
      packageId = c.hourlyPackages.isEmpty ? null : c.hourlyPackages.first.id;
    }

    final sameArea = d.samePlace && d.routeKm == null;
    final next = BookingDraft(
      pickup: d.pickup,
      destination: d.destination,
      passengers: passengers,
      offer: d.offer,
      category: category,
      loading: loading,
      type: type,
      packageId: packageId,
      expectedWaitMin: d.expectedWaitMin,
      scheduledAt: d.scheduledAt,
      manualKm: d.manualKm,
      routeKm: d.routeKm,
      estKm: sameArea ? c.settings.sameAreaKm : null,
    );
    int? offer = d.offer;
    final q = next.quote(c);
    if (q != null && (offer == null || q.check(offer) != FareCheck.ok)) {
      offer = q.recommended;
    }
    return BookingDraft(
      pickup: next.pickup,
      destination: next.destination,
      passengers: passengers,
      offer: offer,
      category: category,
      loading: loading,
      type: type,
      packageId: packageId,
      expectedWaitMin: next.expectedWaitMin,
      scheduledAt: next.scheduledAt,
      manualKm: next.manualKm,
      routeKm: next.routeKm,
      estKm: next.estKm,
    );
  }
}
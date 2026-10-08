// Drives the real Home screen: pick two places, press "Find a Ride", and check
// the request really goes out with the right ride type, fare and labels.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/supabase_providers.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/notifications/domain/app_notification.dart';
import 'package:kamgo_app/features/notifications/presentation/notification_providers.dart';
import 'package:kamgo_app/features/passenger/presentation/booking_draft.dart';
import 'package:kamgo_app/features/passenger/presentation/home_shell.dart';
import 'package:kamgo_app/features/profile/domain/profile.dart';
import 'package:kamgo_app/features/profile/presentation/profile_providers.dart';
import 'package:kamgo_app/features/rides/domain/adda.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/fare_service.dart';
import 'package:kamgo_app/features/rides/domain/map_pick.dart';
import 'package:kamgo_app/features/rides/domain/ride_models.dart';
import 'package:kamgo_app/features/rides/domain/ride_repository.dart';
import 'package:kamgo_app/features/rides/presentation/ride_flow_providers.dart';
import 'package:kamgo_app/features/rides/presentation/ride_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'goldens/golden_fonts.dart';
import 'support/fare_fixtures.dart';

class _Call {
  _Call(this.pickup, this.dropoff, this.passengers, this.fare, this.pickupLabel, this.dropoffLabel, this.category,
      this.type, this.packageId, this.waitMin, this.scheduledAt);
  final GeoPoint pickup;
  final GeoPoint dropoff;
  final int passengers;
  final int fare;
  final String? pickupLabel;
  final String? dropoffLabel;
  final String category;
  final BookingType type;
  final String? packageId;
  final int waitMin;
  final DateTime? scheduledAt;
}

class _FakeRides implements RideRepository {
  final calls = <_Call>[];

  @override
  Future<RideRequest> createRequest({
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required int passengers,
    required int fare,
    String? pickupLabel,
    String? dropoffLabel,
    String category = 'car_mini',
    bool loading = false,
    BookingType bookingType = BookingType.oneWay,
    String? packageId,
    int expectedWaitMin = 0,
    DateTime? scheduledAt,
    double? distanceKm,
  }) async {
    calls.add(_Call(pickup, dropoff, passengers, fare, pickupLabel, dropoffLabel, category, bookingType, packageId,
        expectedWaitMin, scheduledAt));
    throw StateError('stop here: the request was sent'); // no router in this test
  }

  @override
  Future<ActiveState> myActive() async => const ActiveState();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _toba = City(id: 't', name: 'Toba Tek Singh', lat: 30.9709, lng: 72.4826, serviceRadiusKm: 25);
const _kamalia = City(id: 'k', name: 'Kamalia', lat: 30.7258, lng: 72.6447);

final _catalog = Catalog(
  cities: const [_toba, _kamalia],
  routes: const [],
  settings: const AppSettings(),
  categories: testCategories,
  hourlyPackages: testPackages,
);

Future<_FakeRides> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = _FakeRides();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      rideRepositoryProvider.overrideWithValue(fake),
      catalogProvider.overrideWith((_) async => _catalog),
      myProfileProvider.overrideWith((_) async =>
          const Profile(id: 'u', role: UserRole.passenger, onboarded: true, fullName: 'Ali Raza')),
      notificationsProvider.overrideWith((_) async => <AppNotification>[]),
      addaSummaryProvider.overrideWith((_) async => const <AddaSummary>[]),
      popularRouteProvider.overrideWith((_, __) async => null),
      recentDestinationsProvider.overrideWith((_) async => const <String>[]),
      placesProvider.overrideWith((_) async => const []),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true, size: Size(392.7, 850.9)),
        child: HomeShell(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Find a Ride sends the request with category, fare and typed addresses', (tester) async {
    final fake = await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);

    // Pickup typed as an address in a village; destination from a map pin.
    draft.setPickup(const MapPick(
        point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'mohallah ravi town'));
    draft.setDestination(const MapPick(point: GeoPoint(30.7258, 72.6447), nearestName: 'Kamalia'));
    await tester.pumpAndSettle();

    final state = container.read(bookingDraftProvider);
    expect(state.category, 'car_mini');
    expect(state.offer, isNotNull, reason: 'a fare is suggested as soon as both places are chosen');

    final button = find.text('Find a Ride');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(fake.calls, hasLength(1), reason: 'pressing Find a Ride must send the request');
    final c = fake.calls.single;
    expect(c.category, 'car_mini');
    expect(c.passengers, 1);
    expect(c.fare, state.offer);
    expect(c.pickupLabel, 'mohallah ravi town');
    expect(c.dropoffLabel, 'Pinned location', reason: 'a pin without a name still says what it is');
  });

  testWidgets('changing the ride type re-suggests a fare in that type\'s range', (tester) async {
    await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh'));
    draft.setDestination(const MapPick(point: GeoPoint(30.7258, 72.6447), nearestName: 'Kamalia'));
    await tester.pumpAndSettle();

    final miniFare = container.read(bookingDraftProvider).offer!;
    draft.setCategory('car_comfort');
    await tester.pumpAndSettle();
    final alt = container.read(bookingDraftProvider);
    expect(alt.category, 'car_comfort');
    expect(alt.offer, greaterThan(miniFare));
    expect(_catalog.quoteFor('car_comfort', alt.distanceKm!)!.check(alt.offer!), FareCheck.ok);
  });

  testWidgets('two addresses in the same area are counted as the default local distance and can be sent', (tester) async {
    final fake = await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    // "bilal town" and "ravi town kamalia" both resolve to the same area: no two different spots to measure.
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'bilal town'));
    draft.setDestination(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'ravi town'));
    await tester.pumpAndSettle();

    final s = container.read(bookingDraftProvider);
    expect(s.isEstimate, isTrue);
    expect(s.distanceKm, 3, reason: 'same_area_default_km setting');
    expect(find.textContaining('same area'), findsWidgets);

    final button = find.text('Find a Ride');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.pickupLabel, 'bilal town');
  });
  testWidgets('hourly: pick a package, no destination needed, the request carries the package', (tester) async {
    final fake = await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'city centre'));
    draft.setType(BookingType.hourly);
    draft.setPackage('p4');
    await tester.pumpAndSettle();

    final state = container.read(bookingDraftProvider);
    expect(state.type, BookingType.hourly);
    expect(state.offer, 3940, reason: 'the 4h / 40 km Mini package');

    final button = find.text('Find a Ride');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    final c = fake.calls.single;
    expect(c.type, BookingType.hourly);
    expect(c.packageId, 'p4');
    expect(c.fare, 3940);
    expect(c.category, 'car_mini');
  });

  testWidgets('bike cannot be booked hourly or as a round trip: the booking falls back to a car', (tester) async {
    await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh'));
    draft.setDestination(const MapPick(point: GeoPoint(31.05, 72.50), nearestName: 'Toba Tek Singh'));
    draft.setCategory('bike');
    await tester.pumpAndSettle();
    expect(container.read(bookingDraftProvider).category, 'bike');

    draft.setType(BookingType.roundTrip);
    await tester.pumpAndSettle();
    final s = container.read(bookingDraftProvider);
    expect(s.type, BookingType.roundTrip);
    expect(_catalog.category(s.category)!.isCar, isTrue);

    draft.setType(BookingType.oneWay);
    draft.setCategory('bike');
    await tester.pumpAndSettle();
    expect(container.read(bookingDraftProvider).category, 'bike');
  });

  testWidgets('round trip: expected waiting is part of the quote', (tester) async {
    await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh'));
    draft.setDestination(const MapPick(point: GeoPoint(31.05, 72.50), nearestName: 'Toba Tek Singh'));
    draft.setType(BookingType.roundTrip);
    await tester.pumpAndSettle();
    final none = container.read(bookingDraftProvider).offer!;
    draft.setExpectedWait(90);
    await tester.pumpAndSettle();
    expect(container.read(bookingDraftProvider).offer, none + 250);
  });
  testWidgets('same spot on the map: the passenger types the distance and the fare follows it', (tester) async {
    final fake = await _pumpHome(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    final draft = container.read(bookingDraftProvider.notifier);
    draft.setPickup(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'bilal town'));
    draft.setDestination(const MapPick(point: GeoPoint(30.9709, 72.4826), nearestName: 'Toba Tek Singh', label: 'ravi town'));
    await tester.pumpAndSettle();
    expect(container.read(bookingDraftProvider).samePlace, isTrue);

    draft.setManualKm(4);
    await tester.pumpAndSettle();
    final s = container.read(bookingDraftProvider);
    expect(s.samePlace, isFalse);
    expect(s.distanceKm, 4);
    expect(s.offer, _catalog.quoteFor('car_mini', 4, night: _catalog.fareService.isNight(DateTime.now()))!.recommended);

    final button = find.text('Find a Ride');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(fake.calls, hasLength(1));
    expect(fake.calls.single.pickupLabel, 'bilal town');
  });}

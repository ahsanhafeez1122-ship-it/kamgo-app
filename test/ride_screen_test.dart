// The ride screen on a phone-size window: the driver's Start Ride button must be on
// screen without scrolling, and both sides must see when the driver arrives.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/location_service.dart';
import 'package:kamgo_app/core/services/map_provider.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/auth/presentation/auth_providers.dart';
import 'package:kamgo_app/features/driver/domain/driver_models.dart';
import 'package:kamgo_app/features/driver/presentation/driver_providers.dart';
import 'package:kamgo_app/features/rides/domain/ride_models.dart';
import 'package:kamgo_app/features/rides/domain/ride_repository.dart';
import 'package:kamgo_app/features/rides/domain/ride_status.dart';
import 'package:kamgo_app/features/rides/presentation/location_tracker.dart';
import 'package:kamgo_app/features/rides/presentation/ride_flow_providers.dart';
import 'package:kamgo_app/features/rides/presentation/ride_screen.dart';
import 'package:latlong2/latlong.dart';

import 'goldens/golden_fonts.dart';

class _FakeRides implements RideRepository {
  _FakeRides(this.details);
  RideDetails details;
  final statuses = <RideStatus>[];

  @override
  Future<RideDetails> ride(String rideId) async => details;

  @override
  Stream<void> rideChanges(String rideId) => const Stream.empty();

  @override
  Future<void> updateStatus(String rideId, RideStatus status) async {
    statuses.add(status);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDrivers implements DriverRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoTracker extends RideLocationTracker {
  _NoTracker() : super(const LocationService(), _FakeDrivers());

  @override
  Future<void> start(String rideId) async {}

  @override
  Future<void> stop() async {}
}

class _NoMap implements MapProvider {
  @override
  Widget buildMap({
    required List<LatLng> fitPoints,
    List<LatLng> polyline = const [],
    List<MapMarker> markers = const [],
    Color polylineColor = const Color(0xFF16A34A),
  }) =>
      const SizedBox.expand(child: ColoredBox(color: Color(0xFFE5E7EB)));
}

RideDetails _ride({int? etaMin, DateTime? confirmedAt, GeoPoint? driverAt}) => RideDetails(
      id: 'ride1',
      status: RideStatus.confirmed,
      finalFare: 1000,
      passengerCount: 1,
      origin: const Place(id: 'o', name: 'Toba Tek Singh', point: GeoPoint(30.9709, 72.4826)),
      destination: const Place(id: 'd', name: 'Kamalia', point: GeoPoint(30.7258, 72.6447)),
      stops: const [],
      driver: const RideParty(id: 'drv', name: 'Bilal Hussain', phone: '+923000000012', rating: 4.9),
      passenger: const RideParty(id: 'pax', name: 'Ali Raza', phone: '+923000000002', rating: 5),
      vehicle: const VehicleInfo(make: 'Toyota', model: 'Corolla', color: 'Silver', plate: 'TTA-1202'),
      distanceKm: 40,
      confirmedAt: confirmedAt,
      etaMin: etaMin,
      lastLocation: driverAt,
    );

Future<_FakeRides> _pump(WidgetTester tester, {required String me, required RideDetails details}) async {
  tester.view.physicalSize = const Size(1080, 2000); // a short phone window (392 x 727 logical)
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  final fake = _FakeRides(details);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      rideRepositoryProvider.overrideWithValue(fake),
      authUserIdProvider.overrideWith((_) => Stream.value(me)),
      rideLocationTrackerProvider.overrideWithValue(_NoTracker()),
      mapProviderProvider.overrideWithValue(_NoMap()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true, size: Size(392.7, 727.3)),
        child: RideScreen(rideId: 'ride1'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('driver: Start Ride is on screen without scrolling, and works', (tester) async {
    final fake = await _pump(tester, me: 'drv', details: _ride(etaMin: 10, confirmedAt: DateTime.now()));
    final start = find.text('Start Ride');
    expect(start, findsOneWidget);
    final rect = tester.getRect(start);
    expect(rect.bottom, lessThanOrEqualTo(727.3), reason: 'the button must not be below the visible screen');
    expect(find.text("I'm on my way"), findsOneWidget);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(fake.statuses, [RideStatus.rideStarted]);
  });

  testWidgets('both sides see how long until the driver arrives (the driver\'s own ETA)', (tester) async {
    await _pump(tester, me: 'pax', details: _ride(etaMin: 10, confirmedAt: DateTime.now()));
    expect(find.textContaining('Driver arrives in about 10 min'), findsOneWidget);
  });

  testWidgets('driver sees the same countdown worded for them', (tester) async {
    await _pump(tester, me: 'drv', details: _ride(etaMin: 10, confirmedAt: DateTime.now()));
    expect(find.textContaining('Reach the pickup in about 10 min'), findsOneWidget);
  });

  testWidgets('the countdown goes down as time passes, and says "arriving now" at zero', (tester) async {
    final late = DateTime.now().subtract(const Duration(minutes: 15));
    await _pump(tester, me: 'pax', details: _ride(etaMin: 10, confirmedAt: late));
    expect(find.textContaining('arriving now'), findsOneWidget);
  });

  testWidgets('with the driver\'s live position, the ETA comes from the distance', (tester) async {
    // About 3 km from the pickup: roughly 8 minutes at 30 km/h on the road.
    await _pump(tester,
        me: 'pax', details: _ride(etaMin: 60, confirmedAt: DateTime.now(), driverAt: const GeoPoint(30.9709, 72.5100)));
    final text = tester.widgetList<Text>(find.textContaining('Driver arrives in about')).single.data!;
    final mins = int.parse(RegExp(r'about (\d+) min').firstMatch(text)!.group(1)!);
    expect(mins, inInclusiveRange(5, 12));
  });

  testWidgets('no ETA known: no made-up arrival line', (tester) async {
    await _pump(tester, me: 'pax', details: _ride());
    expect(find.textContaining('arrives in about'), findsNothing);
    expect(find.textContaining('Driver arrives'), findsNothing);
  });
}

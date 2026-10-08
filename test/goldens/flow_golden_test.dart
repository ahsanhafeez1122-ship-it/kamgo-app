// Golden renders of the Phase 2–4 screens with fake data:
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/supabase_providers.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/auth/presentation/auth_providers.dart';
import 'package:kamgo_app/features/driver/domain/driver_models.dart';
import 'package:kamgo_app/features/driver/presentation/driver_dashboard_tab.dart';
import 'package:kamgo_app/features/driver/presentation/driver_providers.dart';
import 'package:kamgo_app/features/passenger/presentation/driver_offers_screen.dart';
import 'package:kamgo_app/features/passenger/presentation/finding_drivers_screen.dart';
import 'package:kamgo_app/features/profile/domain/profile.dart';
import 'package:kamgo_app/features/profile/presentation/profile_providers.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/domain/ride_models.dart';
import 'package:kamgo_app/features/rides/domain/ride_status.dart';
import 'package:kamgo_app/features/rides/presentation/live_state.dart';
import 'package:kamgo_app/features/rides/presentation/ride_flow_providers.dart';
import 'package:kamgo_app/features/rides/presentation/ride_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden_fonts.dart';

final _catalog = Catalog(
  cities: const [City(id: 'k', name: 'Kamalia'), City(id: 'p', name: 'Pir Mahal'), City(id: 'r', name: 'Rajana')],
  routes: const [RouteInfo(id: 'r1', originCityId: 'p', destinationCityId: 'r', distanceKm: 22)],
  settings: const AppSettings(),
);

final _future = DateTime.now().add(const Duration(minutes: 12));

final _request = RideRequest(
  id: 'req',
  routeId: 'r1',
  originCityId: 'p',
  destinationCityId: 'r',
  passengerCount: 2,
  offeredFare: 1100,
  status: RideStatus.offerReceived,
  expiresAt: _future,
);

DriverOffer _offer(String id, String name, OfferType t, double fare, double rating, String car, int eta, double km) =>
    DriverOffer(
      id: id, driverId: id, driverName: name, rating: rating, vehicle: car, plate: 'TTA-12$id',
      type: t, fare: fare, status: OfferStatus.pending, expiresAt: _future, etaMin: eta, distanceKm: km,
    );

class _FakeLive extends LiveRequestNotifier {
  _FakeLive(this.offers);
  final List<DriverOffer> offers;

  @override
  Future<LiveRequest> build(String requestId) async => LiveRequest(request: _request, offers: offers);
}

class _FakeFeed extends DriverFeedNotifier {
  @override
  Future<List<FeedRequest>> build() async => [
        FeedRequest(
          requestId: 'a', routeId: 'r4', originName: 'Rajana', destinationName: 'Pir Mahal',
          passengerName: 'Rashid', passengerRating: 4.8, passengerCount: 1, offeredFare: 900,
          distanceKm: 22, createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
          expiresAt: _future, isReturn: true, pickupLabel: 'Rajana Main Bazaar',
        ),
        FeedRequest(
          requestId: 'b', routeId: 'r5', originName: 'Rajana', destinationName: 'Kamalia',
          passengerName: 'Sana', passengerRating: 5, passengerCount: 3, offeredFare: 1600,
          distanceKm: 45, createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
          expiresAt: _future, isReturn: false, myOfferFare: 1800, myOfferIsCounter: true,
        ),
      ];
}

Future<void> _pump(WidgetTester tester, Widget child, List<Override> overrides) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      catalogProvider.overrideWith((_) async => _catalog),
      authUserIdProvider.overrideWith((_) => Stream.value('me')),
      myProfileProvider.overrideWith((_) async =>
          const Profile(id: 'me', role: UserRole.driver, onboarded: true, fullName: 'Bilal Hussain')),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true, size: Size(392.7, 850.9), padding: EdgeInsets.only(top: 28)),
        child: child,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Unmount and let pending timers (animations, polling) finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('driver offers', (tester) async {
    await _pump(tester, const DriverOffersScreen(requestId: 'req'), [
      liveRequestProvider.overrideWith(() => _FakeLive([
            _offer('1', 'Imran Ahmed', OfferType.accept, 1100, 4.8, 'Suzuki Alto', 4, 1.2),
            _offer('2', 'Bilal Hussain', OfferType.counter, 1200, 4.9, 'Toyota Corolla', 6, 1.8),
            _offer('3', 'Usman Tariq', OfferType.counter, 1300, 4.6, 'Suzuki Bolan', 9, 2.6),
          ])),
    ]);
    await expectLater(find.byType(DriverOffersScreen), matchesGoldenFile('offers.png'));
    await _settle(tester);
  });

  testWidgets('finding drivers', (tester) async {
    await _pump(tester, const FindingDriversScreen(requestId: 'req'), [
      liveRequestProvider.overrideWith(() => _FakeLive(const [])),
    ]);
    await expectLater(find.byType(FindingDriversScreen), matchesGoldenFile('finding.png'));
    await _settle(tester);
  });

  testWidgets('driver dashboard', (tester) async {
    await _pump(tester, Scaffold(body: SafeArea(child: DriverDashboardTab(onOpenMenu: () {}))), [
      driverDashboardProvider.overrideWith((_) async => DriverDashboard.fromJson({
            'status': 'APPROVED', 'is_online': true, 'city_id': 'r', 'city_name': 'Rajana', 'rating': 4.9,
            'rating_count': 12, 'total_rides': 40, 'cnic': 'x',
            'vehicle': {'type': 'CAR', 'make': 'Toyota', 'model': 'Corolla', 'plate': 'TTA-1202'},
            'route_ids': [], 'documents': [],
            'earnings': {'today': 1080, 'week': 6400, 'month': 21000, 'rides_today': 1, 'commission_due': 120},
            'adda': {'online_drivers': 4, 'open_requests': 2}, 'recent_ratings': [],
          })),
      driverFeedProvider.overrideWith(_FakeFeed.new),
      activeStateProvider.overrideWith((_) async => const ActiveState()),
    ]);
    await expectLater(find.byType(DriverDashboardTab), matchesGoldenFile('driver_dashboard.png'));
    await _settle(tester);
  });
}

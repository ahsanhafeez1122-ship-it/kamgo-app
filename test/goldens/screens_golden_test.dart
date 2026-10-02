// Renders key screens with the real bundled fonts and fake data, so the
// design can be reviewed without a device:
//   flutter test --update-goldens test/goldens
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamgo_app/core/services/supabase_providers.dart';
import 'package:kamgo_app/core/theme/app_theme.dart';
import 'package:kamgo_app/features/notifications/domain/app_notification.dart';
import 'package:kamgo_app/features/notifications/presentation/notification_providers.dart';
import 'package:kamgo_app/features/passenger/presentation/home_shell.dart';
import 'package:kamgo_app/features/profile/domain/profile.dart';
import 'package:kamgo_app/features/profile/presentation/profile_providers.dart';
import 'package:kamgo_app/features/rides/domain/adda.dart';
import 'package:kamgo_app/features/rides/domain/catalog.dart';
import 'package:kamgo_app/features/rides/presentation/ride_providers.dart';
import 'package:kamgo_app/core/widgets/kamgo_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'golden_fonts.dart';

const _kamalia = City(id: 'k', name: 'Kamalia');
const _pirMahal = City(id: 'p', name: 'Pir Mahal');
const _rajana = City(id: 'r', name: 'Rajana');

final _catalog = Catalog(
  cities: const [_kamalia, _pirMahal, _rajana],
  routes: const [
    RouteInfo(id: 'r1', originCityId: 'p', destinationCityId: 'r', distanceKm: 22),
    RouteInfo(id: 'r2', originCityId: 'p', destinationCityId: 'k', distanceKm: 25),
    RouteInfo(id: 'r3', originCityId: 'k', destinationCityId: 'p', distanceKm: 25),
    RouteInfo(id: 'r4', originCityId: 'r', destinationCityId: 'p', distanceKm: 22),
  ],
  settings: const AppSettings(),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('home', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'last_pickup_city_id': 'p'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        catalogProvider.overrideWith((_) async => _catalog),
        myProfileProvider.overrideWith((_) async => const Profile(
              id: 'u', role: UserRole.passenger, onboarded: true, fullName: 'Ali Raza')),
        notificationsProvider.overrideWith((_) async => [
              AppNotification(id: 'n', type: 'X', title: 'Hi', createdAt: DateTime(2026)),
            ]),
        addaSummaryProvider.overrideWith((_) async => const [
              AddaSummary(cityId: 'p', cityName: 'Pir Mahal', onlineDrivers: 12, openRequests: 3),
            ]),
        popularRouteProvider.overrideWith((_, __) async => const PopularRoute(
              routeId: 'r1', originName: 'Pir Mahal', destinationName: 'Rajana', approxFare: 1200)),
        recentDestinationsProvider.overrideWith((_) async => const ['r', 'k', 'p']),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true, size: Size(392.7, 850.9),
              padding: EdgeInsets.only(top: 28)),
          child: HomeShell(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(HomeShell), matchesGoldenFile('home.png'));
  });

  testWidgets('splash end state', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    // Static rendering of the splash composition (no auth / navigation).
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const _SplashPreview(),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(_SplashPreview), matchesGoldenFile('splash.png'));
  });
}

class _SplashPreview extends StatelessWidget {
  const _SplashPreview();

  @override
  Widget build(BuildContext context) {
    // Mirrors SplashScreen's layout without the navigation side effects.
    return const MediaQuery(
      data: MediaQueryData(disableAnimations: true, size: Size(392.7, 850.9)),
      child: _SplashBody(),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B2347), Color(0xFF0E2B57)],
          ),
        ),
        child: Stack(children: [
          Positioned(top: -110, right: -120, child: _circle(320, const Color(0x2916A34A))),
          Positioned(bottom: -150, left: -130, child: _circle(360, const Color(0x0DFFFFFF))),
          const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LogoBadge(size: 112, radius: 28),
              SizedBox(height: 28),
              Wordmark(size: 34),
              SizedBox(height: 10),
              Text('Apni Ride, Apna Fare',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 16, color: Color(0xB8FFFFFF))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _circle(double s, Color c) =>
      Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: c));
}

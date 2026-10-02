import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/driver/presentation/driver_onboarding_screen.dart';
import '../../features/driver/presentation/driver_shell.dart';
import '../../features/passenger/presentation/driver_offers_screen.dart';
import '../../features/passenger/presentation/finding_drivers_screen.dart';
import '../../features/passenger/presentation/home_shell.dart';
import '../../features/profile/domain/profile.dart';
import '../../features/profile/presentation/profile_setup_screen.dart';
import '../../features/rides/presentation/ride_completed_screen.dart';
import '../../features/rides/presentation/ride_screen.dart';
import '../../features/support/presentation/support_screen.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const otp = '/otp';
  static const setup = '/setup';
  static const home = '/home';
  static const driver = '/driver';
  static const driverOnboarding = '/driver/register';
  static const support = '/support';
  static String finding(String requestId, {bool justSent = false}) =>
      '/request/$requestId/finding${justSent ? '?sent=1' : ''}';
  static String offers(String requestId) => '/request/$requestId/offers';
  static String ride(String rideId) => '/ride/$rideId';
  static String rideComplete(String rideId) => '/ride/$rideId/complete';
}

/// Where a signed-in user lands, based on their server-side profile.
String homeRouteFor(Profile? profile) {
  if (profile == null || !profile.onboarded) return AppRoutes.setup;
  return profile.role == UserRole.driver ? AppRoutes.driver : AppRoutes.home;
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);
  final refresh = _StreamListenable(auth.userIdChanges());
  ref.onDispose(refresh.dispose);

  const publicPaths = {AppRoutes.splash, AppRoutes.login, AppRoutes.otp};

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = auth.currentUserId != null;
      final path = state.matchedLocation;
      if (!signedIn && !publicPaths.contains(path)) return AppRoutes.login;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: AppRoutes.otp,
        redirect: (_, state) => state.extra is String ? null : AppRoutes.login,
        builder: (_, state) => OtpScreen(phone: state.extra! as String),
      ),
      GoRoute(path: AppRoutes.setup, builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: AppRoutes.home, builder: (_, __) => const HomeShell()),
      GoRoute(path: AppRoutes.driver, builder: (_, __) => const DriverShell()),
      GoRoute(path: AppRoutes.driverOnboarding, builder: (_, __) => const DriverOnboardingScreen()),
      GoRoute(
        path: AppRoutes.support,
        builder: (_, state) => SupportScreen(rideId: state.extra as String?),
      ),
      GoRoute(
        path: '/request/:id/finding',
        builder: (_, s) => FindingDriversScreen(
          requestId: s.pathParameters['id']!,
          justSent: s.uri.queryParameters['sent'] == '1',
        ),
      ),
      GoRoute(
        path: '/request/:id/offers',
        builder: (_, s) => DriverOffersScreen(requestId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ride/:id',
        builder: (_, s) => RideScreen(rideId: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'complete',
            builder: (_, s) => RideCompletedScreen(rideId: s.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
});

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

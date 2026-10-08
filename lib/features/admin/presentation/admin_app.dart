import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/kamgo_logo.dart';
import '../../auth/domain/auth_service.dart';
import '../../auth/presentation/auth_providers.dart';
import 'admin_widgets.dart';
import 'pages/catalog_pages.dart';
import 'pages/complaints_page.dart';
import 'pages/places_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/drivers_page.dart';
import 'pages/fares_pages.dart';
import 'pages/passengers_page.dart';
import 'pages/rides_page.dart';
import 'pages/settings_page.dart';

class KamgoAdminApp extends StatelessWidget {
  const KamgoAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'KAM GO Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const _AdminGate(),
      );
}

/// Signed in AND listed in admin_users → panel; otherwise login.
final _isAdminProvider = FutureProvider<bool>((ref) async {
  final uid = await ref.watch(authUserIdProvider.future);
  if (uid == null) return false;
  return ref.watch(adminRepositoryProvider).isAdmin();
});

class _AdminGate extends ConsumerWidget {
  const _AdminGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserIdProvider).valueOrNull;
    final admin = ref.watch(_isAdminProvider);
    if (uid == null) return const _AdminLogin();
    return switch (admin) {
      AsyncData(value: true) => const _AdminShell(),
      AsyncData() => const _AdminLogin(error: 'This number is not a KAM GO admin.', signOut: true),
      AsyncError() => const _AdminLogin(error: 'Could not verify admin access.'),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.green))),
    };
  }
}

class _AdminLogin extends ConsumerStatefulWidget {
  const _AdminLogin({this.error, this.signOut = false});
  final String? error;
  final bool signOut;

  @override
  ConsumerState<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends ConsumerState<_AdminLogin> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  bool _busy = false;
  late String? _error = widget.error;

  @override
  void initState() {
    super.initState();
    if (widget.signOut) ref.read(authServiceProvider).signOut();
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final auth = ref.read(authServiceProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_sentTo == null) {
        final p = normalizePkPhone(_phone.text);
        if (p == null) throw const AuthFailure('Enter a valid mobile number.');
        await auth.sendOtp(p);
        setState(() => _sentTo = p);
      } else {
        await auth.verifyOtp(phoneE164: _sentTo!, code: _code.text.trim());
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not sign in. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: Center(
        child: SizedBox(
          width: 400,
          child: AppCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(children: [
                  LogoBadge(size: 44, radius: 13),
                  SizedBox(width: 12),
                  Wordmark(size: 22, kamColor: AppColors.navy, goColor: AppColors.green),
                ]),
                const SizedBox(height: 18),
                Text('Admin sign in', style: AppText.display(20)),
                const SizedBox(height: 16),
                if (_sentTo == null)
                  TextField(
                    controller: _phone,
                    decoration: const InputDecoration(hintText: '0300 0000001'),
                    onSubmitted: (_) => _go(),
                  )
                else
                  TextField(
                    controller: _code,
                    autofocus: true,
                    decoration: InputDecoration(hintText: 'Code sent to ${formatPkPhone(_sentTo!)}'),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _go(),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: AppText.body(13.5, color: AppColors.danger)),
                ],
                const SizedBox(height: 18),
                PrimaryButton(label: _sentTo == null ? 'Send code' : 'Sign in', loading: _busy, onPressed: _go),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminShell extends ConsumerStatefulWidget {
  const _AdminShell();

  @override
  ConsumerState<_AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<_AdminShell> {
  int _i = 0;

  static const _pages = [
    (Icons.dashboard_rounded, 'Dashboard'),
    (Icons.directions_car_rounded, 'Drivers'),
    (Icons.people_alt_rounded, 'Passengers'),
    (Icons.location_city_rounded, 'Cities'),
    (Icons.alt_route_rounded, 'Routes'),
    (Icons.place_rounded, 'Places'),
    (Icons.category_rounded, 'Ride types'),
    (Icons.directions_car_filled_rounded, 'Vehicle models'),
    (Icons.schedule_rounded, 'Hourly packages'),
    (Icons.bar_chart_rounded, 'Fare report'),
    (Icons.receipt_long_rounded, 'Rides'),
    (Icons.report_rounded, 'Complaints'),
    (Icons.tune_rounded, 'Settings'),
  ];

  Widget _page() => switch (_i) {
        0 => const AdminDashboardPage(),
        1 => const AdminDriversPage(),
        2 => const AdminPassengersPage(),
        3 => const AdminCitiesPage(),
        4 => const AdminRoutesPage(),
        5 => const AdminPlacesPage(),
        6 => const AdminCategoriesPage(),
        7 => const AdminVehicleModelsPage(),
        8 => const AdminPackagesPage(),
        9 => const AdminFareReportPage(),
        10 => const AdminRidesPage(),
        11 => const AdminComplaintsPage(),
        _ => const AdminSettingsPage(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            backgroundColor: AppColors.navy,
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() => _i = i),
            indicatorColor: AppColors.green,
            selectedIconTheme: const IconThemeData(color: AppColors.white),
            unselectedIconTheme: IconThemeData(color: AppColors.white.withValues(alpha: 0.6)),
            selectedLabelTextStyle: AppText.body(14, weight: FontWeight.w600, color: AppColors.white),
            unselectedLabelTextStyle: AppText.body(14, color: AppColors.white.withValues(alpha: 0.7)),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: wide
                  ? const Row(mainAxisSize: MainAxisSize.min, children: [
                      LogoBadge(size: 36, radius: 10),
                      SizedBox(width: 10),
                      Wordmark(size: 19),
                    ])
                  : const LogoBadge(size: 36, radius: 10),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    tooltip: 'Sign out',
                    icon: Icon(Icons.logout_rounded, color: AppColors.white.withValues(alpha: 0.7)),
                    onPressed: () => ref.read(authServiceProvider).signOut(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final (icon, label) in _pages)
                NavigationRailDestination(icon: Icon(icon), label: Text(label)),
            ],
          ),
          Expanded(child: _page()),
        ],
      ),
    );
  }
}

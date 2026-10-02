import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../notifications/presentation/alerts_tab.dart';
import '../../passenger/presentation/home_shell.dart';
import '../../profile/presentation/profile_tab.dart';
import 'driver_dashboard_tab.dart';
import 'earnings_tab.dart';

/// Driver shell: Dashboard · Earnings · Alerts · Profile.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: const [DriverDashboardTab(), EarningsTab(), AlertsTab(), ProfileTab()],
          ),
        ),
        bottomNavigationBar: KamgoBottomNav(
          index: _index,
          onSelect: (i) => setState(() => _index = i),
          items: [
            (Icons.dashboard_rounded, context.tr('nav.dashboard')),
            (Icons.account_balance_wallet_rounded, context.tr('nav.earnings')),
            (Icons.notifications_rounded, context.tr('nav.alerts')),
            (Icons.person_rounded, context.tr('nav.profile')),
          ],
        ),
      ),
    );
  }
}

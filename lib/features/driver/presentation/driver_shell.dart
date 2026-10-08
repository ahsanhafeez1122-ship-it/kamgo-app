import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../notifications/presentation/alerts_tab.dart';
import '../../profile/presentation/kamgo_drawer.dart';
import '../../profile/presentation/profile_tab.dart';
import 'driver_dashboard_tab.dart';
import 'earnings_tab.dart';

/// Driver mode: Dashboard · Earnings · Alerts · Profile, reached from the
/// side menu.
class DriverShell extends StatefulWidget {
  const DriverShell({super.key});

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.dashboard_rounded, context.tr('nav.dashboard')),
      (Icons.account_balance_wallet_rounded, context.tr('nav.earnings')),
      (Icons.notifications_rounded, context.tr('nav.alerts')),
      (Icons.person_rounded, context.tr('nav.profile')),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: KamgoDrawer(
          driverMode: true,
          items: items,
          index: _index,
          onSelect: (i) => setState(() => _index = i),
        ),
        appBar: _index == 0
            ? null
            : AppBar(
                leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: _openMenu),
                title: Text(items[_index].$2),
              ),
        body: SafeArea(
          top: _index == 0,
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              DriverDashboardTab(onOpenMenu: _openMenu),
              const EarningsTab(),
              const AlertsTab(),
              const ProfileTab(),
            ],
          ),
        ),
      ),
    );
  }
}

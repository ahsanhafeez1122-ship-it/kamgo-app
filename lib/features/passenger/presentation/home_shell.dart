import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../notifications/presentation/alerts_tab.dart';
import '../../profile/presentation/kamgo_drawer.dart';
import '../../profile/presentation/profile_tab.dart';
import 'home_tab.dart';
import 'my_rides_tab.dart';

/// Passenger mode: Home · My Rides · Alerts · Profile, reached from a side
/// menu (the hamburger button) instead of a bottom bar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  void _openMenu() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, context.tr('nav.home')),
      (Icons.route_rounded, context.tr('nav.rides')),
      (Icons.notifications_rounded, context.tr('nav.alerts')),
      (Icons.person_rounded, context.tr('nav.profile')),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: KamgoDrawer(driverMode: false, items: items, index: _index, onSelect: _select),
        // Home draws its own top bar (with the menu button); the other pages get a plain one.
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
              HomeTab(
                onOpenAlerts: () => _select(2),
                onOpenProfile: () => _select(3),
                onOpenMenu: _openMenu,
              ),
              const MyRidesTab(),
              const AlertsTab(),
              const ProfileTab(),
            ],
          ),
        ),
      ),
    );
  }
}

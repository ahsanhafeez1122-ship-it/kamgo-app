import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../notifications/presentation/alerts_tab.dart';
import '../../profile/presentation/profile_tab.dart';
import 'home_tab.dart';
import 'my_rides_tab.dart';

/// Passenger shell: Home · My Rides · Alerts · Profile.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              HomeTab(onOpenAlerts: () => _select(2), onOpenProfile: () => _select(3)),
              const MyRidesTab(),
              const AlertsTab(),
              const ProfileTab(),
            ],
          ),
        ),
        bottomNavigationBar: KamgoBottomNav(
          index: _index,
          onSelect: _select,
          items: [
            (Icons.home_rounded, context.tr('nav.home')),
            (Icons.route_rounded, context.tr('nav.rides')),
            (Icons.notifications_rounded, context.tr('nav.alerts')),
            (Icons.person_rounded, context.tr('nav.profile')),
          ],
        ),
      ),
    );
  }
}

class KamgoBottomNav extends StatelessWidget {
  const KamgoBottomNav({super.key, required this.index, required this.onSelect, required this.items});

  final int index;
  final ValueChanged<int> onSelect;
  final List<(IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    highlightShape: BoxShape.rectangle,
                    child: _NavItem(
                      icon: items[i].$1,
                      label: items[i].$2,
                      active: i == index,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.green : AppColors.muted;
    return Semantics(
      selected: active,
      button: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 25),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppText.body(12,
                weight: active ? FontWeight.w600 : FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

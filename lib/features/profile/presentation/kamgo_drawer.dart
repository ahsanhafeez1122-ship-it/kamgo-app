import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/supabase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/buttons.dart';
import '../domain/profile.dart';
import 'app_mode.dart';
import 'profile_providers.dart';

/// Side menu for both modes (inDrive style): the account on top, the pages
/// of the current mode, and a button that flips Passenger ⇄ Driver mode.
class KamgoDrawer extends ConsumerWidget {
  const KamgoDrawer({
    super.key,
    required this.driverMode,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  /// True when the Driver side is showing.
  final bool driverMode;
  final List<(IconData, String)> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;

    return Drawer(
      backgroundColor: AppColors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: AppColors.navy,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.green,
                    child: Text(initialsOf(profile?.fullName),
                        style: AppText.display(20, color: AppColors.white)),
                  ),
                  const SizedBox(height: 12),
                  Text(profile?.fullName ?? '—', style: AppText.display(18, color: AppColors.white)),
                  const SizedBox(height: 2),
                  Text(
                    profile?.phone == null ? '' : formatPkPhone('+${profile!.phone}'),
                    style: AppText.body(13.5, color: AppColors.white.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      driverMode ? 'Driver mode' : 'Passenger mode',
                      style: AppText.body(12, weight: FontWeight.w600, color: AppColors.greenLight),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var i = 0; i < items.length; i++)
                    ListTile(
                      selected: i == index,
                      selectedColor: AppColors.green,
                      selectedTileColor: AppColors.greenSoft,
                      leading: Icon(items[i].$1),
                      title: Text(items[i].$2, style: AppText.body(15.5, weight: FontWeight.w600)),
                      onTap: () {
                        Navigator.pop(context);
                        onSelect(i);
                      },
                    ),
                  const Divider(height: 24),
                  ListTile(
                    leading: const Icon(Icons.support_agent_rounded),
                    title: Text('Help & support', style: AppText.body(15.5, weight: FontWeight.w600)),
                    onTap: () {
                      Navigator.pop(context);
                      context.push(AppRoutes.support);
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PrimaryButton(
                label: driverMode ? 'Passenger mode' : 'Driver mode',
                onPressed: () => driverMode ? switchToPassengerMode(context, ref) : switchToDriverMode(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> switchToPassengerMode(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  await setPassengerMode(ref.read(sharedPrefsProvider), true);
  router.go(AppRoutes.home);
}

Future<void> switchToDriverMode(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final profile = ref.read(myProfileProvider).valueOrNull;
  if (profile == null) return;

  if (profile.role != UserRole.driver) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Become a driver?'),
        content: const Text(
          'You will add your vehicle and documents, and KAM GO reviews them '
          'before you can go online. You can switch back to Passenger mode any time.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(profileRepositoryProvider).becomeDriver();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(friendlyError(e))));
      return;
    }
    ref.invalidate(myProfileProvider);
    ref.invalidate(myDriverInfoProvider);
  }

  await setPassengerMode(ref.read(sharedPrefsProvider), false);
  router.go(AppRoutes.driver);
}

/// Passenger | Driver toggle (inDrive style), shown at the top of both home screens.
class ModeSwitch extends ConsumerWidget {
  const ModeSwitch({super.key, required this.driverMode});

  /// True when the Driver side is showing.
  final bool driverMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget seg(String label, IconData icon, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: selected ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? AppColors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: selected ? AppColors.white : AppColors.navy),
                  const SizedBox(width: 6),
                  Text(label,
                      style: AppText.body(14, weight: FontWeight.w700, color: selected ? AppColors.white : AppColors.navy)),
                ],
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        seg('Passenger', Icons.person_rounded, !driverMode, () => switchToPassengerMode(context, ref)),
        seg('Driver', Icons.directions_car_rounded, driverMode, () => switchToDriverMode(context, ref)),
      ]),
    );
  }
}
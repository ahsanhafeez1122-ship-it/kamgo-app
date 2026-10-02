import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../rides/presentation/ride_providers.dart';
import '../domain/profile.dart';
import 'profile_providers.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final settings = ref.watch(catalogProvider).valueOrNull?.settings;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(context.tr('nav.profile'), style: AppText.display(22)),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.navy,
                child: Text(initialsOf(profile?.fullName),
                    style: AppText.display(20, color: AppColors.white)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile?.fullName ?? '—', style: AppText.display(18)),
                    const SizedBox(height: 3),
                    Text(
                      profile?.phone == null ? '' : formatPkPhone('+${profile!.phone}'),
                      style: AppText.body(14, color: AppColors.mutedDark),
                    ),
                  ],
                ),
              ),
              if (profile != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    profile.role == UserRole.driver ? 'Driver' : 'Passenger',
                    style: AppText.body(12, weight: FontWeight.w600, color: AppColors.green),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              _Tile(
                icon: Icons.contact_emergency_rounded,
                title: 'Emergency contact',
                subtitle: profile?.emergencyContactName?.isNotEmpty == true
                    ? '${profile!.emergencyContactName} · ${profile.emergencyContactPhone ?? ''}'
                    : 'Add someone we can share your trip with',
                onTap: profile == null ? null : () => _editEmergency(context, ref, profile),
              ),
              if (profile?.role == UserRole.driver) ...[
                const Divider(height: 1, indent: 64),
                _Tile(
                  icon: Icons.badge_rounded,
                  title: 'Registration & routes',
                  subtitle: 'Vehicle, documents and the routes you drive',
                  onTap: () => context.push(AppRoutes.driverOnboarding),
                ),
              ],
              const Divider(height: 1, indent: 64),
              _Tile(
                icon: Icons.translate_rounded,
                title: context.tr('profile.language'),
                subtitle: Localizations.localeOf(context).languageCode == 'ur' ? 'اردو' : 'English',
                onTap: () {
                  final n = ref.read(localeProvider.notifier);
                  n.set(Localizations.localeOf(context).languageCode == 'ur' ? 'en' : 'ur');
                },
              ),
              const Divider(height: 1, indent: 64),
              _Tile(
                icon: Icons.support_agent_rounded,
                title: context.tr('profile.help'),
                subtitle: 'FAQ, report a problem, contact KAM GO',
                onTap: () => context.push(AppRoutes.support),
              ),
              const Divider(height: 1, indent: 64),
              _Tile(
                icon: Icons.chat_rounded,
                title: 'Contact KAM GO',
                subtitle: 'Chat with us on WhatsApp',
                onTap: settings?.supportWhatsapp == null
                    ? null
                    : () => launchUrl(
                          Uri.parse('https://wa.me/${settings!.supportWhatsapp}'),
                          mode: LaunchMode.externalApplication,
                        ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SecondaryButton(
          label: 'Sign out',
          color: AppColors.danger,
          onPressed: () async {
            await ref.read(authServiceProvider).signOut();
            if (context.mounted) context.go(AppRoutes.login);
          },
        ),
      ],
    );
  }

  Future<void> _editEmergency(BuildContext context, WidgetRef ref, Profile p) async {
    final name = TextEditingController(text: p.emergencyContactName);
    final phone = TextEditingController(text: p.emergencyContactPhone);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Emergency contact', style: AppText.display(18)),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Mobile number'),
            ),
            const SizedBox(height: 20),
            PrimaryButton(label: 'Save', onPressed: () => Navigator.pop(context, true)),
          ],
        ),
      ),
    );
    if (saved == true) {
      final normalized = normalizePkPhone(phone.text);
      await ref.read(profileRepositoryProvider).updateEmergencyContact(
            name: name.text.trim().isEmpty ? null : name.text.trim(),
            phone: normalized ?? (phone.text.trim().isEmpty ? null : phone.text.trim()),
          );
      ref.invalidate(myProfileProvider);
    }
    name.dispose();
    phone.dispose();
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.navy, size: 21),
      ),
      title: Text(title, style: AppText.body(15, weight: FontWeight.w600)),
      subtitle: Text(subtitle, style: AppText.body(13, color: AppColors.mutedDark)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
    );
  }
}

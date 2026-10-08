import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/buttons.dart';
import '../../auth/presentation/auth_layout.dart';
import '../../rides/presentation/ride_providers.dart';
import '../domain/profile.dart';
import '../../../core/services/supabase_providers.dart';
import 'app_mode.dart';
import 'profile_providers.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  UserRole _role = UserRole.passenger;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Please enter your name.');
      return;
    }
    // There are no addas any more: drivers get requests of their ride type from everywhere.
    // The server still wants a home town for the record, so use the first one.
    final cityId = _role == UserRole.driver ? ref.read(catalogProvider).valueOrNull?.cities.firstOrNull?.id : null;
    if (_role == UserRole.driver && cityId == null) {
      setState(() => _error = 'Could not load the service area. Check your internet and try again.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .completeProfile(fullName: name, role: _role, cityId: cityId);
      ref.invalidate(myProfileProvider);
      ref.invalidate(myDriverInfoProvider);
      final profile = await ref.read(myProfileProvider.future);
      if (mounted) {
        context.go(homeRouteFor(profile, passengerMode: isPassengerMode(ref.read(sharedPrefsProvider))));
      }
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Set up your profile',
      subtitle: 'Just a few details and you are ready to go.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Your name'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            style: AppText.body(16, weight: FontWeight.w600),
            decoration: const InputDecoration(hintText: 'e.g. Ali Raza'),
          ),
          const SizedBox(height: 24),
          const FieldLabel('How will you use KAM GO?'),
          _RoleOption(
            icon: Icons.person_pin_circle_rounded,
            title: 'I need rides',
            subtitle: 'Offer your fare and pick your driver',
            selected: _role == UserRole.passenger,
            onTap: () => setState(() => _role = UserRole.passenger),
          ),
          const SizedBox(height: 10),
          _RoleOption(
            icon: Icons.directions_car_rounded,
            title: 'I drive',
            subtitle: 'Get ride requests and earn',
            selected: _role == UserRole.driver,
            onTap: () => setState(() => _role = UserRole.driver),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _role != UserRole.driver
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Your driver account will be reviewed by KAM GO before you can go online.',
                          style: AppText.body(13, color: AppColors.mutedDark, height: 1.4),
                        ),
                      ],
                    ),
                  ),
          ),
          ErrorText(_error),
          const SizedBox(height: 28),
          PrimaryButton(label: 'Continue', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.border,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: selected ? AppColors.green : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: selected ? AppColors.white : AppColors.navy),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.display(16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppText.body(13, color: AppColors.mutedDark)),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? AppColors.green : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

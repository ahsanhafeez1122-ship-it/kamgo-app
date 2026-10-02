import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/buttons.dart';
import '../domain/auth_service.dart';
import 'auth_layout.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = normalizePkPhone(_controller.text);
    if (phone == null) {
      setState(() => _error = 'Please enter a valid mobile number, like 0300 1234567.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendOtp(phone);
      if (mounted) context.push(AppRoutes.otp, extra: phone);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Welcome',
      subtitle: 'Enter your mobile number to book a ride or start driving.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Mobile number'),
          Row(
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text('🇵🇰 +92', style: AppText.body(16, weight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                    LengthLimitingTextInputFormatter(13),
                  ],
                  style: AppText.body(17, weight: FontWeight.w600),
                  decoration: const InputDecoration(hintText: '300 1234567'),
                  onSubmitted: (_) => _send(),
                ),
              ),
            ],
          ),
          ErrorText(_error),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Send code', loading: _sending, onPressed: _send),
          const SizedBox(height: 16),
          Text(
            'We will send a 6-digit code by SMS.',
            textAlign: TextAlign.center,
            style: AppText.body(13, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

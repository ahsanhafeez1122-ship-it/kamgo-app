import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/phone.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/services/supabase_providers.dart';
import '../../profile/presentation/app_mode.dart';
import '../../profile/presentation/profile_providers.dart';
import '../domain/auth_service.dart';
import 'auth_layout.dart';
import 'auth_providers.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _resendSeconds = 30;

  final _controller = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).verifyOtp(phoneE164: widget.phone, code: code);
      // Read the profile straight from the signed-in session. Going through
      // myProfileProvider here can race the auth stream and return the
      // pre-login (empty) answer, which sends existing users to profile setup.
      final profile = await ref.read(profileRepositoryProvider).fetchMine();
      ref.invalidate(myProfileProvider);
      if (mounted) {
        context.go(homeRouteFor(profile, passengerMode: isPassengerMode(ref.read(sharedPrefsProvider))));
      }
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authServiceProvider).sendOtp(widget.phone);
      _startTimer();
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'No connection. Check your internet and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Enter the code',
      subtitle: 'We sent a 6-digit code to ${formatPkPhone(widget.phone)}.',
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FieldLabel('Verification code'),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: AppText.display(26, height: 1).copyWith(letterSpacing: 10),
            decoration: const InputDecoration(hintText: '------'),
            onChanged: (v) {
              if (v.length == 6 && !_verifying) _verify();
            },
          ),
          ErrorText(_error),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Verify', loading: _verifying, onPressed: _verify),
          const SizedBox(height: 12),
          Center(
            child: _secondsLeft > 0
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Resend code in ${_secondsLeft}s',
                      style: AppText.body(14, color: AppColors.muted),
                    ),
                  )
                : TextButton(
                    onPressed: _resend,
                    child: Text('Resend code',
                        style: AppText.body(14, weight: FontWeight.w600, color: AppColors.green)),
                  ),
          ),
        ],
      ),
    );
  }
}

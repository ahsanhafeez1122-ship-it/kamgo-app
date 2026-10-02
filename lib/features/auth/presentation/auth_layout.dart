import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/kamgo_logo.dart';

/// Shared frame for login / OTP / profile setup: navy header with the logo,
/// white rounded sheet with the form.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: Stack(
          children: [
            Positioned(
              top: -90,
              right: -100,
              child: SoftCircle(size: 260, color: AppColors.green.withValues(alpha: 0.16)),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: onBack == null
                              ? null
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    onPressed: onBack,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.white.withValues(alpha: 0.1),
                                    ),
                                    icon: const Icon(Icons.arrow_back_rounded,
                                        color: AppColors.white),
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        const Row(
                          children: [
                            LogoBadge(size: 48, radius: 14),
                            SizedBox(width: 12),
                            Wordmark(size: 24),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(title, style: AppText.display(26, color: AppColors.white)),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: AppText.body(15,
                              color: AppColors.white.withValues(alpha: 0.7), height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          24,
                          28,
                          24,
                          24 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: AppText.body(14, weight: FontWeight.w600, color: AppColors.mutedDark)),
      );
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});
  final String? message;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: message == null
            ? const SizedBox(height: 0)
            : Padding(
                key: ValueKey(message),
                padding: const EdgeInsets.only(top: 10),
                child: Text(message!, style: AppText.body(13.5, color: AppColors.danger)),
              ),
      );
}

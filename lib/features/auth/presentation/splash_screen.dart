import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/kamgo_logo.dart';
import '../../../core/services/supabase_providers.dart';
import '../../profile/presentation/app_mode.dart';
import '../../profile/presentation/profile_providers.dart';
import 'auth_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _continue());
  }

  Future<void> _continue() async {
    final minShow = Future<void>.delayed(
      reduceMotion(context)
          ? const Duration(milliseconds: 500)
          : const Duration(milliseconds: 2200),
    );
    String target;
    try {
      if (ref.read(authServiceProvider).currentUserId == null) {
        target = AppRoutes.login;
      } else {
        target = homeRouteFor(
          await ref.read(myProfileProvider.future),
          passengerMode: isPassengerMode(ref.read(sharedPrefsProvider)),
        );
      }
    } catch (_) {
      // Offline or backend unreachable: a signed-in user still gets in and
      // sees cached data; screens show their own retry states.
      target = ref.read(authServiceProvider).currentUserId == null
          ? AppRoutes.login
          : AppRoutes.home;
    }
    await minShow;
    if (mounted) context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.navy, AppColors.navyDeep],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -110,
                right: -120,
                child: SoftCircle(
                  size: 320,
                  color: AppColors.green.withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                bottom: -150,
                left: -130,
                child: SoftCircle(
                  size: 360,
                  color: AppColors.white.withValues(alpha: 0.05),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedLogo(),
                    const SizedBox(height: 28),
                    const Wordmark(size: 34)
                        .motion(context, delay: 450.ms)
                        .fadeIn(duration: 450.ms)
                        .moveY(begin: 14, end: 0, curve: Curves.easeOutCubic),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: const _ProgressDots()
                    .motion(context, delay: 1000.ms)
                    .fadeIn(duration: 400.ms),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: AppColors.green.withValues(alpha: 0.35),
              ),
            )
                .animate(delay: 700.ms, onPlay: (c) => c.repeat())
                .scaleXY(begin: 1, end: 1.4, duration: 1600.ms, curve: Curves.easeOut)
                .fadeOut(duration: 1600.ms, curve: Curves.easeOut),
          const LogoBadge(size: 112, radius: 28)
              .motion(context)
              .fadeIn(duration: 250.ms)
              .scaleXY(begin: 0.55, end: 1, duration: 800.ms, curve: Curves.elasticOut),
        ],
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c) => Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(AppColors.green),
        dot(AppColors.white.withValues(alpha: 0.3)),
        dot(AppColors.white.withValues(alpha: 0.3)),
      ],
    );
  }
}

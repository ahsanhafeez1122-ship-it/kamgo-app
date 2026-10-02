import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/states.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../driver/presentation/driver_providers.dart';
import '../domain/ride_models.dart';
import 'ride_flow_providers.dart';
import 'ride_screen.dart';

final _rideOnceProvider = FutureProvider.autoDispose.family<RideDetails, String>(
  (ref, id) => ref.watch(rideRepositoryProvider).ride(id),
);

class RideCompletedScreen extends ConsumerStatefulWidget {
  const RideCompletedScreen({super.key, required this.rideId});
  final String rideId;

  @override
  ConsumerState<RideCompletedScreen> createState() => _RideCompletedScreenState();
}

class _RideCompletedScreenState extends ConsumerState<RideCompletedScreen> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit(String home) async {
    if (_stars == 0) {
      context.go(home);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rideRepositoryProvider).rate(widget.rideId, _stars,
          comment: _comment.text.trim().isEmpty ? null : _comment.text.trim());
      ref.invalidate(activeStateProvider);
      ref.invalidate(rideHistoryProvider);
      ref.invalidate(driverDashboardProvider);
      if (mounted) context.go(home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(_rideOnceProvider(widget.rideId));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: switch (ride) {
            AsyncData(:final value) => _body(value),
            AsyncError(:final error) => InfoState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load this ride',
                message: friendlyError(error),
                actionLabel: context.tr('common.retry'),
                onAction: () => ref.invalidate(_rideOnceProvider(widget.rideId)),
              ),
            _ => const Center(child: CircularProgressIndicator(color: AppColors.green)),
          },
        ),
      ),
    );
  }

  Widget _body(RideDetails r) {
    final isDriver = ref.read(authUserIdProvider).valueOrNull == r.driver.id;
    final home = isDriver ? AppRoutes.driver : AppRoutes.home;
    final other = isDriver ? r.passenger : r.driver;
    if (_stars == 0 && r.myRating != null) _stars = r.myRating!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        const Center(child: SuccessCheck(size: 96)),
        const SizedBox(height: 18),
        Text(context.tr('ride.completed'), textAlign: TextAlign.center, style: AppText.display(24)),
        const SizedBox(height: 4),
        Text(r.routeName, textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.mutedDark)),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            children: [
              Text(isDriver ? 'Collect in cash' : 'Pay in cash', style: AppText.body(13, color: AppColors.muted)),
              const SizedBox(height: 4),
              Text(formatFare(r.finalFare), style: AppText.display(34, weight: FontWeight.w800, color: AppColors.green)),
              const SizedBox(height: 4),
              Text(isDriver ? 'from ${r.passenger.name}' : 'to ${r.driver.name}',
                  style: AppText.body(14, color: AppColors.mutedDark)),
              if (isDriver && r.commission != null) ...[
                const SizedBox(height: 16),
                CommissionBreakdownCard(
                  fare: r.finalFare,
                  commission: r.commission!,
                  earning: r.driverEarning!,
                  note: 'Commission is added to your KAM GO balance (Earnings tab).',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(isDriver ? context.tr('ride.rate_passenger') : context.tr('ride.rate'),
            textAlign: TextAlign.center, style: AppText.display(17)),
        const SizedBox(height: 4),
        Text(other.name, textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.mutedDark)),
        const SizedBox(height: 12),
        StarRatingInput(value: _stars, onChanged: (v) => setState(() => _stars = v)),
        const SizedBox(height: 16),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(hintText: 'Anything to add? (optional)'),
        ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: _stars == 0 ? context.tr('ride.done') : context.tr('ride.submit'),
          loading: _saving,
          onPressed: () => _submit(home),
        ),
        TextButton(
          onPressed: () => context.push(AppRoutes.support, extra: r.id),
          child: Text('Report a problem with this ride', style: AppText.body(13.5, color: AppColors.mutedDark)),
        ),
      ],
    );
  }
}

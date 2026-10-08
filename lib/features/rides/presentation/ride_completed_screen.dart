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
import '../domain/fare_service.dart';
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

    return Column(
      children: [
        Expanded(
          child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
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
              if (r.bookingType != BookingType.oneWay || r.waitingCharge > 0) ...[
                const SizedBox(height: 14),
                _FareBreakdown(ride: r),
              ],
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
        TextButton(
          onPressed: () => context.push(AppRoutes.support, extra: r.id),
          child: Text('Report a problem with this ride', style: AppText.body(13.5, color: AppColors.mutedDark)),
        ),
      ],
          ),
        ),
        // Always visible, so the screen can be left without scrolling.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: PrimaryButton(
            label: _stars == 0 ? context.tr('ride.done') : context.tr('ride.submit'),
            loading: _saving,
            onPressed: () => _submit(home),
          ),
        ),
      ],
    );
  }
}


/// The fare line by line: agreed price, extra km / hours, waiting. Same lines for both people.
class _FareBreakdown extends StatelessWidget {
  const _FareBreakdown({required this.ride});

  final RideDetails ride;

  @override
  Widget build(BuildContext context) {
    final r = ride;
    Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.body(13.5, color: AppColors.mutedDark))),
            Text(value, style: AppText.body(14, weight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? AppColors.navy)),
          ]),
        );
    String hm(int minutes) => minutes >= 60 ? '${minutes ~/ 60} h ${minutes % 60} min' : '$minutes min';
    final agreed = r.acceptedFare ?? r.finalFare - r.waitingCharge;
    final badge = switch (r.bookingType) {
      BookingType.hourly => 'Hourly ${r.packageHours}h · ${r.packageKm?.round()} km',
      BookingType.roundTrip => 'Round trip',
      BookingType.oneWay => null,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) Text(badge, style: AppText.display(14)),
          row(r.bookingType == BookingType.hourly ? 'Package price' : 'Agreed fare', formatFare(agreed)),
          if (r.bookingType == BookingType.hourly) ...[
            row('Distance ${r.actualKm.toStringAsFixed(1)} km${r.extraKm > 0 ? ' · ${r.extraKm.toStringAsFixed(1)} km extra' : ''}',
                r.extraKmCharge > 0 ? '+ ${formatFare(r.extraKmCharge)}' : 'included'),
            row('Time ${hm(r.actualMinutes ?? 0)}${r.extraHours > 0 ? ' · ${r.extraHours} extra h' : ''}',
                r.extraHourCharge > 0 ? '+ ${formatFare(r.extraHourCharge)}' : 'included'),
          ],
          if (r.bookingType == BookingType.roundTrip) ...[
            row('Waited at destination ${hm(r.destWaitingMinutes)}', '+ ${formatFare(r.destWaitingCharge)}'),
            if (r.expectedWaitCharge > 0)
              row('Expected waiting already in the agreed fare', '− ${formatFare(r.expectedWaitCharge)}'),
          ],
          if (r.waitingCharge > 0) row('Waiting at pickup ${r.waitingMinutes} min', '+ ${formatFare(r.waitingCharge)}'),
          const Divider(height: 14),
          row('Total', formatFare(r.finalFare), bold: true, color: AppColors.green),
        ],
      ),
    );
  }
}
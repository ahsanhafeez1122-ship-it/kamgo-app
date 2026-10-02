import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../domain/commission.dart';
import '../domain/ride_models.dart';
import '../domain/ride_repository.dart';
import '../domain/ride_status.dart';
import 'live_ride_map.dart';
import 'live_state.dart';
import 'ride_flow_providers.dart';
import 'ride_providers.dart';

/// The ride screen for both sides: confirmation, live map, and the actions
/// each party may take at each status.
class RideScreen extends ConsumerStatefulWidget {
  const RideScreen({super.key, required this.rideId});
  final String rideId;

  @override
  ConsumerState<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends ConsumerState<RideScreen> {
  bool _busy = false;

  @override
  void dispose() {
    // Stop GPS when leaving the screen; it restarts if the driver returns.
    ref.read(rideLocationTrackerProvider).stop();
    super.dispose();
  }

  bool _isDriver(RideDetails r) => ref.read(authUserIdProvider).valueOrNull == r.driver.id;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(liveRideProvider(widget.rideId).notifier).refresh();
      ref.invalidate(activeStateProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(RideDetails r) async {
    final pct = ref.read(catalogProvider).valueOrNull?.settings.commissionPercent ?? 10;
    final preview = CommissionBreakdown.compute(r.finalFare, pct);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Complete this ride?', style: AppText.display(18)),
              const SizedBox(height: 6),
              Text('Collect ${formatFare(r.finalFare)} in cash from the passenger.',
                  style: AppText.body(14, color: AppColors.mutedDark)),
              const SizedBox(height: 16),
              CommissionBreakdownCard(
                fare: r.finalFare,
                commission: preview.commission,
                earning: preview.driverEarning,
                note: 'Final amounts are calculated by KAM GO when you complete.',
              ),
              const SizedBox(height: 18),
              PrimaryButton(label: context.tr('ride.complete'), onPressed: () => Navigator.pop(context, true)),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(rideRepositoryProvider).completeRide(r.id));
    if (mounted) context.go(AppRoutes.rideComplete(r.id));
  }

  Future<void> _cancel(RideDetails r, bool isDriver) async {
    final choice = await showModalBottomSheet<CancelReason>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cancel ride?', style: AppText.display(18)),
              const SizedBox(height: 14),
              _ReasonTile(
                label: isDriver ? 'I cannot make this trip' : 'I changed my plans',
                onTap: () => Navigator.pop(
                    context, isDriver ? CancelReason.driverCancelled : CancelReason.passengerCancelled),
              ),
              _ReasonTile(
                label: isDriver ? 'Passenger did not show up' : 'Driver did not show up',
                onTap: () => Navigator.pop(
                    context, isDriver ? CancelReason.passengerNoShow : CancelReason.driverNoShow),
              ),
              const SizedBox(height: 8),
              SecondaryButton(label: 'Keep ride', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    await _run(() => ref.read(rideRepositoryProvider).cancelRide(r.id, choice));
  }

  void _share(RideDetails r) {
    final status = switch (r.status) {
      RideStatus.rideStarted => 'is on the way',
      RideStatus.completed => 'has arrived',
      _ => 'is booked',
    };
    SharePlus.instance.share(ShareParams(
      text: 'My KAM GO ride ${r.routeName} $status.\n'
          'Driver: ${r.driver.name}${r.vehicle.plate == null ? '' : ' · ${r.vehicle.title} ${r.vehicle.plate}'}\n'
          'Fare: ${formatFare(r.finalFare)}\n'
          'Apni Ride, Apna Fare — KAM GO',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveRideProvider(widget.rideId));

    ref.listen(liveRideProvider(widget.rideId), (prev, next) {
      final r = next.valueOrNull;
      if (r == null) return;
      final driver = _isDriver(r);
      if (driver && r.isActive) {
        ref.read(rideLocationTrackerProvider).start(r.id);
      } else if (driver) {
        ref.read(rideLocationTrackerProvider).stop();
      }
      if (r.status == RideStatus.completed && prev?.valueOrNull?.status != RideStatus.completed && !driver) {
        context.go(AppRoutes.rideComplete(r.id));
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: switch (live) {
          AsyncData(:final value) => _body(value),
          AsyncError(:final error) => SafeArea(
              child: InfoState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load this ride',
                message: friendlyError(error),
                actionLabel: context.tr('common.retry'),
                onAction: () => ref.invalidate(liveRideProvider(widget.rideId)),
              ),
            ),
          _ => const Center(child: CircularProgressIndicator(color: AppColors.green)),
        },
      ),
    );
  }

  Widget _body(RideDetails r) {
    final isDriver = _isDriver(r);
    final other = isDriver ? r.passenger : r.driver;
    final home = isDriver ? AppRoutes.driver : AppRoutes.home;

    final (title, subtitle) = switch (r.status) {
      RideStatus.confirmed => (context.tr('ride.confirmed'),
          isDriver ? 'Head to the pickup point' : '${r.driver.name} is your driver'),
      RideStatus.driverArriving => (context.tr('ride.arriving'),
          isDriver ? 'Passenger has been told you are coming' : 'Be ready at the pickup point'),
      RideStatus.rideStarted => (context.tr('ride.started'), 'About ${etaMinutes(r)} min to ${r.destination.name}'),
      RideStatus.completed => (context.tr('ride.completed'), r.routeName),
      RideStatus.noShow => ('Marked as no-show', r.routeName),
      _ => ('Ride cancelled', r.routeName),
    };

    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            children: [
              Positioned.fill(child: LiveRideMap(ride: r)),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                left: 12,
                child: Material(
                  color: AppColors.white,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navy),
                    onPressed: () => context.go(home),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.paddingOf(context).bottom),
              children: [
                Row(
                  children: [
                    if (r.status == RideStatus.confirmed) ...[
                      const SuccessCheck(size: 44),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: AppText.display(19)),
                          Text(subtitle, style: AppText.body(13.5, color: AppColors.mutedDark)),
                        ],
                      ),
                    ),
                    Text(formatFare(r.finalFare), style: AppText.display(20, weight: FontWeight.w800, color: AppColors.green)),
                  ],
                ),
                const SizedBox(height: 14),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  child: Row(
                    children: [
                      InitialsAvatar(name: other.name, size: 50),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(other.name, style: AppText.body(16, weight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            if (!isDriver)
                              Text(
                                [r.vehicle.title, r.vehicle.color, r.vehicle.plate]
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                style: AppText.body(13, color: AppColors.mutedDark),
                              )
                            else
                              Text('${r.passengerCount} passenger${r.passengerCount == 1 ? '' : 's'}',
                                  style: AppText.body(13, color: AppColors.mutedDark)),
                            const SizedBox(height: 3),
                            RatingText(other.rating),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  radius: 18,
                  child: Column(
                    children: [
                      _PlaceRow(color: AppColors.green, round: true, label: 'Pickup', value: r.origin.display),
                      const Divider(height: 18, color: AppColors.borderSoft),
                      _PlaceRow(color: AppColors.navy, round: false, label: 'Destination', value: r.destination.display),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (r.isActive)
                  Row(
                    children: [
                      _Action(
                        icon: Icons.call_rounded,
                        label: context.tr('ride.call'),
                        onTap: other.phone == null ? null : () => launchUrl(Uri.parse('tel:${other.phone}')),
                      ),
                      _Action(
                        icon: Icons.sms_rounded,
                        label: 'Message',
                        onTap: other.phone == null ? null : () => launchUrl(Uri.parse('sms:${other.phone}')),
                      ),
                      _Action(icon: Icons.ios_share_rounded, label: context.tr('ride.share'), onTap: () => _share(r)),
                      _Action(
                        icon: Icons.close_rounded,
                        label: context.tr('ride.cancel'),
                        color: AppColors.danger,
                        onTap: _busy ||
                                !(r.status == RideStatus.confirmed || r.status == RideStatus.driverArriving)
                            ? null
                            : () => _cancel(r, isDriver),
                      ),
                    ],
                  ),
                if (isDriver && r.isActive) ...[
                  const SizedBox(height: 16),
                  if (r.status == RideStatus.confirmed) ...[
                    SecondaryButton(
                      label: context.tr('ride.on_way'),
                      onPressed: _busy
                          ? null
                          : () => _run(() =>
                              ref.read(rideRepositoryProvider).updateStatus(r.id, RideStatus.driverArriving)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (r.status != RideStatus.rideStarted)
                    PrimaryButton(
                      label: context.tr('ride.start'),
                      loading: _busy,
                      onPressed: () =>
                          _run(() => ref.read(rideRepositoryProvider).updateStatus(r.id, RideStatus.rideStarted)),
                    )
                  else
                    PrimaryButton(label: context.tr('ride.complete'), loading: _busy, onPressed: () => _complete(r)),
                ],
                if (!r.isActive) ...[
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: r.status == RideStatus.completed ? 'View summary' : 'Back to Home',
                    onPressed: () => r.status == RideStatus.completed
                        ? context.go(AppRoutes.rideComplete(r.id))
                        : context.go(home),
                  ),
                ],
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () => context.push(AppRoutes.support, extra: r.id),
                  icon: const Icon(Icons.support_agent_rounded, size: 18, color: AppColors.mutedDark),
                  label: Text('${context.tr('ride.help')} / Report a problem',
                      style: AppText.body(13.5, color: AppColors.mutedDark)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.color, required this.round, required this.label, required this.value});
  final Color color;
  final bool round;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              shape: round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: round ? null : BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.body(12, color: AppColors.muted)),
                Text(value, style: AppText.body(15, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color = AppColors.navy});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? AppColors.border : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: Icon(icon, color: c),
              ),
              const SizedBox(height: 6),
              Text(label, style: AppText.body(12, weight: FontWeight.w500, color: AppColors.mutedDark)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(label, style: AppText.body(15, weight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: onTap,
          ),
        ),
      );
}

/// Final Fare / KAM GO / Driver split.
class CommissionBreakdownCard extends StatelessWidget {
  const CommissionBreakdownCard({
    super.key,
    required this.fare,
    required this.commission,
    required this.earning,
    this.note,
  });

  final double fare;
  final double commission;
  final double earning;
  final String? note;

  @override
  Widget build(BuildContext context) {
    Widget row(String l, String v, {Color color = AppColors.navy, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(l, style: AppText.body(14.5, color: AppColors.mutedDark))),
              Text(v, style: bold ? AppText.display(17, color: color) : AppText.body(15, weight: FontWeight.w600, color: color)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        children: [
          row('Final fare', formatFare(fare)),
          row('KAM GO commission', '− ${formatFare(commission)}', color: AppColors.amber),
          const Divider(color: AppColors.border),
          row('Driver earning', formatFare(earning), color: AppColors.green, bold: true),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: AppText.body(12, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

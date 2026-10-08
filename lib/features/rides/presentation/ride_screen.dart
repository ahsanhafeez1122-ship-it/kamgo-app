import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/routing_service.dart';
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
import '../domain/fare_service.dart';
import '../domain/ride_models.dart';
import '../domain/ride_repository.dart';
import '../domain/ride_status.dart';
import 'live_ride_map.dart';
import 'location_tracker.dart';
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
  Timer? _clock;
  Timer? _progress;
  late final RideLocationTracker _tracker;

  @override
  void initState() {
    super.initState();
    // Fetched here because ref cannot be used inside dispose().
    _tracker = ref.read(rideLocationTrackerProvider);
    // Re-render every 30 s so the arrival countdown keeps moving.
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // Hourly trips: the driver app reports the km driven every 20 s (the server only keeps the highest).
    _progress = Timer.periodic(const Duration(seconds: 20), (_) {
      final r = ref.read(liveRideProvider(widget.rideId)).valueOrNull;
      if (r == null || r.status != RideStatus.rideStarted || r.bookingType != BookingType.hourly || !_isDriver(r)) return;
      if (_tracker.km > r.actualKm) {
        ref.read(rideRepositoryProvider).updateProgress(r.id, _tracker.km).catchError((_) {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _progress?.cancel();
    // Stop GPS when leaving the screen; it restarts if the driver returns.
    _tracker.stop();
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
    ref.invalidate(driverDashboardProvider);
    ref.invalidate(rideHistoryProvider);
    ref.invalidate(driverFeedProvider);
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

  Future<void> _sos(RideDetails r) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Emergency help', style: AppText.display(18, color: AppColors.danger)),
              const SizedBox(height: 6),
              Text(
                'Send an SOS alert to the KAM GO team with your location, or call the police (15) right now.',
                style: AppText.body(14, color: AppColors.mutedDark),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Send SOS alert', onPressed: () => Navigator.pop(context, 'sos')),
              const SizedBox(height: 10),
              SecondaryButton(label: 'Call police (15)', onPressed: () => Navigator.pop(context, 'call')),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('I am safe')),
            ],
          ),
        ),
      ),
    );
    if (choice == 'call') {
      await launchUrl(Uri.parse('tel:15'));
    } else if (choice == 'sos') {
      try {
        await ref.read(sosServiceProvider).trigger(rideId: r.id);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('SOS sent. The KAM GO team has been alerted.')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
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
      if (prev?.valueOrNull != null && prev!.valueOrNull!.status != r.status && !r.isActive) {
        // Finished or cancelled (by either side): refresh what the dashboards show.
        ref.invalidate(driverDashboardProvider);
        ref.invalidate(rideHistoryProvider);
        ref.invalidate(driverFeedProvider);
        ref.invalidate(activeStateProvider);
      }
      if (driver && r.isActive) {
        final tracker = ref.read(rideLocationTrackerProvider);
        tracker.start(r.id).then((_) {
          tracker.syncKm(r.actualKm);
          tracker.setCounting(r.status == RideStatus.rideStarted);
        });
        tracker.syncKm(r.actualKm);
        tracker.setCounting(r.status == RideStatus.rideStarted);
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

    final arrival = _arrivalText(r, isDriver);

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
            child: Column(
              children: [
                Expanded(
                  child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
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
                if (r.scheduledAt != null && (r.status == RideStatus.confirmed || r.status == RideStatus.driverArriving)) ...[
                  const SizedBox(height: 12),
                  _InfoBanner(icon: Icons.event_rounded, text: 'Scheduled pickup ${_whenText(r.scheduledAt!)}'),
                ],
                if (r.bookingType != BookingType.oneWay && r.status == RideStatus.rideStarted) ...[
                  const SizedBox(height: 12),
                  _TripPanel(
                    ride: r,
                    isDriver: isDriver,
                    freeWaitMinutes: ref.read(catalogProvider).valueOrNull?.settings.fare.roundTripFreeWaitMinutes ?? 30,
                    driverKm: isDriver ? _tracker.km : null,
                  ),
                ],
                if (_waitingText(r, isDriver) case final w?) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.hourglass_bottom_rounded, color: AppColors.green),
                      const SizedBox(width: 10),
                      Expanded(child: Text(w, style: AppText.body(14, weight: FontWeight.w600))),
                    ]),
                  ),
                ],
                if (arrival != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded, color: AppColors.green),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(arrival, style: AppText.body(15, weight: FontWeight.w700, color: AppColors.green)),
                        ),
                      ],
                    ),
                  ),
                ],
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
                        icon: Icons.sos_rounded,
                        label: 'SOS',
                        color: AppColors.danger,
                        onTap: () => _sos(r),
                      ),
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
                // The driver's main buttons stay on screen: no scrolling to find Start Ride.
                if (isDriver && r.isActive) _driverBar(r),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _driverBar(RideDetails r) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.status == RideStatus.confirmed) ...[
            SecondaryButton(
              label: context.tr('ride.on_way'),
              onPressed: _busy
                  ? null
                  : () => _run(() => ref.read(rideRepositoryProvider).updateStatus(r.id, RideStatus.driverArriving)),
            ),
            const SizedBox(height: 10),
          ],
          if (r.arrivedAt == null && (r.status == RideStatus.confirmed || r.status == RideStatus.driverArriving)) ...[
            SecondaryButton(
              label: 'I have arrived at the pickup',
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        // The driver's GPS here is the true spot of the pickup address (KAM GO learns it).
                        final here = await ref
                            .read(locationServiceProvider)
                            .current()
                            .timeout(const Duration(seconds: 6), onTimeout: () => null)
                            .catchError((_) => null);
                        await ref.read(rideRepositoryProvider).driverArrived(r.id, lat: here?.lat, lng: here?.lng);
                      }),
            ),
            const SizedBox(height: 10),
          ],
          if (r.status == RideStatus.rideStarted && r.bookingType == BookingType.roundTrip) ...[
            if (r.destArrivedAt == null)
              SecondaryButton(
                label: 'Arrived at destination',
                onPressed: _busy ? null : () => _run(() => ref.read(rideRepositoryProvider).reachedDestination(r.id)),
              )
            else if (r.returnStartedAt == null)
              SecondaryButton(
                label: 'Return started',
                onPressed: _busy ? null : () => _run(() => ref.read(rideRepositoryProvider).returnStarted(r.id)),
              ),
            if (r.destArrivedAt == null || r.returnStartedAt == null) const SizedBox(height: 10),
          ],
          if (r.status != RideStatus.rideStarted)
            PrimaryButton(
              label: context.tr('ride.start'),
              loading: _busy,
              onPressed: () => _run(() => ref.read(rideRepositoryProvider).updateStatus(r.id, RideStatus.rideStarted)),
            )
          else
            PrimaryButton(label: context.tr('ride.complete'), loading: _busy, onPressed: () => _complete(r)),
        ],
      ),
    );
  }

  /// Waiting at the pickup once the driver has tapped arrived: free minutes, then a per-minute charge.
  String? _waitingText(RideDetails r, bool isDriver) {
    final at = r.arrivedAt;
    if (at == null || r.status == RideStatus.rideStarted || !r.isActive) return null;
    final free = ref.read(catalogProvider).valueOrNull?.settings.fare.waitingFreeMinutes ?? 5;
    final waited = DateTime.now().difference(at).inMinutes;
    final left = free - waited;
    final who = isDriver ? 'Passenger' : 'Driver';
    return left > 0
        ? '$who waiting: free for $left more min'
        : '$who waiting: charge is running (${waited - free} min over the free time)';
  }

  /// How long until the driver is at the pickup. The driver's live position wins;
  /// without it, the ETA the driver promised when they made the offer counts down.
  String? _arrivalText(RideDetails r, bool isDriver) {
    if (r.status != RideStatus.confirmed && r.status != RideStatus.driverArriving) return null;
    int? mins;
    final pickup = r.origin.point;
    // The time the driver chose (3, 5, 10... min), counting down. A live GPS position only replaces it
    // when it is believable (a phone/PC can report a position hundreds of km away).
    if (r.etaMin != null && r.confirmedAt != null) {
      mins = r.etaMin! - DateTime.now().difference(r.confirmedAt!).inMinutes;
    }
    if (r.lastLocation != null && pickup != null) {
      final km = haversineKm(LatLng(r.lastLocation!.lat, r.lastLocation!.lng), LatLng(pickup.lat, pickup.lng)) * roadFactor;
      if (km < 40) mins = math.max(1, (km / 30 * 60).ceil());
    }
    if (mins == null) return null;
    if (mins <= 0) return isDriver ? 'You should be at the pickup now' : 'Your driver should be arriving now';
    return isDriver ? 'Reach the pickup in about $mins min' : 'Driver arrives in about $mins min';
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


String _whenText(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final now = DateTime.now();
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return '${today ? 'today' : '${t.day}/${t.month}'} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _hms(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${s ~/ 3600}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.body(14, weight: FontWeight.w600))),
        ]),
      );
}

/// Live panel for hourly rentals (timer and km counter) and round trips (destination waiting).
/// Both people see the same numbers; the driver app supplies the km.
class _TripPanel extends StatefulWidget {
  const _TripPanel({required this.ride, required this.isDriver, required this.freeWaitMinutes, this.driverKm});

  final RideDetails ride;
  final bool isDriver;
  final int freeWaitMinutes;
  final double? driverKm;

  @override
  State<_TripPanel> createState() => _TripPanelState();
}

class _TripPanelState extends State<_TripPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final now = DateTime.now();
    Widget line(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.body(13.5, color: AppColors.mutedDark))),
            Text(value, style: AppText.body(15, weight: FontWeight.w700, color: color ?? AppColors.navy)),
          ]),
        );
    final children = <Widget>[];
    if (r.bookingType == BookingType.hourly) {
      final started = r.startedAt ?? now;
      final elapsed = now.difference(started);
      final included = Duration(hours: r.packageHours ?? 0);
      final km = math.max(r.actualKm, widget.driverKm ?? 0);
      final over = elapsed > included;
      children.addAll([
        Text('Hourly rental · ${r.packageHours}h / ${r.packageKm?.round()} km', style: AppText.display(15)),
        const SizedBox(height: 6),
        line('Time', '${_hms(elapsed)} of ${_hms(included)}', color: over ? AppColors.danger : null),
        line('Distance', '${km.toStringAsFixed(1)} of ${r.packageKm?.round()} km',
            color: km > (r.packageKm ?? double.infinity) ? AppColors.danger : null),
        if (over || km > (r.packageKm ?? double.infinity))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Over the package: extra km ${formatFare(r.extraKmRate)} each, extra hour ${formatFare(r.extraHourRate)} (a started hour counts).',
              style: AppText.body(12.5, color: AppColors.mutedDark),
            ),
          ),
      ]);
    } else if (r.bookingType == BookingType.roundTrip) {
      final free = 30;
      children.add(Text('Round trip', style: AppText.display(15)));
      children.add(const SizedBox(height: 6));
      if (r.destArrivedAt == null) {
        children.add(line('Status', 'On the way to the destination'));
      } else if (r.returnStartedAt == null) {
        final waited = now.difference(r.destArrivedAt!);
        children.add(line('Waiting at destination', _hms(waited)));
        children.add(Text(
          waited.inMinutes < free
              ? 'The first $free minutes are free.'
              : 'Charge is running: ${formatFare(r.roundTripWaitPerHour)} per started hour after $free minutes.',
          style: AppText.body(12.5, color: AppColors.mutedDark),
        ));
      } else {
        children.add(line('Status', 'Returning'));
        children.add(line('Waited at destination', '${r.returnStartedAt!.difference(r.destArrivedAt!).inMinutes} min'));
      }
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

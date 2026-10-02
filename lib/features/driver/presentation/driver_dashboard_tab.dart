import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/errors.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/kamgo_logo.dart';
import '../../../core/widgets/states.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../passenger/presentation/booking_sheets.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';
import '../domain/driver_models.dart';
import 'counter_offer_sheet.dart';
import 'driver_providers.dart';
import 'request_card.dart';

class DriverDashboardTab extends ConsumerStatefulWidget {
  const DriverDashboardTab({super.key});

  @override
  ConsumerState<DriverDashboardTab> createState() => _DriverDashboardTabState();
}

class _DriverDashboardTabState extends ConsumerState<DriverDashboardTab> {
  bool _toggling = false;
  String? _busyRequest;

  Future<void> _setOnline(bool online, {String? cityId}) async {
    setState(() => _toggling = true);
    try {
      await ref.read(driverRepositoryProvider).setOnline(online, cityId: cityId);
      ref.invalidate(driverDashboardProvider);
      ref.invalidate(addaSummaryProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _offer(FeedRequest r, {required bool accept}) async {
    int? fare;
    if (!accept) {
      final policy = ref.read(catalogProvider).valueOrNull?.settings.farePolicy;
      if (policy == null) return;
      fare = await showCounterOfferSheet(context, r, policy);
      if (fare == null) return;
    }
    setState(() => _busyRequest = r.requestId);
    try {
      final here = await ref.read(locationServiceProvider).current(timeout: const Duration(seconds: 4));
      await ref.read(driverRepositoryProvider)
          .submitOffer(r.requestId, accept: accept, fare: fare, lat: here?.lat, lng: here?.lng);
      await ref.read(driverFeedProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Offer of ${formatFare(fare ?? r.offeredFare)} sent to ${r.passengerName}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      ref.read(driverFeedProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _busyRequest = null);
    }
  }

  Future<void> _dismiss(FeedRequest r) async {
    try {
      await ref.read(driverRepositoryProvider).dismiss(r.requestId);
      await ref.read(driverFeedProvider.notifier).refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _changeCity(DriverDashboard d) async {
    final cities = ref.read(catalogProvider).valueOrNull?.cities ?? const [];
    final id = await showCityPicker(context, title: 'Which adda are you at?', cities: cities, selectedId: d.cityId);
    if (id != null && id != d.cityId) await _setOnline(d.isOnline, cityId: id);
  }

  @override
  Widget build(BuildContext context) {
    final dash = ref.watch(driverDashboardProvider);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final active = ref.watch(activeStateProvider).valueOrNull;

    // Selected by a passenger → open the ride.
    ref.listen(activeStateProvider, (prev, next) {
      final id = next.valueOrNull?.rideId;
      if (id != null && id != prev?.valueOrNull?.rideId && mounted) context.push(AppRoutes.ride(id));
    });

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () async {
        ref.invalidate(driverDashboardProvider);
        ref.invalidate(activeStateProvider);
        await ref.read(driverDashboardProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Row(
            children: [
              const LogoBadge(size: 38, radius: 11),
              const SizedBox(width: 10),
              const Wordmark(size: 21, kamColor: AppColors.navy, goColor: AppColors.green),
              const Spacer(),
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.navy,
                child: Text(initialsOf(profile?.fullName), style: AppText.display(14, color: AppColors.white)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('${greetingFor(DateTime.now())}, ${profile?.firstName ?? ''}', style: AppText.display(22)),
          const SizedBox(height: 16),
          if (active?.rideId != null) ...[
            _ActiveRideBanner(onOpen: () => context.push(AppRoutes.ride(active!.rideId!))),
            const SizedBox(height: 14),
          ],
          switch (dash) {
            AsyncData(:final value) when value != null => _content(value),
            AsyncError(:final error) => AppCard(
                child: InfoState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not load your dashboard',
                  message: friendlyError(error),
                  actionLabel: context.tr('common.retry'),
                  onAction: () => ref.invalidate(driverDashboardProvider),
                ),
              ),
            AsyncData() => const SizedBox.shrink(),
            _ => const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator(color: AppColors.green)),
              ),
          },
        ],
      ),
    );
  }

  Widget _content(DriverDashboard d) {
    if (d.status != DriverStatus.approved) return _StatusCard(dash: d);

    final feed = ref.watch(driverFeedProvider);
    final items = feed.valueOrNull ?? const <FeedRequest>[];
    final returns = items.where((r) => r.isReturn).toList();
    final regular = items.where((r) => !r.isReturn).toList();

    Widget list(List<FeedRequest> rs) => Column(
          children: [
            for (var i = 0; i < rs.length; i++)
              Padding(
                key: ValueKey(rs[i].requestId),
                padding: const EdgeInsets.only(bottom: 12),
                child: RequestCard(
                  request: rs[i],
                  busy: _busyRequest != null,
                  onAccept: () => _offer(rs[i], accept: true),
                  onCounter: () => _offer(rs[i], accept: false),
                  onReject: () => _dismiss(rs[i]),
                )
                    .motion(context, delay: (60 * i).ms)
                    .fadeIn(duration: 280.ms)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OnlineToggle(online: d.isOnline, busy: _toggling, onChanged: (v) => _setOnline(v)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  onTap: () => _changeCity(d),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(context.tr('driver.adda', {'city': d.cityName ?? '—'}),
                              style: AppText.body(13, weight: FontWeight.w600, color: AppColors.mutedDark)),
                        ),
                        const Icon(Icons.edit_location_alt_rounded, size: 17, color: AppColors.muted),
                      ]),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _Count(value: d.addaOnline, label: 'online'),
                          const SizedBox(width: 18),
                          _Count(value: d.addaOpenRequests, label: 'requests'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(16),
                  radius: 18,
                  color: AppColors.navy,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Today', style: AppText.body(13, color: AppColors.white.withValues(alpha: 0.65))),
                      const SizedBox(height: 8),
                      Text(formatFare(d.earnings.today), style: AppText.display(20, color: AppColors.white)),
                      const SizedBox(height: 2),
                      Text('${d.earnings.ridesToday} ride${d.earnings.ridesToday == 1 ? '' : 's'} · due ${formatFare(d.earnings.commissionDue)}',
                          style: AppText.body(12, color: AppColors.greenLight)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (!d.isOnline)
          AppCard(
            child: InfoState(
              icon: Icons.power_settings_new_rounded,
              title: context.tr('driver.offline'),
              message: context.tr('driver.go_online'),
            ),
          )
        else ...[
          if (returns.isNotEmpty) ...[
            Row(children: [
              const Icon(Icons.u_turn_left_rounded, color: AppColors.green, size: 20),
              const SizedBox(width: 6),
              Text(context.tr('driver.return'), style: AppText.display(16)),
            ]),
            const SizedBox(height: 4),
            Text('Passengers going your way from ${d.cityName} — no empty trip back.',
                style: AppText.body(13, color: AppColors.mutedDark)),
            const SizedBox(height: 10),
            list(returns),
            const SizedBox(height: 10),
          ],
          Text(context.tr('driver.requests'), style: AppText.display(16)),
          const SizedBox(height: 10),
          if (feed.isLoading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.green)),
            )
          else if (regular.isEmpty && returns.isEmpty)
            AppCard(
              child: InfoState(
                icon: Icons.hourglass_empty_rounded,
                title: context.tr('driver.no_requests'),
                message: 'New requests from the ${d.cityName ?? ''} adda appear here instantly.',
              ),
            )
          else
            list(regular),
        ],
      ],
    );
  }
}

class _OnlineToggle extends StatelessWidget {
  const _OnlineToggle({required this.online, required this.busy, required this.onChanged});
  final bool online;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: online ? AppColors.green : AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: online ? AppColors.green : AppColors.border),
        boxShadow: online
            ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))]
            : const [],
      ),
      child: Row(
        children: [
          Icon(Icons.power_settings_new_rounded, size: 30, color: online ? AppColors.white : AppColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(online ? context.tr('driver.online') : context.tr('driver.offline'),
                    style: AppText.display(18, color: online ? AppColors.white : AppColors.navy)),
                Text(online ? 'Receiving requests from your adda' : context.tr('driver.go_online'),
                    style: AppText.body(13, color: online ? AppColors.white.withValues(alpha: 0.85) : AppColors.mutedDark)),
              ],
            ),
          ),
          busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : Transform.scale(
                  scale: 1.2,
                  child: Switch(
                    value: online,
                    onChanged: onChanged,
                    activeThumbColor: AppColors.white,
                    activeTrackColor: AppColors.navy,
                  ),
                ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: AppText.display(22, weight: FontWeight.w800)),
          Text(label, style: AppText.body(12, color: AppColors.muted)),
        ],
      );
}

class _ActiveRideBanner extends StatelessWidget {
  const _ActiveRideBanner({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        color: AppColors.navy,
        onTap: onOpen,
        child: Row(
          children: [
            const Icon(Icons.directions_car_rounded, color: AppColors.greenLight),
            const SizedBox(width: 12),
            Expanded(
              child: Text(context.tr('home.active_ride'), style: AppText.display(15, color: AppColors.white)),
            ),
            Text(context.tr('home.open'), style: AppText.body(14, weight: FontWeight.w600, color: AppColors.greenLight)),
          ],
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.dash});
  final DriverDashboard dash;

  @override
  Widget build(BuildContext context) {
    final needsApplication = !dash.hasApplication || dash.documentTypes.length < DriverDocType.values.length;
    final (icon, color, title, message) = switch (dash.status) {
      DriverStatus.rejected => (Icons.cancel_rounded, AppColors.danger, 'Application not approved',
          dash.rejectionReason ?? 'Please update your details and submit again.'),
      DriverStatus.suspended => (Icons.block_rounded, AppColors.danger, 'Account suspended',
          dash.rejectionReason ?? 'Please contact KAM GO support.'),
      _ when needsApplication => (Icons.assignment_rounded, AppColors.amber, 'Finish your registration',
          'Add your CNIC, vehicle, routes and documents so KAM GO can approve you.'),
      _ => (Icons.hourglass_top_rounded, AppColors.amber, 'Under review',
          'KAM GO is checking your documents. You can go online once approved.'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          border: Border.all(color: color.withValues(alpha: 0.35)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.display(16)),
                    const SizedBox(height: 4),
                    Text(message, style: AppText.body(13.5, color: AppColors.mutedDark, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (dash.status != DriverStatus.suspended) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            label: needsApplication || dash.status == DriverStatus.rejected
                ? 'Complete registration'
                : 'View my application',
            onPressed: () => context.push(AppRoutes.driverOnboarding),
          ),
        ],
      ],
    );
  }
}

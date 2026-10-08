import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/states.dart';
import '../../rides/domain/ride_status.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import 'driver_providers.dart';

class EarningsTab extends ConsumerWidget {
  const EarningsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(driverDashboardProvider).valueOrNull;
    final history = ref.watch(rideHistoryProvider);
    final e = d?.earnings;

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () async {
        ref.invalidate(driverDashboardProvider);
        ref.invalidate(rideHistoryProvider);
        await ref.read(rideHistoryProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Text(context.tr('nav.earnings'), style: AppText.display(22)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Tile(label: 'Today', value: e?.today ?? 0, highlight: true)),
              const SizedBox(width: 10),
              Expanded(child: _Tile(label: 'This week', value: e?.week ?? 0)),
              const SizedBox(width: 10),
              Expanded(child: _Tile(label: '30 days', value: e?.month ?? 0)),
            ],
          ),
          const SizedBox(height: 12),
          AppCard(
            color: AppColors.amberSoft,
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_rounded, color: AppColors.amber),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('driver.commission_due'), style: AppText.body(13, color: AppColors.amber)),
                      Text(formatFare(e?.commissionDue ?? 0), style: AppText.display(20, color: AppColors.navy)),
                    ],
                  ),
                ),
                Flexible(
                  child: Text('Pay KAM GO in cash for now. Online payment comes later.',
                      textAlign: TextAlign.right, style: AppText.body(12, color: AppColors.mutedDark)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your rating', style: AppText.body(13, color: AppColors.muted)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Text((d?.rating ?? 5).toStringAsFixed(1), style: AppText.display(24, weight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                      ]),
                      Text('${d?.ratingCount ?? 0} ratings · ${d?.totalRides ?? 0} rides',
                          style: AppText.body(12.5, color: AppColors.mutedDark)),
                    ],
                  ),
                ),
                if (d != null && d.recentRatings.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final r in d.recentRatings.take(2))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('${'★' * r.stars} ${r.comment ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(12.5, color: AppColors.mutedDark)),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Ride history', style: AppText.display(16)),
          const SizedBox(height: 10),
          switch (history) {
            AsyncData(:final value) when value.isEmpty => const InfoState(
                icon: Icons.route_rounded, title: 'No rides yet', message: 'Completed rides will appear here.'),
            AsyncData(:final value) => Column(
                children: [
                  for (final h in value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                        radius: 16,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            InitialsAvatar(name: h.otherName, size: 42, radius: 13),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tripTitle(h.originName, h.destinationName),
                                      style: AppText.body(14.5, weight: FontWeight.w600)),
                                  Text('${DateFormat('d MMM, h:mm a').format(h.createdAt)} · ${h.otherName}',
                                      style: AppText.body(12, color: AppColors.muted)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  h.status == RideStatus.completed
                                      ? formatFare(h.driverEarning ?? h.fare)
                                      : h.status.code.replaceAll('_', ' ').toLowerCase(),
                                  style: AppText.display(14.5,
                                      color: h.status == RideStatus.completed ? AppColors.green : AppColors.muted),
                                ),
                                if (h.commission != null)
                                  Text('fee ${formatFare(h.commission!)}',
                                      style: AppText.body(11.5, color: AppColors.muted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            AsyncError() => InfoState(
                icon: Icons.wifi_off_rounded,
                title: 'Could not load history',
                actionLabel: context.tr('common.retry'),
                onAction: () => ref.invalidate(rideHistoryProvider)),
            _ => const Center(child: CircularProgressIndicator(color: AppColors.green)),
          },
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.highlight = false});
  final String label;
  final double value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        radius: 16,
        color: highlight ? AppColors.navy : AppColors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.body(12, color: highlight ? AppColors.white.withValues(alpha: 0.7) : AppColors.muted)),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(formatFare(value),
                  style: AppText.display(17, color: highlight ? AppColors.greenLight : AppColors.navy)),
            ),
          ],
        ),
      );
}

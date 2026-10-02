import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/states.dart';
import '../../rides/domain/ride_status.dart';
import '../../rides/presentation/ride_flow_providers.dart';

class MyRidesTab extends ConsumerWidget {
  const MyRidesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rides = ref.watch(rideHistoryProvider);
    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () => ref.refresh(rideHistoryProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            sliver: SliverToBoxAdapter(child: Text(context.tr('nav.rides'), style: AppText.display(22))),
          ),
          switch (rides) {
            AsyncData(:final value) when value.isEmpty => const SliverFillRemaining(
                hasScrollBody: false,
                child: InfoState(
                  icon: Icons.route_rounded,
                  title: 'No rides yet',
                  message: 'Your rides will show up here once you travel with KAM GO.',
                ),
              ),
            AsyncData(:final value) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final r = value[i];
                    final done = r.status == RideStatus.completed;
                    final active = !r.status.isTerminal;
                    return AppCard(
                      radius: 18,
                      padding: const EdgeInsets.all(16),
                      onTap: () => context.push(done ? AppRoutes.rideComplete(r.rideId) : AppRoutes.ride(r.rideId)),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: done || active ? AppColors.greenSoft : AppColors.background,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              done ? Icons.check_rounded : active ? Icons.directions_car_rounded : Icons.close_rounded,
                              color: done || active ? AppColors.green : AppColors.muted,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r.originName} → ${r.destinationName}',
                                    style: AppText.body(15, weight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(
                                  '${DateFormat('d MMM, h:mm a').format(r.createdAt)} · ${r.otherName}',
                                  style: AppText.body(12.5, color: AppColors.muted),
                                ),
                                if (done && r.myRating == null)
                                  Text('Tap to rate', style: AppText.body(12.5, weight: FontWeight.w600, color: AppColors.green)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatFare(r.fare), style: AppText.display(15)),
                              if (!done)
                                Text(r.status.code.replaceAll('_', ' ').toLowerCase(),
                                    style: AppText.body(12, color: active ? AppColors.green : AppColors.muted)),
                              if (r.myRating != null)
                                Text('★' * r.myRating!, style: AppText.body(12, color: const Color(0xFFF59E0B))),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            AsyncError() => SliverFillRemaining(
                hasScrollBody: false,
                child: InfoState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not load your rides',
                  actionLabel: context.tr('common.retry'),
                  onAction: () => ref.invalidate(rideHistoryProvider),
                ),
              ),
            _ => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: AppColors.green)),
              ),
          },
        ],
      ),
    );
  }
}

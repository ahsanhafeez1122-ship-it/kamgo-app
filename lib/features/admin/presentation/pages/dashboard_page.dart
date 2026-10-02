import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/widgets/app_card.dart';
import '../admin_widgets.dart';

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(adminRepositoryProvider);
    return AdminPage(
      title: 'Dashboard',
      child: AdminLoader<Map<String, dynamic>>(
        load: repo.stats,
        builder: (context, s, reload) {
          num n(String k) => (s[k] as num?) ?? 0;
          final tiles = [
            ('Passengers', '${n('passengers')}', Icons.people_alt_rounded, false),
            ('Drivers', '${n('drivers')}', Icons.directions_car_rounded, false),
            ('Online drivers', '${n('online_drivers')}', Icons.wifi_tethering_rounded, false),
            ('Pending drivers', '${n('pending_drivers')}', Icons.hourglass_top_rounded, n('pending_drivers') > 0),
            ('Rides today', '${n('rides_today')}', Icons.today_rounded, false),
            ('Completed rides', '${n('completed_rides')}', Icons.check_circle_rounded, false),
            ('Cancelled rides', '${n('cancelled_rides')}', Icons.cancel_rounded, false),
            ('Open requests', '${n('open_requests')}', Icons.campaign_rounded, false),
            ('Total ride value', formatFare(n('total_ride_value')), Icons.payments_rounded, false),
            ('KAM GO commission', formatFare(n('total_commission')), Icons.account_balance_rounded, false),
            ('Commission outstanding', formatFare(n('commission_outstanding')), Icons.pending_actions_rounded,
                n('commission_outstanding') > 0),
            ('Active cities', '${n('active_cities')}', Icons.location_city_rounded, false),
            ('Open complaints', '${n('open_complaints')}', Icons.report_rounded, n('open_complaints') > 0),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TextButton.icon(onPressed: reload, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final (label, value, icon, warn) in tiles)
                    SizedBox(
                      width: 230,
                      child: AppCard(
                        border: warn ? Border.all(color: AppColors.amber.withValues(alpha: 0.5)) : null,
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: warn ? AppColors.amberSoft : AppColors.greenSoft,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(icon, color: warn ? AppColors.amber : AppColors.green),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: AppText.body(12.5, color: AppColors.muted)),
                                  FittedBox(child: Text(value, style: AppText.display(20, weight: FontWeight.w800))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/states.dart';
import 'notification_providers.dart';

class AlertsTab extends ConsumerWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final hasUnread = ref.watch(hasUnreadProvider);
    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () => ref.refresh(notificationsProvider.future),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(child: Text('Alerts', style: AppText.display(22))),
                  if (hasUnread)
                    TextButton(
                      onPressed: () async {
                        await ref.read(notificationsRepositoryProvider).markAllRead();
                        ref.invalidate(notificationsProvider);
                      },
                      child: Text('Mark all read',
                          style: AppText.body(14, weight: FontWeight.w600, color: AppColors.green)),
                    ),
                ],
              ),
            ),
          ),
          switch (list) {
            AsyncData(:final value) when value.isEmpty => const SliverFillRemaining(
                hasScrollBody: false,
                child: InfoState(
                  icon: Icons.notifications_none_rounded,
                  title: 'All caught up',
                  message: 'Driver offers and ride updates will appear here.',
                ),
              ),
            AsyncData(:final value) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: SliverList.separated(
                  itemCount: value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final n = value[i];
                    return AppCard(
                      radius: 18,
                      padding: const EdgeInsets.all(16),
                      border: n.isUnread
                          ? Border.all(color: AppColors.green.withValues(alpha: 0.4))
                          : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 6, right: 12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: n.isUnread ? AppColors.green : AppColors.border,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: AppText.body(15, weight: FontWeight.w600)),
                                if (n.body != null) ...[
                                  const SizedBox(height: 3),
                                  Text(n.body!,
                                      style: AppText.body(13.5,
                                          color: AppColors.mutedDark, height: 1.4)),
                                ],
                                const SizedBox(height: 6),
                                Text(DateFormat('d MMM, h:mm a').format(n.createdAt),
                                    style: AppText.body(12, color: AppColors.muted)),
                              ],
                            ),
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
                  title: 'Could not load alerts',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(notificationsProvider),
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

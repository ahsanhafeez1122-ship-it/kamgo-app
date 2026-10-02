import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/auth_providers.dart';
import '../../features/notifications/presentation/notification_providers.dart';
import '../l10n/strings.dart';
import '../services/connectivity_service.dart';
import '../services/supabase_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/motion.dart';

/// Wraps every screen: shows a "Connection lost" strip when offline and
/// slides in-app notifications down from the top as they arrive.
class AppOverlays extends ConsumerStatefulWidget {
  const AppOverlays({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppOverlays> createState() => _AppOverlaysState();
}

class _AppOverlaysState extends ConsumerState<AppOverlays> {
  RealtimeChannel? _channel;
  String? _uid;
  _Banner? _banner;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    final ch = _channel;
    if (ch != null) ref.read(supabaseClientProvider).removeChannel(ch);
    super.dispose();
  }

  void _listenFor(String? uid) {
    if (uid == _uid) return;
    final client = ref.read(supabaseClientProvider);
    if (_channel != null) client.removeChannel(_channel!);
    _channel = null;
    _uid = uid;
    if (uid == null) return;
    _channel = client
        .channel('my-notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) {
            final r = p.newRecord;
            ref.invalidate(notificationsProvider);
            _show(_Banner(r['title'] as String? ?? '', r['body'] as String?));
          },
        )
        .subscribe();
  }

  void _show(_Banner b) {
    if (!mounted) return;
    _hide?.cancel();
    setState(() => _banner = b);
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _banner = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    _listenFor(ref.watch(authUserIdProvider).valueOrNull);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final top = MediaQuery.paddingOf(context).top;
    final duration = reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 280);

    return Stack(
      children: [
        widget.child,
        // Connection lost strip
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: AnimatedSlide(
              duration: duration,
              offset: online ? const Offset(0, -1) : Offset.zero,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, top + 6, 16, 8),
                color: AppColors.amber,
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded, color: AppColors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tr('common.connection_lost'),
                          style: AppText.body(13, weight: FontWeight.w600, color: AppColors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // In-app notification
        Positioned(
          left: 12,
          right: 12,
          top: top + 8,
          child: AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, a) => SlideTransition(
              position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: a, child: child),
            ),
            child: _banner == null
                ? const SizedBox.shrink()
                : GestureDetector(
                    key: ValueKey(_banner),
                    onTap: () => setState(() => _banner = null),
                    onVerticalDragEnd: (_) => setState(() => _banner = null),
                    child: Material(
                      color: AppColors.navy,
                      elevation: 6,
                      shadowColor: AppColors.navy.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: AppColors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.notifications_active_rounded,
                                  color: AppColors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_banner!.title,
                                      style: AppText.body(14.5, weight: FontWeight.w600, color: AppColors.white)),
                                  if (_banner!.body != null)
                                    Text(_banner!.body!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.body(13,
                                            color: AppColors.white.withValues(alpha: 0.75))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _Banner {
  _Banner(this.title, this.body);
  final String title;
  final String? body;
}

/// Full-screen "No Internet Connection" state with Retry.
class NoInternetView extends StatelessWidget {
  const NoInternetView({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(30)),
              child: const Icon(Icons.wifi_off_rounded, size: 44, color: AppColors.amber),
            ),
            const SizedBox(height: 20),
            Text(context.tr('common.no_internet'), style: AppText.display(19), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Check mobile data or Wi-Fi and try again.',
                textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.mutedDark)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('common.retry')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                minimumSize: const Size(160, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

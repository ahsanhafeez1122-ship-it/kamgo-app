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
import '../../rides/domain/ride_status.dart';
import '../../rides/presentation/live_state.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';

class FindingDriversScreen extends ConsumerStatefulWidget {
  const FindingDriversScreen({super.key, required this.requestId, this.justSent = false});

  final String requestId;
  final bool justSent;

  @override
  ConsumerState<FindingDriversScreen> createState() => _FindingDriversScreenState();
}

class _FindingDriversScreenState extends ConsumerState<FindingDriversScreen> {
  late bool _showSent = widget.justSent;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    if (_showSent) {
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showSent = false);
      });
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await ref.read(rideRepositoryProvider).cancelRequest(widget.requestId);
      ref.invalidate(activeStateProvider);
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        setState(() => _cancelling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveRequestProvider(widget.requestId));
    final catalog = ref.watch(catalogProvider).valueOrNull;

    // First live offer → move to the offers screen.
    ref.listen(liveRequestProvider(widget.requestId), (_, next) {
      final v = next.valueOrNull;
      if (v != null && v.liveOffers.isNotEmpty && mounted) {
        context.pushReplacement(AppRoutes.offers(widget.requestId));
      }
    });

    final req = live.valueOrNull?.request;
    final origin = catalog?.city(req?.originCityId)?.name ?? '';
    final destination = catalog?.city(req?.destinationCityId)?.name ?? '';
    final closed = req != null && !req.status.isOpen;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(AppRoutes.home),
          ),
          title: Text(req == null ? '' : '$origin → $destination'),
        ),
        body: SafeArea(
          child: live.hasError && req == null
              ? InfoState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load your request',
                  message: friendlyError(live.error!),
                  actionLabel: context.tr('common.retry'),
                  onAction: () => ref.invalidate(liveRequestProvider(widget.requestId)),
                )
              : closed
                  ? _Closed(status: req.status)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 350),
                                child: _showSent
                                    ? Column(
                                        key: const ValueKey('sent'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const SuccessCheck(size: 104),
                                          const SizedBox(height: 22),
                                          Text(context.tr('finding.sent'), style: AppText.display(20)),
                                        ],
                                      )
                                    : Column(
                                        key: const ValueKey('search'),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const RadarSearch(size: 250),
                                          const SizedBox(height: 26),
                                          AnimatedEllipsisText(
                                            context.tr('finding.title'),
                                            style: AppText.display(19),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            context.tr('finding.subtitle', {'city': origin}),
                                            textAlign: TextAlign.center,
                                            style: AppText.body(14, color: AppColors.muted),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          if (req != null)
                            AppCard(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _Stat(label: 'Your Offer', value: formatFare(req.offeredFare), green: true),
                                    ),
                                    const VerticalDivider(width: 1, color: AppColors.borderSoft),
                                    Expanded(child: _Stat(label: 'Passengers', value: '${req.passengerCount}')),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          SecondaryButton(
                            label: _cancelling ? '…' : context.tr('finding.cancel'),
                            onPressed: _cancelling || req == null ? null : _cancel,
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.green = false});
  final String label;
  final String value;
  final bool green;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: AppText.body(13, color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(value, style: AppText.display(20, color: green ? AppColors.green : AppColors.navy)),
        ],
      );
}

class _Closed extends StatelessWidget {
  const _Closed({required this.status});
  final RideStatus status;

  @override
  Widget build(BuildContext context) {
    final expired = status == RideStatus.expired;
    return InfoState(
      icon: expired ? Icons.timer_off_rounded : Icons.cancel_rounded,
      title: expired ? 'No driver was selected in time' : 'Request closed',
      message: expired ? 'Try again — raising your offer a little often helps.' : null,
      actionLabel: 'Back to Home',
      onAction: () => context.go(AppRoutes.home),
    );
  }
}

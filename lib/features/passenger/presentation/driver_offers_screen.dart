import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../../core/widgets/states.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/domain/ride_status.dart';
import '../../rides/presentation/live_state.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';

class DriverOffersScreen extends ConsumerStatefulWidget {
  const DriverOffersScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends ConsumerState<DriverOffersScreen> {
  String? _selecting;

  Future<void> _select(DriverOffer o) async {
    setState(() => _selecting = o.id);
    try {
      final rideId = await ref.read(rideRepositoryProvider).selectOffer(o.id);
      ref.invalidate(activeStateProvider);
      if (mounted) context.go(AppRoutes.ride(rideId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() => _selecting = null);
      ref.read(liveRequestProvider(widget.requestId).notifier).refresh();
    }
  }

  Future<void> _reject(DriverOffer o) async {
    try {
      await ref.read(rideRepositoryProvider).rejectOffer(o.id);
      ref.read(liveRequestProvider(widget.requestId).notifier).refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  Future<void> _cancel() async {
    try {
      await ref.read(rideRepositoryProvider).cancelRequest(widget.requestId);
      ref.invalidate(activeStateProvider);
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveRequestProvider(widget.requestId));
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final data = live.valueOrNull;
    final req = data?.request;

    // A driver accepted the fare himself: the ride is on, open it.
    if (req != null && req.status == RideStatus.confirmed && _selecting == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_selecting != null || !mounted) return;
        _selecting = 'auto';
        ref.invalidate(activeStateProvider);
        final a = await ref.read(rideRepositoryProvider).myActive();
        if (context.mounted && a.rideId != null) context.go(AppRoutes.ride(a.rideId!));
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.green)));
    }
    if (req != null && !req.status.isOpen && _selecting == null) {
      return Scaffold(
        appBar: AppBar(),
        body: InfoState(
          icon: Icons.timer_off_rounded,
          title: 'This request is closed',
          message: 'It expired or was cancelled.',
          actionLabel: 'Back to Home',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    final offers = data?.liveOffers ?? const <DriverOffer>[];
    final n = offers.length;
    final route = req == null
        ? ''
        : tripTitle(
            placeName(req.pickupLabel, catalog?.city(req.originCityId)?.name ?? ''),
            placeName(req.dropoffLabel, catalog?.city(req.destinationCityId)?.name ?? ''),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(AppRoutes.home),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(n == 1 ? context.tr('offers.one_responded') : context.tr('offers.responded', {'n': n}),
                  style: AppText.display(17)),
              if (req != null)
                Text('$route · ${req.passengerCount} passenger${req.passengerCount == 1 ? '' : 's'} · '
                    'offer ${formatFare(req.offeredFare)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body(12.5, color: AppColors.muted)),
            ],
          ),
        ),
        body: live.isLoading && data == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.green))
            : RefreshIndicator(
                color: AppColors.green,
                onRefresh: () => ref.read(liveRequestProvider(widget.requestId).notifier).refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (var i = 0; i < offers.length; i++)
                      Padding(
                        key: ValueKey(offers[i].id),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _OfferCard(
                          offer: offers[i],
                          recommended: offers[i].type == OfferType.accept &&
                              offers.indexWhere((o) => o.type == OfferType.accept) == i,
                          busy: _selecting != null,
                          selecting: _selecting == offers[i].id,
                          onSelect: () => _select(offers[i]),
                          onReject: () => _reject(offers[i]),
                        )
                            .motion(context, delay: (90 * i).ms)
                            .fadeIn(duration: 300.ms)
                            .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
                      ),
                    if (n == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
                          children: [
                            const RadarSearch(size: 160),
                            const SizedBox(height: 16),
                            AnimatedEllipsisText(context.tr('offers.waiting'), style: AppText.display(16)),
                          ],
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: AnimatedEllipsisText(context.tr('offers.waiting'),
                              style: AppText.body(13.5, color: AppColors.muted)),
                        ),
                      ),
                    if (req != null) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Request open for ', style: AppText.body(13, color: AppColors.muted)),
                            CountdownText(
                              until: req.expiresAt,
                              style: AppText.body(13, weight: FontWeight.w600, color: AppColors.mutedDark),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _selecting == null ? _cancel : null,
                        child: Text(context.tr('finding.cancel'),
                            style: AppText.body(14, weight: FontWeight.w600, color: AppColors.danger)),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.recommended,
    required this.busy,
    required this.selecting,
    required this.onSelect,
    required this.onReject,
  });

  final DriverOffer offer;
  final bool recommended;
  final bool busy;
  final bool selecting;
  final VoidCallback onSelect;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final accepted = offer.type == OfferType.accept;
    final fareStyle = AppText.display(21, weight: FontWeight.w800, color: accepted ? AppColors.green : AppColors.navy);
    final details = [
      if (offer.etaMin != null) 'Arrives in ${offer.etaMin} min',
      if (offer.distanceKm != null) '${offer.distanceKm!.toStringAsFixed(1)} km away',
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: recommended ? AppColors.green : AppColors.borderSoft,
          width: recommended ? 1.8 : 1,
        ),
        boxShadow: const [BoxShadow(color: Color(0x0F0B2347), blurRadius: 18, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(name: offer.driverName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.driverName, style: AppText.body(16, weight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      [offer.vehicle, if (offer.plate != null) offer.plate].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13, color: AppColors.mutedDark),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        RatingText(offer.rating),
                        if (details.isNotEmpty)
                          Flexible(
                            child: Text(' · $details',
                                overflow: TextOverflow.ellipsis,
                                style: AppText.body(13, color: AppColors.mutedDark)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // A revised counter offer counts smoothly to its new value.
                  reduceMotion(context)
                      ? Text(formatFare(offer.fare), style: fareStyle)
                      : TweenAnimationBuilder<double>(
                          tween: Tween(end: offer.fare),
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => Text(formatFare(v.round()), style: fareStyle),
                        ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: accepted ? AppColors.greenSoft : AppColors.amberSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      accepted ? context.tr('offers.accepted') : context.tr('offers.counter'),
                      style: AppText.body(11.5, weight: FontWeight.w600,
                          color: accepted ? AppColors.green : AppColors.amber),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: recommended
                    ? PrimaryButton(
                        label: context.tr('offers.select'),
                        loading: selecting,
                        onPressed: busy ? null : onSelect,
                      )
                    : SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: busy ? null : onSelect,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.navy,
                            side: const BorderSide(color: AppColors.navy, width: 1.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            textStyle: AppText.display(15),
                          ),
                          child: selecting
                              ? const SizedBox.square(
                                  dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                              : Text(context.tr('offers.select')),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Not this one',
                onPressed: busy ? null : onReject,
                style: IconButton.styleFrom(
                  fixedSize: const Size.square(56),
                  backgroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.close_rounded, color: AppColors.mutedDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/errors.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/motion.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/buttons.dart';
import '../../../core/widgets/kamgo_logo.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/supabase_providers.dart';
import '../../notifications/presentation/notification_providers.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/fare_policy.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';
import 'booking_draft.dart';
import 'booking_sheets.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key, required this.onOpenAlerts, required this.onOpenProfile});

  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenProfile;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(catalogProvider);
    ref.invalidate(addaSummaryProvider);
    ref.invalidate(popularRouteProvider);
    ref.invalidate(recentDestinationsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(activeStateProvider);
    await ref.read(catalogProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);

    Widget section(Widget child, int i) => child
        .motion(context, delay: (60 * i).ms)
        .fadeIn(duration: 320.ms)
        .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic);

    return RefreshIndicator(
      color: AppColors.green,
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _TopBar(onOpenAlerts: onOpenAlerts, onOpenProfile: onOpenProfile),
          const SizedBox(height: 18),
          const _ActiveBanner(),
          section(const _HeroCard(), 0),
          const SizedBox(height: 16),
          switch (catalog) {
            AsyncData(:final value) => section(_BookingCard(catalog: value), 1),
            AsyncError() => AppCard(
                child: InfoState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Could not load cities',
                  message: 'Check your internet connection and try again.',
                  actionLabel: 'Retry',
                  onAction: () => ref.invalidate(catalogProvider),
                ),
              ),
            _ => const AppCard(
                child: SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator(color: AppColors.green)),
                ),
              ),
          },
          if (catalog.valueOrNull case final c?) ...[
            const SizedBox(height: 24),
            section(_RecentDestinations(catalog: c), 2),
            const SizedBox(height: 20),
            section(_AddaRow(catalog: c), 3),
          ],
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onOpenAlerts, required this.onOpenProfile});

  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(myProfileProvider).valueOrNull?.fullName;
    final unread = ref.watch(hasUnreadProvider);
    return Row(
      children: [
        const LogoBadge(size: 38, radius: 11),
        const SizedBox(width: 10),
        const Wordmark(size: 21, kamColor: AppColors.navy, goColor: AppColors.green),
        const Spacer(),
        Semantics(
          label: unread ? 'Alerts, unread' : 'Alerts',
          button: true,
          child: InkWell(
            onTap: onOpenAlerts,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderSoft),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.notifications_none_rounded, color: AppColors.navy),
                  if (unread)
                    Positioned(
                      top: 11,
                      right: 12,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onOpenProfile,
          child: CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.navy,
            child: Text(
              initialsOf(name),
              style: AppText.display(15, color: AppColors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.navy, AppColors.navyDeep],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -46,
              right: -36,
              child: SoftCircle(size: 150, color: AppColors.green.withValues(alpha: 0.3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.tagline,
                      style: AppText.display(22, weight: FontWeight.w800, color: AppColors.white)),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.heroSubtitle,
                    style: AppText.body(14, color: AppColors.white.withValues(alpha: 0.72)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final notifier = ref.read(bookingDraftProvider.notifier);
    final pickup = catalog.city(draft.pickupCityId);
    final destination = catalog.city(draft.destinationCityId);
    final route = catalog.routeBetween(draft.pickupCityId, draft.destinationCityId);
    final policy = catalog.settings.farePolicy;

    Future<void> choosePickup() async {
      final starts = {for (final r in catalog.routes) r.originCityId};
      final id = await showCityPicker(
        context,
        title: 'Pickup location',
        cities: catalog.cities.where((c) => starts.contains(c.id)).toList(),
        selectedId: draft.pickupCityId,
      );
      if (id != null) notifier.setPickup(id);
    }

    Future<void> chooseDestination() async {
      if (draft.pickupCityId == null) return;
      final reachable = catalog
          .routesFrom(draft.pickupCityId!)
          .map((r) => catalog.city(r.destinationCityId))
          .whereType<City>()
          .toList();
      final id = await showCityPicker(
        context,
        title: 'Destination',
        cities: reachable,
        selectedId: draft.destinationCityId,
      );
      if (id != null) notifier.setDestination(id);
    }

    Future<void> choosePassengers() async {
      final n = await showPassengersSheet(
        context,
        initial: draft.passengers,
        max: catalog.settings.maxPassengers,
      );
      if (n != null) notifier.setPassengers(n);
    }

    Future<void> chooseOffer() async {
      if (route == null) return;
      final fare = await showOfferSheet(
        context,
        initial: draft.offer ?? policy.suggestedFare(route.distanceKm),
        distanceKm: route.distanceKm,
        policy: policy,
      );
      if (fare != null) notifier.setOffer(fare);
    }

    Future<void> findRide() async {
      if (route == null || draft.offer == null) return;
      if (policy.check(draft.offer!, route.distanceKm) != FareCheck.ok) {
        chooseOffer();
        return;
      }
      ref.read(_requestingProvider.notifier).state = true;
      try {
        final req = await ref.read(rideRepositoryProvider).createRequest(
              routeId: route.id,
              passengers: draft.passengers,
              fare: draft.offer!,
            );
        ref.invalidate(activeStateProvider);
        if (context.mounted) context.push(AppRoutes.finding(req.id, justSent: true));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
        ref.invalidate(activeStateProvider);
      } finally {
        ref.read(_requestingProvider.notifier).state = false;
      }
    }

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('home.where'), style: AppText.display(17)),
          const SizedBox(height: 14),
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _LocationRow(
                      marker: const _Dot(color: AppColors.green, round: true),
                      label: context.tr('home.pickup'),
                      value: pickup?.name ?? 'Choose city',
                      onTap: choosePickup,
                    ),
                    const Divider(height: 1, indent: 44, endIndent: 56, color: AppColors.borderSoft),
                    _LocationRow(
                      marker: const _Dot(color: AppColors.navy, round: false),
                      label: context.tr('home.destination'),
                      value: destination?.name ?? 'Choose city',
                      onTap: chooseDestination,
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Material(
                    color: AppColors.white,
                    shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
                    child: IconButton(
                      tooltip: 'Swap pickup and destination',
                      onPressed: catalog.routeBetween(
                                draft.destinationCityId,
                                draft.pickupCityId,
                              ) ==
                              null
                          ? null
                          : notifier.swap,
                      icon: const Icon(Icons.swap_vert_rounded, color: AppColors.navy, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniField(
                  label: context.tr('home.passengers'),
                  icon: Icons.people_alt_rounded,
                  value: '${draft.passengers}',
                  onTap: choosePassengers,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniField(
                  label: context.tr('home.offer'),
                  icon: Icons.payments_rounded,
                  value: draft.offer == null ? '—' : formatFare(draft.offer!),
                  valueColor: AppColors.green,
                  onTap: chooseOffer,
                  animateNumber: draft.offer,
                ),
              ),
            ],
          ),
          if (route != null) ...[
            const SizedBox(height: 10),
            Text(
              '${route.distanceKm.toStringAsFixed(0)} km · fair range '
              '${formatFare(policy.minFare(route.distanceKm))} – '
              '${formatFare(policy.maxFare(route.distanceKm))}',
              style: AppText.body(12.5, color: AppColors.muted),
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: context.tr('home.find'),
            loading: ref.watch(_requestingProvider),
            onPressed: route == null ? null : findRide,
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.round});

  final Color color;
  final bool round;

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(3),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), spreadRadius: 3)],
        ),
      );
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.marker,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final Widget marker;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 64, 13),
        child: Row(
          children: [
            marker,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.body(12, color: AppColors.muted)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(15.5, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  const _MiniField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onTap,
    this.valueColor = AppColors.navy,
    this.animateNumber,
  });

  final String label;
  final IconData icon;
  final String value;
  final VoidCallback onTap;
  final Color valueColor;

  /// When set, the value counts smoothly to this number on change.
  final int? animateNumber;

  @override
  Widget build(BuildContext context) {
    final style = AppText.display(17, color: valueColor);
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: AppColors.muted),
                  const SizedBox(width: 5),
                  Text(label, style: AppText.body(12, color: AppColors.muted)),
                ],
              ),
              const SizedBox(height: 3),
              if (animateNumber == null || reduceMotion(context))
                Text(value, style: style)
              else
                TweenAnimationBuilder<double>(
                  tween: Tween(end: animateNumber!.toDouble()),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text(formatFare(v.round()), style: style),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentDestinations extends ConsumerWidget {
  const _RecentDestinations({required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final recentIds = ref.watch(recentDestinationsProvider).valueOrNull ?? const [];
    // No history yet: suggest the places reachable from the pickup city.
    final ids = recentIds.isNotEmpty
        ? recentIds
        : catalog
            .routesFrom(draft.pickupCityId ?? '')
            .map((r) => r.destinationCityId)
            .toList();
    final cities = ids
        .where((id) => id != draft.pickupCityId)
        .map(catalog.city)
        .whereType<City>()
        .toList();
    if (cities.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('home.recent'), style: AppText.display(15.5)),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: cities.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final city = cities[i];
              final selected = city.id == draft.destinationCityId;
              return Material(
                color: selected ? AppColors.greenSoft : AppColors.white,
                shape: StadiumBorder(
                  side: BorderSide(color: selected ? AppColors.green : AppColors.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () {
                    if (catalog.routeBetween(draft.pickupCityId, city.id) != null) {
                      ref.read(bookingDraftProvider.notifier).setDestination(city.id);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                          'No route to ${city.name} from '
                          '${catalog.city(draft.pickupCityId)?.name ?? 'here'} yet.',
                        ),
                      ));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 17, color: selected ? AppColors.green : AppColors.muted),
                        const SizedBox(width: 6),
                        Text(city.name,
                            style: AppText.body(14,
                                weight: FontWeight.w600,
                                color: selected ? AppColors.green : AppColors.navy)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddaRow extends ConsumerWidget {
  const _AddaRow({required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final pickup = catalog.city(draft.pickupCityId);
    final adda = ref.watch(addaSummaryProvider).valueOrNull;
    final online = adda?.where((a) => a.cityId == pickup?.id).firstOrNull?.onlineDrivers;
    final popular = ref.watch(popularRouteProvider(draft.pickupCityId)).valueOrNull;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(16),
              radius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(context.tr('home.online'),
                          style: AppText.body(12.5, color: AppColors.mutedDark)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      online == null ? '–' : '$online',
                      key: ValueKey(online),
                      style: AppText.display(28, weight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pickup == null ? 'near you' : context.tr('home.in_adda', {'city': pickup.name}),
                    style: AppText.body(12.5, color: AppColors.muted),
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
              onTap: popular == null
                  ? null
                  : () {
                      final route = catalog.routes.where((r) => r.id == popular.routeId).firstOrNull;
                      if (route == null) return;
                      final n = ref.read(bookingDraftProvider.notifier);
                      n.setPickup(route.originCityId);
                      n.setDestination(route.destinationCityId);
                    },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('home.popular'),
                      style: AppText.body(12.5, color: AppColors.white.withValues(alpha: 0.65))),
                  const SizedBox(height: 8),
                  Text(
                    popular == null
                        ? '–'
                        : '${popular.originName} → ${popular.destinationName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(14.5, color: AppColors.white, height: 1.3),
                  ),
                  const Spacer(),
                  const SizedBox(height: 6),
                  Text(
                    popular == null ? '' : '~ ${formatFare(popular.approxFare)}',
                    style: AppText.display(15, color: AppColors.greenLight),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _requestingProvider = StateProvider.autoDispose<bool>((_) => false);

/// Resume an in-progress request / ride, or rate the last one. Uses the
/// server's answer, and the last cached answer when offline.
class _ActiveBanner extends ConsumerWidget {
  const _ActiveBanner();

  static const _cacheKey = 'active_state_cache';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPrefsProvider);
    final live = ref.watch(activeStateProvider);
    String? rideId, requestId, unrated;
    if (live.valueOrNull case final a?) {
      rideId = a.rideId;
      requestId = a.requestId;
      unrated = a.unratedRideId;
      prefs.setString(_cacheKey, [rideId ?? '', requestId ?? ''].join('|'));
    } else if (live.hasError) {
      final cached = (prefs.getString(_cacheKey) ?? '|').split('|');
      rideId = cached[0].isEmpty ? null : cached[0];
      requestId = cached.length > 1 && cached[1].isNotEmpty ? cached[1] : null;
    }

    final (String? label, String? target) = rideId != null
        ? (context.tr('home.active_ride'), AppRoutes.ride(rideId))
        : requestId != null
            ? (context.tr('home.active_request'), AppRoutes.finding(requestId))
            : unrated != null
                ? (context.tr('home.rate_last'), AppRoutes.rideComplete(unrated))
                : (null, null);
    if (label == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        color: AppColors.green,
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onTap: () => context.push(target!),
        child: Row(
          children: [
            Icon(unrated != null && rideId == null && requestId == null
                    ? Icons.star_rounded
                    : Icons.directions_car_rounded,
                color: AppColors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppText.display(15, color: AppColors.white))),
            Text(context.tr('home.open'), style: AppText.body(14, weight: FontWeight.w600, color: AppColors.white)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}

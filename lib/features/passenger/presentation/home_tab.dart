import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/constants/app_strings.dart';
import '../../../core/services/map_provider.dart';
import '../../../core/services/routing_service.dart';
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
import '../../profile/presentation/kamgo_drawer.dart';
import '../../profile/presentation/profile_providers.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/fare_service.dart';
import '../../rides/domain/map_pick.dart';
import '../../rides/domain/ride_models.dart';
import '../../rides/presentation/ride_flow_providers.dart';
import '../../rides/presentation/ride_providers.dart';
import 'booking_draft.dart';
import 'booking_sheets.dart';
import 'map_pick_screen.dart';
import 'place_pick_screen.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({
    super.key,
    required this.onOpenAlerts,
    required this.onOpenProfile,
    required this.onOpenMenu,
  });

  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenMenu;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(catalogProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(activeStateProvider);
    await ref.read(catalogProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogProvider);
    ref.watch(scheduledReminderProvider);

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
          _TopBar(onOpenAlerts: onOpenAlerts, onOpenProfile: onOpenProfile, onOpenMenu: onOpenMenu),
          const SizedBox(height: 12),
          const ModeSwitch(driverMode: false),
          const SizedBox(height: 14),
          const _ActiveBanner(),
          section(
              switch (catalog) {
                AsyncData(:final value) => _PickupMapCard(catalog: value),
                _ => const _HeroCard(),
              },
              0),
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
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.onOpenAlerts, required this.onOpenProfile, required this.onOpenMenu});

  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(myProfileProvider).valueOrNull?.fullName;
    final unread = ref.watch(hasUnreadProvider);
    return Row(
      children: [
        IconButton(
          tooltip: 'Menu',
          onPressed: onOpenMenu,
          icon: const Icon(Icons.menu_rounded, color: AppColors.navy),
        ),
        const SizedBox(width: 4),
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
    final distanceKm = draft.distanceKm;
    final quote = draft.quote(catalog);
    final category = catalog.category(draft.category);
    // The ride city is the city nearest to the pickup; outside its service radius there is no service yet.
    final pickupCity =
        draft.pickup == null ? null : catalog.serviceCity(draft.pickup!.point.lat, draft.pickup!.point.lng);
    final outsideService = draft.pickup != null && pickupCity == null;
    final night = catalog.fareService.isNight(DateTime.now());

    Future<void> choosePickup() async {
      // inDrive style: the map opens on where you are; move it so the pin is on the pickup.
      final pick = await pickOnMap(context,
          title: 'Pickup location',
          catalog: catalog,
          initial: draft.pickup,
          other: draft.destination,
          requireService: true,
          startAtMyLocation: draft.pickup == null);
      if (pick == null) return;
      notifier.setPickup(pick);
      // A destination that no longer fits (other city / same city) is dropped.
      final d = ref.read(bookingDraftProvider).destination;
      final city = catalog.serviceCity(pick.point.lat, pick.point.lng);
      if (d != null && city != null) {
        final dc = catalog.nearestCity(d.point.lat, d.point.lng)?.city.id;
        final inter = ref.read(_intercityModeProvider);
        if (inter ? dc == city.id : dc != city.id) notifier.clearDestination();
      }
    }

    Future<void> chooseDestination() async {
      if (pickupCity == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose the pickup first.')));
        return;
      }
      final inter = ref.read(_intercityModeProvider);
      final allowed = {
        for (final c in catalog.cities)
          if (inter ? c.id != pickupCity.id : c.id == pickupCity.id) c.id,
      };
      final pick = await pickPlace(
        context,
        title: inter ? 'Destination city' : 'Destination in ${pickupCity.name}',
        catalog: catalog,
        allowedCityIds: allowed,
      );
      if (pick != null) notifier.setDestination(pick);
    }

    Future<void> choosePassengers() async {
      final n = await showPassengersSheet(
        context,
        initial: draft.passengers,
        max: catalog.maxPassengersFor(draft.category),
      );
      if (n != null) notifier.setPassengers(n);
    }

    Future<void> chooseOffer() async {
      if (quote == null) return;
      final fare = await showOfferSheet(
        context,
        initial: draft.offer ?? quote.recommended,
        distanceKm: distanceKm ?? catalog.package(draft.packageId)?.includedKm ?? 0,
        quote: quote,
      );
      if (fare != null) notifier.setOffer(fare);
    }

    Future<void> findRide() async {
      final from = draft.pickup;
      final to = draft.destination;
      final hourly = draft.type == BookingType.hourly;
      if (from == null || (!hourly && to == null) || draft.offer == null || quote == null || outsideService) return;
      if (quote.check(draft.offer!) != FareCheck.ok) {
        chooseOffer();
        return;
      }
      ref.read(_requestingProvider.notifier).state = true;
      try {
        final spot = ref.read(_pickupSpotProvider).trim();
        final req = await ref.read(rideRepositoryProvider).createRequest(
              pickup: from.point,
              dropoff: (hourly ? from : to!).point,
              passengers: draft.passengers,
              fare: draft.offer!,
              // The extra exact spot is added to the address, not a replacement for it.
              pickupLabel: spot.isEmpty ? from.serverLabel : '${from.serverLabel} — $spot',
              dropoffLabel: hourly ? null : to!.serverLabel,
              category: draft.category,
              loading: draft.loading,
              bookingType: draft.type,
              packageId: hourly ? draft.packageId : null,
              expectedWaitMin: draft.type == BookingType.roundTrip ? draft.expectedWaitMin : 0,
              scheduledAt: draft.scheduledAt,
              distanceKm: draft.manualKm ?? draft.routeKm ?? draft.estKm,
            );
        ref.read(_pickupSpotProvider.notifier).state = '';
        ref.invalidate(activeStateProvider);
        if (context.mounted) context.push(AppRoutes.finding(req.id, justSent: true));
      } catch (e) {
        ref.invalidate(activeStateProvider);
        // Stop the button spinner before any dialog opens (the dialog waits for a tap).
        ref.read(_requestingProvider.notifier).state = false;
        if (!context.mounted) return;
        if (e is PostgrestException && e.code == '23505') {
          // Already has a request or a ride: say so clearly and offer to open it
          // (a snackbar at the bottom is easy to miss).
          final a = await ref.read(rideRepositoryProvider).myActive().catchError((_) => const ActiveState());
          if (!context.mounted) return;
          final target = a.rideId != null
              ? AppRoutes.ride(a.rideId!)
              : a.requestId != null
                  ? AppRoutes.finding(a.requestId!)
                  : null;
          final open = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(a.rideId != null ? 'You have a ride in progress' : 'You already have a ride request'),
              content: Text(friendlyError(e)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
                if (target != null)
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(a.rideId != null ? 'Open my ride' : 'Open my request'),
                  ),
              ],
            ),
          );
          if (open == true && target != null && context.mounted) context.push(target);
        } else {
          // A dialog, not a snackbar: the bottom of the screen is easy to miss.
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Could not send your request'),
              content: Text(friendlyError(e)),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          );
        }
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
          const SizedBox(height: 12),
          const _ScopeTabs(),
          const SizedBox(height: 10),
          const _BookingTypeTabs(),
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
                      value: draft.pickup?.title ?? 'Set pickup on the map',
                      onTap: choosePickup,
                    ),
                    if (draft.type != BookingType.hourly) ...[
                      const Divider(height: 1, indent: 44, endIndent: 56, color: AppColors.borderSoft),
                      _LocationRow(
                        marker: const _Dot(color: AppColors.navy, round: false),
                        label: context.tr('home.destination'),
                        value: draft.destination?.title ?? 'Where to?',
                        onTap: chooseDestination,
                      ),
                    ],
                  ],
                ),
              ),
              if (draft.type != BookingType.hourly)
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
                      onPressed: draft.pickup == null || draft.destination == null ? null : notifier.swap,
                      icon: const Icon(Icons.swap_vert_rounded, color: AppColors.navy, size: 20),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (draft.pickup != null && draft.destination != null && !draft.samePlace) ...[
            const SizedBox(height: 12),
            _RoutePreview(from: draft.pickup!.point, to: draft.destination!.point),
          ],
          if (ref.watch(_intercityModeProvider) && pickupCity != null) ...[
            const SizedBox(height: 14),
            _CityCards(catalog: catalog, pickupCity: pickupCity),
          ],
          const SizedBox(height: 14),
          _CategoryBar(catalog: catalog),
          if (category?.hasLoading == true) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Loading help (+${formatFare(category!.fare.loadingCharge)})',
                  style: AppText.body(14, weight: FontWeight.w600)),
              subtitle: Text('The driver helps load and unload', style: AppText.body(12.5, color: AppColors.muted)),
              value: draft.loading,
              activeThumbColor: AppColors.green,
              onChanged: notifier.setLoading,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              // Bike and Courier carry one person or one load: no count to pick.
              if (category?.isSingle != true) ...[
                Expanded(
                  child: _MiniField(
                    label: context.tr('home.passengers'),
                    icon: Icons.people_alt_rounded,
                    value: '${draft.passengers}',
                    onTap: choosePassengers,
                  ),
                ),
                const SizedBox(width: 12),
              ],
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
          if (draft.pickup != null && draft.destination != null) ...[
            const SizedBox(height: 12),
            _MiniField(
              label: draft.manualKm != null
                  ? 'Distance (entered by you)'
                  : draft.isEstimate
                      ? 'Distance (estimate, tap to correct)'
                      : 'Distance (tap to change)',
              icon: Icons.straighten_rounded,
              value: '${draft.isEstimate ? '≈ ' : ''}${(distanceKm ?? 0).toStringAsFixed(1)} km',
              onTap: () async {
                final km = await _askKm(context, distanceKm, draft.manualKm != null);
                if (km != null) notifier.setManualKm(km <= 0 ? null : km);
              },
            ),
          ],
          if (draft.type == BookingType.roundTrip) ...[
            const SizedBox(height: 12),
            _MiniField(
              label: 'Waiting at destination (${catalog.settings.fare.roundTripFreeWaitMinutes} min free)',
              icon: Icons.hourglass_bottom_rounded,
              value: _waitText(draft.expectedWaitMin),
              onTap: () async {
                final m = await _pickWait(context, draft.expectedWaitMin, catalog.settings.fare.roundTripFreeWaitMinutes);
                if (m != null) notifier.setExpectedWait(m);
              },
            ),
          ],
          const SizedBox(height: 12),
          const _PickupSpotField(),
          const SizedBox(height: 10),
          Text(
            outsideService
                ? 'Service is not available here yet. Choose a pickup closer to one of our cities.'
                : quote == null
                    ? (draft.type == BookingType.hourly
                        ? 'Write the pickup to see the fare.'
                        : 'Write pickup and destination to see the distance and fare.')
                    : draft.isEstimate
                        ? 'Both places are in the same area, so we count about ${(distanceKm ?? 0).toStringAsFixed(0)} km. Tap Distance if it is different · recommended ${formatFare(quote.recommended)}'
                        : '${_tripText(draft, catalog, distanceKm)} · recommended ${formatFare(quote.recommended)}${night && draft.type == BookingType.oneWay ? ' (night fare)' : ''} · '
                            'you can offer ${formatFare(quote.minOffer)} – ${formatFare(quote.maxOffer)}',
            style: AppText.body(12.5,
                color: outsideService ? AppColors.danger : AppColors.muted),
          ),
          if (pickupCity != null && quote != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Drivers in ${pickupCity.name} will see your request.',
                  style: AppText.body(12, color: AppColors.muted)),
            ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: context.tr('home.find'),
            loading: ref.watch(_requestingProvider),
            onPressed: quote == null || !draft.complete || outsideService ? null : findRide,
          ),
        ],
      ),
    );
  }
}

IconData _categoryIcon(String code) => switch (code) {
      'bike' => Icons.two_wheeler_rounded,
      'rickshaw' => Icons.electric_rickshaw_rounded,
      'car_comfort' => Icons.directions_car_filled_rounded,
      'car_xl' => Icons.airport_shuttle_rounded,
      'loader' => Icons.local_shipping_rounded,
      _ => Icons.directions_car_rounded,
    };

/// Ride types in the order set in the admin panel, all in one row (no scrolling). A type is hidden when
/// the trip is longer than it takes. The recommended fare is shown on a card only if the admin turns that on.
class _CategoryBar extends ConsumerWidget {
  const _CategoryBar({required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final km = draft.distanceKm;
    final shown = [
      for (final c in catalog.categoriesFor(draft.type == BookingType.hourly ? null : km))
        if (draft.type == BookingType.oneWay || c.isCar) c,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final night = catalog.fareService.isNight(DateTime.now());
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(
            child: _categoryCard(
              ref,
              shown[i],
              shown[i].code == draft.category,
              price: catalog.settings.showCategoryPrices && km != null && draft.type == BookingType.oneWay
                  ? catalog.quoteFor(shown[i].code, km, night: night)?.recommended
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _categoryCard(WidgetRef ref, RideCategory c, bool selected, {int? price}) {
    return Material(
      color: selected ? AppColors.greenSoft : AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => ref.read(bookingDraftProvider.notifier).setCategory(c.code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.green : AppColors.border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_categoryIcon(c.code), size: 24, color: selected ? AppColors.green : AppColors.navy),
              const SizedBox(height: 5),
              // The name shrinks to fit (two words, e.g. "Car Comfort", on a narrow phone).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(c.name,
                    maxLines: 1,
                    style: AppText.body(11.5, weight: FontWeight.w700, color: selected ? AppColors.green : AppColors.navy)),
              ),
              if (price != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(formatFare(price), style: AppText.body(10.5, color: AppColors.muted)),
                ),
            ],
          ),
        ),
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

final _requestingProvider = StateProvider.autoDispose<bool>((_) => false);

/// Home screen mode: false = City Ride (inside the pickup city), true = City to City.
final _intercityModeProvider = StateProvider<bool>((_) => false);

/// Optional "exact pickup spot" the passenger types; sent as the pickup label.
final _pickupSpotProvider = StateProvider<String>((_) => '');

class _PickupSpotField extends ConsumerStatefulWidget {
  const _PickupSpotField();

  @override
  ConsumerState<_PickupSpotField> createState() => _PickupSpotFieldState();
}

class _PickupSpotFieldState extends ConsumerState<_PickupSpotField> {
  late final _controller = TextEditingController(text: ref.read(_pickupSpotProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cleared after a request is sent.
    ref.listen(_pickupSpotProvider, (_, next) {
      if (next.isEmpty && _controller.text.isNotEmpty) _controller.clear();
    });
    return TextField(
      controller: _controller,
      maxLength: 120,
      textInputAction: TextInputAction.done,
      onChanged: (v) => ref.read(_pickupSpotProvider.notifier).state = v,
      decoration: const InputDecoration(
        counterText: '',
        labelText: 'Exact pickup spot (optional)',
        hintText: 'e.g. near Bus Stand, House 12 Model Town',
        prefixIcon: Icon(Icons.edit_location_alt_rounded, size: 20),
      ),
    );
  }
}

/// Resume an in-progress request / ride, or rate the last one. Uses the
/// server's answer, and the last cached answer when offline.
class _ActiveBanner extends ConsumerStatefulWidget {
  const _ActiveBanner();

  @override
  ConsumerState<_ActiveBanner> createState() => _ActiveBannerState();
}

class _ActiveBannerState extends ConsumerState<_ActiveBanner> {
  static const _cacheKey = 'active_state_cache';

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // The state changes on the other side (driver completes the ride, request
    // expires), so re-ask the server while Home is showing.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) ref.invalidate(activeStateProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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


String _waitText(int minutes) {
  if (minutes <= 0) return 'None';
  final h = minutes ~/ 60, m = minutes % 60;
  return [if (h > 0) '$h h', if (m > 0) '$m min'].join(' ');
}

String _tripText(BookingDraft d, Catalog c, double? km) {
  switch (d.type) {
    case BookingType.hourly:
      final p = c.package(d.packageId);
      return p == null ? 'Hourly' : 'Hourly ${p.hours}h · ${p.includedKm.round()} km included';
    case BookingType.roundTrip:
      return 'Round trip ${km?.toStringAsFixed(1) ?? '—'} km each way';
    case BookingType.oneWay:
      return '${km?.toStringAsFixed(1) ?? '—'} km';
  }
}

Future<int?> _pickWait(BuildContext context, int initial, int freeMinutes) {
  var minutes = initial;
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('How long will you wait at the destination?', style: AppText.display(17)),
              const SizedBox(height: 6),
              Text('The first $freeMinutes minutes are free; after that you pay per started hour.',
                  textAlign: TextAlign.center, style: AppText.body(13, color: AppColors.muted)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: minutes <= 0 ? null : () => set(() => minutes = (minutes - 30).clamp(0, 1440)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(width: 130, child: Center(child: Text(_waitText(minutes), style: AppText.display(22)))),
                  IconButton.filledTonal(
                    onPressed: () => set(() => minutes = (minutes + 30).clamp(0, 1440)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context, minutes)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// City Ride (inside the pickup city) or City to City. The choice decides which places the
/// destination search accepts; the trip itself is told apart by the cities of its two ends.
class _ScopeTabs extends ConsumerWidget {
  const _ScopeTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inter = ref.watch(_intercityModeProvider);
    Widget tab(String label, IconData icon, bool selected, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: selected ? null : onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.navy : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 19, color: selected ? AppColors.white : AppColors.navy),
                const SizedBox(width: 7),
                Text(label, style: AppText.body(14, weight: FontWeight.w700, color: selected ? AppColors.white : AppColors.navy)),
              ]),
            ),
          ),
        );
    void set(bool v) {
      ref.read(_intercityModeProvider.notifier).state = v;
      // The old destination belongs to the other mode.
      ref.read(bookingDraftProvider.notifier).clearDestination();
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(children: [
        tab('City Ride', Icons.location_city_rounded, !inter, () => set(false)),
        tab('City to City', Icons.alt_route_rounded, inter, () => set(true)),
      ]),
    );
  }
}

/// One way or round trip (round trip: cars only).
class _BookingTypeTabs extends ConsumerWidget {
  const _BookingTypeTabs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    return Row(
      children: [
        for (final t in const [BookingType.oneWay, BookingType.roundTrip]) ...[
          if (t != BookingType.oneWay) const SizedBox(width: 8),
          ChoiceChip(
            avatar: Icon(t == BookingType.oneWay ? Icons.arrow_forward_rounded : Icons.swap_horiz_rounded,
                size: 16, color: draft.type == t ? AppColors.white : AppColors.navy),
            label: Text(t.label),
            selected: draft.type == t,
            showCheckmark: false,
            selectedColor: AppColors.green,
            backgroundColor: AppColors.white,
            side: BorderSide(color: draft.type == t ? AppColors.green : AppColors.border),
            labelStyle: AppText.body(13, weight: FontWeight.w700, color: draft.type == t ? AppColors.white : AppColors.navy),
            onSelected: (_) => ref.read(bookingDraftProvider.notifier).setType(t),
          ),
        ],
      ],
    );
  }
}

/// City to City: the other cities as tappable cards with the distance and the fare from here.
class _CityCards extends ConsumerWidget {
  const _CityCards({required this.catalog, required this.pickupCity});

  final Catalog catalog;
  final City pickupCity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final others = [
      for (final c in catalog.cities)
        if (c.id != pickupCity.id && c.lat != null && c.lng != null) c,
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: others.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = others[i];
          final from = draft.pickup?.point;
          final km = from == null ? null : tripDistanceKm(from, GeoPoint(c.lat!, c.lng!));
          final fare = km == null
              ? null
              : catalog.quoteBooking(draft.category, draft.type == BookingType.roundTrip ? BookingType.roundTrip : BookingType.oneWay,
                  distanceKm: km, expectedWaitMinutes: draft.expectedWaitMin)?.recommended;
          final selected = draft.destination != null &&
              catalog.nearestCity(draft.destination!.point.lat, draft.destination!.point.lng)?.city.id == c.id;
          return GestureDetector(
            onTap: () => ref
                .read(bookingDraftProvider.notifier)
                .setDestination(MapPick(point: GeoPoint(c.lat!, c.lng!), nearestName: c.name, isTownCentre: true)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 138,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: selected ? AppColors.greenSoft : AppColors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? AppColors.green : AppColors.border, width: selected ? 1.6 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Icon(Icons.location_on_rounded, size: 16, color: selected ? AppColors.green : AppColors.navy),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(c.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14, weight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(km == null ? 'Choose pickup' : '${km.round()} km',
                      style: AppText.body(12.5, color: AppColors.mutedDark)),
                  if (fare != null)
                    Text('from ${formatFare(fare)}',
                        style: AppText.body(13, weight: FontWeight.w700, color: AppColors.green)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Asks how far the trip is (for addresses that are not on the map). Returns km, 0 = go back to the map pins.
Future<double?> _askKm(BuildContext context, double? current, bool isManual) {
  final ctrl = TextEditingController(text: isManual && current != null ? current.toStringAsFixed(1) : '');
  return showDialog<double>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('How far is it?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'If your address is not on the map, enter the distance in km between the two places. The fare is worked out from it.',
            style: AppText.body(13, color: AppColors.mutedDark),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Distance (km)', hintText: current == null ? 'e.g. 4' : current.toStringAsFixed(1)),
          ),
        ],
      ),
      actions: [
        if (isManual) TextButton(onPressed: () => Navigator.pop(context, 0.0), child: const Text('Use map')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
            if (v != null && v >= 1 && v <= 300) Navigator.pop(context, v);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

final _previewRouteProvider = FutureProvider.autoDispose.family<RouteEstimate, String>((ref, key) {
  final p = key.split(',').map(double.parse).toList();
  return ref.watch(routingServiceProvider).route([LatLng(p[0], p[1]), LatLng(p[2], p[3])]);
});

/// The trip on a small map: pickup, destination and the road between them, so the passenger
/// can see the places were understood correctly.
class _RoutePreview extends ConsumerWidget {
  const _RoutePreview({required this.from, required this.to});

  final GeoPoint from;
  final GeoPoint to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = LatLng(from.lat, from.lng), b = LatLng(to.lat, to.lng);
    final est = ref.watch(_previewRouteProvider('${from.lat},${from.lng},${to.lat},${to.lng}')).valueOrNull;
    final map = ref.watch(mapProviderProvider);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 150,
        // A picture of the trip: it must not catch the page's scrolling.
        child: IgnorePointer(
          child: KeyedSubtree(
            key: ValueKey('${from.lat},${from.lng},${to.lat},${to.lng}'),
            child: map.buildMap(
            fitPoints: [a, b],
            polyline: est?.points ?? [a, b],
            markers: [
              MapMarker(point: a, size: 20, child: const _Dot(color: AppColors.green, round: true)),
              MapMarker(point: b, size: 20, child: const _Dot(color: AppColors.navy, round: false)),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The top of Home, inDrive style: a map with the pickup pin. Tap it to move the pickup.
class _PickupMapCard extends ConsumerWidget {
  const _PickupMapCard({required this.catalog});

  final Catalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(bookingDraftProvider);
    final map = ref.watch(mapProviderProvider);
    final firstCity = catalog.cities.where((c) => c.lat != null && c.lng != null).firstOrNull;
    final at = draft.pickup?.point ?? (firstCity == null ? const GeoPoint(30.9709, 72.4826) : GeoPoint(firstCity.lat!, firstCity.lng!));
    final centre = LatLng(at.lat, at.lng);

    Future<void> open() async {
      final pick = await pickOnMap(context,
          title: 'Pickup location',
          catalog: catalog,
          initial: draft.pickup,
          other: draft.destination,
          requireService: true,
          startAtMyLocation: draft.pickup == null);
      if (pick != null) ref.read(bookingDraftProvider.notifier).setPickup(pick);
    }

    return GestureDetector(
      onTap: open,
      // The map underneath ignores touches, so this layer must take them itself.
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 210,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: KeyedSubtree(
                    key: ValueKey('${at.lat},${at.lng}'),
                    child: map.buildMap(fitPoints: [centre]),
                  ),
                ),
              ),
              // The pin: its tip on the pickup.
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 34),
                  child: Icon(Icons.location_on_rounded, size: 44, color: AppColors.green),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10)],
                  ),
                  child: Row(children: [
                    const Icon(Icons.my_location_rounded, color: AppColors.green, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Pickup', style: AppText.body(11.5, color: AppColors.muted)),
                          Text(draft.pickup?.title ?? 'Tap to set your pickup on the map',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14.5, weight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_location_alt_rounded, color: AppColors.navy),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

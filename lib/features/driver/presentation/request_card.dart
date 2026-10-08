import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../../rides/domain/fare_service.dart';
import '../domain/driver_models.dart';

class _PlaceLine extends StatelessWidget {
  const _PlaceLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.body(14.5, weight: FontWeight.w600))),
        ],
      );
}

String _when(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final now = DateTime.now();
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return '${today ? 'today' : '${t.day}/${t.month}'} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    this.categoryName,
    required this.busy,
    required this.onAccept,
    required this.onCounter,
    required this.onReject,
  });

  final FeedRequest request;

  /// The ride type's display name (from the admin-managed catalog).
  final String? categoryName;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onCounter;
  final VoidCallback onReject;

  String _ago(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    return m < 1 ? 'just now' : '$m min ago';
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: r.isReturn ? AppColors.green.withValues(alpha: 0.5) : AppColors.borderSoft),
        boxShadow: const [BoxShadow(color: Color(0x0F0B2347), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(categoryName ?? r.category, style: AppText.display(16.5)),
              ),
              Text(formatFare(r.offeredFare), style: AppText.display(19, weight: FontWeight.w800, color: AppColors.green)),
            ],
          ),
          if (r.badge != null || r.scheduledAt != null) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (r.badge != null) _Badge(r.badge!),
              if (r.scheduledAt != null) _Badge('Scheduled ${_when(r.scheduledAt!)}'),
            ]),
          ],
          const SizedBox(height: 8),
          // Exactly the words the passenger wrote or chose (the town only if there were none).
          _PlaceLine(
            icon: Icons.circle,
            color: AppColors.green,
            text: placeName(r.pickupLabel, r.originName),
          ),
          const SizedBox(height: 4),
          _PlaceLine(
            icon: Icons.square_rounded,
            color: AppColors.navy,
            text: placeName(r.dropoffLabel, r.destinationName),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r.passengerName, style: AppText.body(13, color: AppColors.mutedDark)),
                const SizedBox(width: 4),
                RatingText(r.passengerRating),
              ]),
              _Meta(Icons.people_alt_rounded, '${r.passengerCount}'),
              _Meta(Icons.straighten_rounded, '${r.distanceKm.toStringAsFixed(0)} km trip'),
              if (r.pickupKm != null) _Meta(Icons.near_me_rounded, '${r.pickupKm!.toStringAsFixed(1)} km away'),
              _Meta(Icons.schedule_rounded, _ago(r.createdAt)),
            ],
          ),
          if (r.commission > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('Commission ${formatFare(r.commission)}',
                    style: AppText.body(13, color: AppColors.mutedDark)),
              ),
              Text('You will get ${formatFare(r.driverGets)}',
                  style: AppText.body(14, weight: FontWeight.w700, color: AppColors.green)),
            ]),
          ],
          if (r.bookingType == BookingType.hourly && r.packageKm != null) ...[
            const SizedBox(height: 6),
            Text('${r.packageHours} hours · ${r.packageKm!.round()} km included — extra km and hours are paid on top',
                style: AppText.body(12.5, color: AppColors.mutedDark)),
          ],
          if (r.bookingType == BookingType.roundTrip) ...[
            const SizedBox(height: 6),
            Text(
              r.expectedWaitMin > 0
                  ? 'Goes there and back · passenger expects to wait ${r.expectedWaitMin} min at the destination'
                  : 'Goes there and back',
              style: AppText.body(12.5, color: AppColors.mutedDark),
            ),
          ],
          if (r.isNight || r.loadingSelected) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              if (r.isNight) const _Badge('Night fare'),
              if (r.loadingSelected) const _Badge('Loading help'),
            ]),
          ],
          if (r.hasMyOffer) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Your ${r.myOfferIsCounter ? 'counter' : 'acceptance'} of ${formatFare(r.myOfferFare!)} '
                'was sent — waiting for the passenger.',
                style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!r.hasMyOffer) ...[
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: busy ? null : onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.green,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: AppText.display(14),
                      ),
                      child: FittedBox(child: Text(context.tr('driver.accept', {'fare': formatFare(r.offeredFare)}))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: busy ? null : onCounter,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy, width: 1.3),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: AppText.display(14),
                    ),
                    child: FittedBox(child: Text(r.hasMyOffer ? 'Change offer' : context.tr('driver.counter'))),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: context.tr('driver.reject'),
                onPressed: busy ? null : onReject,
                icon: const Icon(Icons.close_rounded, color: AppColors.mutedDark),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: AppText.body(12, weight: FontWeight.w600, color: AppColors.green)),
      );
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.muted),
          const SizedBox(width: 3),
          Text(text, style: AppText.body(13, color: AppColors.mutedDark)),
        ],
      );
}

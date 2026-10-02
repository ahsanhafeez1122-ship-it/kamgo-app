import 'package:flutter/material.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/motion_widgets.dart';
import '../domain/driver_models.dart';

class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onCounter,
    required this.onReject,
  });

  final FeedRequest request;
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
                child: Text('${r.originName} → ${r.destinationName}', style: AppText.display(16.5)),
              ),
              Text(formatFare(r.offeredFare), style: AppText.display(19, weight: FontWeight.w800, color: AppColors.green)),
            ],
          ),
          const SizedBox(height: 6),
          if (r.pickupLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.place_rounded, size: 16, color: AppColors.green),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(r.pickupLabel!, style: AppText.body(13.5, weight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
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
              _Meta(Icons.straighten_rounded, '${r.distanceKm.toStringAsFixed(0)} km'),
              _Meta(Icons.schedule_rounded, _ago(r.createdAt)),
            ],
          ),
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/strings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/buttons.dart';
import '../../rides/domain/fare_policy.dart';
import '../domain/driver_models.dart';

/// Bottom sheet for a driver to name their fare.
Future<int?> showCounterOfferSheet(BuildContext context, FeedRequest r, FarePolicy policy) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CounterSheet(request: r, policy: policy),
  );
}

class _CounterSheet extends StatefulWidget {
  const _CounterSheet({required this.request, required this.policy});
  final FeedRequest request;
  final FarePolicy policy;

  @override
  State<_CounterSheet> createState() => _CounterSheetState();
}

class _CounterSheetState extends State<_CounterSheet> {
  late final _c = TextEditingController(
    text: '${((widget.request.myOfferFare ?? widget.request.offeredFare + 100) / 50).round() * 50}',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _set(int v) => setState(() => _c.text = '$v');

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final km = r.distanceKm;
    final v = int.tryParse(_c.text);
    final check = v == null ? FareCheck.tooLow : widget.policy.check(v, km);
    final min = widget.policy.minFare(km);
    final max = widget.policy.maxFare(km);
    final base = r.offeredFare.round();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('driver.counter'), style: AppText.display(18)),
              const SizedBox(height: 4),
              Text('${r.originName} → ${r.destinationName} · passenger offered ${formatFare(r.offeredFare)}',
                  style: AppText.body(13, color: AppColors.muted)),
              const SizedBox(height: 18),
              TextField(
                controller: _c,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                onChanged: (_) => setState(() {}),
                style: AppText.display(30, weight: FontWeight.w800),
                decoration: InputDecoration(prefixText: 'Rs. ', prefixStyle: AppText.display(18)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final add in const [50, 100, 200, 300])
                    ActionChip(
                      label: Text('+$add'),
                      onPressed: () => _set(base + add),
                      backgroundColor: AppColors.background,
                      side: const BorderSide(color: AppColors.border),
                      shape: const StadiumBorder(),
                      labelStyle: AppText.body(14, weight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                check == FareCheck.ok
                    ? 'The passenger will see your offer right away.'
                    : 'Allowed for this route: ${formatFare(min)} – ${formatFare(max)}',
                textAlign: TextAlign.center,
                style: AppText.body(13, color: check == FareCheck.ok ? AppColors.mutedDark : AppColors.danger),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Send offer',
                onPressed: check == FareCheck.ok ? () => Navigator.pop(context, v) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

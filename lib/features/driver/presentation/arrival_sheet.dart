import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/buttons.dart';

/// "When can you reach the pickup?" — the driver picks the minutes, and the passenger
/// sees "Driver arrives in about N min". Returns the minutes, or null if cancelled.
Future<int?> showArrivalSheet(
  BuildContext context, {
  required int fare,
  required bool accept,
  int initial = 10,
}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (_) => _ArrivalSheet(fare: fare, accept: accept, initial: initial),
  );
}

class _ArrivalSheet extends StatefulWidget {
  const _ArrivalSheet({required this.fare, required this.accept, required this.initial});

  final int fare;
  final bool accept;
  final int initial;

  @override
  State<_ArrivalSheet> createState() => _ArrivalSheetState();
}

class _ArrivalSheetState extends State<_ArrivalSheet> {
  static const _options = [3, 5, 10, 15, 20, 30, 45, 60];
  late int _mins = _options.contains(widget.initial) ? widget.initial : _nearest(widget.initial);

  static int _nearest(int v) => _options.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('When can you reach the pickup?', style: AppText.display(18)),
            const SizedBox(height: 4),
            Text('The passenger sees this with your offer of ${formatFare(widget.fare)}.',
                style: AppText.body(13, color: AppColors.muted)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _options)
                  ChoiceChip(
                    label: Text(m >= 60 ? '1 hr' : '$m min'),
                    selected: _mins == m,
                    onSelected: (_) => setState(() => _mins = m),
                    labelStyle: AppText.body(14,
                        weight: FontWeight.w600, color: _mins == m ? AppColors.white : AppColors.navy),
                    selectedColor: AppColors.green,
                    backgroundColor: AppColors.white,
                    showCheckmark: false,
                    side: const BorderSide(color: AppColors.border),
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: widget.accept ? 'Accept · arrive in $_mins min' : 'Send offer · arrive in $_mins min',
              onPressed: () => Navigator.pop(context, _mins),
            ),
          ],
        ),
      ),
    );
  }
}

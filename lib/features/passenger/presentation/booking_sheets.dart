import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/buttons.dart';
import '../../rides/domain/catalog.dart';
import '../../rides/domain/fare_service.dart';

Future<String?> showCityPicker(
  BuildContext context, {
  required String title,
  required List<City> cities,
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.display(18)),
            const SizedBox(height: 12),
            if (cities.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('No routes available yet.',
                    style: AppText.body(15, color: AppColors.mutedDark)),
              ),
            for (final c in cities)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: c.id == selectedId ? AppColors.greenSoft : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: Icon(Icons.location_city_rounded,
                        color: c.id == selectedId ? AppColors.green : AppColors.navy),
                    title: Text(c.name, style: AppText.body(16, weight: FontWeight.w600)),
                    trailing: c.id == selectedId
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.green)
                        : null,
                    onTap: () => Navigator.pop(context, c.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<int?> showPassengersSheet(BuildContext context, {required int initial, required int max}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) {
      var count = initial;
      return StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('How many passengers?', style: AppText.display(18)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundIconButton(
                      icon: Icons.remove_rounded,
                      onTap: count > 1 ? () => setState(() => count--) : null,
                    ),
                    SizedBox(
                      width: 96,
                      child: Text('$count',
                          textAlign: TextAlign.center,
                          style: AppText.display(40, weight: FontWeight.w800)),
                    ),
                    _RoundIconButton(
                      icon: Icons.add_rounded,
                      onTap: count < max ? () => setState(() => count++) : null,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Up to $max per ride',
                    textAlign: TextAlign.center,
                    style: AppText.body(13, color: AppColors.muted)),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Done', onPressed: () => Navigator.pop(context, count)),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The passenger's offer. [quote] comes from the shared fare service, so the band and the
/// recommendation are the same numbers the server will check.
Future<int?> showOfferSheet(
  BuildContext context, {
  required int initial,
  required double distanceKm,
  required FareQuote quote,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _OfferSheet(initial: initial, distanceKm: distanceKm, quote: quote),
  );
}

class _OfferSheet extends StatefulWidget {
  const _OfferSheet({required this.initial, required this.distanceKm, required this.quote});

  final int initial;
  final double distanceKm;
  final FareQuote quote;

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late final _controller = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _value => int.tryParse(_controller.text);

  void _bump(int delta) {
    final next = ((_value ?? widget.initial) + delta).clamp(0, 999999);
    setState(() => _controller.text = '$next');
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.quote;
    final v = _value;
    final check = v == null ? FareCheck.tooLow : q.check(v);
    final message = switch (check) {
      FareCheck.ok => 'Drivers can accept this or send a counter offer. Tap Recommended to use our suggestion.',
      FareCheck.tooLow => 'Lowest offer for this trip is ${formatFare(q.minOffer)}.',
      FareCheck.tooHigh => 'Highest offer for this trip is ${formatFare(q.maxOffer)}.',
      FareCheck.invalidRoute => 'This route is not available.',
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your offer', style: AppText.display(18)),
              const SizedBox(height: 4),
              Text(
                '${widget.distanceKm.toStringAsFixed(1)} km · recommended ${formatFare(q.recommended)} · '
                'you can offer ${formatFare(q.minOffer)} – ${formatFare(q.maxOffer)}',
                style: AppText.body(13, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.green),
                  label: Text('Recommended ${formatFare(q.recommended)}'),
                  onPressed: () => setState(() => _controller.text = '${q.recommended}'),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _RoundIconButton(icon: Icons.remove_rounded, onTap: () => _bump(-10)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) => setState(() {}),
                      style: AppText.display(28, weight: FontWeight.w800, color: AppColors.green),
                      decoration: InputDecoration(
                        prefixText: 'Rs. ',
                        prefixStyle: AppText.display(18, color: AppColors.green),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _RoundIconButton(icon: Icons.add_rounded, onTap: () => _bump(10)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body(13,
                    color: check == FareCheck.ok ? AppColors.mutedDark : AppColors.danger),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Set offer',
                onPressed: check == FareCheck.ok ? () => Navigator.pop(context, v) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 26,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(52),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.navy,
        disabledForegroundColor: AppColors.border,
        side: const BorderSide(color: AppColors.border),
      ),
      icon: Icon(icon),
    );
  }
}

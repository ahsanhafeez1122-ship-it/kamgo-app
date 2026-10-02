import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/motion.dart';
import 'kamgo_logo.dart';

/// Concentric green rings that scale out and fade, staggered like a radar
/// ping, around a navy disc with a gently bobbing car.
class RadarSearch extends StatefulWidget {
  const RadarSearch({super.key, this.size = 240});
  final double size;

  @override
  State<RadarSearch> createState() => _RadarSearchState();
}

class _RadarSearchState extends State<RadarSearch> with TickerProviderStateMixin {
  late final AnimationController _rings =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _rings.stop();
      _bob.stop();
    } else {
      if (!_rings.isAnimating) _rings.repeat();
      if (!_bob.isAnimating) _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _rings.dispose();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final core = widget.size * 0.38;
    return SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _rings,
              builder: (_, __) => CustomPaint(
                size: Size.square(widget.size),
                painter: _RingsPainter(_rings.value, core / 2),
              ),
            ),
            AnimatedBuilder(
              animation: _bob,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, -4 + 8 * Curves.easeInOut.transform(_bob.value)),
                child: child,
              ),
              child: Container(
                width: core,
                height: core,
                decoration: BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8)),
                  ],
                ),
                alignment: Alignment.center,
                child: CustomPaint(
                  size: Size.square(core * 0.56),
                  painter: const CarLinePainter(fill: AppColors.navy),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.minRadius);
  final double t;
  final double minRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final r = minRadius + (maxR - minRadius) * p;
      canvas.drawCircle(
        c,
        r,
        Paint()..color = AppColors.green.withValues(alpha: 0.28 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

/// "Finding drivers near you..." with a cycling ellipsis.
class AnimatedEllipsisText extends StatefulWidget {
  const AnimatedEllipsisText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<AnimatedEllipsisText> createState() => _AnimatedEllipsisTextState();
}

class _AnimatedEllipsisTextState extends State<AnimatedEllipsisText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final dots = reduceMotion(context) ? 3 : (_c.value * 4).floor().clamp(0, 3);
        // Reserve the width of three dots so the text doesn't jiggle.
        return Text.rich(
          TextSpan(children: [
            TextSpan(text: widget.text),
            TextSpan(text: '.' * dots),
            TextSpan(text: '.' * (3 - dots), style: const TextStyle(color: Colors.transparent)),
          ]),
          style: widget.style,
          textAlign: TextAlign.center,
        );
      },
    );
  }
}

/// Green circle with a check mark that draws itself.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({super.key, this.size = 96});
  final double size;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final circle = Curves.easeOutBack.transform((_c.value / 0.55).clamp(0, 1));
        final check = Curves.easeOut.transform(((_c.value - 0.45) / 0.55).clamp(0, 1));
        return Transform.scale(
          scale: circle,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: AppColors.green,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4)],
            ),
            child: CustomPaint(painter: _CheckPainter(check)),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width * 0.28, s.height * 0.52)
      ..lineTo(s.width * 0.44, s.height * 0.67)
      ..lineTo(s.width * 0.73, s.height * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * t),
      Paint()
        ..color = AppColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// Tappable 1–5 stars.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({super.key, required this.value, required this.onChanged, this.size = 44});
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: true,
            label: '$i stars',
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedScale(
                scale: i <= value ? 1.1 : 1,
                duration: const Duration(milliseconds: 150),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: size,
                    color: i <= value ? const Color(0xFFF59E0B) : AppColors.border,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small rating chip: ★ 4.8
class RatingText extends StatelessWidget {
  const RatingText(this.rating, {super.key, this.color = AppColors.mutedDark});
  final double? rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
        const SizedBox(width: 2),
        Text(rating == null ? '–' : rating!.toStringAsFixed(1),
            style: AppText.body(13, weight: FontWeight.w600, color: color)),
      ],
    );
  }
}

/// Colored rounded-square avatar with initials, colour picked from the name.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 52, this.radius = 16});
  final String name;
  final double size;
  final double radius;

  static const _palette = [
    Color(0xFF0B2347), Color(0xFF16A34A), Color(0xFF7C3AED), Color(0xFFDB2777),
    Color(0xFFEA580C), Color(0xFF0891B2), Color(0xFF4F46E5),
  ];

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.take(2).map((p) => p[0].toUpperCase()).join();
    final color = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      alignment: Alignment.center,
      child: Text(initials.isEmpty ? '?' : initials,
          style: AppText.display(size * 0.34, color: AppColors.white)),
    );
  }
}

/// Seconds left until [until], refreshed every second.
class CountdownText extends StatefulWidget {
  const CountdownText({super.key, required this.until, this.style});
  final DateTime until;
  final TextStyle? style;

  @override
  State<CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<CountdownText> {
  late final Stream<int> _tick = Stream.periodic(const Duration(seconds: 1), (i) => i);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _tick,
      builder: (_, __) {
        final left = widget.until.difference(DateTime.now());
        final s = math.max(0, left.inSeconds);
        return Text('${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}', style: widget.style);
      },
    );
  }
}

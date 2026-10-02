import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Green rounded-square badge with the white line-art car.
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 112, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(radius ?? size * 0.25),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size.square(size * 0.7),
        painter: const CarLinePainter(),
      ),
    );
  }
}

/// Simple line-art car drawn in a 100×100 box, so it stays crisp at any size
/// without shipping an image asset.
class CarLinePainter extends CustomPainter {
  const CarLinePainter({this.color = AppColors.white, this.fill = AppColors.green});

  final Color color;

  /// Colour behind the wheels, so they "cut" the body outline cleanly.
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Body
    canvas.drawRRect(
      RRect.fromLTRBR(10, 46, 90, 72, const Radius.circular(9)),
      stroke,
    );
    // Roof / cabin
    final roof = Path()
      ..moveTo(24, 46)
      ..lineTo(33, 28)
      ..quadraticBezierTo(35, 25, 39, 25)
      ..lineTo(63, 25)
      ..quadraticBezierTo(67, 25, 69, 28)
      ..lineTo(78, 46);
    canvas.drawPath(roof, stroke);
    // Window pillar
    canvas.drawLine(const Offset(51, 26), const Offset(51, 46), stroke);
    // Headlight
    canvas.drawLine(const Offset(80, 57), const Offset(84, 57), stroke);

    // Wheels
    final wheelFill = Paint()..color = fill;
    for (final x in const [30.0, 70.0]) {
      canvas.drawCircle(Offset(x, 72), 9, wheelFill);
      canvas.drawCircle(Offset(x, 72), 9, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CarLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}

/// "KAM" + "GO" wordmark.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.size = 34,
    this.kamColor = AppColors.white,
    this.goColor = AppColors.greenLight,
  });

  final double size;
  final Color kamColor;
  final Color goColor;

  @override
  Widget build(BuildContext context) {
    final style = AppText.display(size, weight: FontWeight.w800, height: 1.1);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'KAM ', style: style.copyWith(color: kamColor)),
        TextSpan(text: 'GO', style: style.copyWith(color: goColor)),
      ]),
      semanticsLabel: 'KAM GO',
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The KG mark on a white rounded tile (readable on both light and navy backgrounds).
class LogoBadge extends StatelessWidget {
  const LogoBadge({super.key, this.size = 112, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius ?? size * 0.25),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Image.asset('assets/logo/logo_mark.png', fit: BoxFit.contain, semanticLabel: 'KAM GO'),
    );
  }
}

/// The "KAM GO" lettering from the logo. [kamColor] only picks the variant:
/// a light colour (the default, for navy backgrounds) uses the white-and-green
/// version, a dark one uses the navy-and-green original.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.size = 34,
    this.kamColor = AppColors.white,
    this.goColor = AppColors.greenLight,
  });

  /// Roughly the font size the old text wordmark used; the image is scaled to match.
  final double size;
  final Color kamColor;
  final Color goColor;

  @override
  Widget build(BuildContext context) {
    final onDark = kamColor.computeLuminance() > 0.5;
    return Image.asset(
      onDark ? 'assets/logo/logo_wordmark_white.png' : 'assets/logo/logo_wordmark.png',
      height: size * 0.95,
      fit: BoxFit.contain,
      semanticLabel: 'KAM GO',
    );
  }
}

/// The full logo (mark above the lettering) for big spots such as the splash screen.
class KamgoLogo extends StatelessWidget {
  const KamgoLogo({super.key, this.height = 140});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/logo/logo_full.png', height: height, fit: BoxFit.contain, semanticLabel: 'KAM GO');
  }
}

/// Simple line-art car drawn in a 100×100 box (used for the map car marker and
/// the radar), so it stays crisp at any size without an image asset.
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
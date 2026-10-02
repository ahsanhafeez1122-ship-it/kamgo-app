import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// True when the OS "remove animations" / reduce-motion setting is on.
bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

extension MotionAware on Widget {
  /// Like `.animate()`, but jumps straight to the end state when the user
  /// has asked the OS to reduce motion.
  Animate motion(BuildContext context, {Duration? delay}) {
    final reduce = reduceMotion(context);
    return reduce ? animate(autoPlay: false, value: 1) : animate(delay: delay);
  }
}

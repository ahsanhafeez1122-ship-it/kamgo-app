import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Poppins for display (600–800), Inter for body (400–600).
abstract final class AppText {
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.navy,
    double height = 1.2,
  }) =>
      TextStyle(
        fontFamily: 'Poppins',
        // Poppins has no arrows (→) and some symbols; Inter fills the gaps.
        fontFamilyFallback: const ['Inter'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
      );

  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.navy,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: weight,
        // Inter ships as a variable font; drive the weight axis explicitly.
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        color: color,
        height: height,
      );
}

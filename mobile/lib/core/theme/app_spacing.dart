import 'package:flutter/material.dart';

/// Design system spacing, radii and elevation constants.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double screenHorizontal = 20;
  static const double screenVertical = 16;
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: screenHorizontal,
    vertical: screenVertical,
  );

  /// Gap between product cards in the 2-column grid.
  static const double gridGap = 14;

  /// Smallest tap target (SRS §8): Android's 48 dp, which also covers
  /// Apple's 44 pt. Icon buttons keep their visual size and pad the hit area.
  static const double minTapTarget = 48;
}

class AppRadius {
  AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  /// Fully rounded (pill) — buttons, chips, search bar.
  static const double pill = 999;
}

class AppElevation {
  AppElevation._();

  static List<BoxShadow> get soft => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ];
}

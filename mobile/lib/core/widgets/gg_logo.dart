import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Golden Gift logo — gold gift-box emblem (two Gs + bow) with optional wordmark.
///
/// Assets come from `branding/` (see `branding/README.md`):
/// `assets/images/logo_transparent.png` works on both light and dark surfaces.
class GGLogo extends StatelessWidget {
  const GGLogo({
    super.key,
    this.size = 64,
    this.showWordmark = true,
    this.direction = Axis.vertical,
  });

  /// Emblem height/width in logical pixels.
  final double size;

  /// Show "GOLDEN GIFT" next to / under the emblem.
  final bool showWordmark;

  /// `Axis.vertical` = wordmark under the emblem, `Axis.horizontal` = beside it.
  final Axis direction;

  @override
  Widget build(BuildContext context) {
    final emblem = Image.asset(
      'assets/images/logo_transparent.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'Golden Gift',
    );
    if (!showWordmark) return emblem;

    final wordmark = Text(
      'GOLDEN GIFT',
      style: TextStyle(
        fontSize: size * (direction == Axis.vertical ? 0.26 : 0.34),
        fontWeight: FontWeight.w700,
        letterSpacing: size * 0.05,
        color: AppColors.gold(context),
        height: 1,
      ),
    );

    final gap = SizedBox(width: size * 0.2, height: size * 0.18);
    return direction == Axis.vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [emblem, gap, wordmark])
        : Row(mainAxisSize: MainAxisSize.min, children: [emblem, gap, wordmark]);
  }
}

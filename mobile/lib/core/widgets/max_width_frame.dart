import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// SRS §8 Compatibility: tablets (and wide web windows) render the phone
/// layouts in a centred column of at most [maxWidth]. MediaQuery reports the
/// column's width, so size-based layouts, dialogs and sheets match phones.
class MaxWidthFrame extends StatelessWidget {
  const MaxWidthFrame({super.key, required this.child, this.maxWidth = defaultMaxWidth});

  static const defaultMaxWidth = 600.0;

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= maxWidth) return child;
    final side = (mq.size.width - maxWidth) / 2;
    return ColoredBox(
      color: AppColors.isDark(context) ? AppColors.black : AppColors.surfaceSecondary,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          child: MediaQuery(
            data: mq.copyWith(
              size: Size(maxWidth, mq.size.height),
              // The column's own edges have no system insets on the sides.
              padding: mq.padding.copyWith(left: (mq.padding.left - side).clamp(0, double.infinity), right: (mq.padding.right - side).clamp(0, double.infinity)),
              viewPadding: mq.viewPadding.copyWith(left: (mq.viewPadding.left - side).clamp(0, double.infinity), right: (mq.viewPadding.right - side).clamp(0, double.infinity)),
            ),
            child: ClipRect(child: child),
          ),
        ),
      ),
    );
  }
}

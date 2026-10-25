import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Shared label / icon / spinner row for [PrimaryButton] and [OutlineButton].
/// Internal helper — not exported from `widgets.dart`.
class GGButtonContent extends StatelessWidget {
  const GGButtonContent({
    super.key,
    required this.label,
    required this.isLoading,
    required this.spinnerColor,
    this.icon,
    this.fitLabel = false,
  });

  final String label;
  final bool isLoading;
  final Color spinnerColor;
  final IconData? icon;

  /// Shrink a label that doesn't fit instead of cutting it with "…".
  final bool fitLabel;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Semantics(
        label: label,
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: spinnerColor),
        ),
      );
    }
    final Widget text = fitLabel
        ? FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1))
        : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: text),
      ],
    );
  }
}

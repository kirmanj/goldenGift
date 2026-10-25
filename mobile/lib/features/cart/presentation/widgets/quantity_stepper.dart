import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';

/// Pill "−  2  +" stepper (SRS §5.9 bottom bar, §5.10 cart lines).
///
/// Buttons are ≥ 48 dp tap targets and disable at [min] / [max]. The whole
/// control is also exposed to screen readers as one adjustable value
/// ("Quantity, 2") with increase / decrease actions. A null [onChanged]
/// disables it.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 99,
    this.height = AppSpacing.minTapTarget,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// 56 next to a [PrimaryButton], 48 in cart lines.
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canDecrease = onChanged != null && value > min;
    final canIncrease = onChanged != null && value < max;
    const buttonWidth = AppSpacing.minTapTarget;

    Widget button(IconData icon, String tooltip, bool enabled, int delta) => SizedBox(
          width: buttonWidth,
          height: height,
          child: IconButton(
            onPressed: enabled ? () => onChanged!(value + delta) : null,
            tooltip: tooltip,
            icon: Icon(icon, size: 20),
            color: AppColors.text(context),
            disabledColor: AppColors.textMuted(context).withValues(alpha: 0.45),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(width: buttonWidth, height: height),
          ),
        );

    return Semantics(
      container: true,
      label: l10n.quantity,
      value: '$value',
      increasedValue: canIncrease ? '${value + 1}' : null,
      decreasedValue: canDecrease ? '${value - 1}' : null,
      onIncrease: canIncrease ? () => onChanged!(value + 1) : null,
      onDecrease: canDecrease ? () => onChanged!(value - 1) : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.field(context),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        // Painted on top, so the buttons keep the full height as tap targets.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.line(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.remove_rounded, l10n.decreaseQuantity, canDecrease, -1),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: ExcludeSemantics(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: AppTextStyles.label.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text(context),
                  ),
                ),
              ),
            ),
            button(Icons.add_rounded, l10n.increaseQuantity, canIncrease, 1),
          ],
        ),
      ),
    );
  }
}

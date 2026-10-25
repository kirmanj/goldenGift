import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Read-only field that looks like `GGInput` (label above, pill below) for
/// values chosen elsewhere: phone (changed via OTP), birthday (date picker),
/// city (sheet). Tapping the pill calls [onTap]; it is announced as a button
/// with the label and the shown text. Shows [hint] in the hint colour when
/// [value] is empty.
class ProfileValueField extends StatelessWidget {
  const ProfileValueField({
    super.key,
    required this.label,
    this.value,
    this.hint,
    this.onTap,
    this.trailing,
    this.valueDirection,
  });

  final String label;
  final String? value;
  final String? hint;
  final VoidCallback? onTap;

  /// Icon or action at the end of the pill.
  final Widget? trailing;

  /// Force a direction for the value (phone numbers are always LTR).
  final TextDirection? valueDirection;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final hasValue = value != null && value!.isNotEmpty;
    final hintColor = dark ? AppColors.darkTextHint : AppColors.textHint;
    final pill = Material(
      color: AppColors.card(context),
      shape: StadiumBorder(side: BorderSide(color: AppColors.line(context))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: AppSpacing.lg,
              end: trailing == null ? AppSpacing.lg : AppSpacing.sm,
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      hasValue ? value! : (hint ?? ''),
                      textDirection: hasValue ? valueDirection : null,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: hasValue ? AppColors.text(context) : hintColor,
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(label, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
        ),
        const SizedBox(height: AppSpacing.sm),
        // The visible value (or hint) is read after the label.
        Semantics(button: onTap != null, label: label, child: pill),
      ],
    );
  }
}

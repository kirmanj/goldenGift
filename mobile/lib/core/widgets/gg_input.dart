import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';

/// Labelled text field (SRS §5.2 IMG_4475, §5.9 option inputs IMG_4503).
///
/// * Single-line: pill on the surface colour, label above, hint inside.
/// * [multiline]: rounded-rect text area on `AppColors.field` (Notes,
///   long text options, special-request idea).
/// * [errorText] turns the border red and shows the message under the field.
/// * [maxLength] enforces a limit; [showCounter] adds the live `n/max`
///   counter on the end side (product text options, §5.9).
/// * [prefix] sits inside the field at the start (country-code picker).
class GGInput extends StatefulWidget {
  const GGInput({
    super.key,
    this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.prefix,
    this.suffix,
    this.maxLength,
    this.showCounter = false,
    this.multiline = false,
    this.minLines = 4,
    this.maxLines = 8,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  final String? label;
  final String? hint;
  final TextEditingController? controller;

  /// Used only when no [controller] is passed.
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final Widget? prefix;
  final Widget? suffix;
  final int? maxLength;
  final bool showCounter;
  final bool multiline;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<GGInput> createState() => _GGInputState();
}

class _GGInputState extends State<GGInput> {
  TextEditingController? _ownController;

  TextEditingController get _controller => widget.controller ?? _ownController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownController = TextEditingController(text: widget.initialValue);
    }
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(GGInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onText);
      if (widget.controller == null) {
        _ownController ??= TextEditingController(text: old.controller?.text);
      }
      _controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _ownController?.dispose();
    super.dispose();
  }

  void _onText() {
    if (widget.showCounter && widget.maxLength != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final radius = BorderRadius.circular(widget.multiline ? AppRadius.md : AppRadius.pill);
    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: color, width: width),
        );
    final idleColor = hasError ? AppColors.error : AppColors.line(context);
    final focusColor = hasError ? AppColors.error : AppColors.gold(context);
    final hintColor = dark ? AppColors.darkTextHint : AppColors.textHint;
    final showCounter = widget.showCounter && widget.maxLength != null;

    final field = TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      obscureText: widget.obscureText,
      keyboardType:
          widget.keyboardType ?? (widget.multiline ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction ??
          (widget.multiline ? TextInputAction.newline : TextInputAction.next),
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      minLines: widget.multiline ? widget.minLines : 1,
      maxLines: widget.multiline ? widget.maxLines : 1,
      cursorColor: AppColors.gold(context),
      style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context)),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppTextStyles.bodyLarge.copyWith(color: hintColor),
        hintMaxLines: widget.multiline ? 3 : 1,
        filled: true,
        fillColor: widget.multiline ? AppColors.field(context) : AppColors.card(context),
        isDense: true,
        contentPadding: widget.multiline
            ? const EdgeInsetsDirectional.all(AppSpacing.md)
            : const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        prefixIcon: widget.prefix == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpacing.xs, end: AppSpacing.sm),
                child: widget.prefix,
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: widget.suffix == null
            ? null
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                child: widget.suffix,
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: border(idleColor),
        enabledBorder: border(idleColor),
        disabledBorder: border(AppColors.line(context).withValues(alpha: 0.6)),
        focusedBorder: border(focusColor, 1.4),
      ),
    );

    final hasFooter = hasError || showCounter;
    // Merge so screen readers announce the label, value and error together.
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          field,
          if (hasFooter)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                top: AppSpacing.xs + AppSpacing.xxs,
                start: AppSpacing.sm,
                end: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: hasError
                        ? Text(
                            widget.errorText!,
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (showCounter)
                    Text(
                      '${_controller.text.characters.length}/${widget.maxLength}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

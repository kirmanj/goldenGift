import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'gg_circle_button.dart';

/// Pill search field with a search icon, clear button and an optional
/// circular filter button (SRS §5.7, §5.8 IMG_4481).
///
/// [onChanged] is debounced ([debounce], default 400 ms per §5.8);
/// clearing the field and [onSubmitted] fire immediately.
/// [readOnly] + [onTap] turns it into a tappable fake field that opens
/// another screen (Home's AI search entry point).
class GGSearchBar extends StatefulWidget {
  const GGSearchBar({
    super.key,
    this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.debounce = const Duration(milliseconds: 400),
    this.onFilterTap,
    this.filterActive = false,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  /// Defaults to the localized "Search".
  final String? hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Duration debounce;

  /// Shows the circular filter button when set.
  final VoidCallback? onFilterTap;

  /// Draws the filter icon in gold when filters are applied.
  final bool filterActive;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  static const double height = 52;

  @override
  State<GGSearchBar> createState() => _GGSearchBarState();
}

class _GGSearchBarState extends State<GGSearchBar> {
  TextEditingController? _ownController;
  Timer? _timer;

  TextEditingController get _controller => widget.controller ?? _ownController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _ownController = TextEditingController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(GGSearchBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onControllerChanged);
      if (widget.controller == null) {
        _ownController ??= TextEditingController(text: old.controller?.text);
      }
      _controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.removeListener(_onControllerChanged);
    _ownController?.dispose();
    super.dispose();
  }

  // Rebuild to show / hide the clear button.
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleChanged(String value) {
    _timer?.cancel();
    if (widget.onChanged == null) return;
    if (widget.debounce == Duration.zero) {
      widget.onChanged!(value);
      return;
    }
    _timer = Timer(widget.debounce, () => widget.onChanged?.call(value));
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged?.call('');
  }

  void _submit(String value) {
    _timer?.cancel();
    widget.onSubmitted?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hint = widget.hint ?? l10n.search;
    final dark = AppColors.isDark(context);
    final hintColor = dark ? AppColors.darkTextHint : AppColors.textHint;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: BorderSide(color: AppColors.line(context)),
    );
    final searchIcon = Icon(Icons.search_rounded, color: AppColors.textMuted(context), size: 22);

    final Widget field;
    if (widget.readOnly) {
      final text = _controller.text;
      field = Semantics(
        button: true,
        label: text.isEmpty ? hint : text,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: Material(
          color: AppColors.card(context),
          shape: StadiumBorder(side: BorderSide(color: AppColors.line(context))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: SizedBox(
              height: GGSearchBar.height,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.md),
                child: Row(
                  children: [
                    searchIcon,
                    const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                    Expanded(
                      child: Text(
                        text.isEmpty ? hint : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: text.isEmpty ? hintColor : AppColors.text(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      field = SizedBox(
        height: GGSearchBar.height,
        child: TextField(
          controller: _controller,
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onChanged: _handleChanged,
          onSubmitted: _submit,
          onTap: widget.onTap,
          textInputAction: TextInputAction.search,
          cursorColor: AppColors.gold(context),
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context)),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.bodyLarge.copyWith(color: hintColor),
            filled: true,
            fillColor: AppColors.card(context),
            isDense: true,
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + AppSpacing.xs,
            ),
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.sm),
              child: searchIcon,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.clear,
                    onPressed: _clear,
                    icon: Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted(context)),
                  ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: AppColors.gold(context), width: 1.4),
            ),
          ),
        ),
      );
    }

    if (widget.onFilterTap == null) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
        GGCircleButton(
          icon: Icons.tune_rounded,
          size: GGSearchBar.height,
          iconColor: widget.filterActive ? AppColors.gold(context) : AppColors.text(context),
          tooltip: l10n.filter,
          onPressed: widget.onFilterTap,
        ),
      ],
    );
  }
}

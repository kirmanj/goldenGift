import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';

/// Themed yes / no dialog (logout, discard changes, delete account).
/// [destructive] paints the confirm button error-red with white text.
/// Resolves to true only when the confirm button is pressed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel ?? AppLocalizations.of(dialogContext)!.cancel,
      destructive: destructive,
    ),
  );
  return result ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final buttonText = AppTextStyles.label.copyWith(fontFamily: font);
    final Widget confirm = destructive
        ? FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
              minimumSize: const Size(44, 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + AppSpacing.xs),
              shape: const StadiumBorder(),
              textStyle: buttonText,
            ),
            child: Text(confirmLabel, textAlign: TextAlign.center),
          )
        : PrimaryButton(
            label: confirmLabel,
            expand: false,
            height: 48,
            onPressed: () => Navigator.of(context).pop(true),
          );
    return AlertDialog(
      backgroundColor: AppColors.card(context),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      title: Text(title, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
      content: message == null
          ? null
          : Text(
              message!,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
            ),
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      actionsOverflowButtonSpacing: AppSpacing.sm,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.text(context),
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            shape: const StadiumBorder(),
            textStyle: buttonText,
          ),
          child: Text(cancelLabel),
        ),
        confirm,
      ],
    );
  }
}

/// Non-dismissible spinner over the page while a long call runs. Close it
/// with the returned callback (safe to call once the page is gone).
VoidCallback showBlockingProgress(BuildContext context) {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.card(dialogContext),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Semantics(
            label: AppLocalizations.of(dialogContext)!.loading,
            child: SizedBox.square(
              dimension: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.gold(dialogContext),
              ),
            ),
          ),
        ),
      ),
    ),
  ).whenComplete(() => open = false);
  return () {
    if (open) {
      open = false;
      navigator.pop();
    }
  };
}

/// Leaves a pushed profile page. Opened by deep link (web) there is nothing
/// underneath, so it goes to Main instead of popping an empty stack.
void popOrGoMain(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go(AppRoutes.main);
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import 'order_section.dart';

/// "Cancel this order?" with an optional reason. Resolves to the reason
/// (possibly empty) when confirmed, null when dismissed.
Future<String?> showCancelOrderDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const _CancelOrderDialog());

class _CancelOrderDialog extends StatefulWidget {
  const _CancelOrderDialog();

  @override
  State<_CancelOrderDialog> createState() => _CancelOrderDialogState();
}

class _CancelOrderDialogState extends State<_CancelOrderDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.card(context),
      title: Text(l10n.cancelOrderConfirm, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
      content: SingleChildScrollView(
        child: GGInput(
          key: const ValueKey('cancel-reason'),
          hint: l10n.cancelReasonHint,
          controller: _reason,
          multiline: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 200,
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('cancel-dialog-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close, style: TextStyle(color: AppColors.textMuted(context))),
        ),
        TextButton(
          key: const ValueKey('cancel-dialog-confirm'),
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(l10n.cancelOrder, style: TextStyle(fontWeight: FontWeight.w700, color: errorText(context))),
        ),
      ],
    );
  }
}

/// Full-screen, swipeable, zoomable view of uploaded photos.
Future<void> showPhotoViewer(BuildContext context, List<String> urls, {int initialIndex = 0}) => showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: AppColors.black,
      builder: (_) => _PhotoViewer(urls: urls, initialIndex: initialIndex),
    );

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.urls, required this.initialIndex});
  final List<String> urls;
  final int initialIndex;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog.fullscreen(
      key: const ValueKey('photo-viewer'),
      backgroundColor: AppColors.black,
      child: Stack(
        children: [
          PageView(
            controller: _pages,
            children: [
              for (final url in widget.urls)
                InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: GGNetworkImage(url: url, fit: BoxFit.contain)),
                ),
            ],
          ),
          PositionedDirectional(
            top: MediaQuery.paddingOf(context).top + AppSpacing.sm,
            end: AppSpacing.md,
            child: GGCircleButton(
              key: const ValueKey('photo-viewer-close'),
              icon: Icons.close_rounded,
              tooltip: l10n.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

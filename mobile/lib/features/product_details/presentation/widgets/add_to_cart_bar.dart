import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/widgets/quantity_stepper.dart';
import '../providers/product_details_controller.dart';

/// Sticky bottom bar (SRS §5.9 item 7): quantity stepper (1 … maxQty) and
/// the gold "Add to Cart · 45,000 IQD" button with the live line total.
///
/// The button stays enabled while groups are incomplete — tapping it shows
/// the hints — and is disabled only when the product is out of stock. When
/// the label doesn't fit beside the stepper (narrow phone / large text) the
/// stepper moves to its own row above a full-width button.
class AddToCartBar extends ConsumerWidget {
  const AddToCartBar({
    super.key,
    required this.productId,
    required this.outOfStock,
    required this.onAddToCart,
  });

  final String productId;
  final bool outOfStock;
  final VoidCallback onAddToCart;

  static const double _buttonHeight = 56;

  /// Stepper width at height 56: two 48 px buttons + the value + border.
  static const double _stepperWidth = 48 * 2 + 40 + 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final provider = productDetailsControllerProvider(productId);
    final qty = ref.watch(provider.select((s) => s.config?.qty ?? 1));
    final maxQty = ref.watch(provider.select((s) => s.config?.maxQty ?? 1));
    final lineTotal = ref.watch(provider.select((s) => s.config?.lineTotal ?? 0));
    final uploading = ref.watch(provider.select((s) => s.isUploading));

    final label = outOfStock ? l10n.outOfStock : '${l10n.addToCart} · ${CurrencyFormatter.format(lineTotal)}';
    final button = PrimaryButton(
      label: label,
      height: _buttonHeight,
      isLoading: uploading,
      onPressed: outOfStock ? null : onAddToCart,
    );
    final stepper = QuantityStepper(
      value: qty,
      max: maxQty,
      height: _buttonHeight,
      onChanged: outOfStock || uploading ? null : (v) => ref.read(provider.notifier).setQty(v),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border(top: BorderSide(color: AppColors.line(context))),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.card,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm + AppSpacing.xs,
            AppSpacing.screenHorizontal,
            AppSpacing.sm + AppSpacing.xs,
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            if (outOfStock) return button;
            const gap = AppSpacing.sm + AppSpacing.xs;
            final buttonTextWidth = constraints.maxWidth - _stepperWidth - gap - AppSpacing.lg * 2;
            if (_labelWidth(context, label) <= buttonTextWidth) {
              return Row(children: [stepper, const SizedBox(width: gap), Expanded(child: button)]);
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.quantity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                      ),
                    ),
                    QuantityStepper(
                      value: qty,
                      max: maxQty,
                      onChanged: stepper.onChanged,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                button,
              ],
            );
          }),
        ),
      ),
    );
  }

  static double _labelWidth(BuildContext context, String label) {
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final painter = TextPainter(
      text: TextSpan(text: label, style: AppTextStyles.button.copyWith(fontFamily: font)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// Blocks the page (and back navigation) while customer photos upload,
/// showing "Uploading photos… 40%". Renders nothing otherwise.
class UploadProgressOverlay extends ConsumerWidget {
  const UploadProgressOverlay({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(productDetailsControllerProvider(productId).select((s) => s.uploadProgress));
    if (progress == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final percent = (progress * 100).round().clamp(0, 100);
    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ModalBarrier(dismissible: false, color: AppColors.black.withValues(alpha: 0.45)),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.card(context),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 48,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      color: AppColors.gold(context),
                      backgroundColor: AppColors.line(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      l10n.uploadingPhotos(percent),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/product_model.dart';
import '../../data/product_repository.dart';
import '../providers/product_details_controller.dart';

/// SRS §5.9 item 3: warning "requires N days for preparation" (reacting to
/// the selected values' overrides), success "can be shipped same day", or
/// error "Out of stock".
class AvailabilityBanner extends ConsumerWidget {
  const AvailabilityBanner({super.key, required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (product.isOutOfStock) {
      return InfoBanner(message: l10n.outOfStock, type: InfoBannerType.error);
    }
    final days = ref.watch(productDetailsControllerProvider(product.id)
        .select((s) => s.config?.preparationDays ?? product.preparationDays));
    if (days > 0) return InfoBanner(message: l10n.preparationDays(days), type: InfoBannerType.warning);
    if (product.availability == ProductAvailability.sameDay) {
      return InfoBanner(message: l10n.sameDayShipping, type: InfoBannerType.success);
    }
    return const SizedBox.shrink();
  }
}

/// SRS §5.9 item 4: large gold price for the current configuration (price +
/// Σ option deltas; the old price moves with the deltas so the struck price
/// stays meaningful) and the Share pill.
class PriceShareRow extends ConsumerWidget {
  const PriceShareRow({super.key, required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final unit =
        ref.watch(productDetailsControllerProvider(product.id).select((s) => s.config?.unitPrice ?? product.price));
    final oldPrice = product.hasDiscount ? product.compareAtPrice! + (unit - product.price) : null;
    final title = product.title.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: PriceText(price: unit, oldPrice: oldPrice, size: PriceTextSize.large),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _SharePill(
          label: l10n.share,
          onTap: () => unawaited(shareProduct(ref, product, title).catchError((Object _) {})),
        ),
      ],
    );
  }
}

class _SharePill extends StatelessWidget {
  const _SharePill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: AppColors.field(context),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.share_outlined, size: 20, color: AppColors.text(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// SRS §5.9 item 5: "About the Product", collapsed to two lines with a
/// Read more / Read less toggle when the text is longer. Line breaks in the
/// description are kept.
class AboutProductSection extends StatefulWidget {
  const AboutProductSection({super.key, required this.text});

  final String text;

  @override
  State<AboutProductSection> createState() => _AboutProductSectionState();
}

class _AboutProductSectionState extends State<AboutProductSection> {
  bool _expanded = false;

  static const _collapsedLines = 2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final style = DefaultTextStyle.of(context)
        .style
        .merge(AppTextStyles.bodyLarge.copyWith(fontSize: 15, color: AppColors.textMuted(context)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.aboutTheProduct,
            style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            maxLines: _collapsedLines,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final overflows = painter.didExceedMaxLines;
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: AlignmentDirectional.topStart,
                child: Text(
                  text,
                  style: style,
                  maxLines: _expanded ? null : _collapsedLines,
                  overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
              ),
              if (overflows)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _expanded ? l10n.readLess : l10n.readMore,
                            style: AppTextStyles.link.copyWith(color: AppColors.goldText(context)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: AppColors.goldText(context),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

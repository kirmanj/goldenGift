import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/product_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/localized_text_ext.dart';
import 'featured_badge.dart';
import 'gg_circle_button.dart';
import 'gg_network_image.dart';
import 'price_text.dart';
import 'wishlist_heart.dart';

/// Product grid card (SRS §4.4, §5.8; IMG_4477, IMG_4481): square image
/// with wishlist heart (top-end), ★ Featured badge (top-start), up to 5
/// colour dots (bottom-end) and an out-of-stock overlay; then a two-line
/// title and [PriceText] with old price + discount badge.
///
/// Width comes from the parent. In a grid use [ProductCard.gridDelegate]
/// so every cell is tall enough for the current text scale:
/// ```dart
/// LayoutBuilder(builder: (context, c) => GridView.builder(
///   gridDelegate: ProductCard.gridDelegate(context, c.maxWidth), ...));
/// ```
/// The heart is shown only when [onWishlistChanged] is set.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.isWishlisted = false,
    this.onTap,
    this.onWishlistChanged,
  });

  final ProductModel product;
  final bool isWishlisted;
  final VoidCallback? onTap;
  final WishlistToggle? onWishlistChanged;

  /// Gap between the card edge and the image (outer radius lg, inner md).
  static const double imageInset = AppSpacing.xs;
  static const double _titleFont = 14;
  static const double _titleHeight = 1.4;

  static double _titleBlockHeight(TextScaler s) => 2 * s.scale(_titleFont) * _titleHeight;

  /// Height of everything below the image, for the current text scale.
  static double infoHeight(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return AppSpacing.sm +
        _titleBlockHeight(s) +
        AppSpacing.xs +
        PriceText.smallMaxHeight(s) +
        AppSpacing.sm;
  }

  /// Total card height for a given card width.
  static double heightFor(BuildContext context, double cardWidth) =>
      cardWidth + infoHeight(context) + 2; // +2: sub-pixel rounding slack

  /// 2-column (by default) grid delegate sized for [ProductCard], with the
  /// standard [AppSpacing.gridGap].
  static SliverGridDelegate gridDelegate(
    BuildContext context,
    double maxWidth, {
    int crossAxisCount = 2,
  }) {
    const gap = AppSpacing.gridGap;
    if (!maxWidth.isFinite) {
      return SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: gap,
        crossAxisSpacing: gap,
        childAspectRatio: 0.6,
      );
    }
    final cardWidth = (maxWidth - gap * (crossAxisCount - 1)) / crossAxisCount;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      mainAxisExtent: heightFor(context, cardWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textScaler = MediaQuery.textScalerOf(context);
    final title = product.title.of(context);
    final dots = product.colorDots.map(_parseHex).whereType<Color>().toList();

    return Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(imageInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GGNetworkImage(url: product.mainImage),
                          if (dots.isNotEmpty)
                            PositionedDirectional(
                              end: AppSpacing.sm,
                              bottom: AppSpacing.sm,
                              child: _ColorDots(colors: dots),
                            ),
                          if (product.isOutOfStock) _OutOfStockOverlay(label: l10n.outOfStock),
                        ],
                      ),
                    ),
                    if (product.isFeatured)
                      const PositionedDirectional(
                        top: AppSpacing.sm + AppSpacing.xs,
                        start: AppSpacing.sm,
                        // Keep clear of the heart's 44 px tap target.
                        end: AppSpacing.sm + GGCircleButton.minTapTarget,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: FeaturedBadge(),
                        ),
                      ),
                    if (onWishlistChanged != null)
                      PositionedDirectional(
                        top: AppSpacing.xs,
                        end: AppSpacing.xs,
                        child: WishlistHeart(
                          isActive: isWishlisted,
                          onChanged: onWishlistChanged,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _titleBlockHeight(textScaler),
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: _titleFont,
                            height: _titleHeight,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text(context),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    PriceText.fromProduct(product),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// `#RRGGBB` / `#AARRGGBB` → Color; null when malformed.
  static Color? _parseHex(String hex) {
    var h = hex.trim().replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }
}

class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.colors});
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + AppSpacing.xxs,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < colors.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.85), width: 1.2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OutOfStockOverlay extends StatelessWidget {
  const _OutOfStockOverlay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.black.withValues(alpha: 0.45),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xs,
            vertical: AppSpacing.xs + AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.text(context),
            ),
          ),
        ),
      ),
    );
  }
}

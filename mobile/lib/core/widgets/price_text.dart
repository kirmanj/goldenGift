import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../models/product_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/currency_formatter.dart';
import 'discount_badge.dart';

enum PriceTextSize { small, large }

/// Current price in bold gold + optional struck-through old price and
/// discount badge (SRS §4.4). [PriceTextSize.small] for product cards,
/// [PriceTextSize.large] (26 px) for Product Details (§5.9 item 4).
/// Always formatted with [CurrencyFormatter] (IQD, no decimals).
///
/// Wraps the old price + badge onto a second line when space is tight
/// (IQD amounts are long), so it never overflows a narrow grid card.
///
/// Light mode uses the deep gold token for the price: brand gold
/// (#C9A227) on white is ≈ 2.4:1, too faint for price text; deep gold
/// (#9C7A14) still reads gold at ≈ 4:1. Dark mode uses the bright accent.
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.price,
    this.oldPrice,
    this.discountPercent,
    this.size = PriceTextSize.small,
  });

  /// Price, old price (when discounted) and badge from a product.
  PriceText.fromProduct(
    ProductModel product, {
    super.key,
    this.size = PriceTextSize.small,
    bool showDiscountBadge = true,
  })  : price = product.price,
        oldPrice = product.hasDiscount ? product.compareAtPrice : null,
        discountPercent = product.hasDiscount && showDiscountBadge ? product.discountPercent : null;

  /// Whole IQD.
  final int price;

  /// Shown struck-through only when greater than [price].
  final int? oldPrice;

  /// Shown as a [DiscountBadge] when > 0.
  final int? discountPercent;
  final PriceTextSize size;

  bool get _large => size == PriceTextSize.large;

  static const double _priceHeight = 1.3;
  static const double _oldHeight = 1.3;
  static double _priceFont(bool large) => large ? 26 : 16;
  static double _oldFont(bool large) => large ? 18 : 12;

  /// Height of the small variant when it wraps onto two lines — used to
  /// size product grid cells for the current text scale.
  static double smallMaxHeight(TextScaler textScaler) =>
      textScaler.scale(_priceFont(false)) * _priceHeight +
      AppSpacing.xxs +
      math.max(textScaler.scale(_oldFont(false)) * _oldHeight, DiscountBadge.heightFor(textScaler));

  /// Price colour: gold text colour (deep gold on light, bright gold on dark — SRS §8).
  static Color priceColor(BuildContext context) => AppColors.goldText(context);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hint = AppColors.isDark(context) ? AppColors.darkTextHint : AppColors.textHint;
    final showOld = oldPrice != null && oldPrice! > price;
    final percent = discountPercent ?? 0;

    final current = Text(
      CurrencyFormatter.format(price),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (_large ? AppTextStyles.price : AppTextStyles.priceSmall).copyWith(
        fontSize: _priceFont(_large),
        fontWeight: FontWeight.w700,
        height: _priceHeight,
        color: priceColor(context),
      ),
    );

    final extras = <Widget>[
      if (showOld)
        Flexible(
          child: Semantics(
            label: l10n.originalPrice(CurrencyFormatter.format(oldPrice!)),
            excludeSemantics: true,
            child: Text(
              CurrencyFormatter.format(oldPrice!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.priceOld.copyWith(
                fontSize: _oldFont(_large),
                height: _oldHeight,
                color: hint,
                decorationColor: hint,
              ),
            ),
          ),
        ),
      if (percent > 0) ...[
        if (showOld) const SizedBox(width: AppSpacing.sm - AppSpacing.xxs),
        DiscountBadge(percent: percent, large: _large),
      ],
    ];

    if (extras.isEmpty) return current;
    return Wrap(
      spacing: _large ? AppSpacing.sm + AppSpacing.xs : AppSpacing.sm - AppSpacing.xxs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        current,
        Row(mainAxisSize: MainAxisSize.min, children: extras),
      ],
    );
  }
}

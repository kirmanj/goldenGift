import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../data/product_query.dart';
import '../gift_audience_ui.dart';

/// Opens the products list filtered by a gift type (SRS §5.8a).
void openGiftAudience(BuildContext context, GiftAudience audience) =>
    context.push(AppRoutes.productsFor(ProductQuery(giftFor: audience)));

/// Home "Shop for" tile (SRS §5.4 item 3): gold-rimmed icon medallion, the
/// gift type and its short line.
class GiftAudienceTile extends StatelessWidget {
  const GiftAudienceTile({super.key, required this.audience, required this.onTap});

  final GiftAudience audience;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Semantics(
      button: true,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: radius, boxShadow: AppElevation.soft),
        child: Material(
          color: AppColors.card(context),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.line(context)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
              child: Column(
                children: [
                  GiftAudienceMedallion(icon: audience.icon),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    audience.label(l10n),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    audience.tagline(l10n),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft-gold disc with a gold gradient rim around [icon].
class GiftAudienceMedallion extends StatelessWidget {
  const GiftAudienceMedallion({super.key, required this.icon, this.size = 52});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.headerGradient),
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(context)),
        // goldText: the deep gold keeps the glyph legible on the soft-gold disc.
        child: Icon(icon, size: size * 0.52, color: AppColors.goldText(context)),
      ),
    );
  }
}

/// Product Details "Gift for" line (SRS §5.9 item 4): one small pill per gift
/// type; a pill opens the products list filtered by it.
class GiftForPills extends StatelessWidget {
  const GiftForPills({super.key, required this.audiences});

  final List<GiftAudience> audiences;

  @override
  Widget build(BuildContext context) {
    if (audiences.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.giftForTitle,
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
        ),
        for (final a in audiences) _GiftForPill(audience: a),
      ],
    );
  }
}

class _GiftForPill extends StatelessWidget {
  const _GiftForPill({required this.audience});
  final GiftAudience audience;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.soft(context),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: AppColors.gold(context))),
        child: InkWell(
          borderRadius: radius,
          onTap: () => openGiftAudience(context, audience),
          child: ConstrainedBox(
            // The visual pill is compact; the hit area keeps 48 dp.
            constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(audience.icon, size: 18, color: AppColors.goldText(context)),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    audience.label(l10n),
                    style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.goldText(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

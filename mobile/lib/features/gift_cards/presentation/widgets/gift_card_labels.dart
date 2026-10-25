import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/gift_card_model.dart';
import '../../../orders/presentation/widgets/order_status_chip.dart';
import '../../data/gift_cards_repository.dart';

/// Localized message for every redeem failure (SRS §5.22, `redeemGiftCard`).
String redeemFailureMessage(AppLocalizations l10n, RedeemFailureReason reason) => switch (reason) {
      RedeemFailureReason.notFound => l10n.redeemNotFound,
      RedeemFailureReason.expired => l10n.redeemExpired,
      RedeemFailureReason.alreadyRedeemed => l10n.redeemAlreadyRedeemed,
      RedeemFailureReason.disabled => l10n.redeemDisabled,
      RedeemFailureReason.notYetSent => l10n.redeemNotYetSent,
      RedeemFailureReason.tooManyAttempts => l10n.redeemTooManyAttempts,
      RedeemFailureReason.unavailable => l10n.redeemUnavailable,
      RedeemFailureReason.network => l10n.authErrorNetwork,
      RedeemFailureReason.unknown => l10n.somethingWentWrong,
    };

/// Status as the recipient / the buyer sees it.
String giftCardStatusLabel(AppLocalizations l10n, GiftCardModel card, {required bool received}) =>
    switch (card.status) {
      GiftCardStatus.pending => card.scheduledAt != null ? l10n.giftCardStatusScheduled : l10n.giftCardStatusPending,
      GiftCardStatus.sent => received ? l10n.giftCardStatusActive : l10n.giftCardStatusSent,
      GiftCardStatus.redeemed => l10n.giftCardStatusRedeemed,
      GiftCardStatus.expired => l10n.giftCardStatusExpired,
      GiftCardStatus.disabled => l10n.giftCardStatusDisabled,
    };

OrderStatusTone giftCardStatusTone(GiftCardStatus status) => switch (status) {
      GiftCardStatus.pending => OrderStatusTone.info,
      GiftCardStatus.sent => OrderStatusTone.progress,
      GiftCardStatus.redeemed => OrderStatusTone.success,
      GiftCardStatus.expired || GiftCardStatus.disabled => OrderStatusTone.error,
    };

/// Small pill coloured like the order status chips.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.fg, required this.bg, this.icon});

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: fg),
              ),
            ),
          ],
        ),
      );
}

/// Neutral (grey) pill colours in the current theme.
(Color fg, Color bg) neutralPillColors(BuildContext context) => (AppColors.text(context), AppColors.field(context));

/// Soft colours for a semantic tone ([InfoBannerType]).
(Color fg, Color bg) tonePillColors(BuildContext context, InfoBannerType type, Color base) {
  final fg = AppColors.isDark(context)
      ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), base)
      : Color.alphaBlend(AppColors.black.withValues(alpha: 0.3), base);
  return (fg, InfoBanner.softColor(context, type));
}

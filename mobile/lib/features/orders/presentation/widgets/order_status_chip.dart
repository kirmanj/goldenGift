import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import 'order_labels.dart';

/// Colour family of a status (SRS §5.12 "status chip, colour per status"):
/// waiting = info blue, in progress = gold, delivered = green, left the flow = red.
enum OrderStatusTone { info, progress, success, error }

OrderStatusTone orderStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.pending || OrderStatus.confirmed => OrderStatusTone.info,
      OrderStatus.preparing || OrderStatus.readyForDelivery || OrderStatus.outForDelivery => OrderStatusTone.progress,
      OrderStatus.delivered => OrderStatusTone.success,
      OrderStatus.cancelledByBuyer ||
      OrderStatus.cancelledBySeller ||
      OrderStatus.returned ||
      OrderStatus.refunded =>
        OrderStatusTone.error,
    };

/// Foreground / background for a tone in the current theme. Semantic colours
/// are darkened on light surfaces and lifted on dark ones (as [InfoBanner]) so
/// the label keeps ≥ 4.5:1.
(Color fg, Color bg) orderStatusColors(BuildContext context, OrderStatusTone tone) {
  if (tone == OrderStatusTone.progress) return (AppColors.goldText(context), AppColors.soft(context));
  final base = switch (tone) {
    OrderStatusTone.info => AppColors.info,
    OrderStatusTone.success => AppColors.success,
    _ => AppColors.error,
  };
  final type = switch (tone) {
    OrderStatusTone.info => InfoBannerType.info,
    OrderStatusTone.success => InfoBannerType.success,
    _ => InfoBannerType.error,
  };
  final fg = AppColors.isDark(context)
      ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), base)
      : Color.alphaBlend(AppColors.black.withValues(alpha: 0.3), base);
  return (fg, InfoBanner.softColor(context, type));
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status, this.compact = false});

  final OrderStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = orderStatusColors(context, orderStatusTone(status));
    return Container(
      key: ValueKey('status-chip-${status.name}'),
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.sm + AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        orderStatusLabel(AppLocalizations.of(context)!, status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: fg),
      ),
    );
  }
}

/// Payment status colour (Order Details, SRS §5.12): not paid yet = info blue,
/// paid = green, failed = red, refunded = gold.
OrderStatusTone paymentStatusTone(PaymentStatus status) => switch (status) {
      PaymentStatus.pending => OrderStatusTone.info,
      PaymentStatus.paid => OrderStatusTone.success,
      PaymentStatus.failed => OrderStatusTone.error,
      PaymentStatus.refunded => OrderStatusTone.progress,
    };

class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = orderStatusColors(context, paymentStatusTone(status));
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm + AppSpacing.xs, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(
        paymentStatusLabel(AppLocalizations.of(context)!, status),
        style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, height: 1.3, color: fg),
      ),
    );
  }
}

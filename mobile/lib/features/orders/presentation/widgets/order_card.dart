import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/order_model.dart';
import 'order_status_chip.dart';

/// Leaves a page; with nothing underneath (opened via `go` or a deep link) it
/// goes to [fallback] instead of closing the app.
void popOrGo(BuildContext context, String fallback) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    context.go(fallback);
  }
}

/// One order in the list (SRS §5.12): number, date, status chip, the first
/// item thumbnails and the total.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  static const maxThumbnails = 3;
  static const double thumbSize = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final thumbs = order.items.take(maxThumbnails).toList();
    final extra = order.items.length - thumbs.length;

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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderNumber(order.orderNumber),
                          style: AppTextStyles.label.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.text(context),
                          ),
                        ),
                        if (order.createdAt != null)
                          Text(
                            AppDates.display(order.createdAt!),
                            style: AppTextStyles.bodySmall.copyWith(color: muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: OrderStatusChip(status: order.status)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final item in thumbs)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: SizedBox.square(
                              dimension: thumbSize,
                              child: GGNetworkImage(url: item.line.imageSnapshot),
                            ),
                          ),
                        ),
                      if (extra > 0)
                        Container(
                          width: thumbSize,
                          height: thumbSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.field(context),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '+$extra',
                            textDirection: TextDirection.ltr,
                            style: AppTextStyles.label.copyWith(fontSize: 14, color: muted),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    CurrencyFormatter.format(order.total),
                    key: ValueKey('order-total-${order.id}'),
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.label.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.goldText(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

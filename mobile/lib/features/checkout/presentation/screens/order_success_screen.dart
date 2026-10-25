import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../orders/data/orders_repository.dart';
import '../../../orders/presentation/widgets/order_labels.dart';

/// Order Success (SRS §5.11): order number, estimated delivery, Track order /
/// Continue shopping. Back never returns to Checkout — it goes to Main.
class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({super.key, required this.orderId});
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final orderAsync = ref.watch(orderByIdProvider(orderId));
    final order = orderAsync.valueOrNull;
    final slots = ref.watch(generalSettingsProvider).valueOrNull?.deliverySlots ?? DeliverySlot.defaults;
    final muted = AppColors.textMuted(context);
    final bottom = math.max(AppSpacing.lg, MediaQuery.paddingOf(context).bottom + AppSpacing.md);

    final Widget body;
    if (order != null && order.orderNumber.isNotEmpty) {
      body = Text(
        l10n.orderPlacedBody(order.orderNumber),
        key: const ValueKey('order-placed-body'),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyLarge.copyWith(color: muted),
      );
    } else if (orderAsync.isLoading) {
      body = const SkeletonLoader.line(width: 220);
    } else {
      body = const SizedBox.shrink();
    }
    final when = order == null ? '' : deliveryWhen(context, order.deliveryDate, order.deliverySlot, slots);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.mainTab(0));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg(context),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding:
                  EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - AppSpacing.lg - bottom)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: _SuccessIllustration()),
                    const SizedBox(height: AppSpacing.lg),
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.orderPlacedTitle,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heading2.copyWith(color: AppColors.text(context)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Center(child: body),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        key: const ValueKey('order-eta'),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.card(context),
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: AppColors.line(context)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.local_shipping_outlined, color: AppColors.gold(context)),
                            const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.estimatedDelivery, style: AppTextStyles.bodySmall.copyWith(color: muted)),
                                  Text(
                                    when,
                                    style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      key: const ValueKey('track-order'),
                      label: l10n.trackOrder,
                      icon: Icons.local_shipping_outlined,
                      onPressed: () => context.go(AppRoutes.order(orderId)),
                    ),
                    const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                    OutlineButton(
                      key: const ValueKey('continue-shopping'),
                      label: l10n.continueShopping,
                      onPressed: () => context.go(AppRoutes.mainTab(0)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessIllustration extends StatelessWidget {
  const _SuccessIllustration();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 148,
          height: 148,
          decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
          child: Center(
            child: Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(gradient: AppColors.headerGradient, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 52, color: AppColors.textOnPrimary),
            ),
          ),
        ),
      );
}

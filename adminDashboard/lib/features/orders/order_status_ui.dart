import 'package:flutter/material.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/theme/app_colors.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/models/order_model.dart';

import '../../core/session/admin_session.dart';

/// English labels for the dashboard (the app localizes its own).
String orderStatusLabel(OrderStatus s) => switch (s) {
      OrderStatus.pending => 'Pending',
      OrderStatus.confirmed => 'Confirmed',
      OrderStatus.preparing => 'Preparing',
      OrderStatus.readyForDelivery => 'Ready for delivery',
      OrderStatus.outForDelivery => 'Out for delivery',
      OrderStatus.delivered => 'Delivered',
      OrderStatus.cancelledByBuyer => 'Cancelled by customer',
      OrderStatus.cancelledBySeller => 'Cancelled by us',
      OrderStatus.returned => 'Returned',
      OrderStatus.refunded => 'Refunded',
    };

String paymentMethodLabel(PaymentMethod m) => switch (m) {
      PaymentMethod.cashOnDelivery => 'Cash on delivery',
      PaymentMethod.wallet => 'Wallet',
      PaymentMethod.card => 'Card',
      PaymentMethod.fastPay => 'FastPay',
      PaymentMethod.zainCash => 'ZainCash',
    };

/// Same colour families as the app's order chips.
Color orderStatusColor(OrderStatus s) => switch (s) {
      OrderStatus.pending || OrderStatus.confirmed => AppColors.info,
      OrderStatus.preparing || OrderStatus.readyForDelivery || OrderStatus.outForDelivery => AppColors.primaryDark,
      OrderStatus.delivered => AppColors.success,
      _ => AppColors.error,
    };

/// Transitions that leave the happy path need a reason for the customer.
bool statusNeedsNote(OrderStatus next) =>
    next == OrderStatus.cancelledBySeller || next == OrderStatus.returned || next == OrderStatus.refunded;

/// Who may move orders: ops + super admins every transition; finance only
/// refunds; content editors and sellers (Phase 8) none.
List<OrderStatus> staffTransitions(AdminSession session, OrderStatus current) {
  final next = current.allowedNext;
  return switch (session.role) {
    AdminRole.superAdmin || AdminRole.ops => next,
    AdminRole.finance => next.where((s) => s == OrderStatus.refunded).toList(),
    AdminRole.content || AdminRole.seller => const [],
  };
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final color = orderStatusColor(status);
    final fg = AppColors.isDark(context) && color == AppColors.primaryDark ? AppColors.accent : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(orderStatusLabel(status),
          style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// An online payment (ZainCash / card) that hasn't arrived yet: ops must not
/// prepare the order — it is cancelled automatically when unpaid (SRS §5.11).
bool awaitingOnlinePayment(OrderModel o) =>
    const {PaymentMethod.zainCash, PaymentMethod.fastPay, PaymentMethod.card}.contains(o.paymentMethod) &&
    o.paymentStatus == PaymentStatus.pending &&
    !o.status.isFinal &&
    o.status.tab != OrderTab.cancelled;

class AwaitingPaymentChip extends StatelessWidget {
  const AwaitingPaymentChip({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        child: const Text('Awaiting payment',
            style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}


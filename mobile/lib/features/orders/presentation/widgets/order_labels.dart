import 'package:flutter/widgets.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';

/// Localized labels for order enums (SRS §5.12, §6.15).

String orderStatusLabel(AppLocalizations l10n, OrderStatus status) => switch (status) {
      OrderStatus.pending => l10n.statusPending,
      OrderStatus.confirmed => l10n.statusConfirmed,
      OrderStatus.preparing => l10n.statusPreparing,
      OrderStatus.readyForDelivery => l10n.statusReadyForDelivery,
      OrderStatus.outForDelivery => l10n.statusOutForDelivery,
      OrderStatus.delivered => l10n.statusDelivered,
      OrderStatus.cancelledByBuyer => l10n.statusCancelledByBuyer,
      OrderStatus.cancelledBySeller => l10n.statusCancelledBySeller,
      OrderStatus.returned => l10n.statusReturned,
      OrderStatus.refunded => l10n.statusRefunded,
    };

/// ZainCash (Phase 9) by name; card and FastPay read "Card / e-wallet".
String paymentMethodLabel(AppLocalizations l10n, PaymentMethod method) => switch (method) {
      PaymentMethod.cashOnDelivery => l10n.cashOnDelivery,
      PaymentMethod.wallet => l10n.walletPayment,
      PaymentMethod.zainCash => l10n.paymentZainCash,
      PaymentMethod.card || PaymentMethod.fastPay => l10n.cardPayment,
    };

/// A timeline note / `cancelReason`: the system's codes for an online payment
/// that failed or ran out of time (SRS §6.7) are translated; reasons typed by
/// the customer or staff are shown as written.
String orderNoteText(AppLocalizations l10n, String note) => switch (note) {
      'payment_failed' => l10n.orderCancelReasonPaymentFailed,
      'payment_expired' => l10n.orderCancelReasonPaymentExpired,
      _ => note,
    };

String paymentStatusLabel(AppLocalizations l10n, PaymentStatus status) => switch (status) {
      PaymentStatus.pending => l10n.paymentStatusPending,
      PaymentStatus.paid => l10n.paymentStatusPaid,
      PaymentStatus.failed => l10n.paymentStatusFailed,
      PaymentStatus.refunded => l10n.paymentStatusRefunded,
    };

/// Unicode isolates keep "10:00–14:00" left-to-right inside Arabic / Kurdish text.
final _lri = String.fromCharCode(0x2066);
final _pdi = String.fromCharCode(0x2069);

String slotTimeRange(DeliverySlot slot) => '$_lri${slot.from}–${slot.to}$_pdi';

/// "Morning · 10:00–14:00"; the raw id when the slot is no longer configured.
String? deliverySlotLabel(BuildContext context, String? slotId, List<DeliverySlot> slots) {
  if (slotId == null || slotId.isEmpty) return null;
  final slot = slots.where((s) => s.id == slotId).firstOrNull;
  if (slot == null) return slotId;
  final name = slot.label.of(context);
  return name.isEmpty ? slotTimeRange(slot) : '$name · ${slotTimeRange(slot)}';
}

/// "02/11/2026 · Morning · 10:00–14:00".
String deliveryWhen(BuildContext context, DateTime? date, String? slotId, List<DeliverySlot> slots) {
  final slot = deliverySlotLabel(context, slotId, slots);
  return [if (date != null) AppDates.display(date), if (slot != null) slot].join(' · ');
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

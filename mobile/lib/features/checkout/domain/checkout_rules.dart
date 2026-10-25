import 'dart:math' as math;

import '../../../models/app_settings_model.dart';
import '../../../models/product_model.dart';
import '../../cart/presentation/providers/cart_lines.dart';

/// Pure checkout rules (SRS §5.11), shared by the screen and tests. The
/// `placeOrder` function re-checks everything server-side.
class CheckoutRules {
  CheckoutRules._();

  /// "14:00" → (14, 0); null when malformed.
  static (int, int)? parseHm(String value) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  static bool _atOrAfter(DateTime now, (int, int) hm) =>
      now.hour > hm.$1 || (now.hour == hm.$1 && now.minute >= hm.$2);

  /// today + max(preparationDays), +1 day when ordering after the cut-off.
  static DateTime earliestDeliveryDate({
    required DateTime now,
    required int maxPreparationDays,
    required String sameDayCutoff,
  }) {
    final cutoff = parseHm(sameDayCutoff) ?? (14, 0);
    final days = maxPreparationDays + (_atOrAfter(now, cutoff) ? 1 : 0);
    return DateTime(now.year, now.month, now.day + days);
  }

  /// The dates offered in the date picker row.
  static List<DateTime> deliveryDates(DateTime earliest, {int count = 14}) =>
      [for (var i = 0; i < count; i++) DateTime(earliest.year, earliest.month, earliest.day + i)];

  /// Slots still bookable on [date]: all of them on later days; on today only
  /// those that haven't started yet.
  static List<DeliverySlot> availableSlots(DateTime date, DateTime now, List<DeliverySlot> slots) {
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    if (!isToday) return slots;
    return slots.where((s) {
      final start = parseHm(s.from);
      return start != null && !_atOrAfter(now, start);
    }).toList();
  }

  /// Orderable lines that can't be delivered to [cityId] (SRS §4.3: rejected
  /// with a clear message per line).
  static List<CartLine> cityConflicts(CartSummary summary, Map<String, ProductModel> products, String cityId) => [
        for (final line in summary.lines)
          if (line.counts && !(products[line.item.productId]?.isAvailableIn(cityId) ?? true)) line,
      ];

  static CheckoutTotals totals({
    required int subtotal,
    required int deliveryFee,
    int discount = 0,
    int credits = 0,
    int wallet = 0,
  }) {
    final beforePayments = math.max(0, subtotal - discount) + deliveryFee;
    final creditsUsed = math.min(credits, beforePayments);
    final walletUsed = math.min(wallet, beforePayments - creditsUsed);
    return CheckoutTotals(
      subtotal: subtotal,
      discount: math.min(discount, subtotal),
      deliveryFee: deliveryFee,
      creditsUsed: creditsUsed,
      walletUsed: walletUsed,
      total: beforePayments - creditsUsed - walletUsed,
    );
  }

  static bool meetsMinimum(int subtotal, int minOrder) => minOrder <= 0 || subtotal >= minOrder;
}

class CheckoutTotals {
  const CheckoutTotals({
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.creditsUsed,
    required this.walletUsed,
    required this.total,
  });

  final int subtotal;
  final int discount;
  final int deliveryFee;
  final int creditsUsed;
  final int walletUsed;

  /// To pay on delivery (or online).
  final int total;
}

import 'dart:math' as math;

import '../../models/promo_code_model.dart';

/// Why a code can't be used (mapped to localized text by the UI). The same
/// names are the `reason` of `placeOrder`'s `failed-precondition` errors.
enum PromoRejection { notFound, inactive, expired, minOrder, usageLimit, perUserLimit, firstOrderOnly, notApplicable }

/// One cart line as the promo rules see it.
class PromoLine {
  const PromoLine({required this.productId, required this.storeId, required this.categoryIds, required this.lineTotal});
  final String productId;
  final String storeId;
  final List<String> categoryIds;
  final int lineTotal;
}

class PromoEvaluation {
  const PromoEvaluation.ok(this.discount, this.eligibleSubtotal) : rejection = null;
  const PromoEvaluation.rejected(PromoRejection this.rejection)
      : discount = 0,
        eligibleSubtotal = 0;

  final int discount;

  /// Subtotal of the lines the code applies to.
  final int eligibleSubtotal;
  final PromoRejection? rejection;

  bool get isValid => rejection == null;
}

/// SRS §5.23 / §6.9 promo maths — MUST stay identical to
/// functions/src/orders/promoRules.ts; both are checked against
/// test/fixtures/promo_cases.json.
///
/// - `minOrder` is compared with the whole cart subtotal; the discount is
///   computed on the eligible lines only (category / store restriction).
/// - percent: floor(eligible × value / 100), capped by `maxDiscount`;
///   fixed: min(value, eligible). Never more than the eligible subtotal.
/// - `usageLimit` counts every customer; `perUserLimit` 0 = unlimited.
/// - `firstOrderOnly` = the customer has no previous non-cancelled order.
class PromoRules {
  PromoRules._();

  static PromoEvaluation evaluate(
    PromoCodeModel? promo, {
    required List<PromoLine> lines,
    required DateTime now,
    int userUsageCount = 0,
    int userOrderCount = 0,
  }) {
    if (promo == null) return const PromoEvaluation.rejected(PromoRejection.notFound);
    if (!promo.isActive || promo.value <= 0) return const PromoEvaluation.rejected(PromoRejection.inactive);
    if (promo.expiresAt != null && !now.isBefore(promo.expiresAt!)) {
      return const PromoEvaluation.rejected(PromoRejection.expired);
    }
    if (promo.usageLimit != null && promo.usageCount >= promo.usageLimit!) {
      return const PromoEvaluation.rejected(PromoRejection.usageLimit);
    }
    if (promo.perUserLimit > 0 && userUsageCount >= promo.perUserLimit) {
      return const PromoEvaluation.rejected(PromoRejection.perUserLimit);
    }
    if (promo.firstOrderOnly && userOrderCount > 0) return const PromoEvaluation.rejected(PromoRejection.firstOrderOnly);

    final subtotal = lines.fold<int>(0, (s, l) => s + l.lineTotal);
    if (promo.minOrder != null && subtotal < promo.minOrder!) return const PromoEvaluation.rejected(PromoRejection.minOrder);

    bool applies(PromoLine l) =>
        (promo.categoryIds.isEmpty || l.categoryIds.any(promo.categoryIds.contains)) &&
        (promo.storeIds.isEmpty || promo.storeIds.contains(l.storeId));
    final eligible = lines.where(applies).fold<int>(0, (s, l) => s + l.lineTotal);
    if (eligible <= 0) return const PromoEvaluation.rejected(PromoRejection.notApplicable);

    var discount = switch (promo.type) {
      PromoType.percent => eligible * math.min(promo.value, 100) ~/ 100,
      PromoType.fixed => promo.value,
    };
    if (promo.maxDiscount != null && promo.maxDiscount! > 0) discount = math.min(discount, promo.maxDiscount!);
    return PromoEvaluation.ok(math.min(discount, eligible), eligible);
  }
}

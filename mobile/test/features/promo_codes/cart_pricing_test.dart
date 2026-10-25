import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/promo_rules.dart';
import 'package:golden_gift/features/promo_codes/presentation/providers/cart_pricing.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/promo_code_model.dart';

void main() {
  const promo = PromoCodeModel(code: 'GOLD10', title: LocalizedText('Gold'), type: PromoType.percent, value: 10);
  const ok = (promo, PromoEvaluation.ok(8000, 80000));
  const rejected = (promo, PromoEvaluation.rejected(PromoRejection.minOrder));

  test('no promo, no credits: total = subtotal', () {
    final p = CartPricing.compute(subtotal: 80000);
    expect((p.discount, p.creditsUsed, p.total, p.promoCode), (0, 0, 80000, null));
  });

  test('a valid promo is deducted and its code kept for placeOrder', () {
    final p = CartPricing.compute(subtotal: 80000, promo: ok);
    expect((p.discount, p.total, p.promoCode), (8000, 72000, 'GOLD10'));
  });

  test('a rejected promo deducts nothing', () {
    final p = CartPricing.compute(subtotal: 80000, promo: rejected);
    expect((p.discount, p.total, p.promoCode), (0, 80000, null));
  });

  test('credits only when the toggle is on, capped at what is still due', () {
    expect(CartPricing.compute(subtotal: 80000, credits: 5000).creditsUsed, 0);
    final some = CartPricing.compute(subtotal: 80000, promo: ok, credits: 5000, useCredits: true);
    expect((some.creditsUsed, some.total), (5000, 67000));
    final capped = CartPricing.compute(subtotal: 80000, promo: ok, credits: 100000, useCredits: true);
    expect((capped.creditsAvailable, capped.creditsUsed, capped.total), (100000, 72000, 0));
  });

  test('checkout: delivery is payable with credits too', () {
    final p = CartPricing.compute(subtotal: 80000, promo: ok, credits: 100000, useCredits: true, deliveryFee: 5000);
    expect((p.creditsUsed, p.total), (77000, 0));
    final partial = CartPricing.compute(subtotal: 80000, credits: 3000, useCredits: true, deliveryFee: 5000);
    expect(partial.total, 82000);
  });

  test('a discount never exceeds the subtotal; negative credits are ignored', () {
    final p = CartPricing.compute(
        subtotal: 5000, promo: (promo, const PromoEvaluation.ok(8000, 5000)), credits: -10, useCredits: true);
    expect((p.discount, p.creditsUsed, p.total), (5000, 0, 0));
  });
}

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/promo_rules.dart';
import '../../../../models/promo_code_model.dart';
import '../../../cart/presentation/providers/cart_lines.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../../data/promo_repository.dart';

typedef PromoResult = (PromoCodeModel?, PromoEvaluation);

/// The evaluation of the code that is applied *now*: null when no code is
/// applied or while it is being (re)checked for a different code, so a
/// previous code's result never leaks into the totals. A reload for the same
/// code (the cart changed) keeps showing the last result.
final currentPromoResultProvider = Provider.autoDispose<PromoResult?>((ref) {
  final applied = ref.watch(appliedPromoProvider);
  final eval = ref.watch(promoEvaluationProvider);
  final value = eval.valueOrNull;
  if (applied == null || value == null) return null;
  if (value.$1 == null) return eval.isLoading ? null : value; // notFound: can't tell which code it was for
  return value.$1!.code == applied ? value : null;
});

/// Cart / checkout money maths (SRS §5.10, §5.11): subtotal − promo discount
/// (+ delivery at checkout) − credits, credits capped at what is still due.
/// The server (`placeOrder`) recomputes all of it.
class CartPricing {
  const CartPricing({
    required this.subtotal,
    this.discount = 0,
    this.promoCode,
    this.creditsAvailable = 0,
    this.creditsUsed = 0,
    this.deliveryFee = 0,
  });

  final int subtotal;

  /// Promo discount (0 unless the applied code is valid for this cart).
  final int discount;

  /// The applied code when it is valid (what to send to `placeOrder`).
  final String? promoCode;
  final int creditsAvailable;
  final int creditsUsed;
  final int deliveryFee;

  int get total => subtotal - discount + deliveryFee - creditsUsed;

  static CartPricing compute({
    required int subtotal,
    PromoResult? promo,
    int credits = 0,
    bool useCredits = false,
    int deliveryFee = 0,
  }) {
    final valid = promo != null && promo.$2.isValid;
    final discount = valid ? math.min(math.max(0, promo.$2.discount), subtotal) : 0;
    final due = math.max(0, subtotal - discount + deliveryFee);
    final available = math.max(0, credits);
    return CartPricing(
      subtotal: subtotal,
      discount: discount,
      promoCode: valid ? promo.$1?.code : null,
      creditsAvailable: available,
      creditsUsed: useCredits ? math.min(available, due) : 0,
      deliveryFee: deliveryFee,
    );
  }
}

/// Credits the signed-in customer can spend (0 for guests / until the wallet loads).
final availableCreditsProvider = Provider.autoDispose<int>((ref) {
  if (!ref.watch(isSignedInProvider)) return 0;
  return ref.watch(walletProvider).valueOrNull?.credits ?? 0;
});

/// The cart's pricing before delivery; null while the cart lines load.
final cartPricingProvider = Provider.autoDispose<CartPricing?>((ref) {
  final summary = ref.watch(cartSummaryProvider).valueOrNull;
  if (summary == null) return null;
  return CartPricing.compute(
    subtotal: summary.subtotal,
    promo: ref.watch(currentPromoResultProvider),
    credits: ref.watch(availableCreditsProvider),
    useCredits: ref.watch(useCreditsProvider),
  );
});

import { HttpsError } from 'firebase-functions/v2/https';
import type { PromoRejection } from './promoRules';

/**
 * `details.reason` of the `failed-precondition` errors `placeOrder` / `cancelOrder`
 * throw. The app maps them in `OrderFailure.from`
 * (mobile/lib/features/orders/data/orders_repository.dart) — keep both in step.
 */
export const OrderFailureReason = [
  'cart_changed',
  'city_not_allowed',
  'out_of_stock',
  'min_order',
  'empty_cart',
  'not_cancellable',
  /** The promo code fails a §6.9 rule; `details.promoReason` = the PromoRejection name. */
  'promo_invalid',
  /** Wallet balance (+ credits) does not cover a `wallet` payment. */
  'insufficient_funds',
] as const;
export type OrderFailureReason = (typeof OrderFailureReason)[number];

const MESSAGES: Record<OrderFailureReason, string> = {
  cart_changed: 'Some items in your cart changed. Please review your cart.',
  city_not_allowed: "Some items can't be delivered to this city.",
  out_of_stock: 'Some items just sold out.',
  min_order: 'The order is below the minimum amount.',
  empty_cart: 'Your cart is empty.',
  not_cancellable: 'This order can no longer be cancelled.',
  promo_invalid: 'This promo code can no longer be used.',
  insufficient_funds: "Your wallet doesn't cover this order.",
};

/** `HttpsError('failed-precondition', msg, { reason, productIds? })`. */
export function orderFailure(reason: OrderFailureReason, productIds?: readonly string[]): HttpsError {
  const details: { reason: OrderFailureReason; productIds?: string[] } = { reason };
  if (productIds !== undefined) details.productIds = [...new Set(productIds)].sort();
  return new HttpsError('failed-precondition', MESSAGES[reason], details);
}

/** `HttpsError('failed-precondition', msg, { reason: 'promo_invalid', promoReason })`. */
export function promoFailure(promoReason: PromoRejection): HttpsError {
  return new HttpsError('failed-precondition', MESSAGES.promo_invalid, { reason: 'promo_invalid', promoReason });
}

/**
 * Partial cancellation of a multi-vendor order (SRS §6.7, §7 `updateOrderItems`):
 * a seller cancels THEIR lines (`cancelledBySeller`) while other lines stay on
 * the main flow, so the order itself is not cancelled and `onOrderStatusChange`
 * (which handles whole-order cancellations) does nothing for them. In the
 * seller's `updateOrderItems` transaction:
 *
 *  1. Stock: the lines' `stock` / option-value stock is released and `salesCount`
 *     lowered at once (releaseStock.ts); each line gets `stockReleased: true`, so
 *     no later cancellation of the order releases it twice.
 *  2. Money — the lines' value after their share of the promo discount, `R`
 *     (the discount is spread over the lines in proportion to their `lineTotal`;
 *     the delivery fee stays — the rest is still delivered), is split like the
 *     order was paid: a credits part `round(R × credits still on the order /
 *     what the order still holds)` and the rest as money. Then
 *       - nothing paid yet (cash on delivery): the credits part comes back as
 *         credits (a new `refund` lot), the money part is taken off what the
 *         courier collects — `subtotal`, `discount` and `total` are recomputed
 *         without the cancelled lines (`originalSubtotal` / `originalDiscount`
 *         keep the checkout figures);
 *       - already paid (wallet, ZainCash): the credits part back as credits, the
 *         money part to the wallet BALANCE (`refund` transactions), recorded in
 *         `refundedCredits` / `refundedBalance` — so a later full cancellation or
 *         refund (orderRefunds.ts) only pays what is still owed.
 *     An order still waiting for its online payment cannot be partly cancelled
 *     (`awaiting_payment`): its payment session is for the full amount.
 *  3. The customer is told which items were cancelled (an in-app notification in
 *     the same transaction; push after the commit).
 *
 * Once only: the lines move to `cancelledBySeller` in the same transaction, so a
 * retried call finds nothing left to cancel (`not_allowed`).
 */
import type { DocumentData } from 'firebase-admin/firestore';
import type { UserNotification } from '../notifications/notifyUser';
import type { Trilingual } from '../notifications/orderMessages';
import { ORDER_NOTIFICATION_TYPE } from '../notifications/orderMessages';
import { integer, mapList, string, stringOrNull } from '../shared/firestoreParse';
import { formatIqd } from '../wallet/walletTexts';

/** Line statuses that no longer count toward the order's value. */
export const CANCELLED_LINE_STATUSES: readonly string[] = ['cancelledByBuyer', 'cancelledBySeller'];

export interface LineCancellationPlan {
  /** Σ `lineTotal` of the lines cancelled now. */
  linesValue: number;
  /** Their share of the promo discount. */
  discountShare: number;
  /** What the lines were worth to the customer: `linesValue − discountShare` (capped by what the order still holds). */
  reduction: number;
  /** Back as credits (a new `refund` lot). */
  creditsBack: number;
  /** Paid: to the wallet balance. Unpaid: off the amount still to collect. */
  moneyBack: number;
  /** The order was paid already (`paymentStatus == paid`). */
  paid: boolean;
  /** Unpaid only: the recomputed figures (null for a paid order — its figures stay what was charged). */
  totals: { subtotal: number; discount: number; total: number; originalSubtotal: number; originalDiscount: number } | null;
}

/** Whether a line still counts (not cancelled). */
export function lineActive(item: Record<string, unknown>): boolean {
  return !CANCELLED_LINE_STATUSES.includes(string(item.status));
}

/**
 * The money side of cancelling `cancelledIds` (lines still active in `order`,
 * read in the transaction). Pure.
 */
export function planLineCancellation(order: DocumentData, cancelledIds: ReadonlySet<string>): LineCancellationPlan {
  const items = mapList(order.items);
  const lineTotal = (i: Record<string, unknown>) => Math.max(0, integer(i.lineTotal));
  const originalSubtotal = items.reduce((sum, i) => sum + lineTotal(i), 0);
  const originalDiscount = Math.max(0, Math.min(originalSubtotal, integer(order.originalDiscount ?? order.discount)));
  const cancelling = items.filter((i) => lineActive(i) && cancelledIds.has(string(i.id)));
  const activeBefore = items.filter(lineActive).reduce((sum, i) => sum + lineTotal(i), 0);
  const linesValue = cancelling.reduce((sum, i) => sum + lineTotal(i), 0);
  const activeAfter = Math.max(0, activeBefore - linesValue);

  // The discount spread over the active lines in proportion to their totals.
  const discountOn = (subtotal: number) =>
    originalSubtotal > 0 ? Math.min(subtotal, Math.round((originalDiscount * subtotal) / originalSubtotal)) : 0;
  const discountBefore = discountOn(activeBefore);
  const discountAfter = discountOn(activeAfter);
  const discountShare = Math.max(0, discountBefore - discountAfter);

  const paid = order.paymentStatus === 'paid';
  const fee = Math.max(0, integer(order.deliveryFee));
  const credits = Math.max(0, integer(order.creditsUsed) - Math.max(0, integer(order.refundedCredits)));
  const total = Math.max(0, integer(order.total));
  const money = paid
    ? Math.max(0, Math.max(0, integer(order.walletUsed)) + total - Math.max(0, integer(order.refundedBalance)))
    : total;
  const holds = credits + money;

  // Never more than the order still holds beyond its delivery fee (other lines are still delivered).
  const reduction = Math.max(0, Math.min(linesValue - discountShare, holds - fee));
  let creditsBack = holds > 0 ? Math.min(credits, reduction, Math.round((reduction * credits) / holds)) : 0;
  const moneyBack = Math.min(money, reduction - creditsBack);
  creditsBack = Math.min(credits, reduction - moneyBack);

  return {
    linesValue,
    discountShare,
    reduction,
    creditsBack,
    moneyBack,
    paid,
    totals: paid
      ? null
      : {
          subtotal: activeAfter,
          discount: discountAfter,
          total: Math.max(0, total - moneyBack),
          originalSubtotal,
          originalDiscount,
        },
  };
}

/** The line's title in each language (the order snapshot), English as the fallback. */
function lineTitles(item: Record<string, unknown>): Trilingual {
  const en = string(item.titleSnapshot) || 'Item';
  return {
    en,
    ar: stringOrNull(item.titleSnapshotAr) ?? en,
    ku: stringOrNull(item.titleSnapshotKu) ?? en,
  };
}

/** "Some items of order GG-… were cancelled" with the items and what happens to the money. */
export function itemsCancelledNotification(
  order: { orderId: string; orderNumber: string },
  lines: ReadonlyArray<Record<string, unknown>>,
  plan: Pick<LineCancellationPlan, 'creditsBack' | 'moneyBack' | 'paid'>,
  reason: string | null,
): UserNotification {
  const names = lines.map(lineTitles);
  const list = (lang: keyof Trilingual, sep: string) => names.map((n) => n[lang]).join(sep);
  const amount = formatIqd(plan.creditsBack + plan.moneyBack);
  const back = plan.creditsBack + plan.moneyBack > 0;
  const money: Trilingual = !back
    ? { en: '', ar: '', ku: '' }
    : plan.paid
      ? {
          en: ` ${amount} went back to your wallet.`,
          ar: ` أُعيد ${amount} إلى محفظتك.`,
          ku: ` ${amount} گەڕایەوە بۆ جزدانەکەت.`,
        }
      : plan.moneyBack > 0
        ? {
            en: ` Your order total is now ${amount} lower.`,
            ar: ` أصبح إجمالي طلبك أقل بـ ${amount}.`,
            ku: ` کۆی داواکارییەکەت ${amount} کەمتر بوو.`,
          }
        : {
            en: ` ${amount} went back to your wallet credits.`,
            ar: ` أُعيد ${amount} إلى مكافآتك.`,
            ku: ` ${amount} گەڕایەوە بۆ خاڵەکانت.`,
          };
  const why = reason?.trim()
    ? { en: ` Reason: ${reason.trim()}.`, ar: ` السبب: ${reason.trim()}.`, ku: ` هۆکار: ${reason.trim()}.` }
    : { en: '', ar: '', ku: '' };
  return {
    type: ORDER_NOTIFICATION_TYPE,
    title: {
      en: `Some items of order ${order.orderNumber} were cancelled`,
      ar: `أُلغيت بعض منتجات الطلب ${order.orderNumber}`,
      ku: `هەندێک بەرهەمی داواکاری ${order.orderNumber} هەڵوەشێنرانەوە`,
    },
    body: {
      en: `The store cancelled: ${list('en', ', ')}. The rest of your order is on its way.${why.en}${money.en}`,
      ar: `ألغى المتجر: ${list('ar', '، ')}. باقي طلبك في الطريق.${why.ar}${money.ar}`,
      ku: `فرۆشگاکە ئەمانەی هەڵوەشاندەوە: ${list('ku', '، ')}. بەشەکەی تری داواکارییەکەت لە ڕێگادایە.${why.ku}${money.ku}`,
    },
    route: `/orders/${order.orderId}`,
    id: order.orderId,
  };
}

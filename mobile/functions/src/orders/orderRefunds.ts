/**
 * Money back to the wallet (SRS §5.18, §9 Orders "refund to wallet", Phase 7).
 *
 *  - Cancellation (`cancelOrder`, or `onOrderStatusChange` for a cancellation the
 *    dashboard made): what the order took from the wallet goes back — `creditsUsed`
 *    as a NEW credit lot (source `refund`, expiring `creditsExpiryDays` from now),
 *    `walletUsed` to the balance — and the promo usage is released
 *    (`usageCount` − 1, `usages/{uid}.count` − 1).
 *  - A cancelled order that was paid online (ZainCash, Phase 9) also gets its
 *    paid `total` back to the balance.
 *  - `refunded` (admin, `onOrderStatusChange`): additionally, when the order was
 *    PAID, the money collected for it (`total`: cash on delivery / card) goes to
 *    the balance. An unpaid order only gets its credits / wallet back.
 *
 * Exactly once, whatever replays: the order keeps what has already been returned
 * (`refundedCredits`, `refundedBalance`; `refundedToWallet` = anything was) and a
 * refund only pays the difference. `paymentStatus` becomes `refunded` once
 * everything the customer paid is back.
 */
import { FieldValue, type DocumentData, type DocumentReference, type Firestore, type Transaction } from 'firebase-admin/firestore';
import { integer, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { creditExpiryAt, parseReferralSettings } from '../wallet/walletSettings';
import { orderRefundTitle } from '../wallet/walletTexts';

export type RefundKind = 'cancel' | 'refund';

/** Payment methods collected before delivery through a gateway (paid at checkout). */
export const ONLINE_PAYMENT_METHODS: readonly unknown[] = ['card', 'fastPay', 'zainCash'];

export interface RefundPlan {
  /** Credits to return (new lot). */
  credits: number;
  /** IQD to add to the balance. */
  balance: number;
  /** `paymentStatus` → `refunded` (everything paid is back). */
  markRefunded: boolean;
}

/** What is still owed to the customer for `order` (pure). */
export function refundPlan(order: DocumentData, kind: RefundKind): RefundPlan {
  const creditsUsed = Math.max(0, integer(order.creditsUsed));
  const walletUsed = Math.max(0, integer(order.walletUsed));
  const total = Math.max(0, integer(order.total));
  const paid = order.paymentStatus === 'paid';
  const refundedCredits = Math.max(0, integer(order.refundedCredits));
  const refundedBalance = Math.max(0, integer(order.refundedBalance));

  const credits = Math.max(0, creditsUsed - refundedCredits);
  // A cancelled order that was already paid ONLINE (Phase 9 gateways) gives the
  // paid total back too; cash on delivery is only ever paid on delivery.
  const paidOnline = paid && ONLINE_PAYMENT_METHODS.includes(order.paymentMethod);
  const balanceDue = walletUsed + ((kind === 'refund' && paid) || paidOnline ? total : 0);
  const balance = Math.max(0, balanceDue - refundedBalance);
  const markRefunded = paid && refundedBalance + balance >= walletUsed + total;
  return { credits, balance, markRefunded };
}

/** A promo code that can be a document id (anything else was never applied). */
function promoDocId(v: unknown): string | null {
  const code = stringOrNull(v);
  if (code === null || code.length > 64 || code.includes('/') || code === '.' || code === '..' || /^__.*__$/.test(code)) {
    return null;
  }
  return code;
}

export interface PreparedRefund {
  plan: RefundPlan;
  /** Whether the promo usage is released. */
  releasesPromo: boolean;
  /** Stages the wallet / promo writes; returns the fields to merge into the order update. */
  apply(): Record<string, unknown>;
}

/**
 * Reads (in `tx`) what a refund of `order` needs. Call before the transaction's
 * first write; call `apply()` with the other writes. `order` must be the order
 * as read in `tx`.
 */
export async function prepareOrderRefund(
  db: Firestore,
  tx: Transaction,
  orderId: string,
  order: DocumentData,
  kind: RefundKind,
  nowMs: number,
): Promise<PreparedRefund> {
  const uid = stringOrNull(order.userId);
  const plan = refundPlan(order, kind);
  const moves = uid !== null && plan.credits + plan.balance > 0;
  const promoId = kind === 'cancel' && order.promoReleased !== true && uid !== null ? promoDocId(order.promoCode) : null;

  // ── Reads ──
  const wallet = moves ? await readWallet(db, tx, uid) : null;
  const settings =
    moves && plan.credits > 0
      ? parseReferralSettings((await tx.get(db.collection(P.appSettings).doc('referral'))).data())
      : null;
  let promo: { ref: DocumentReference; count: number } | null = null;
  let usage: { ref: DocumentReference; count: number } | null = null;
  if (promoId !== null) {
    const promoRef = db.collection(P.promoCodes).doc(promoId);
    const usageRef = promoRef.collection(P.usages).doc(uid!);
    const [promoSnap, usageSnap] = await tx.getAll(promoRef, usageRef);
    if (promoSnap.exists) promo = { ref: promoRef, count: integer(promoSnap.get('usageCount')) };
    if (usageSnap.exists) usage = { ref: usageRef, count: integer(usageSnap.get('count')) };
  }

  return {
    plan,
    releasesPromo: promoId !== null,
    apply: () => {
      const update: Record<string, unknown> = {};
      if (wallet !== null) {
        const ledger = new WalletLedger(tx, wallet);
        const txn = { type: 'refund' as const, title: orderRefundTitle(string(order.orderNumber)), orderId };
        if (plan.credits > 0) {
          ledger.addCredits(plan.credits, txn, {
            source: 'refund',
            expiresAtMs: creditExpiryAt(nowMs, settings?.creditsExpiryDays ?? 0),
            orderId,
          });
        }
        if (plan.balance > 0) ledger.addBalance(plan.balance, txn);
        ledger.apply();
        update.refundedCredits = Math.max(0, integer(order.refundedCredits)) + plan.credits;
        update.refundedBalance = Math.max(0, integer(order.refundedBalance)) + plan.balance;
        update.refundedToWallet = true;
        update.refundedAt = FieldValue.serverTimestamp();
      }
      if (plan.markRefunded) update.paymentStatus = 'refunded';
      if (promoId !== null) {
        if (promo !== null) tx.update(promo.ref, { usageCount: Math.max(0, promo.count - 1) });
        if (usage !== null) {
          tx.update(usage.ref, { count: Math.max(0, usage.count - 1), updatedAt: FieldValue.serverTimestamp() });
        }
        update.promoReleased = true;
      }
      return update;
    },
  };
}

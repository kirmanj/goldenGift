/**
 * Applies a VERIFIED gateway verdict to `payment_sessions/{id}` in one
 * transaction (SRS §5.11, §5.18, §6.14) — the only code that marks an online
 * payment paid or failed. Called by `zainCashReturn` (redirect token verified
 * with the merchant secret) and `expirePaymentSessions` (the gateway's own
 * server-to-server status check, before a session is given up).
 *
 *  - paid, order still awaiting payment → order `paymentStatus: 'paid'`,
 *    `paymentRef` (gateway transaction id), `paidAt`; then the "order received"
 *    notification (placeOrder skips it for gateway orders);
 *  - paid, order no longer awaiting it (cancelled, expired, paid by another
 *    session) → the amount goes to the wallet BALANCE (`refund` transaction), so
 *    money is never lost;
 *  - paid top-up → `topUp` transaction on the balance;
 *  - failed (session still pending) → session `failed` and, if the order still
 *    awaits payment, the order is cancelled through the customer-cancellation
 *    path (stock, promo and credits back; `cancelReason: 'payment_failed'`,
 *    `paymentStatus: 'failed'`);
 *  - pending → nothing.
 *
 * Exactly once: `paid` is final (a replayed token changes nothing), wallet
 * transactions have fixed ids (`topUp-{sessionId}-1`, `payment-{sessionId}-1`),
 * and a verdict whose gateway transaction id differs from the session's is refused.
 */
import { FieldValue, Timestamp, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { notifyUser } from '../notifications/notifyUser';
import { orderStatusNotification } from '../notifications/orderMessages';
import type { PushMessaging } from '../notifications/push';
import { CUSTOMER_CANCELLABLE, prepareCancellation } from '../orders/cancelOrder';
import { integer, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { PAYMENT_FAILED_REASON, TOP_UP_TITLE, latePaymentTitle } from './paymentTexts';
import type { GatewayOutcome } from './zainCash';

export const SessionStatus = ['pending', 'paid', 'failed', 'expired'] as const;
export type SessionStatus = (typeof SessionStatus)[number];
export type SessionPurpose = 'order' | 'topUp';

export interface GatewayVerdict {
  outcome: GatewayOutcome;
  transactionId: string;
  rawStatus: string;
  message: string | null;
}

export interface SettleDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info' | 'error'>;
}

export type SettleResult =
  | { found: false }
  | {
      found: true;
      status: SessionStatus;
      purpose: SessionPurpose;
      orderId: string | null;
      /** This call changed the session. */
      changed: boolean;
      /** The verdict names another gateway transaction than the session's: refused. */
      mismatch?: boolean;
      /** paid: the order was marked paid / the amount went to the wallet. */
      effect?: 'orderPaid' | 'walletCredited' | 'toppedUp' | 'orderCancelled' | 'none';
    };

/** Whether `order` (owned by `uid`) still waits for an online payment. */
export function awaitsPayment(order: DocumentData | undefined, uid: string, gateway: string): boolean {
  return (
    order !== undefined &&
    order.userId === uid &&
    order.paymentMethod === gateway &&
    order.paymentStatus === 'pending' &&
    (CUSTOMER_CANCELLABLE as readonly string[]).includes(string(order.status))
  );
}

export async function settlePaymentSession(
  deps: SettleDeps,
  sessionId: string,
  verdict: GatewayVerdict,
): Promise<SettleResult> {
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const nowMs = (deps.now ?? Date.now)();
  const sessionRef = db.collection(P.paymentSessions).doc(sessionId);

  let notifyOrder: { orderId: string; uid: string; orderNumber: string } | null = null;
  const result = await db.runTransaction(async (tx): Promise<SettleResult> => {
    notifyOrder = null; // the transaction may run more than once
    // ── Reads ──
    const snap = await tx.get(sessionRef);
    const session = snap.data();
    if (session === undefined) return { found: false };
    const status = string(session.status) as SessionStatus;
    const purpose: SessionPurpose = session.purpose === 'topUp' ? 'topUp' : 'order';
    const orderId = stringOrNull(session.orderId);
    const uid = string(session.uid);
    const base = { found: true as const, purpose, orderId };
    const known = stringOrNull(session.gatewayTxnId);
    if (known !== null && known !== verdict.transactionId) return { ...base, status, changed: false, mismatch: true };
    if (verdict.outcome === 'pending' || status === 'paid') return { ...base, status, changed: false, effect: 'none' };
    if (verdict.outcome === 'failed' && status !== 'pending') return { ...base, status, changed: false, effect: 'none' };

    const orderRef = orderId === null ? null : db.collection(P.orders).doc(orderId);
    const order = orderRef === null ? undefined : (await tx.get(orderRef)).data();
    const awaiting = purpose === 'order' && awaitsPayment(order, uid, string(session.gateway));
    const amount = Math.max(0, integer(session.amount));
    const ts = FieldValue.serverTimestamp();
    const sessionUpdate: Record<string, unknown> = {
      gatewayTxnId: verdict.transactionId,
      gatewayStatus: verdict.rawStatus || null,
      settledAt: ts,
      updatedAt: ts,
    };

    if (verdict.outcome === 'failed') {
      const cancellation =
        awaiting && orderRef !== null
          ? await prepareCancellation(db, tx, orderRef, order!, {
              reason: PAYMENT_FAILED_REASON,
              note: null,
              byUid: null,
              byRole: 'system',
              nowMs,
              orderFields: { paymentStatus: 'failed' },
            })
          : null;
      // ── Writes ──
      tx.update(sessionRef, { ...sessionUpdate, status: 'failed', failureReason: verdict.message ?? (verdict.rawStatus || 'failed') });
      cancellation?.apply();
      return { ...base, status: 'failed', changed: true, effect: cancellation === null ? 'none' : 'orderCancelled' };
    }

    // ── paid ──
    const credit = purpose === 'topUp' || !awaiting;
    const wallet = credit && amount > 0 && uid.length > 0 ? await readWallet(db, tx, uid) : null;

    // ── Writes ──
    let effect: 'orderPaid' | 'walletCredited' | 'toppedUp' | 'none' = 'none';
    let walletTxnId: string | null = null;
    if (purpose === 'order' && awaiting && orderRef !== null) {
      tx.update(orderRef, {
        paymentStatus: 'paid',
        paymentRef: verdict.transactionId,
        paidAt: Timestamp.fromMillis(nowMs),
        updatedAt: ts,
      });
      effect = 'orderPaid';
    } else if (wallet !== null) {
      const topUp = purpose === 'topUp';
      const ledger = new WalletLedger(tx, wallet, { idPrefix: `${topUp ? 'topUp' : 'payment'}-${sessionId}` });
      const entry = ledger.addBalance(amount, {
        type: topUp ? 'topUp' : 'refund',
        title: topUp ? TOP_UP_TITLE : latePaymentTitle(string(session.orderNumber) || string(order?.orderNumber)),
        orderId,
      });
      ledger.apply();
      walletTxnId = entry.txnId;
      effect = topUp ? 'toppedUp' : 'walletCredited';
    }
    tx.update(sessionRef, {
      ...sessionUpdate,
      status: 'paid',
      paidAt: ts,
      creditedToWallet: effect === 'walletCredited' || effect === 'toppedUp',
      walletTxnId,
      // A late payment for an order that stopped waiting is noted for support.
      ...(status !== 'pending' && { lateFrom: status }),
    });
    if (effect === 'orderPaid' && orderId !== null) notifyOrder = { orderId, uid, orderNumber: string(order?.orderNumber) };
    return { ...base, status: 'paid', changed: true, effect };
  });

  if (result.found && result.mismatch) {
    log.error('payment: verdict for another gateway transaction refused', { sessionId, transactionId: verdict.transactionId });
  }
  const n = notifyOrder as { orderId: string; uid: string; orderNumber: string } | null;
  if (n !== null) {
    await notifyUser(
      { db, messaging: deps.messaging, logger: log },
      n.uid,
      orderStatusNotification('pending', { orderId: n.orderId, orderNumber: n.orderNumber }),
      { notificationId: `${n.orderId}-placed` },
    ).catch((e: unknown) =>
      log.warn('payment: order notification failed', { orderId: n.orderId, error: e instanceof Error ? e.message : String(e) }),
    );
  }
  return result;
}

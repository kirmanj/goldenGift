/**
 * `expirePaymentSessions` (scheduled every 15 minutes, SRS §7):
 *
 *  1. Sessions still `pending` after `expiresAt`: when the gateway transaction
 *     exists, its status is checked server-to-server first (the customer may have
 *     paid and never come back through `zainCashReturn`) — completed → settled as
 *     paid, failed → settled as failed; otherwise (still pending, no answer, never
 *     created) the session becomes `expired`.
 *  2. Gateway orders still unpaid after `paymentDueBy` and still pending /
 *     confirmed → cancelled through the customer-cancellation path (stock, promo
 *     and credits back; `cancelReason: 'payment_expired'`, `paymentStatus:
 *     'failed'`). An overdue order that no longer waits (the customer cancelled
 *     it, or staff moved it on) only loses `paymentDueBy`, so it is not looked at
 *     again.
 *
 * Idempotent (every step re-checks inside its own transaction); a run that stops
 * half-way is finished by the next one. A payment that still arrives later is
 * credited to the wallet (settlePayment.ts).
 */
import { FieldValue, Timestamp, type Firestore, type QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import type { PushMessaging } from '../notifications/push';
import { prepareCancellation } from '../orders/cancelOrder';
import { GATEWAY_PAYMENT_METHODS } from '../orders/placeOrder';
import { epochMillis, string, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { PAYMENT_EXPIRED_REASON } from './paymentTexts';
import { awaitsPayment, settlePaymentSession } from './settlePayment';
import type { PaymentGateway } from './zainCash';

export const EXPIRY_PAGE_SIZE = 100;
export const EXPIRY_MAX_PAGES = 20;

export interface ExpireDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  gateway: PaymentGateway | null;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info' | 'error'>;
}

export interface ExpireResult {
  sessionsPaid: string[];
  sessionsFailed: string[];
  sessionsExpired: string[];
  ordersCancelled: string[];
  ordersReleased: string[];
}

export async function expirePaymentSessions(deps: ExpireDeps, nowMs: number): Promise<ExpireResult> {
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const result: ExpireResult = { sessionsPaid: [], sessionsFailed: [], sessionsExpired: [], ordersCancelled: [], ordersReleased: [] };
  const cutoff = Timestamp.fromMillis(nowMs);

  // ── 1. Sessions ──
  let lastSession: QueryDocumentSnapshot | null = null;
  for (let page = 0; page < EXPIRY_MAX_PAGES; page++) {
    let q = db
      .collection(P.paymentSessions)
      .where('status', '==', 'pending')
      .where('expiresAt', '<=', cutoff)
      .orderBy('expiresAt')
      .limit(EXPIRY_PAGE_SIZE);
    if (lastSession !== null) q = q.startAfter(lastSession);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const id = doc.id;
      const txnId = stringOrNull(doc.get('gatewayTxnId'));
      if (txnId !== null && deps.gateway !== null) {
        try {
          const check = await deps.gateway.checkTransaction(txnId, nowMs);
          if (check.outcome !== 'pending' && (check.reference === null || check.reference === id)) {
            const settled = await settlePaymentSession(
              { db, messaging: deps.messaging, logger: log, now: () => nowMs },
              id,
              { outcome: check.outcome, transactionId: txnId, rawStatus: check.rawStatus, message: null },
            );
            if (settled.found && settled.changed) {
              (settled.status === 'paid' ? result.sessionsPaid : result.sessionsFailed).push(id);
              continue;
            }
          }
        } catch (e) {
          log.warn('expirePaymentSessions: status check failed, expiring', { sessionId: id, error: errorMessage(e) });
        }
      }
      const expired = await db.runTransaction(async (tx) => {
        const fresh = await tx.get(doc.ref);
        if (fresh.get('status') !== 'pending') return false;
        const ts = FieldValue.serverTimestamp();
        tx.update(doc.ref, { status: 'expired', settledAt: ts, updatedAt: ts });
        return true;
      });
      if (expired) result.sessionsExpired.push(id);
    }
    if (snap.size < EXPIRY_PAGE_SIZE) break;
    lastSession = snap.docs[snap.docs.length - 1];
  }

  // ── 2. Overdue orders ──
  let lastOrder: QueryDocumentSnapshot | null = null;
  for (let page = 0; page < EXPIRY_MAX_PAGES; page++) {
    let q = db
      .collection(P.orders)
      .where('paymentStatus', '==', 'pending')
      .where('paymentDueBy', '<=', cutoff)
      .orderBy('paymentDueBy')
      .limit(EXPIRY_PAGE_SIZE);
    if (lastOrder !== null) q = q.startAfter(lastOrder);
    const snap = await q.get();
    for (const doc of snap.docs) {
      const outcome = await db.runTransaction(async (tx): Promise<'cancelled' | 'released' | 'skipped'> => {
        const order = (await tx.get(doc.ref)).data();
        if (order === undefined || order.paymentStatus !== 'pending') return 'skipped';
        const dueMs = epochMillis(order.paymentDueBy);
        if (dueMs === null || dueMs > nowMs) return 'skipped';
        const method = string(order.paymentMethod);
        if (GATEWAY_PAYMENT_METHODS.includes(method as never) && awaitsPayment(order, string(order.userId), method)) {
          const cancellation = await prepareCancellation(db, tx, doc.ref, order, {
            reason: PAYMENT_EXPIRED_REASON,
            note: null,
            byUid: null,
            byRole: 'system',
            nowMs,
            orderFields: { paymentStatus: 'failed' },
          });
          cancellation.apply();
          return 'cancelled';
        }
        tx.update(doc.ref, { paymentDueBy: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
        return 'released';
      });
      if (outcome === 'cancelled') result.ordersCancelled.push(doc.id);
      if (outcome === 'released') result.ordersReleased.push(doc.id);
    }
    if (snap.size < EXPIRY_PAGE_SIZE) break;
    lastOrder = snap.docs[snap.docs.length - 1];
  }
  return result;
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

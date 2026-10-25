/**
 * `cancelOrder` (SRS §5.12, §7): the customer cancels their own order while it is
 * `pending` or `confirmed`. One transaction: the order (and every line) becomes
 * `cancelledByBuyer` with the reason, the stock it reserved is released,
 * `users.totalOrders` goes back down, the credits / wallet balance it used go
 * back to the wallet and its promo usage is released (orderRefunds.ts).
 *
 * The timeline entry and the customer notification come from
 * `onOrderStatusChange`, which sees the status change like any other
 * (statusUpdatedBy = the customer, statusUpdatedByRole = 'customer', statusNote = reason).
 */
import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { OrderStatus } from '../shared/enums';
import { integer, mapList, string } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { graphemeLength } from '../shared/text';
import { orderFailure } from './orderErrors';
import { prepareOrderRefund } from './orderRefunds';
import { releaseOrderStock } from './releaseStock';

/** Statuses the customer may cancel from (`OrderStatusX.customerCanCancel` in order_model.dart). */
export const CUSTOMER_CANCELLABLE: readonly OrderStatus[] = ['pending', 'confirmed'];
export const CANCEL_REASON_MAX = 300;

export interface CancelOrderRequest {
  orderId: string;
  reason: string | null;
}

export function parseCancelOrderData(data: unknown): CancelOrderRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw new HttpsError('invalid-argument', 'Expected { orderId, reason? }.');
  }
  const d = data as Record<string, unknown>;
  if (typeof d.orderId !== 'string' || d.orderId.length === 0 || d.orderId.length > 128 || d.orderId.includes('/')) {
    throw new HttpsError('invalid-argument', '`orderId` is missing or invalid.');
  }
  let reason: string | null = null;
  if (d.reason !== undefined && d.reason !== null) {
    if (typeof d.reason !== 'string') throw new HttpsError('invalid-argument', '`reason` must be a string.');
    const trimmed = d.reason.trim();
    if (graphemeLength(trimmed) > CANCEL_REASON_MAX) {
      throw new HttpsError('invalid-argument', `\`reason\` is longer than ${CANCEL_REASON_MAX} characters.`);
    }
    reason = trimmed.length > 0 ? trimmed : null;
  }
  return { orderId: d.orderId, reason };
}

export async function cancelOrderCore(
  db: Firestore,
  data: unknown,
  uid: string | undefined,
  options: { now?: () => number } = {},
): Promise<{ ok: true }> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to cancel an order.');
  const request = parseCancelOrderData(data);
  const orderRef = db.collection(P.orders).doc(request.orderId);

  await db.runTransaction(async (tx) => {
    // ── Reads ──
    const snap = await tx.get(orderRef);
    const order = snap.data();
    if (order === undefined) throw new HttpsError('not-found', 'Order not found.');
    if (order.userId !== uid) throw new HttpsError('permission-denied', 'This is not your order.');
    if (!(CUSTOMER_CANCELLABLE as readonly string[]).includes(string(order.status))) throw orderFailure('not_cancellable');
    const cancellation = await prepareCancellation(db, tx, orderRef, order, {
      reason: request.reason,
      note: request.reason,
      byUid: uid,
      byRole: 'customer',
      nowMs: (options.now ?? Date.now)(),
    });

    // ── Writes ──
    cancellation.apply();
  });
  return { ok: true };
}

export interface CancellationInput {
  /** `cancelReason`. */
  reason: string | null;
  /** `statusNote` (copied into the timeline entry by onOrderStatusChange). */
  note: string | null;
  /** `statusUpdatedBy` — null for the system (payment expiry / failure). */
  byUid: string | null;
  byRole: 'customer' | 'system';
  nowMs: number;
  /** More order fields to set in the same update (e.g. `paymentStatus: 'failed'`). */
  orderFields?: Record<string, unknown>;
}

/**
 * The customer cancellation of `order` (read in `tx`) as a reusable step — also
 * used when an online payment fails or expires (payments/*): reads (in `tx`)
 * what releasing the stock, `users.totalOrders` and the refund need; `apply()`
 * stages the writes — `cancelledByBuyer` on the order and every line, the stock,
 * the credits / wallet balance back, the promo usage released. Call before the
 * transaction's first write; call `apply()` with the other writes.
 */
export async function prepareCancellation(
  db: Firestore,
  tx: Transaction,
  orderRef: DocumentReference,
  order: DocumentData,
  input: CancellationInput,
): Promise<{ apply(): void }> {
  const ownerId = typeof order.userId === 'string' && order.userId.length > 0 && !order.userId.includes('/') ? order.userId : null;
  const userRef = ownerId === null ? null : db.collection(P.users).doc(ownerId);
  const release = await releaseOrderStock(db, tx, order.items);
  const user = userRef === null ? undefined : (await tx.get(userRef)).data();
  const refund = await prepareOrderRefund(db, tx, orderRef.id, order, 'cancel', input.nowMs);
  return {
    apply: () => {
      const status: OrderStatus = 'cancelledByBuyer';
      tx.update(orderRef, {
        ...refund.apply(),
        status,
        cancelReason: input.reason,
        items: mapList(order.items).map((item) => ({ ...item, status })),
        statusNote: input.note,
        statusUpdatedBy: input.byUid,
        statusUpdatedByRole: input.byRole,
        ...input.orderFields,
        updatedAt: FieldValue.serverTimestamp(),
      });
      release.apply();
      if (userRef !== null && user !== undefined) {
        tx.update(userRef, { totalOrders: Math.max(0, integer(user.totalOrders) - 1) });
      }
    },
  };
}

/**
 * `onOrderStatusChange` (SRS §5.12, §7): runs on every update of `orders/{id}`
 * and acts only when `status` changed.
 *
 * Timeline rule (the only writers of `orders/{id}/status_history`):
 *  - `placeOrder` writes the first entry (`pending`) in its own transaction —
 *    creating a document is not an update, so this trigger never sees it;
 *  - every later status change gets exactly one entry from this trigger, keyed by
 *    the event id (`function_runs/orderStatus:{orderId}:{eventId}`), so a retried or
 *    replayed event never adds a second one. `cancelOrder` and the dashboard only
 *    set `status` + `statusNote` / `statusUpdatedBy` / `statusUpdatedByRole`.
 *
 * In the same once-only transaction: `delivered` marks a cash-on-delivery order
 * paid and adds what was paid with money (the total, less any part of it
 * already returned to the wallet) to `users.totalSpent`; a line a seller
 * cancelled earlier (`stockReleased`) that a whole-order status change moved
 * back onto the flow (the dashboard writes every line) is put back to
 * `cancelledBySeller` — its stock and money were already given back; `cancelledBySeller` releases the
 * stock the order reserved and lowers `users.totalOrders` (what `cancelOrder`
 * does for customer cancellations); a cancellation returns the credits / wallet
 * balance the order used and releases its promo usage, and `refunded` also
 * returns the amount a paid order was paid with (orderRefunds.ts — only what has
 * not been returned yet, so `cancelOrder` and replays never pay twice).
 *
 * Then: `delivered` → the referrer's `orderBonus` when this is the friend's first
 * delivered + paid order (referrals/orderBonus.ts, once per referral), and the
 * customer is notified (in-app document with an id derived from the event, so a
 * retry never duplicates it; push best effort).
 */
import { createHash } from 'node:crypto';
import { FieldValue, type DocumentData } from 'firebase-admin/firestore';
import { notifyUser, type NotifyDeps } from '../notifications/notifyUser';
import { orderStatusNotification } from '../notifications/orderMessages';
import { OrderStatus } from '../shared/enums';
import { integer, string, stringOrNull } from '../shared/firestoreParse';
import { isOnFlow } from './orderTransitions';
import { runOnce } from '../shared/idempotency';
import { FirestorePaths as P } from '../shared/paths';
import { paymentCancellationNotification } from '../payments/paymentTexts';
import { applyOrderBonus, type OrderBonusOutcome } from '../referrals/orderBonus';
import { prepareOrderRefund, type RefundKind } from './orderRefunds';
import { releaseOrderStock } from './releaseStock';

const CANCELLED: readonly string[] = ['cancelledByBuyer', 'cancelledBySeller'];

export interface OrderStatusChangeEvent {
  /** CloudEvent id — stable across retries of the same event. */
  eventId: string;
  orderId: string;
  before: DocumentData | undefined;
  after: DocumentData | undefined;
}

export type OrderStatusChangeResult =
  | { handled: false; reason: 'unchanged' | 'missing' | 'unknownStatus' }
  | {
      handled: true;
      status: OrderStatus;
      /** false when this event was already processed (replay / retry). */
      applied: boolean;
      notified: boolean;
      /** `delivered` only: the referral check. */
      orderBonus?: OrderBonusOutcome;
    };

/** `function_runs` key of one status-change event. */
export function statusChangeKey(orderId: string, eventId: string): string {
  return `orderStatus:${orderId}:${eventHash(eventId)}`;
}

/** Event ids are opaque; hash them so keys and notification ids are always valid document ids. */
function eventHash(eventId: string): string {
  return createHash('sha256').update(eventId, 'utf8').digest('hex').slice(0, 16);
}

export async function handleOrderStatusChange(
  deps: NotifyDeps & { now?: () => number },
  event: OrderStatusChangeEvent,
): Promise<OrderStatusChangeResult> {
  const { before, after, orderId } = event;
  if (before === undefined || after === undefined) return { handled: false, reason: 'missing' };
  const from = string(before.status);
  const to = string(after.status);
  if (from === to) return { handled: false, reason: 'unchanged' };
  if (!(OrderStatus as readonly string[]).includes(to)) return { handled: false, reason: 'unknownStatus' };
  const status = to as OrderStatus;

  const { db } = deps;
  const orderRef = db.collection(P.orders).doc(orderId);
  const userId = stringOrNull(after.userId);
  const userRef = userId === null ? null : db.collection(P.users).doc(userId);

  const nowMs = (deps.now ?? Date.now)();
  const refundKind: RefundKind | null = CANCELLED.includes(status) ? 'cancel' : status === 'refunded' ? 'refund' : null;

  const applied = await runOnce(db, statusChangeKey(orderId, event.eventId), async (tx) => {
    // ── Reads ──
    const current = (await tx.get(orderRef)).data();
    const order = current ?? after;
    const release =
      status === 'cancelledBySeller' && !CANCELLED.includes(from) ? await releaseOrderStock(db, tx, after.items) : null;
    const user = userRef === null ? undefined : (await tx.get(userRef)).data();
    // Refunds are recorded on the order, so a deleted order gets none.
    const refund =
      refundKind !== null && current !== undefined ? await prepareOrderRefund(db, tx, orderId, current, refundKind, nowMs) : null;

    // ── Writes ──
    tx.create(orderRef.collection(P.statusHistory).doc(), {
      status,
      byUid: stringOrNull(after.statusUpdatedBy),
      byRole: stringOrNull(after.statusUpdatedByRole) ?? 'admin',
      note: stringOrNull(after.statusNote),
      at: FieldValue.serverTimestamp(),
    });

    const orderUpdate: Record<string, unknown> = {};
    if (status === 'delivered') {
      const cashOnDelivery = order.paymentMethod === 'cashOnDelivery';
      if (cashOnDelivery && order.paymentStatus !== 'paid') orderUpdate.paymentStatus = 'paid';
      if ((cashOnDelivery || order.paymentStatus === 'paid') && userRef !== null && user !== undefined) {
        // Money already returned from the paid total (cancelled lines of a paid order) is not spent.
        const returned = Math.max(0, integer(order.refundedBalance) - Math.max(0, integer(order.walletUsed)));
        const spent = Math.max(0, integer(order.total) - returned);
        tx.update(userRef, { totalSpent: integer(user.totalSpent) + spent });
      }
    }
    const lines = current?.items;
    if (Array.isArray(lines)) {
      let restored = false;
      const fixed = lines.map((line: unknown) => {
        if (line === null || typeof line !== 'object') return line;
        const l = line as Record<string, unknown>;
        if (l.stockReleased !== true || !isOnFlow(l.status as OrderStatus)) return line;
        restored = true;
        return { ...l, status: 'cancelledBySeller' };
      });
      if (restored) orderUpdate.items = fixed;
    }
    if (refund !== null) Object.assign(orderUpdate, refund.apply());
    if (current !== undefined && Object.keys(orderUpdate).length > 0) {
      tx.update(orderRef, { ...orderUpdate, updatedAt: FieldValue.serverTimestamp() });
    }

    if (release !== null) {
      release.apply();
      if (userRef !== null && user !== undefined) {
        tx.update(userRef, { totalOrders: Math.max(0, integer(user.totalOrders) - 1) });
      }
    }
  });

  // Not tied to `applied`: a retry after a failure here still pays (once per referral).
  const orderBonus = status === 'delivered' && userId !== null ? await applyOrderBonus(deps, orderId, userId) : undefined;

  let notified = false;
  if (userId !== null) {
    const reason = status === 'cancelledBySeller' ? (stringOrNull(after.cancelReason) ?? stringOrNull(after.statusNote)) : null;
    const order = { orderId, orderNumber: string(after.orderNumber) };
    // An online payment that failed / ran out of time gets its own wording (payments/*).
    const paymentNotice = status === 'cancelledByBuyer' ? paymentCancellationNotification(after.cancelReason, order) : null;
    const result = await notifyUser(
      deps,
      userId,
      paymentNotice ?? orderStatusNotification(status, { ...order, reason }),
      // Created at most once per event, so a retry after a failed push never duplicates it.
      { notificationId: `${orderId}-${status}-${eventHash(event.eventId)}` },
    );
    notified = result.created;
  }
  return { handled: true, status, applied, notified, ...(orderBonus !== undefined && { orderBonus }) };
}

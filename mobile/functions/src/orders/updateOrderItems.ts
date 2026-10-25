/**
 * `updateOrderItems` (SRS §9 "Seller view", §10 Phase 8): a partner moves THEIR
 * lines of a multi-vendor order. Caller: custom claim `seller == storeId` (never
 * `admin`), store active, the store in `order.storeIds`.
 *
 * Data `{ orderId, status, note? (≤ 500) }` → `{ status }` (the order's status after).
 *
 * In one transaction:
 *  - of the seller's lines, only those on the main flow (pending … delivered)
 *    whose `allowedNext` (orderTransitions.ts, mirror of `OrderStatusX.allowedNext`)
 *    contains `status` move; lines already final or off the flow (cancelled /
 *    returned / refunded) stay as they are, other stores' lines are never touched;
 *    `failed-precondition` `{ reason: 'not_allowed' }` when none can move;
 *  - the ORDER status becomes the least advanced line status along the flow
 *    (`derivedOrderStatus`; all lines cancelled → cancelled). When it changes, the
 *    update carries `statusNote` (the note), `statusUpdatedBy` (the seller) and
 *    `statusUpdatedByRole: 'seller'`, so onOrderStatusChange writes the timeline
 *    entry and notifies the customer as for any other status change;
 *  - cancelling SOME lines of an order that stays active (other stores' lines go
 *    on) releases their stock, gives their share back (credits back, the amount
 *    to collect recomputed — or, when already paid, the money to the wallet
 *    balance) and tells the customer which items were cancelled
 *    (lineCancellation.ts). Cancelling the last lines cancels the order, which
 *    onOrderStatusChange handles as a whole (stock and money still owed).
 * Sellers never set `refunded` — money is Golden Gift's. Caller check: the claim
 * AND the live store doc (active, `ownerUid` = the caller).
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { sellerStoreOf } from '../admin/adminCaller';
import type { AdminCaller } from '../admin/setAdminClaim';
import { notificationDoc, pushToUser, type UserNotification } from '../notifications/notifyUser';
import type { PushMessaging } from '../notifications/push';
import { OrderStatus } from '../shared/enums';
import { enumValue, integer, mapList, string, stringList, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { creditExpiryAt, parseReferralSettings } from '../wallet/walletSettings';
import { orderRefundTitle } from '../wallet/walletTexts';
import { isDocId } from './createOrderDoc';
import { itemsCancelledNotification, planLineCancellation } from './lineCancellation';
import { allowedNext, derivedOrderStatus, isOnFlow, SELLER_FORBIDDEN } from './orderTransitions';
import { GATEWAY_PAYMENT_METHODS } from './placeOrder';
import { releaseOrderStock } from './releaseStock';

export const NOTE_MAX = 500;

export interface UpdateOrderItemsRequest {
  orderId: string;
  status: OrderStatus;
  note: string | null;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parseUpdateOrderItemsData(data: unknown): UpdateOrderItemsRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected { orderId, status, note? }.');
  const d = data as Record<string, unknown>;
  if (!isDocId(d.orderId)) throw bad('`orderId` is missing or invalid.');
  if (typeof d.status !== 'string' || !(OrderStatus as readonly string[]).includes(d.status)) {
    throw bad('`status` is not an order status.');
  }
  const status = d.status as OrderStatus;
  if (SELLER_FORBIDDEN.includes(status)) throw bad('Refunds are handled by Golden Gift.');
  let note: string | null = null;
  if (d.note !== undefined && d.note !== null) {
    if (typeof d.note !== 'string') throw bad('`note` must be a string.');
    const trimmed = d.note.trim();
    if (trimmed.length > NOTE_MAX) throw bad(`\`note\` is longer than ${NOTE_MAX} characters.`);
    note = trimmed.length > 0 ? trimmed : null;
  }
  return { orderId: d.orderId, status, note };
}

export interface UpdateOrderItemsDeps {
  db: Firestore;
  /** null = no push (the in-app notification is still written). */
  messaging?: PushMessaging | null;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn'>;
}

export interface UpdateOrderItemsResult {
  status: OrderStatus;
  moved: number;
  /** Lines of an order that stays active cancelled by this call (with their stock and money back). */
  cancelledLines?: { lineIds: string[]; creditsBack: number; moneyBack: number; notificationId: string };
}

/** `failed-precondition` reason: an order still waiting for its online payment cannot lose lines. */
export const AWAITING_PAYMENT = 'awaiting_payment';

export async function updateOrderItemsCore(
  depsOrDb: UpdateOrderItemsDeps | Firestore,
  data: unknown,
  caller: AdminCaller,
): Promise<UpdateOrderItemsResult> {
  const deps: UpdateOrderItemsDeps = 'collection' in depsOrDb ? { db: depsOrDb as Firestore } : depsOrDb;
  const { db } = deps;
  const uid = caller.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to the dashboard first.');
  const storeId = sellerStoreOf(caller);
  if (storeId === null) throw new HttpsError('permission-denied', 'Partner accounts only.');
  const request = parseUpdateOrderItemsData(data);
  const orderRef = db.collection(P.orders).doc(request.orderId);
  const storeRef = db.collection(P.stores).doc(storeId);
  const nowMs = (deps.now ?? Date.now)();
  let notice: { userId: string; notificationId: string; notification: UserNotification } | null = null;

  const result = await db.runTransaction(async (tx): Promise<UpdateOrderItemsResult> => {
    notice = null; // the transaction may run more than once
    // ── Reads ──
    const [orderSnap, storeSnap] = await tx.getAll(orderRef, storeRef);
    // The live store, not only the claim: active, and still this caller's.
    if (storeSnap.get('status') !== 'active' || storeSnap.get('ownerUid') !== uid) {
      throw new HttpsError('permission-denied', 'Your store is not active.');
    }
    const order = orderSnap.data();
    if (order === undefined) throw new HttpsError('not-found', 'Order not found.');
    if (!stringList(order.storeIds).includes(storeId)) throw new HttpsError('permission-denied', 'This order has none of your items.');

    const items = mapList(order.items);
    const lineStatus = (i: Record<string, unknown>) => enumValue(OrderStatus, i.status, 'pending');
    const mine = items.filter((i) => string(i.storeId) === storeId);
    if (mine.length === 0) throw new HttpsError('permission-denied', 'This order has none of your items.');
    const movable = (i: Record<string, unknown>) =>
      string(i.storeId) === storeId && isOnFlow(lineStatus(i)) && allowedNext(lineStatus(i)).includes(request.status);
    const moving = items.filter(movable);
    if (moving.length === 0) {
      throw new HttpsError('failed-precondition', `None of your items can move to ${request.status}.`, { reason: 'not_allowed' });
    }

    let nextItems = items.map((i) => (movable(i) ? { ...i, status: request.status } : i));
    const current = enumValue(OrderStatus, order.status, 'pending');
    const derived = derivedOrderStatus(nextItems.map(lineStatus)) ?? current;
    const update: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };

    // ── Some lines cancelled, the order goes on: stock and money for those lines now ──
    let cancelled: UpdateOrderItemsResult['cancelledLines'];
    const partial = request.status === 'cancelledBySeller' && isOnFlow(derived);
    let apply: (() => void) | null = null;
    if (partial) {
      const method = string(order.paymentMethod);
      if (order.paymentStatus === 'pending' && (GATEWAY_PAYMENT_METHODS as readonly string[]).includes(method)) {
        throw new HttpsError('failed-precondition', 'This order is waiting for its online payment. Try again once it is paid.', {
          reason: AWAITING_PAYMENT,
        });
      }
      const lineIds = moving.map((i) => string(i.id));
      const release = await releaseOrderStock(db, tx, moving);
      const plan = planLineCancellation(order, new Set(lineIds));
      const customer = stringOrNull(order.userId);
      const toWallet = customer !== null && !customer.includes('/') && (plan.creditsBack > 0 || (plan.paid && plan.moneyBack > 0));
      const wallet = toWallet ? await readWallet(db, tx, customer!) : null;
      const settings =
        toWallet && plan.creditsBack > 0
          ? parseReferralSettings((await tx.get(db.collection(P.appSettings).doc('referral'))).data())
          : null;
      const seq = Math.max(0, integer(order.lineCancellations)) + 1;
      const notificationId = `${request.orderId}-itemsCancelled-${seq}`;

      const released = new Set(moving);
      nextItems = nextItems.map((i, n) => (released.has(items[n]) ? { ...i, stockReleased: true } : i));
      update.lineCancellations = seq;
      if (plan.totals !== null) Object.assign(update, plan.totals);
      apply = () => {
        release.apply();
        if (wallet !== null) {
          // Fixed ids per cancellation: orderItems-{orderId}-{seq}-1 (credits), -2 (balance).
          const ledger = new WalletLedger(tx, wallet, { idPrefix: `orderItems-${request.orderId}-${seq}` });
          const txn = { type: 'refund' as const, title: orderRefundTitle(string(order.orderNumber)), orderId: request.orderId };
          if (plan.creditsBack > 0) {
            ledger.addCredits(plan.creditsBack, txn, {
              source: 'refund',
              expiresAtMs: creditExpiryAt(nowMs, settings?.creditsExpiryDays ?? 0),
              orderId: request.orderId,
            });
          }
          if (plan.paid && plan.moneyBack > 0) ledger.addBalance(plan.moneyBack, txn);
          ledger.apply();
          update.refundedCredits = Math.max(0, integer(order.refundedCredits)) + plan.creditsBack;
          update.refundedBalance = Math.max(0, integer(order.refundedBalance)) + (plan.paid ? plan.moneyBack : 0);
          update.refundedToWallet = true;
          update.refundedAt = FieldValue.serverTimestamp();
        }
        if (customer !== null && !customer.includes('/')) {
          const notification = itemsCancelledNotification(
            { orderId: request.orderId, orderNumber: string(order.orderNumber) },
            moving,
            plan,
            request.note,
          );
          tx.create(db.collection(P.notifications).doc(notificationId), notificationDoc(customer, notification));
          notice = { userId: customer, notificationId, notification };
        }
      };
      cancelled = { lineIds, creditsBack: plan.creditsBack, moneyBack: plan.moneyBack, notificationId };
    }

    // ── Writes ──
    apply?.();
    update.items = nextItems;
    if (derived !== current) {
      update.status = derived;
      update.statusNote = request.note;
      update.statusUpdatedBy = uid;
      update.statusUpdatedByRole = 'seller';
      if (derived === 'cancelledBySeller') update.cancelReason = request.note;
    }
    tx.update(orderRef, update);
    return { status: derived, moved: moving.length, ...(cancelled !== undefined && { cancelledLines: cancelled }) };
  });

  // Push after the commit (best effort; the in-app notification is already there).
  const sent = notice as { userId: string; notificationId: string; notification: UserNotification } | null;
  if (sent !== null && deps.messaging) {
    await pushToUser({ db, messaging: deps.messaging, logger: deps.logger }, sent.userId, sent.notificationId, sent.notification);
  }
  return result;
}

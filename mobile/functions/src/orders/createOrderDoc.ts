/**
 * Orders that do not come from the cart (SRS §5.17, §5.22): a gift-card purchase
 * (`purchaseGiftCard`) and an accepted special-request quote (`acceptQuote`).
 *
 * One synthetic line, and otherwise exactly what `placeOrder` writes (§6.7): the
 * idempotent order id (sha256 of uid + clientRequestId), the monthly order number
 * from `counters/orders-{YYMM}`, the first `status_history` entry, `users.totalOrders`
 * + 1 (cancelOrder takes it back) and — for a wallet payment — the `orderPayment`
 * debit of the wallet BALANCE through the wallet ledger. Credits never pay for
 * these orders.
 *
 * Use inside a transaction: `existingOrder` first, then the caller's own reads,
 * then `prepareSyntheticOrder` (its reads), then the caller's checks, then
 * `apply()` with the caller's other writes.
 */
import {
  FieldValue,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { Trilingual } from '../notifications/orderMessages';
import type { OrderStatus, PaymentStatus } from '../shared/enums';
import { integer, string } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { readWallet, WalletLedger } from '../wallet/ledger';
import { orderPaymentTitle } from '../wallet/walletTexts';
import { checkoutTotals, type CheckoutTotals, type LocalDateTime } from './checkoutRules';
import { orderFailure } from './orderErrors';
import { formatOrderNumber, orderCounterId } from './orderNumber';

/** The platform's own store (seeded): gift cards and special requests are Golden Gift's. */
export const HOME_STORE_ID = 'golden-gift-home';

export const MAX_CLIENT_REQUEST_ID_LENGTH = 128;

/** Payment methods these orders take: cash on delivery or the wallet balance. */
export type SyntheticPaymentMethod = 'cashOnDelivery' | 'wallet';
export const SYNTHETIC_PAYMENT_METHODS: readonly SyntheticPaymentMethod[] = ['cashOnDelivery', 'wallet'];

/** The callables' response (`PlacedOrder` in the app). */
export interface PlacedSyntheticOrder {
  orderId: string;
  orderNumber: string;
  /** What is left to pay on delivery (0 for a wallet payment). */
  total: number;
  deliveryDate: string | null;
}

export interface SyntheticLine {
  /** Line id (`orders.items[].id`). */
  id: string;
  /** '' — the line is not a catalogue product. */
  productId: string;
  storeId: string;
  title: Trilingual;
  image: string | null;
  unitPrice: number;
  selections: Array<Record<string, unknown>>;
}

export interface SyntheticOrderInput {
  uid: string;
  clientRequestId: string;
  orderType: 'giftCard' | 'specialRequest';
  line: SyntheticLine;
  deliveryFee: number;
  paymentMethod: SyntheticPaymentMethod;
  /** Snapshot (`addressSnapshot`), or null when nothing is delivered. */
  address: Record<string, unknown> | null;
  deliveryDate: string | null;
  deliverySlot: string | null;
  /** Extra order fields, e.g. `giftCard` or `specialRequestId`. */
  extra?: Record<string, unknown>;
}

export interface PreparedOrder {
  orderNumber: string;
  totals: CheckoutTotals;
  paymentStatus: PaymentStatus;
  /** Writes the counter, the order, its first timeline entry, `users.totalOrders` and the wallet debit. */
  apply(): PlacedSyntheticOrder;
}

export const bad = (message: string) => new HttpsError('invalid-argument', message);

export function isDocId(v: unknown, max = 128): v is string {
  return (
    typeof v === 'string' &&
    v.length > 0 &&
    v.length <= max &&
    !v.includes('/') &&
    v !== '.' &&
    v !== '..' &&
    !/^__.*__$/.test(v)
  );
}

export function parseSyntheticPaymentMethod(v: unknown): SyntheticPaymentMethod {
  const method = v ?? 'cashOnDelivery';
  if (typeof method !== 'string' || !(SYNTHETIC_PAYMENT_METHODS as readonly string[]).includes(method)) {
    throw bad('`paymentMethod` must be cashOnDelivery or wallet.');
  }
  return method as SyntheticPaymentMethod;
}

/** `placeOrder`'s address snapshot (§6.7): the address without `id` / `isDefault`. */
export function addressSnapshot(a: DocumentData): Record<string, unknown> {
  const text = (v: unknown) => (typeof v === 'string' ? v : '');
  const coord = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  return {
    label: text(a.label),
    name: text(a.name),
    phone: text(a.phone),
    city: text(a.city),
    area: text(a.area),
    street: text(a.street),
    building: text(a.building),
    floor: text(a.floor),
    notes: text(a.notes),
    lat: coord(a.lat),
    lng: coord(a.lng),
  };
}

/** The order a retry addresses, if the first call already created it (same uid only). */
export function existingOrder(snap: DocumentSnapshot, uid: string): PlacedSyntheticOrder | null {
  if (!snap.exists) return null;
  if (snap.get('userId') !== uid) throw new HttpsError('internal', 'Order id collision.');
  const deliveryDate = snap.get('deliveryDate');
  return {
    orderId: snap.id,
    orderNumber: string(snap.get('orderNumber')),
    total: integer(snap.get('total')),
    deliveryDate: typeof deliveryDate === 'string' ? deliveryDate : null,
  };
}

/** `users/{uid}` must exist and may order (what placeOrder checks). */
export function assertMayOrder(user: DocumentData | undefined): asserts user is DocumentData {
  if (user === undefined) throw new HttpsError('failed-precondition', 'Complete your profile before ordering.');
  if (user.isDeleted === true || user.isBlocked === true) {
    throw new HttpsError('permission-denied', 'This account cannot place orders.');
  }
}

/** Reads (in `tx`) the counter and, for a wallet payment, the wallet; `insufficient_funds` when the balance is short. */
export async function prepareSyntheticOrder(
  db: Firestore,
  tx: Transaction,
  orderRef: DocumentReference,
  now: LocalDateTime,
  input: SyntheticOrderInput,
): Promise<PreparedOrder> {
  const counterRef = db.collection(P.counters).doc(orderCounterId(now));
  const counterSnap = await tx.get(counterRef);
  const payWithBalance = input.paymentMethod === 'wallet';
  const wallet = payWithBalance ? await readWallet(db, tx, input.uid) : null;

  const subtotal = input.line.unitPrice;
  const totals = checkoutTotals({
    subtotal,
    deliveryFee: input.deliveryFee,
    wallet: wallet === null ? 0 : Math.max(0, wallet.balance),
  });
  if (payWithBalance && totals.total > 0) throw orderFailure('insufficient_funds');

  const sequence = Math.max(1, integer(counterSnap.get('next'), 1));
  const orderNumber = formatOrderNumber(now, sequence);
  const paymentStatus: PaymentStatus = payWithBalance ? 'paid' : 'pending';

  return {
    orderNumber,
    totals,
    paymentStatus,
    apply: () => {
      const ts = FieldValue.serverTimestamp();
      const status: OrderStatus = 'pending';
      const { line } = input;
      tx.set(counterRef, { next: sequence + 1, updatedAt: ts }, { merge: true });
      tx.create(orderRef, {
        orderNumber,
        userId: input.uid,
        storeIds: [line.storeId],
        items: [
          {
            id: line.id,
            productId: line.productId,
            storeId: line.storeId,
            titleSnapshot: line.title.en,
            titleSnapshotAr: line.title.ar,
            titleSnapshotKu: line.title.ku,
            imageSnapshot: line.image,
            unitPrice: line.unitPrice,
            qty: 1,
            selections: line.selections,
            lineTotal: line.unitPrice,
            preparationDays: 0,
            status,
          },
        ],
        subtotal: totals.subtotal,
        discount: 0,
        promoCode: null,
        creditsUsed: 0,
        walletUsed: totals.walletUsed,
        deliveryFee: totals.deliveryFee,
        total: totals.total,
        paymentMethod: input.paymentMethod,
        paymentStatus,
        paymentRef: null,
        address: input.address,
        deliveryDate: input.deliveryDate,
        deliverySlot: input.deliverySlot,
        isGift: false,
        giftMessage: null,
        hidePrices: false,
        status,
        cancelReason: null,
        orderType: input.orderType,
        referralCredited: false,
        refundedToWallet: false,
        rewards: {},
        statusNote: null,
        statusUpdatedBy: input.uid,
        statusUpdatedByRole: 'customer',
        clientRequestId: input.clientRequestId,
        ...input.extra,
        createdAt: ts,
        updatedAt: ts,
      });
      tx.create(orderRef.collection(P.statusHistory).doc(), {
        status,
        byUid: input.uid,
        byRole: 'customer',
        note: null,
        at: ts,
      });
      tx.update(db.collection(P.users).doc(input.uid), { totalOrders: FieldValue.increment(1) });
      if (wallet !== null && totals.walletUsed > 0) {
        // Same fixed transaction ids as placeOrder (order-{id}-n).
        const ledger = new WalletLedger(tx, wallet, { idPrefix: `order-${orderRef.id}` });
        ledger.spendBalance(totals.walletUsed, {
          type: 'orderPayment',
          title: orderPaymentTitle(orderNumber),
          orderId: orderRef.id,
        });
        ledger.apply();
      }
      return { orderId: orderRef.id, orderNumber, total: totals.total, deliveryDate: input.deliveryDate };
    },
  };
}

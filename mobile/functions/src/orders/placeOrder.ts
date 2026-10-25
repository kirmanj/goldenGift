/**
 * `placeOrder` (SRS §5.11, §6.7, §7): turns the signed-in customer's cart into
 * an order in ONE Firestore transaction — re-pricing, city, stock, delivery
 * date / slot, payment and minimum checks, the promo code (every §6.9 rule),
 * credits and wallet balance, stock reservation, order number, the order + its
 * first timeline entry, promo usage counters, the wallet transactions, an empty
 * cart and `users.totalOrders` — so concurrent orders on the last unit never
 * oversell, a promo's usage limit holds under concurrent checkouts and nothing
 * is ever left half-done.
 *
 * Payment (Phase 7): the discount first, then credits (when `useCredits`; spent
 * FIFO from the credit lots), then — only with `paymentMethod: 'wallet'` — the
 * balance, which must cover the rest (else `insufficient_funds`); a wallet order
 * is `paid` at once. Cash on delivery collects the rest.
 * Phase 9: `paymentMethod: 'zainCash'` (when `app_settings/payments.zainCash`)
 * creates the order `pending` payment with `paymentDueBy` = now + 30 min —
 * stock, promo and credits reserved as usual; the app then opens a
 * `createPaymentSession` and the gateway marks it paid, or the failure /
 * `expirePaymentSessions` cancels it (payments/*). Its "order received"
 * notification is sent when it is paid.
 *
 * Every new order carries `productIds` (its lines' products) for the review rules.
 *
 * Idempotent: the order id is derived from uid + `clientRequestId`, so a retry
 * returns the order the first call created, without side effects.
 *
 * After the commit (best effort, never fails the order): customer photos are
 * copied into the order's Storage folder and the "order received" notification
 * is sent.
 */
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type DocumentSnapshot,
  type Firestore,
  type Transaction,
} from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { notifyUser } from '../notifications/notifyUser';
import { orderStatusNotification } from '../notifications/orderMessages';
import type { PushMessaging } from '../notifications/push';
import { PaymentMethod, type OrderStatus, type PaymentStatus } from '../shared/enums';
import { integer, string, stringList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { graphemeLength } from '../shared/text';
import { checkCartLine, orderItem, type PricedLine } from './cartLines';
import {
  availableSlots,
  baghdadNow,
  checkoutTotals,
  earliestDeliveryDate,
  lastDeliveryDate,
  meetsMinimum,
  parseCities,
  parseGeneralSettings,
  parseIsoDate,
  parsePaymentSettings,
  type LocalDateTime,
  type PaymentSettings,
} from './checkoutRules';
import { orderFailure, promoFailure } from './orderErrors';
import { formatOrderNumber, orderCounterId, orderIdFor } from './orderNumber';
import { copyOrderPhotos, type Bucket } from './orderPhotos';
import { evaluatePromo, normalizePromoCode, parsePromoCode } from './promoRules';
import { coversDemand, stockDemand, stockUpdate } from './stock';
import { readOpenCreditLots, readWallet, WalletLedger, type CreditLot } from '../wallet/ledger';
import { orderPaymentTitle } from '../wallet/walletTexts';

/** `CheckoutController.giftMessageMax`. */
export const GIFT_MESSAGE_MAX = 200;
export const MAX_CLIENT_REQUEST_ID_LENGTH = 128;
export const MAX_PROMO_CODE_LENGTH = 40;
/**
 * Transaction write budget: 4 fixed writes + 2 per line + promo (2) + wallet
 * (1 + 2 transactions + up to MAX_OPEN_LOTS lots) stays below Firestore's 500.
 */
export const MAX_CART_LINES = 100;

/** Cash on delivery, wallet / credits and (Phase 9) ZainCash; cards and FastPay are not integrated yet. */
export const SUPPORTED_PAYMENT_METHODS: readonly PaymentMethod[] = ['cashOnDelivery', 'wallet', 'zainCash'];
/** Paid at checkout through a gateway session (`createPaymentSession`), before `paymentDueBy`. */
export const GATEWAY_PAYMENT_METHODS: readonly PaymentMethod[] = ['zainCash'];
/** An unpaid gateway order is cancelled (`payment_expired`) this long after it was placed. */
export const PAYMENT_WINDOW_MS = 30 * 60 * 1000;
/** ZainCash refuses tiny amounts (its docs: min 250 IQD; its samples: more than 1,000). */
export const MIN_GATEWAY_AMOUNT = 1000;

export interface PlaceOrderDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  /** Default Storage bucket for the photo copy; omitted = photos keep their upload URLs. */
  bucket?: () => Bucket;
  /** Epoch ms; tests pin the clock. */
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info'>;
}

/** Validated `placeOrder` data (the app's `PlaceOrderRequest.toMap()`). */
export interface PlaceOrderRequest {
  clientRequestId: string;
  addressId: string;
  /** yyyy-MM-dd, Iraq calendar date. */
  deliveryDate: string;
  deliverySlot: string;
  isGift: boolean;
  giftMessage: string | null;
  hidePrices: boolean;
  paymentMethod: PaymentMethod;
  /** Normalised like `PromoCodeModel.normalize` (no spaces, upper case); null = none. */
  promoCode: string | null;
  /** Spend credits first (the cart / checkout toggle). */
  useCredits: boolean;
  /**
   * The app sends true exactly when `paymentMethod` is `wallet`. The balance is
   * only ever spent on a `wallet` payment (what the Checkout screen shows), so
   * this flag alone changes nothing.
   */
  useWallet: boolean;
}

/** The callable's response (`PlacedOrder` in the app). */
export interface PlacedOrder {
  orderId: string;
  orderNumber: string;
  total: number;
  deliveryDate: string;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

function isDocId(v: unknown, max = 128): v is string {
  return typeof v === 'string' && v.length > 0 && v.length <= max && !v.includes('/') && v !== '.' && v !== '..';
}

/** A code that can name a `promo_codes` document (anything else cannot exist → notFound). */
function isPromoDocId(code: string): boolean {
  return isDocId(code, MAX_PROMO_CODE_LENGTH) && !/^__.*__$/.test(code);
}

function optionalBoolean(v: unknown, name: string): boolean {
  if (v === undefined || v === null) return false;
  if (typeof v !== 'boolean') throw bad(`\`${name}\` must be true or false.`);
  return v;
}

export function parsePlaceOrderData(data: unknown): PlaceOrderRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { clientRequestId, addressId, deliveryDate, deliverySlot, paymentMethod, … }.');
  }
  const d = data as Record<string, unknown>;
  if (!isDocId(d.clientRequestId, MAX_CLIENT_REQUEST_ID_LENGTH)) throw bad('`clientRequestId` is missing or invalid.');
  if (!isDocId(d.addressId)) throw bad('`addressId` is missing or invalid.');
  if (parseIsoDate(d.deliveryDate) === null) throw bad('`deliveryDate` must be a date "yyyy-MM-dd".');
  if (typeof d.deliverySlot !== 'string' || d.deliverySlot.length === 0 || d.deliverySlot.length > 64) {
    throw bad('`deliverySlot` is missing.');
  }

  const isGift = optionalBoolean(d.isGift, 'isGift');
  let giftMessage: string | null = null;
  if (d.giftMessage !== undefined && d.giftMessage !== null) {
    if (typeof d.giftMessage !== 'string') throw bad('`giftMessage` must be a string.');
    const message = d.giftMessage.trim();
    if (graphemeLength(message) > GIFT_MESSAGE_MAX) throw bad(`\`giftMessage\` is longer than ${GIFT_MESSAGE_MAX} characters.`);
    giftMessage = message.length > 0 ? message : null;
  }
  const hidePrices = optionalBoolean(d.hidePrices, 'hidePrices');

  const paymentMethod = d.paymentMethod ?? 'cashOnDelivery';
  if (typeof paymentMethod !== 'string' || !(PaymentMethod as readonly string[]).includes(paymentMethod)) {
    throw bad('`paymentMethod` is not a payment method.');
  }

  let promoCode: string | null = null;
  if (d.promoCode !== undefined && d.promoCode !== null) {
    if (typeof d.promoCode !== 'string' || d.promoCode.length > MAX_PROMO_CODE_LENGTH) throw bad('`promoCode` is invalid.');
    promoCode = normalizePromoCode(d.promoCode) || null;
  }

  return {
    clientRequestId: d.clientRequestId,
    addressId: d.addressId,
    deliveryDate: d.deliveryDate as string,
    deliverySlot: d.deliverySlot,
    isGift,
    // Gift options only mean something on a gift (CheckoutController.place does the same).
    giftMessage: isGift ? giftMessage : null,
    hidePrices: isGift && hidePrices,
    paymentMethod: paymentMethod as PaymentMethod,
    promoCode,
    useCredits: optionalBoolean(d.useCredits, 'useCredits'),
    useWallet: optionalBoolean(d.useWallet, 'useWallet'),
  };
}

/** Whether `method` is switched on in `app_settings/payments`. */
function paymentEnabled(settings: PaymentSettings, method: PaymentMethod): boolean {
  switch (method) {
    case 'cashOnDelivery':
      return settings.cashOnDelivery;
    case 'wallet':
      return settings.wallet;
    case 'card':
      return settings.card;
    case 'fastPay':
      return settings.fastPay;
    case 'zainCash':
      return settings.zainCash;
  }
}

/** Thrown inside the transaction when lines are unavailable or stale (→ cart_changed). */
class CartChanged extends Error {
  constructor(
    readonly productIds: string[],
    readonly refresh: Array<{ itemId: string; update: Record<string, unknown> }>,
  ) {
    super('cart changed');
  }
}

/** The address snapshot stored on the order (§6.7): the address without `id` / `isDefault`. */
function addressSnapshot(a: DocumentData): Record<string, unknown> {
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

function placedFrom(snap: DocumentSnapshot): PlacedOrder {
  return {
    orderId: snap.id,
    orderNumber: string(snap.get('orderNumber')),
    total: integer(snap.get('total')),
    deliveryDate: string(snap.get('deliveryDate')),
  };
}

type TransactionOutcome = { created: false; placed: PlacedOrder } | { created: true; placed: PlacedOrder; viaGateway: boolean };

export async function placeOrderCore(deps: PlaceOrderDeps, data: unknown, uid: string | undefined): Promise<PlacedOrder> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to place an order.');
  const request = parsePlaceOrderData(data);
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const nowMs = (deps.now ?? Date.now)();
  const now = baghdadNow(nowMs);

  const orderId = orderIdFor(uid, request.clientRequestId);
  const orderRef = db.collection(P.orders).doc(orderId);

  let outcome: TransactionOutcome;
  try {
    outcome = await db.runTransaction((tx) => orderTransaction(deps, tx, uid, request, orderRef, now, nowMs), {
      maxAttempts: 10,
    });
  } catch (e) {
    if (!(e instanceof CartChanged)) throw e;
    await refreshCart(db, uid, e.refresh, log);
    throw orderFailure('cart_changed', e.productIds);
  }
  if (!outcome.created) return outcome.placed;

  // Best effort, in parallel: neither may fail the order that already exists.
  const placed = outcome.placed;
  await Promise.all([
    deps.bucket === undefined
      ? Promise.resolve()
      : copyOrderPhotos({ db, bucket: deps.bucket }, orderId, uid)
          .then((r) => {
            if (r.copied + r.failed + r.skipped > 0) log.info('placeOrder: photos', { orderId, ...r });
          })
          .catch((err: unknown) => log.warn('placeOrder: photo copy failed', { orderId, error: errorMessage(err) })),
    // A gateway order is "received" once it is paid (payments/settlePayment.ts sends it then).
    outcome.viaGateway
      ? Promise.resolve()
      : notifyUser(
          { db, messaging: deps.messaging, logger: log },
          uid,
          orderStatusNotification('pending', { orderId, orderNumber: placed.orderNumber }),
          { notificationId: `${orderId}-placed` },
        ).catch((err: unknown) => log.warn('placeOrder: notification failed', { orderId, error: errorMessage(err) })),
  ]);
  return placed;
}

async function orderTransaction(
  deps: PlaceOrderDeps,
  tx: Transaction,
  uid: string,
  request: PlaceOrderRequest,
  orderRef: DocumentReference,
  now: LocalDateTime,
  nowMs: number,
): Promise<TransactionOutcome> {
  const { db } = deps;

  // ── Reads (every one before the first write) ──
  const existing = await tx.get(orderRef);
  if (existing.exists) {
    if (existing.get('userId') !== uid) throw new HttpsError('internal', 'Order id collision.');
    return { created: false, placed: placedFrom(existing) };
  }

  const userRef = db.collection(P.users).doc(uid);
  const addressRef = userRef.collection(P.addresses).doc(request.addressId);
  const settings = db.collection(P.appSettings);
  const counterRef = db.collection(P.counters).doc(orderCounterId(now));
  const [userSnap, addressSnap, generalSnap, citiesSnap, paymentsSnap, counterSnap] = await tx.getAll(
    userRef,
    addressRef,
    settings.doc('general'),
    settings.doc('cities'),
    settings.doc('payments'),
    counterRef,
  );

  const user = userSnap.data();
  if (user === undefined) throw new HttpsError('failed-precondition', 'Complete your profile before ordering.');
  if (user.isDeleted === true || user.isBlocked === true) {
    throw new HttpsError('permission-denied', 'This account cannot place orders.');
  }

  // The promo code and its per-customer usage; the wallet when it may pay.
  const promoRef =
    request.promoCode !== null && isPromoDocId(request.promoCode) ? db.collection(P.promoCodes).doc(request.promoCode) : null;
  const usageRef = promoRef?.collection(P.usages).doc(uid) ?? null;
  const [promoSnap, usageSnap] = promoRef === null ? [null, null] : await tx.getAll(promoRef, usageRef!);
  const payWithBalance = request.paymentMethod === 'wallet';
  const wallet = request.useCredits || payWithBalance ? await readWallet(db, tx, uid) : null;

  const cartRef = db.collection(P.carts).doc(uid).collection(P.items);
  // Bounded: the cart is client-written; one line over the limit is enough to refuse.
  const cart = await tx.get(cartRef.limit(MAX_CART_LINES + 1));
  if (cart.empty) throw orderFailure('empty_cart');
  if (cart.size > MAX_CART_LINES) throw bad(`A cart can hold at most ${MAX_CART_LINES} lines.`);

  const address = addressSnap.data();
  if (address === undefined) throw bad('That address does not exist.');

  const productIds = [...new Set(cart.docs.map((d) => string(d.get('productId'))).filter((id) => isDocId(id)))];
  const productSnaps = productIds.length === 0 ? [] : await tx.getAll(...productIds.map((id) => db.collection(P.products).doc(id)));
  const products = new Map(productSnaps.filter((s) => s.exists).map((s) => [s.id, s.data()!]));
  const storeIds = [...new Set([...products.values()].map((p) => string(p.storeId)).filter((id) => isDocId(id)))];
  const storeSnaps = storeIds.length === 0 ? [] : await tx.getAll(...storeIds.map((id) => db.collection(P.stores).doc(id)));
  const stores = new Map(storeSnaps.filter((s) => s.exists).map((s) => [s.id, s.data()!]));

  // ── Re-price every line against the current product ──
  const changed: string[] = [];
  const refresh: Array<{ itemId: string; update: Record<string, unknown> }> = [];
  const lines: PricedLine[] = [];
  for (const doc of cart.docs) {
    const item = doc.data();
    const product = products.get(string(item.productId));
    const check = checkCartLine(doc.id, item, product, product === undefined ? undefined : stores.get(string(product.storeId)));
    if (check.kind === 'unavailable') {
      changed.push(check.productId);
    } else if (check.kind === 'stale') {
      changed.push(check.productId);
      refresh.push({ itemId: doc.id, update: check.refresh });
    } else {
      lines.push(check.line);
    }
  }
  if (changed.length > 0) throw new CartChanged([...new Set(changed)], refresh);

  // ── City (SRS §4.3) ──
  const cityId = string(address.city);
  const city = parseCities(citiesSnap.data()).find((c) => c.id === cityId && c.isActive);
  const blocked =
    city === undefined
      ? lines.map((l) => l.productId)
      : lines
          .filter((l) => {
            const allowed = products.get(l.productId)?.availableCities;
            return Array.isArray(allowed) && allowed.length > 0 && !allowed.includes(cityId);
          })
          .map((l) => l.productId);
  if (city === undefined || blocked.length > 0) throw orderFailure('city_not_allowed', blocked);

  // ── Stock: Σ quantity per product (and per stocked option value) ──
  const demand = stockDemand(lines.map((l) => ({ productId: l.productId, qty: l.qty, values: l.stockedValues })));
  const short = [...demand].filter(([id, d]) => !coversDemand(products.get(id)!, d)).map(([id]) => id);
  if (short.length > 0) throw orderFailure('out_of_stock', short);

  // ── Payment ──
  if (!paymentEnabled(parsePaymentSettings(paymentsSnap.data()), request.paymentMethod)) {
    throw bad('That payment method is not available.');
  }
  if (!SUPPORTED_PAYMENT_METHODS.includes(request.paymentMethod)) {
    throw bad('That payment method is not available yet.');
  }

  // ── Delivery date & slot (SRS §5.11, same rules as CheckoutRules) ──
  const general = parseGeneralSettings(generalSnap.data());
  const maxPreparationDays = Math.max(0, ...lines.map((l) => l.preparationDays));
  const earliest = earliestDeliveryDate(now, maxPreparationDays, general.sameDayCutoff);
  if (request.deliveryDate < earliest || request.deliveryDate > lastDeliveryDate(earliest)) {
    throw bad(`Delivery date must be between ${earliest} and ${lastDeliveryDate(earliest)}.`);
  }
  if (!availableSlots(request.deliveryDate, now, general.deliverySlots).some((s) => s.id === request.deliverySlot)) {
    throw bad('That delivery time is not available.');
  }

  // ── Totals ──
  const subtotal = lines.reduce((sum, l) => sum + l.lineTotal, 0);
  if (!meetsMinimum(subtotal, general.minOrder)) throw orderFailure('min_order');

  // ── Promo code (SRS §5.23, §6.9): every rule, on the re-priced lines ──
  let discount = 0;
  if (request.promoCode !== null) {
    const promo = promoSnap?.exists ? parsePromoCode(promoSnap.id, promoSnap.data()!) : null;
    const evaluation = evaluatePromo(promo, {
      lines: lines.map((l) => ({
        productId: l.productId,
        storeId: l.storeId,
        categoryIds: stringList(products.get(l.productId)?.categoryIds),
        lineTotal: l.lineTotal,
      })),
      nowMs,
      userUsageCount: integer(usageSnap?.get('count')),
      // placeOrder / cancelOrder / onOrderStatusChange keep it = non-cancelled orders.
      userOrderCount: Math.max(0, integer(user.totalOrders)),
    });
    if (!evaluation.valid) throw promoFailure(evaluation.rejection);
    discount = evaluation.discount;
  }

  // ── Credits first, then (wallet payment only) the balance ──
  const totals = checkoutTotals({
    subtotal,
    deliveryFee: city.deliveryFee,
    discount,
    credits: request.useCredits && wallet !== null ? Math.max(0, wallet.credits) : 0,
    wallet: payWithBalance && wallet !== null ? Math.max(0, wallet.balance) : 0,
  });
  if (payWithBalance && totals.total > 0) throw orderFailure('insufficient_funds');
  const viaGateway = GATEWAY_PAYMENT_METHODS.includes(request.paymentMethod);
  if (viaGateway && totals.total < MIN_GATEWAY_AMOUNT) {
    throw bad(`Online payment needs at least ${MIN_GATEWAY_AMOUNT} IQD to pay. Choose another payment method.`);
  }
  const lots: CreditLot[] = totals.creditsUsed > 0 ? await readOpenCreditLots(db, tx, uid) : [];

  // ── Order number (PROVISIONAL storage, SRS §12 item 8) ──
  const sequence = Math.max(1, integer(counterSnap.get('next'), 1));
  const orderNumber = formatOrderNumber(now, sequence);

  // ── Writes ──
  const ts = FieldValue.serverTimestamp();
  const status: OrderStatus = 'pending';
  const paymentStatus: PaymentStatus = payWithBalance ? 'paid' : 'pending';
  tx.set(counterRef, { next: sequence + 1, updatedAt: ts }, { merge: true });
  tx.create(orderRef, {
    orderNumber,
    userId: uid,
    storeIds: [...new Set(lines.map((l) => l.storeId))],
    // The review rules check "the customer bought it" against this (SRS §5.26).
    productIds: [...new Set(lines.map((l) => l.productId))],
    items: lines.map((l) => orderItem(l, status)),
    subtotal: totals.subtotal,
    discount: totals.discount,
    promoCode: promoRef === null ? null : promoRef.id,
    creditsUsed: totals.creditsUsed,
    walletUsed: totals.walletUsed,
    deliveryFee: totals.deliveryFee,
    total: totals.total,
    paymentMethod: request.paymentMethod,
    paymentStatus,
    paymentRef: null,
    ...(viaGateway && { paymentDueBy: Timestamp.fromMillis(nowMs + PAYMENT_WINDOW_MS) }),
    address: addressSnapshot(address),
    deliveryDate: request.deliveryDate,
    deliverySlot: request.deliverySlot,
    isGift: request.isGift,
    giftMessage: request.giftMessage,
    hidePrices: request.hidePrices,
    status,
    cancelReason: null,
    orderType: 'standard',
    referralCredited: false,
    refundedToWallet: false,
    rewards: {},
    statusNote: null,
    statusUpdatedBy: uid,
    statusUpdatedByRole: 'customer',
    clientRequestId: request.clientRequestId,
    createdAt: ts,
    updatedAt: ts,
  });
  // The first timeline entry. Later ones come only from onOrderStatusChange
  // (creating a document is not an update, so the trigger never writes this one).
  tx.create(orderRef.collection(P.statusHistory).doc(), {
    status,
    byUid: uid,
    byRole: 'customer',
    note: null,
    at: ts,
  });
  for (const [productId, d] of demand) {
    tx.update(db.collection(P.products).doc(productId), stockUpdate(products.get(productId)!, d, 1));
  }
  for (const doc of cart.docs) tx.delete(doc.ref);
  // totalSpent is added when the order is delivered (onOrderStatusChange).
  tx.update(userRef, { totalOrders: FieldValue.increment(1) });

  if (promoRef !== null) {
    tx.update(promoRef, { usageCount: FieldValue.increment(1) });
    tx.set(usageRef!, { count: FieldValue.increment(1), updatedAt: ts }, { merge: true });
  }
  if (wallet !== null && totals.creditsUsed + totals.walletUsed > 0) {
    // Transactions order-{id}-1 (credits) and -2 (balance): fixed ids, like the order's.
    const ledger = new WalletLedger(tx, wallet, { idPrefix: `order-${orderRef.id}`, openLots: lots });
    const txn = { type: 'orderPayment' as const, title: orderPaymentTitle(orderNumber), orderId: orderRef.id };
    if (totals.creditsUsed > 0) ledger.spendCredits(totals.creditsUsed, txn);
    if (totals.walletUsed > 0) ledger.spendBalance(totals.walletUsed, txn);
    ledger.apply();
  }

  return {
    created: true,
    placed: { orderId: orderRef.id, orderNumber, total: totals.total, deliveryDate: request.deliveryDate },
    viaGateway,
  };
}

/** Writes the current prices / preparation days onto stale cart lines (best effort). */
async function refreshCart(
  db: Firestore,
  uid: string,
  refresh: Array<{ itemId: string; update: Record<string, unknown> }>,
  log: Pick<typeof functionsLogger, 'warn'>,
): Promise<void> {
  if (refresh.length === 0) return;
  try {
    const batch = db.batch();
    const items = db.collection(P.carts).doc(uid).collection(P.items);
    for (const r of refresh) batch.update(items.doc(r.itemId), r.update);
    await batch.commit();
  } catch (e) {
    log.warn('placeOrder: cart refresh failed', { uid, error: errorMessage(e) });
  }
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

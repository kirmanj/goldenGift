/**
 * `createPaymentSession` (SRS §5.11, §5.18, §6.14): the signed-in customer
 * starts paying a ZainCash order, or tops up their wallet balance.
 *
 * Data `{ purpose: 'order', orderId }` | `{ purpose: 'topUp', amount }` (whole
 * IQD, 5,000–1,000,000) → `{ sessionId, payUrl, expiresAt }` (ISO-8601).
 * Writes `payment_sessions/{sessionId}` `{ uid, purpose, orderId, orderNumber,
 * amount, currency, gateway: 'zainCash', env, status: 'pending', gatewayTxnId,
 * payUrl, expiresAt, lang, createdAt, updatedAt }`, then creates the gateway
 * transaction (its `orderId` = the session id) and stores its id + pay URL. The
 * app opens `payUrl`; the gateway sends the customer back through
 * `zainCashReturn`, which settles the session (settlePayment.ts) and deep-links
 * to `goldengift://payment?sid=…&status=…`.
 *
 * An order session expires with the order (`paymentDueBy`, 30 min after it was
 * placed); a top-up session after 30 minutes. A new session for the same order
 * can be started while it is still payable (e.g. after the customer backed out).
 *
 * Errors: unauthenticated; invalid-argument; not-found ("Order not found.");
 * permission-denied (not the owner / blocked account); failed-precondition
 * `{ reason }` = gateway_disabled (`app_settings/payments.zainCash` off) |
 * not_payable | already_paid | expired; unavailable (gateway not configured or
 * not answering — nothing is charged, try again); resource-exhausted (more than
 * 20 sessions per customer in a rolling hour).
 */
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { parsePaymentSettings } from '../orders/checkoutRules';
import { MIN_GATEWAY_AMOUNT, PAYMENT_WINDOW_MS } from '../orders/placeOrder';
import { epochMillis, integer, string } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { consumeRateLimit, type RateLimit } from '../shared/rateLimit';
import { orderServiceType, TOP_UP_SERVICE_TYPE } from './paymentTexts';
import { awaitsPayment } from './settlePayment';
import type { PaymentGateway } from './zainCash';

export const TOP_UP_MIN = 5_000;
export const TOP_UP_MAX = 1_000_000;
/** A top-up session (and its gateway token) is valid this long. */
export const TOP_UP_WINDOW_MS = PAYMENT_WINDOW_MS;
/** Payment sessions per customer per rolling hour (each one is a gateway transaction). */
export const SESSION_RATE_LIMIT: RateLimit = { limit: 20, windowMs: 60 * 60 * 1000 };

export const PaymentFailureReason = ['gateway_disabled', 'not_payable', 'already_paid', 'expired'] as const;
export type PaymentFailureReason = (typeof PaymentFailureReason)[number];

const MESSAGES: Record<PaymentFailureReason, string> = {
  gateway_disabled: 'Online payment is switched off.',
  not_payable: 'This order cannot be paid online.',
  already_paid: 'This order is already paid.',
  expired: 'The time to pay this order has run out.',
};

export function paymentFailure(reason: PaymentFailureReason): HttpsError {
  return new HttpsError('failed-precondition', MESSAGES[reason], { reason });
}

export type PaymentSessionRequest = { purpose: 'order'; orderId: string } | { purpose: 'topUp'; amount: number };

export interface PaymentSessionResponse {
  sessionId: string;
  payUrl: string;
  /** ISO-8601. */
  expiresAt: string;
}

export interface CreatePaymentSessionDeps {
  db: Firestore;
  /** null = not configured → `unavailable`. */
  gateway: PaymentGateway | null;
  /** `zainCashReturn`'s public URL (the session id is appended as `?sid=`). */
  returnUrl: string;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'error'>;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parsePaymentSessionData(data: unknown): PaymentSessionRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad("Expected { purpose: 'order', orderId } or { purpose: 'topUp', amount }.");
  }
  const d = data as Record<string, unknown>;
  if (d.purpose === 'order') {
    const id = d.orderId;
    if (typeof id !== 'string' || id.length === 0 || id.length > 128 || id.includes('/') || id === '.' || id === '..') {
      throw bad('`orderId` is missing or invalid.');
    }
    return { purpose: 'order', orderId: id };
  }
  if (d.purpose === 'topUp') {
    const amount = d.amount;
    if (typeof amount !== 'number' || !Number.isInteger(amount) || amount < TOP_UP_MIN || amount > TOP_UP_MAX) {
      throw bad(`\`amount\` must be a whole number of IQD between ${TOP_UP_MIN} and ${TOP_UP_MAX}.`);
    }
    return { purpose: 'topUp', amount };
  }
  throw bad("`purpose` must be 'order' or 'topUp'.");
}

/** The gateway page language for the customer's app language. */
export function gatewayLang(locale: unknown): 'en' | 'ar' | 'ku' {
  return locale === 'ar' ? 'ar' : locale === 'ckb' || locale === 'ku' ? 'ku' : 'en';
}

export async function createPaymentSessionCore(
  deps: CreatePaymentSessionDeps,
  data: unknown,
  uid: string | undefined,
): Promise<PaymentSessionResponse> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to pay.');
  const request = parsePaymentSessionData(data);
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const nowMs = (deps.now ?? Date.now)();

  const settings = parsePaymentSettings((await db.collection(P.appSettings).doc('payments').get()).data());
  if (!settings.zainCash) throw paymentFailure('gateway_disabled');
  const gateway = deps.gateway;
  if (gateway === null) throw new HttpsError('unavailable', 'Online payment is not available right now.');
  await consumeRateLimit(db, `rl:paySession:${uid}`, SESSION_RATE_LIMIT, nowMs, 'Too many payment attempts. Please try again later.');

  const sessionRef = db.collection(P.paymentSessions).doc();
  const userRef = db.collection(P.users).doc(uid);
  const prepared = await db.runTransaction(async (tx) => {
    const user = (await tx.get(userRef)).data();
    if (user === undefined) throw new HttpsError('failed-precondition', 'Complete your profile first.');
    if (user.isDeleted === true || user.isBlocked === true) throw new HttpsError('permission-denied', 'This account cannot pay.');

    let amount: number;
    let expiresAtMs: number;
    let orderNumber: string | null = null;
    if (request.purpose === 'order') {
      const order = (await tx.get(db.collection(P.orders).doc(request.orderId))).data();
      if (order === undefined) throw new HttpsError('not-found', 'Order not found.');
      if (order.userId !== uid) throw new HttpsError('permission-denied', 'This is not your order.');
      if (order.paymentStatus === 'paid') throw paymentFailure('already_paid');
      if (!awaitsPayment(order, uid, gateway.id)) throw paymentFailure('not_payable');
      const dueMs = epochMillis(order.paymentDueBy);
      if (dueMs === null || dueMs <= nowMs) throw paymentFailure('expired');
      amount = integer(order.total);
      if (amount < MIN_GATEWAY_AMOUNT) throw paymentFailure('not_payable');
      expiresAtMs = dueMs;
      orderNumber = string(order.orderNumber) || null;
    } else {
      amount = request.amount;
      expiresAtMs = nowMs + TOP_UP_WINDOW_MS;
    }

    const lang = gatewayLang(user.locale);
    const ts = FieldValue.serverTimestamp();
    tx.create(sessionRef, {
      uid,
      purpose: request.purpose,
      orderId: request.purpose === 'order' ? request.orderId : null,
      orderNumber,
      amount,
      currency: 'IQD',
      gateway: gateway.id,
      env: gateway.env,
      status: 'pending',
      gatewayTxnId: null,
      payUrl: null,
      expiresAt: Timestamp.fromMillis(expiresAtMs),
      lang,
      createdAt: ts,
      updatedAt: ts,
    });
    return { amount, expiresAtMs, orderNumber, lang };
  });

  let created: { transactionId: string; payUrl: string };
  try {
    created = await gateway.createTransaction(
      {
        reference: sessionRef.id,
        amount: prepared.amount,
        serviceType: prepared.orderNumber === null ? TOP_UP_SERVICE_TYPE : orderServiceType(prepared.orderNumber),
        redirectUrl: `${deps.returnUrl}?sid=${encodeURIComponent(sessionRef.id)}`,
        lang: prepared.lang,
        expiresAtMs: prepared.expiresAtMs,
      },
      nowMs,
    );
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    log.error('createPaymentSession: gateway init failed', { sessionId: sessionRef.id, error: message });
    // Nothing was charged; the order stays payable until paymentDueBy.
    await sessionRef
      .update({
        status: 'failed',
        // The customer reads their session: the gateway's own error text stays in the log.
        failureReason: 'init_failed',
        settledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      })
      .catch(() => undefined);
    throw new HttpsError('unavailable', 'Online payment is not available right now. Please try again.');
  }

  await sessionRef.update({
    gatewayTxnId: created.transactionId,
    payUrl: created.payUrl,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { sessionId: sessionRef.id, payUrl: created.payUrl, expiresAt: new Date(prepared.expiresAtMs).toISOString() };
}

/**
 * Online payments (ZainCash, SRS §5.11, §5.18, §12 item 4) against the Firestore
 * emulator: placeOrder with `zainCash`, createPaymentSession, zainCashReturn
 * (success / failure / tampered token / replay / late payment), wallet top-ups and
 * expirePaymentSessions. The gateway is the real ZainCash client with a fake
 * fetch and a local signing secret, so every return token is really verified.
 * Own demo- project; skipped without the emulator (see ./emulators.ts).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { cancelOrderCore } from '../src/orders/cancelOrder';
import { handleOrderStatusChange } from '../src/orders/onOrderStatusChange';
import { placeOrderCore, type PlaceOrderDeps } from '../src/orders/placeOrder';
import { CHECK_RATE_LIMIT, checkPaymentStatusCore } from '../src/payments/checkPaymentStatus';
import { expirePaymentSessions } from '../src/payments/expirePayments';
import { signHs256 } from '../src/payments/jwt';
import { createPaymentSessionCore, type CreatePaymentSessionDeps } from '../src/payments/paymentSessions';
import { ZAINCASH_HOSTS, zainCashGateway, type FetchLike, type PaymentGateway } from '../src/payments/zainCash';
import { handleZainCashReturn, type ReturnDeps } from '../src/payments/zainCashReturn';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { assertWalletConsistent, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-payments';
const SECRET = 'local-test-secret';
const RETURN_URL = 'https://europe-west1-demo.cloudfunctions.net/zainCashReturn';
/** 2026-10-21 08:00 in Baghdad: the morning slot is open. */
const OCT_21_8AM = Date.UTC(2026, 9, 21, 5, 0);
const MINUTE = 60 * 1000;
const silent = { warn: () => undefined, info: () => undefined, error: () => undefined };

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    if (reason !== undefined) assert.equal((e.details as { reason?: string } | undefined)?.reason, reason);
    return true;
  });
}

describe('online payments — ZainCash (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `payments-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  let clock = OCT_21_8AM;

  // ── Fake ZainCash HTTP API behind the real client ──
  let txnSeq = 0;
  let initFails = false;
  const gatewayStatus = new Map<string, string>();
  const inits: URLSearchParams[] = [];
  /** Server-to-server status checks (`/transaction/get`) made. */
  let gets = 0;
  const fakeFetch: FetchLike = async (url, init) => {
    const form = new URLSearchParams(init.body);
    let body: unknown;
    if (url.endsWith('/transaction/init')) {
      inits.push(form);
      body = initFails ? { err: { msg: 'Service unavailable' } } : { id: `txn-${++txnSeq}`, status: 'pending' };
    } else {
      gets++;
      const claims = JSON.parse(Buffer.from(form.get('token')!.split('.')[1], 'base64url').toString()) as { id: string };
      body = { id: claims.id, status: gatewayStatus.get(claims.id) ?? 'pending', amount: '0' };
    }
    return { ok: true, status: 200, text: async () => JSON.stringify(body) };
  };
  const gateway: PaymentGateway = zainCashGateway(
    { env: 'test', host: ZAINCASH_HOSTS.test, merchantId: 'merchant-1', msisdn: '9647835077893', secret: SECRET, publicTestMerchant: false },
    { fetch: fakeFetch },
  );

  const orderDeps: PlaceOrderDeps = { db, messaging: fcm, now: () => clock, logger: silent };
  const sessionDeps = (over: Partial<CreatePaymentSessionDeps> = {}): CreatePaymentSessionDeps => ({
    db,
    gateway,
    returnUrl: RETURN_URL,
    now: () => clock,
    logger: silent,
    ...over,
  });
  const returnDeps: ReturnDeps = { db, messaging: fcm, gateway, now: () => clock, logger: silent };

  const read = async (path: string) => (await db.doc(path).get()).data();
  const placedNotice = async (orderId: string) => (await db.doc(`notifications/${orderId}-placed`).get()).exists;

  /** What ZainCash appends to the redirect URL: a JWT signed with the merchant secret. */
  const returnToken = (sid: string, txnId: string, status: string, secret = SECRET) =>
    signHs256({ status, orderid: sid, id: txnId, ...(status === 'failed' && { msg: 'Not enough credit on balance' }), iat: Math.floor(clock / 1000), exp: Math.floor(clock / 1000) + 3600 }, secret);
  const back = (sid: string, token?: string) => handleZainCashReturn(returnDeps, { sid, ...(token !== undefined && { token }) });

  async function addToCart(uid: string, id: string, qty = 1): Promise<void> {
    await db.doc(`carts/${uid}/items/${id}`).set({
      productId: 'mug',
      storeId: 'home',
      titleSnapshot: 'Mug',
      imageSnapshot: null,
      unitPrice: 15000,
      qty,
      selections: [],
      lineTotal: 15000 * qty,
      preparationDays: 0,
      addedAt: Timestamp.now(),
    });
  }

  /** Places a ZainCash order of `qty` mugs for alice (1 mug = 15,000 + 3,000 delivery). */
  async function placeZainCash(request = 'req-1', over: Record<string, unknown> = {}, qty = 2) {
    await addToCart('alice', `line-${request}`, qty);
    return placeOrderCore(
      orderDeps,
      {
        clientRequestId: request,
        addressId: 'home',
        deliveryDate: '2026-10-21',
        deliverySlot: 'morning',
        isGift: false,
        hidePrices: false,
        paymentMethod: 'zainCash',
        promoCode: null,
        useCredits: false,
        useWallet: false,
        ...over,
      },
      'alice',
    );
  }

  const startPayment = (orderId: string, uid = 'alice') => createPaymentSessionCore(sessionDeps(), { purpose: 'order', orderId }, uid);

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    clock = OCT_21_8AM;
    txnSeq = 0;
    initFails = false;
    gatewayStatus.clear();
    inits.length = 0;
    gets = 0;
    const batch = db.batch();
    batch.set(db.doc('app_settings/general'), { sameDayCutoff: '14:00', minOrder: 0 });
    batch.set(db.doc('app_settings/cities'), { items: [{ id: 'erbil', name: 'Erbil', deliveryFee: 3000, isActive: true }] });
    batch.set(db.doc('app_settings/payments'), { cashOnDelivery: true, wallet: true, card: false, fastPay: false, zainCash: true });
    batch.set(db.doc('app_settings/referral'), { joinBonus: 0, orderBonus: 0, maxReferralsPerMonth: 0, creditsExpiryDays: 90 });
    batch.set(db.doc('stores/home'), { name: 'Golden Gift Home', status: 'active' });
    batch.set(db.doc('products/mug'), { title: 'Mug', storeId: 'home', images: [], price: 15000, isActive: true, availability: 'sameDay', preparationDays: 0, availableCities: [], stock: 10, salesCount: 0 });
    batch.set(db.doc('promo_codes/GOLD10'), {
      code: 'GOLD10', title: 'GOLD10', type: 'percent', value: 10, usageCount: 0, perUserLimit: 5, firstOrderOnly: false,
      categoryIds: [], storeIds: [], isPublic: true, isActive: true, expiresAt: Timestamp.fromMillis(OCT_21_8AM + 30 * 24 * 60 * MINUTE),
    });
    for (const uid of ['alice', 'bob']) {
      batch.set(db.doc(`users/${uid}`), { name: uid, phone: '7501234567', countryCode: '+964', locale: uid === 'alice' ? 'ar' : 'en', fcmTokens: [`tok-${uid}`], notificationsEnabled: true, totalOrders: 0, totalSpent: 0, isBlocked: false, isDeleted: false });
      batch.set(db.doc(`users/${uid}/addresses/home`), { label: 'Home', name: uid, phone: '7501234567', city: 'erbil', area: 'Ankawa', street: '', building: '', floor: '', notes: '', isDefault: true });
    }
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  // ── placeOrder ──

  test('placeOrder: zainCash only when enabled; pending payment due in 30 min, stock reserved, productIds, no "received" yet', async () => {
    await db.doc('app_settings/payments').update({ zainCash: false });
    await rejectsWith(placeZainCash(), 'invalid-argument');
    await db.doc('app_settings/payments').update({ zainCash: true });

    const placed = await placeZainCash(); // the refused attempt left its cart line: same line, same request
    assert.equal(placed.total, 33000);
    const order = await read(`orders/${placed.orderId}`);
    assert.equal(order?.paymentMethod, 'zainCash');
    assert.equal(order?.paymentStatus, 'pending');
    assert.equal(order?.status, 'pending');
    assert.ok((order?.paymentDueBy as Timestamp).isEqual(Timestamp.fromMillis(clock + 30 * MINUTE)));
    assert.deepEqual(order?.productIds, ['mug']);
    assert.equal((await read('products/mug'))?.stock, 8);
    assert.equal(await placedNotice(placed.orderId), false);
  });

  test('placeOrder: a cash order gets productIds and no paymentDueBy; nothing left to pay online → refused', async () => {
    await addToCart('alice', 'cod');
    const cod = await placeOrderCore(orderDeps, { clientRequestId: 'cod', addressId: 'home', deliveryDate: '2026-10-21', deliverySlot: 'morning', paymentMethod: 'cashOnDelivery' }, 'alice');
    const order = await read(`orders/${cod.orderId}`);
    assert.deepEqual(order?.productIds, ['mug']);
    assert.equal(order?.paymentDueBy, undefined);
    assert.equal(await placedNotice(cod.orderId), true);

    await grantCredits(db, 'alice', 18000);
    await rejectsWith(placeZainCash('all-credits', { useCredits: true }, 1), 'invalid-argument');
  });

  // ── createPaymentSession ──

  test('createPaymentSession (order): session doc + gateway transaction for the order total', async () => {
    const placed = await placeZainCash();
    const session = await startPayment(placed.orderId);
    assert.equal(session.payUrl, 'https://test.zaincash.iq/transaction/pay?id=txn-1');
    assert.equal(session.expiresAt, new Date(clock + 30 * MINUTE).toISOString());

    const doc = await read(`payment_sessions/${session.sessionId}`);
    assert.equal(doc?.uid, 'alice');
    assert.equal(doc?.purpose, 'order');
    assert.equal(doc?.orderId, placed.orderId);
    assert.equal(doc?.orderNumber, placed.orderNumber);
    assert.equal(doc?.amount, 33000);
    assert.equal(doc?.gateway, 'zainCash');
    assert.equal(doc?.env, 'test');
    assert.equal(doc?.status, 'pending');
    assert.equal(doc?.gatewayTxnId, 'txn-1');
    assert.equal(doc?.payUrl, session.payUrl);
    assert.equal(doc?.lang, 'ar');
    assert.ok(doc?.createdAt instanceof Timestamp && doc?.updatedAt instanceof Timestamp);

    const claims = JSON.parse(Buffer.from(inits[0].get('token')!.split('.')[1], 'base64url').toString());
    assert.equal(claims.amount, 33000);
    assert.equal(claims.orderId, session.sessionId);
    assert.equal(claims.redirectUrl, `${RETURN_URL}?sid=${session.sessionId}`);
    assert.equal(claims.serviceType, `Golden Gift order ${placed.orderNumber}`);
    assert.equal(inits[0].get('lang'), 'ar');
  });

  test('createPaymentSession errors', async () => {
    const placed = await placeZainCash();
    await rejectsWith(startPayment(placed.orderId, 'bob'), 'permission-denied');
    await rejectsWith(startPayment('missing'), 'not-found');
    await rejectsWith(createPaymentSessionCore(sessionDeps(), { purpose: 'order', orderId: placed.orderId }, undefined), 'unauthenticated');
    await rejectsWith(createPaymentSessionCore(sessionDeps(), { purpose: 'topUp', amount: 4999 }, 'alice'), 'invalid-argument');
    await rejectsWith(createPaymentSessionCore(sessionDeps(), { purpose: 'topUp', amount: 1_000_001 }, 'alice'), 'invalid-argument');
    await rejectsWith(createPaymentSessionCore(sessionDeps(), { purpose: 'refund' }, 'alice'), 'invalid-argument');
    await rejectsWith(createPaymentSessionCore(sessionDeps({ gateway: null }), { purpose: 'order', orderId: placed.orderId }, 'alice'), 'unavailable');

    await addToCart('alice', 'cod');
    const cod = await placeOrderCore(orderDeps, { clientRequestId: 'cod', addressId: 'home', deliveryDate: '2026-10-21', deliverySlot: 'morning', paymentMethod: 'cashOnDelivery' }, 'alice');
    await rejectsWith(startPayment(cod.orderId), 'failed-precondition', 'not_payable');

    await db.doc('app_settings/payments').update({ zainCash: false });
    await rejectsWith(startPayment(placed.orderId), 'failed-precondition', 'gateway_disabled');
    await db.doc('app_settings/payments').update({ zainCash: true });

    clock += 31 * MINUTE;
    await rejectsWith(startPayment(placed.orderId), 'failed-precondition', 'expired');
  });

  test('gateway down at init → unavailable, nothing charged, the order stays payable', async () => {
    const placed = await placeZainCash();
    initFails = true;
    await rejectsWith(startPayment(placed.orderId), 'unavailable');
    const failed = await db.collection('payment_sessions').where('orderId', '==', placed.orderId).get();
    assert.equal(failed.size, 1);
    assert.equal(failed.docs[0].get('status'), 'failed');
    assert.match(failed.docs[0].get('failureReason'), /^init_failed/);
    assert.equal((await read(`orders/${placed.orderId}`))?.status, 'pending');
    initFails = false;
    const retry = await startPayment(placed.orderId);
    assert.equal((await read(`payment_sessions/${retry.sessionId}`))?.status, 'pending');
  });

  // ── zainCashReturn ──

  test('success: the verified token marks the order paid once; replays change nothing', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);

    const page = await back(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    assert.equal(page.httpStatus, 200);
    assert.equal(page.status, 'paid');
    assert.ok(page.html.includes(`goldengift://payment?sid=${sessionId}&amp;status=paid`));

    const order = await read(`orders/${placed.orderId}`);
    assert.equal(order?.paymentStatus, 'paid');
    assert.equal(order?.paymentRef, 'txn-1');
    assert.ok(order?.paidAt instanceof Timestamp);
    assert.equal(order?.status, 'pending');
    const session = await read(`payment_sessions/${sessionId}`);
    assert.equal(session?.status, 'paid');
    assert.equal(session?.gatewayStatus, 'success');
    assert.equal(session?.creditedToWallet, false);
    assert.equal(await placedNotice(placed.orderId), true);
    assert.equal(fcm.calls.length, 1);

    // Replay (browser refresh, attacker re-sending the URL): nothing changes.
    const again = await back(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    assert.equal(again.status, 'paid');
    assert.equal(fcm.calls.length, 1);
    // A failure token after success cannot undo it.
    assert.equal((await back(sessionId, returnToken(sessionId, 'txn-1', 'failed'))).status, 'paid');
    assert.equal((await read(`orders/${placed.orderId}`))?.paymentStatus, 'paid');
    assert.equal((await walletTxns(db, 'alice')).length, 0);
    await rejectsWith(startPayment(placed.orderId), 'failed-precondition', 'already_paid');
  });

  test('failure: the order is cancelled through the cancellation path (stock, credits, promo back) and is never paid', async () => {
    await grantCredits(db, 'alice', 5000);
    const placed = await placeZainCash('req-1', { useCredits: true, promoCode: 'GOLD10' });
    assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 1);
    const { sessionId } = await startPayment(placed.orderId);

    const page = await back(sessionId, returnToken(sessionId, 'txn-1', 'failed'));
    assert.equal(page.status, 'failed');
    const order = await read(`orders/${placed.orderId}`);
    assert.equal(order?.status, 'cancelledByBuyer');
    assert.equal(order?.cancelReason, 'payment_failed');
    assert.equal(order?.paymentStatus, 'failed');
    assert.equal(order?.statusUpdatedByRole, 'system');
    assert.equal(order?.statusUpdatedBy, null);
    assert.ok((order?.items as DocumentData[]).every((i) => i.status === 'cancelledByBuyer'));
    assert.equal((await read('products/mug'))?.stock, 10);
    assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 0);
    assert.equal((await read('wallets/alice'))?.credits, 5000);
    assert.equal((await read('users/alice'))?.totalOrders, 0);
    const session = await read(`payment_sessions/${sessionId}`);
    assert.equal(session?.status, 'failed');
    assert.equal(session?.failureReason, 'Not enough credit on balance');

    // The customer hears "the payment didn't go through", not "cancelled as you requested".
    await handleOrderStatusChange({ db, messaging: null }, { eventId: 'evt-1', orderId: placed.orderId, before: { ...order, status: 'pending' }, after: order });
    const notes = await db.collection('notifications').where('userId', '==', 'alice').get();
    const cancelled = notes.docs.find((d) => d.id.startsWith(`${placed.orderId}-cancelledByBuyer`));
    assert.match(cancelled?.get('body') as string, /payment didn't go through/);
    assert.match(cancelled?.get('bodyAr') as string, /الدفع/);

    // A success that still arrives (late) goes to the wallet balance, once — never a paid order.
    const late = await back(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    assert.equal(late.status, 'paid');
    await back(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    const after = await read(`orders/${placed.orderId}`);
    assert.equal(after?.paymentStatus, 'failed');
    assert.equal(after?.status, 'cancelledByBuyer');
    const wallet = await read('wallets/alice');
    assert.equal(wallet?.balance, placed.total);
    const lateSession = await read(`payment_sessions/${sessionId}`);
    assert.equal(lateSession?.creditedToWallet, true);
    assert.equal(lateSession?.lateFrom, 'failed');
    const refunds = (await walletTxns(db, 'alice')).filter((t) => t.id === `payment-${sessionId}-1`);
    assert.equal(refunds.length, 1);
    assert.equal(refunds[0].type, 'refund');
    await assertWalletConsistent(db, 'alice');
  });

  test('tampered, foreign or missing tokens change nothing', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);
    const other = await startPayment(placed.orderId); // txn-2

    const forged = await back(sessionId, returnToken(sessionId, 'txn-1', 'success', 'attacker-secret'));
    assert.deepEqual([forged.httpStatus, forged.status], [400, 'error']);
    const [h, , s] = returnToken(sessionId, 'txn-1', 'failed').split('.');
    const swapped = Buffer.from(JSON.stringify({ status: 'success', orderid: sessionId, id: 'txn-1' })).toString('base64url');
    assert.equal((await back(sessionId, `${h}.${swapped}.${s}`)).status, 'error');
    // A valid token of the OTHER session presented with this sid.
    assert.equal((await back(sessionId, returnToken(other.sessionId, 'txn-2', 'success'))).httpStatus, 400);
    // A valid token naming another gateway transaction than the session's.
    assert.equal((await back(sessionId, returnToken(sessionId, 'txn-2', 'success'))).httpStatus, 400);
    // Unknown session.
    assert.equal((await back('nope', returnToken('nope', 'txn-9', 'success'))).httpStatus, 404);
    // "Cancel and go back": no token.
    const cancelled = await back(sessionId);
    assert.deepEqual([cancelled.httpStatus, cancelled.status], [200, 'pending']);
    // Not configured: cannot verify.
    const noGateway = await handleZainCashReturn({ ...returnDeps, gateway: null }, { sid: sessionId, token: returnToken(sessionId, 'txn-1', 'success') });
    assert.deepEqual([noGateway.httpStatus, noGateway.status], [503, 'error']);

    assert.equal((await read(`orders/${placed.orderId}`))?.paymentStatus, 'pending');
    assert.equal((await read(`payment_sessions/${sessionId}`))?.status, 'pending');
    assert.equal((await read(`payment_sessions/${other.sessionId}`))?.status, 'pending');
  });

  test('two sessions for one order: the second success goes to the wallet', async () => {
    const placed = await placeZainCash();
    const first = await startPayment(placed.orderId);
    const second = await startPayment(placed.orderId);
    await back(first.sessionId, returnToken(first.sessionId, 'txn-1', 'success'));
    await back(second.sessionId, returnToken(second.sessionId, 'txn-2', 'completed'));
    assert.equal((await read(`orders/${placed.orderId}`))?.paymentRef, 'txn-1');
    assert.equal((await read('wallets/alice'))?.balance, placed.total);
    await assertWalletConsistent(db, 'alice');
  });

  test('cancelling a PAID ZainCash order returns the paid total to the balance', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);
    await back(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    await cancelOrderCore(db, { orderId: placed.orderId }, 'alice', { now: () => clock });
    const order = await read(`orders/${placed.orderId}`);
    assert.equal(order?.paymentStatus, 'refunded');
    assert.equal(order?.refundedBalance, placed.total);
    assert.equal((await read('wallets/alice'))?.balance, placed.total);
    await assertWalletConsistent(db, 'alice');
  });

  // ── Wallet top-up ──

  test('top-up: credited to the balance exactly once (topUp transaction)', async () => {
    const session = await createPaymentSessionCore(sessionDeps(), { purpose: 'topUp', amount: 50000 }, 'bob');
    assert.equal(session.expiresAt, new Date(clock + 30 * MINUTE).toISOString());
    const doc = await read(`payment_sessions/${session.sessionId}`);
    assert.deepEqual([doc?.purpose, doc?.orderId, doc?.amount, doc?.lang], ['topUp', null, 50000, 'en']);

    await back(session.sessionId, returnToken(session.sessionId, 'txn-1', 'success'));
    await back(session.sessionId, returnToken(session.sessionId, 'txn-1', 'success'));
    const wallet = await read('wallets/bob');
    assert.deepEqual([wallet?.balance, wallet?.credits], [50000, 0]);
    const txns = await walletTxns(db, 'bob');
    assert.deepEqual(txns.map((t) => [t.id, t.type, t.amount, t.bucket]), [[`topUp-${session.sessionId}-1`, 'topUp', 50000, 'balance']]);
    assert.equal(txns[0].title, 'Top-up · ZainCash');
    assert.equal((await read(`payment_sessions/${session.sessionId}`))?.walletTxnId, `topUp-${session.sessionId}-1`);
    await assertWalletConsistent(db, 'bob');
  });

  test('top-up failure: nothing credited', async () => {
    const session = await createPaymentSessionCore(sessionDeps(), { purpose: 'topUp', amount: 10000 }, 'bob');
    assert.equal((await back(session.sessionId, returnToken(session.sessionId, 'txn-1', 'failed'))).status, 'failed');
    assert.equal(await read('wallets/bob'), undefined);
  });

  // ── expirePaymentSessions ──

  test('expiry: unpaid orders cancelled (payment_expired), paid-at-gateway reconciled, idempotent', async () => {
    const a = await placeZainCash('a', {}, 1); // session, never paid
    const b = await placeZainCash('b', {}, 1); // no session at all
    const c = await placeZainCash('c', {}, 1); // paid at ZainCash, the customer never came back
    const d = await placeZainCash('d', {}, 1); // cancelled by the customer while unpaid
    const sa = await startPayment(a.orderId);
    const sc = await startPayment(c.orderId);
    await cancelOrderCore(db, { orderId: d.orderId }, 'alice', { now: () => clock });
    gatewayStatus.set('txn-2', 'completed');
    assert.equal((await read('products/mug'))?.stock, 7);

    // Not due yet: nothing happens.
    clock += 29 * MINUTE;
    assert.deepEqual(await expirePaymentSessions({ db, messaging: fcm, gateway, logger: silent }, clock), {
      sessionsPaid: [], sessionsFailed: [], sessionsExpired: [], ordersCancelled: [], ordersReleased: [],
    });

    clock += 2 * MINUTE;
    const run = await expirePaymentSessions({ db, messaging: fcm, gateway, logger: silent }, clock);
    assert.deepEqual(run.sessionsPaid, [sc.sessionId]);
    assert.deepEqual(run.sessionsExpired, [sa.sessionId]);
    assert.deepEqual(new Set(run.ordersCancelled), new Set([a.orderId, b.orderId]));
    assert.deepEqual(run.ordersReleased, [d.orderId]);

    for (const id of [a.orderId, b.orderId]) {
      const o = await read(`orders/${id}`);
      assert.deepEqual([o?.status, o?.cancelReason, o?.paymentStatus, o?.statusUpdatedByRole], ['cancelledByBuyer', 'payment_expired', 'failed', 'system']);
    }
    const paid = await read(`orders/${c.orderId}`);
    assert.deepEqual([paid?.status, paid?.paymentStatus, paid?.paymentRef], ['pending', 'paid', 'txn-2']);
    assert.equal((await read(`orders/${d.orderId}`))?.paymentDueBy, undefined);
    assert.equal((await read(`payment_sessions/${sa.sessionId}`))?.status, 'expired');
    assert.equal((await read('products/mug'))?.stock, 9); // only c still holds its unit

    // A success arriving after expiry is credited to the wallet, never pays the cancelled order.
    await back(sa.sessionId, returnToken(sa.sessionId, 'txn-1', 'success'));
    assert.equal((await read(`orders/${a.orderId}`))?.paymentStatus, 'failed');
    assert.equal((await read('wallets/alice'))?.balance, a.total);

    // Second run: nothing left to do.
    assert.deepEqual(await expirePaymentSessions({ db, messaging: fcm, gateway, logger: silent }, clock + 15 * MINUTE), {
      sessionsPaid: [], sessionsFailed: [], sessionsExpired: [], ordersCancelled: [], ordersReleased: [],
    });
    await assertWalletConsistent(db, 'alice');
  });

  // ── checkPaymentStatus ("I've paid — check status") ──

  const check = (sessionId: unknown, uid: string | undefined = 'alice', over: { gateway?: PaymentGateway | null } = {}) =>
    checkPaymentStatusCore(
      { db, messaging: fcm, gateway: over.gateway === undefined ? gateway : over.gateway, now: () => clock, logger: silent },
      { sessionId },
      uid,
    );

  test('checkPaymentStatus: a pending gateway answer changes nothing; a completed one settles it once', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);

    assert.deepEqual(await check(sessionId), { status: 'pending' });
    assert.equal(gets, 1);
    assert.equal((await read(`orders/${placed.orderId}`))?.paymentStatus, 'pending');
    assert.equal((await read(`payment_sessions/${sessionId}`))?.settledAt, undefined);

    gatewayStatus.set('txn-1', 'completed'); // paid, but the browser was closed before the redirect
    assert.deepEqual(await check(sessionId), { status: 'paid' });
    const order = await read(`orders/${placed.orderId}`);
    assert.deepEqual([order?.paymentStatus, order?.paymentRef], ['paid', 'txn-1']);
    assert.equal(await placedNotice(placed.orderId), true);
    assert.equal(fcm.calls.length, 1);

    // Settled: answered from Firestore, no gateway call; the late redirect changes nothing either.
    assert.deepEqual(await check(sessionId), { status: 'paid' });
    assert.equal(gets, 2);
    assert.equal((await back(sessionId, returnToken(sessionId, 'txn-1', 'success'))).status, 'paid');
    assert.equal(fcm.calls.length, 1);
    assert.equal((await walletTxns(db, 'alice')).length, 0);
  });

  test('checkPaymentStatus: a failed payment cancels the order through the usual path', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);
    gatewayStatus.set('txn-1', 'failed');
    assert.deepEqual(await check(sessionId), { status: 'failed' });
    const order = await read(`orders/${placed.orderId}`);
    assert.deepEqual([order?.status, order?.cancelReason, order?.paymentStatus], ['cancelledByBuyer', 'payment_failed', 'failed']);
    assert.equal((await read('products/mug'))?.stock, 10, 'stock back');
    assert.deepEqual(await check(sessionId), { status: 'failed' });
  });

  test('checkPaymentStatus: paid after the order stopped waiting → the money goes to the wallet', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);
    await cancelOrderCore(db, { orderId: placed.orderId }, 'alice', { now: () => clock });
    gatewayStatus.set('txn-1', 'completed');
    assert.deepEqual(await check(sessionId), { status: 'paid' });
    assert.equal((await read('wallets/alice'))?.balance, placed.total);
    await assertWalletConsistent(db, 'alice');
  });

  test('checkPaymentStatus errors and limits', async () => {
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);
    await rejectsWith(checkPaymentStatusCore({ db, messaging: fcm, gateway, logger: silent }, { sessionId }, undefined), 'unauthenticated');
    await rejectsWith(check('../x'), 'invalid-argument');
    await rejectsWith(check(42), 'invalid-argument');
    await rejectsWith(check('missing-session'), 'not-found');
    await rejectsWith(check(sessionId, 'bob'), 'permission-denied');
    await rejectsWith(check(sessionId, 'alice', { gateway: null }), 'unavailable');
    const down = zainCashGateway(
      { env: 'test', host: ZAINCASH_HOSTS.test, merchantId: 'merchant-1', msisdn: '9647835077893', secret: SECRET, publicTestMerchant: false },
      { fetch: async () => { throw new Error('ECONNRESET'); } },
    );
    await rejectsWith(check(sessionId, 'alice', { gateway: down }), 'unavailable');
    // Strangers never use up the owner's checks; the owner gets CHECK_RATE_LIMIT per 5 minutes.
    for (let i = 0; i < 10; i++) await rejectsWith(check(sessionId, 'bob'), 'permission-denied');
    const used = 2; // the two `unavailable` calls above counted
    for (let i = used; i < CHECK_RATE_LIMIT.limit; i++) assert.deepEqual(await check(sessionId), { status: 'pending' });
    await rejectsWith(check(sessionId), 'resource-exhausted', 'rate_limited');
    clock += CHECK_RATE_LIMIT.windowMs + 1;
    assert.deepEqual(await check(sessionId), { status: 'pending' });
  });

  // ── ZainCash's PUBLIC sandbox merchant: its secret is public, a token proves nothing ──

  test('public sandbox merchant: a forged "success" token is confirmed with the gateway before anything is paid', async () => {
    const sandbox = zainCashGateway(
      { env: 'test', host: ZAINCASH_HOSTS.test, merchantId: 'merchant-1', msisdn: '9647835077893', secret: SECRET, publicTestMerchant: true },
      { fetch: fakeFetch },
    );
    assert.equal(sandbox.confirmsReturnServerSide, true);
    const sandboxBack = (sid: string, token: string) =>
      handleZainCashReturn({ db, messaging: fcm, gateway: sandbox, now: () => clock, logger: silent }, { sid, token });
    const placed = await placeZainCash();
    const { sessionId } = await startPayment(placed.orderId);

    // Anyone can sign this with the published secret; ZainCash says it is still pending.
    const forged = await sandboxBack(sessionId, returnToken(sessionId, 'txn-1', 'success'));
    assert.equal(forged.status, 'pending');
    assert.equal((await read(`orders/${placed.orderId}`))?.paymentStatus, 'pending');
    assert.equal((await read(`payment_sessions/${sessionId}`))?.status, 'pending');

    gatewayStatus.set('txn-1', 'completed');
    assert.equal((await sandboxBack(sessionId, returnToken(sessionId, 'txn-1', 'success'))).status, 'paid');
    assert.equal((await read(`orders/${placed.orderId}`))?.paymentStatus, 'paid');
    assert.equal(gateway.confirmsReturnServerSide, false, 'own merchant: the signed token is enough');
  });
});

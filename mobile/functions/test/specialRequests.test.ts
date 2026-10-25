/**
 * Special requests against the Firestore emulator (skipped without it): acceptQuote
 * (cash on delivery and wallet), the thread / quote notifications. Own demo-
 * project, cleared before every test. SRS Phase 8 exit: "a special request is
 * quoted → accepted → ordered".
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { acceptQuoteCore } from '../src/specialRequests/acceptQuote';
import { handleSpecialRequestMessage, handleSpecialRequestUpdate } from '../src/specialRequests/onSpecialRequestEvents';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { assertWalletConsistent, grantBalance, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-special-requests';
/** 2026-10-21 08:00 in Baghdad. */
const NOW = Date.UTC(2026, 9, 21, 5, 0);
const IDEA = 'A wooden jewellery box engraved with our names and the date we met, lined with red velvet inside';

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string): Promise<HttpsError> {
  let error: HttpsError | undefined;
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    if (reason !== undefined) assert.equal((e.details as { reason?: string } | undefined)?.reason, reason);
    error = e;
    return true;
  });
  return error!;
}

describe('special requests (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `special-requests-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  let clock = NOW;
  const deps = { db, messaging: fcm, now: () => clock, logger: quiet };

  const read = async (path: string) => (await db.doc(path).get()).data();
  const notificationsOf = async (uid: string) =>
    (await db.collection('notifications').where('userId', '==', uid).get()).docs.map((d) => ({ id: d.id, ...d.data() }) as DocumentData);
  const messages = async (requestId: string) =>
    (await db.collection(`special_requests/${requestId}/messages`).get()).docs.map((d) => d.data());

  const acceptData = (over: Record<string, unknown> = {}) => ({
    requestId: 'sr1',
    clientRequestId: 'accept-1',
    addressId: 'home',
    deliveryDate: '2026-10-21',
    deliverySlot: 'morning',
    paymentMethod: 'cashOnDelivery',
    ...over,
  });
  const accept = (uid: string, over: Record<string, unknown> = {}) => acceptQuoteCore(deps, acceptData(over), uid);

  const request = (over: DocumentData = {}): DocumentData => ({
    userId: 'alice',
    type: 'gift',
    text: IDEA,
    images: ['https://img/idea-1.jpg', 'https://img/idea-2.jpg'],
    status: 'quoted',
    quoteAmount: 30000,
    quoteNote: 'Ready in 5 days',
    customerName: 'Alice',
    customerPhone: '+9647501234567',
    lastMessageAt: Timestamp.fromMillis(NOW - 3600_000),
    lastMessageBy: 'admin',
    createdAt: Timestamp.fromMillis(NOW - 86_400_000),
    updatedAt: Timestamp.fromMillis(NOW - 3600_000),
    ...over,
  });

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    clock = NOW;
    const batch = db.batch();
    batch.set(db.doc('app_settings/cities'), {
      items: [
        { id: 'erbil', deliveryFee: 3000, isActive: true },
        { id: 'mosul', deliveryFee: 5000, isActive: false },
      ],
    });
    for (const [uid, locale] of [['alice', 'ckb'], ['bob', 'en']]) {
      batch.set(db.doc(`users/${uid}`), { name: uid, locale, fcmTokens: [`tok-${uid}`], notificationsEnabled: true, totalOrders: 0, totalSpent: 0 });
      batch.set(db.doc(`users/${uid}/addresses/home`), { label: 'Home', name: uid, phone: '7501234567', city: 'erbil', area: 'Ankawa', street: '100m' });
      batch.set(db.doc(`users/${uid}/addresses/far`), { label: 'Far', name: uid, city: 'mosul' });
    }
    batch.set(db.doc('special_requests/sr1'), request());
    batch.set(db.doc('special_requests/sr-new'), request({ status: 'submitted', quoteAmount: null }));
    batch.set(db.doc('special_requests/sr-low'), request({ quoteAmount: 500 }));
    batch.set(db.doc('special_requests/sr-bob'), request({ userId: 'bob' }));
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  describe('acceptQuote', () => {
    test('cash on delivery: quote + the city fee, one order, request accepted, system message', async () => {
      const placed = await accept('alice');
      assert.deepEqual(placed, { orderId: placed.orderId, orderNumber: 'GG-2610-00001', total: 33000, deliveryDate: '2026-10-21' });

      const order = (await read(`orders/${placed.orderId}`))!;
      assert.equal(order.orderType, 'specialRequest');
      assert.equal(order.specialRequestId, 'sr1');
      assert.equal(order.subtotal, 30000);
      assert.equal(order.deliveryFee, 3000);
      assert.equal(order.total, 33000);
      assert.equal(order.paymentMethod, 'cashOnDelivery');
      assert.equal(order.paymentStatus, 'pending');
      assert.equal(order.deliverySlot, 'morning');
      assert.equal(order.address.city, 'erbil');
      assert.equal(order.status, 'pending');
      assert.equal(order.statusUpdatedByRole, 'customer');
      const line = order.items[0];
      assert.equal(order.items.length, 1);
      assert.equal(line.titleSnapshot, 'Special request');
      assert.equal(line.titleSnapshotAr, 'طلب خاص');
      assert.equal(line.titleSnapshotKu, 'داواکاریی تایبەت');
      assert.equal(line.storeId, 'golden-gift-home');
      assert.equal(line.unitPrice, 30000);
      assert.equal(line.imageSnapshot, 'https://img/idea-1.jpg');
      assert.equal(line.selections[0].type, 'longText');
      assert.equal(Array.from(line.selections[0].text as string).length, 60);
      assert.ok((line.selections[0].text as string).startsWith('A wooden jewellery box'));
      assert.ok((line.selections[0].text as string).endsWith('…'));
      assert.equal((await db.collection(`orders/${placed.orderId}/status_history`).get()).size, 1);
      assert.equal((await read('users/alice'))?.totalOrders, 1);

      const sr = (await read('special_requests/sr1'))!;
      assert.equal(sr.status, 'accepted');
      assert.equal(sr.orderId, placed.orderId);
      assert.ok(sr.acceptedAt);
      assert.equal(sr.lastMessageBy, 'customer');
      const thread = await messages('sr1');
      assert.equal(thread.length, 1);
      assert.deepEqual(
        { ...thread[0], at: undefined },
        { senderUid: 'system', role: 'admin', text: 'Quote accepted — order GG-2610-00001', images: [], system: true, at: undefined },
      );
      const n = await notificationsOf('alice');
      assert.ok(n.some((x) => x.id === `${placed.orderId}-placed` && x.type === 'orderStatus'));
    });

    test('the same clientRequestId returns the same order; a second accept is refused', async () => {
      const first = await accept('alice');
      assert.deepEqual(await accept('alice'), first);
      await rejectsWith(accept('alice', { clientRequestId: 'accept-2' }), 'failed-precondition', 'quote_unavailable');
      assert.equal((await db.collection('orders').get()).size, 1);
      assert.equal((await messages('sr1')).length, 1);
    });

    test('wallet: the BALANCE must cover quote + fee; then it is paid', async () => {
      await grantBalance(db, 'alice', 32999);
      await grantCredits(db, 'alice', 100000);
      await rejectsWith(accept('alice', { paymentMethod: 'wallet' }), 'failed-precondition', 'insufficient_funds');
      await grantBalance(db, 'alice', 1);
      const placed = await accept('alice', { paymentMethod: 'wallet', clientRequestId: 'accept-w' });
      assert.equal(placed.total, 0);
      const order = (await read(`orders/${placed.orderId}`))!;
      assert.equal(order.walletUsed, 33000);
      assert.equal(order.creditsUsed, 0);
      assert.equal(order.paymentStatus, 'paid');
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 0, credits: 100000 });
      const payment = (await walletTxns(db, 'alice')).find((t) => t.type === 'orderPayment')!;
      assert.equal(payment.id, `order-${placed.orderId}-1`);
      assert.equal(payment.amount, -33000);
      assert.equal(payment.bucket, 'balance');
    });

    test('only the owner, only a real quote', async () => {
      await rejectsWith(accept('bob'), 'permission-denied');
      const missing = await rejectsWith(accept('alice', { requestId: 'nope' }), 'not-found');
      assert.equal(missing.message, 'Special request not found.');
      await rejectsWith(accept('alice', { requestId: 'sr-new' }), 'failed-precondition', 'quote_unavailable');
      await rejectsWith(accept('alice', { requestId: 'sr-low' }), 'failed-precondition', 'quote_unavailable');
      await rejectsWith(acceptQuoteCore(deps, acceptData(), undefined), 'unauthenticated');
    });

    test('address, date and slot by the checkout rules (0 preparation days)', async () => {
      await rejectsWith(accept('alice', { addressId: 'far' }), 'failed-precondition', 'city_not_allowed');
      await rejectsWith(accept('alice', { addressId: 'gone' }), 'invalid-argument');
      await rejectsWith(accept('alice', { deliveryDate: '2026-10-20' }), 'invalid-argument');
      await rejectsWith(accept('alice', { deliveryDate: '2026-11-04' }), 'invalid-argument');
      clock = Date.UTC(2026, 9, 21, 8, 0); // 11:00 Baghdad: the morning slot has started
      await rejectsWith(accept('alice', { deliverySlot: 'morning' }), 'invalid-argument');
      await rejectsWith(accept('alice', { deliverySlot: 'midnight' }), 'invalid-argument');
      const placed = await accept('alice', { deliverySlot: 'afternoon' });
      assert.equal(placed.deliveryDate, '2026-10-21');
      clock = Date.UTC(2026, 9, 21, 12, 0); // 15:00: after the cut-off, tomorrow is the earliest
      await db.doc('special_requests/sr-bob').update({ status: 'quoted' });
      await rejectsWith(accept('bob', { requestId: 'sr-bob', clientRequestId: 'b1', deliverySlot: 'evening' }), 'invalid-argument');
      assert.equal((await accept('bob', { requestId: 'sr-bob', clientRequestId: 'b2', deliveryDate: '2026-10-22' })).deliveryDate, '2026-10-22');
    });

    test('payment methods follow app_settings/payments', async () => {
      await db.doc('app_settings/payments').set({ cashOnDelivery: false, wallet: true });
      await rejectsWith(accept('alice'), 'invalid-argument');
      await rejectsWith(accept('alice', { paymentMethod: 'card' }), 'invalid-argument');
    });
  });

  describe('notifications', () => {
    const at = Timestamp.fromMillis(NOW);
    const message = (over: DocumentData = {}): DocumentData => ({ senderUid: 'admin-1', role: 'admin', text: 'We can do it in walnut.', images: [], at, ...over });

    test('an admin reply notifies the customer once', async () => {
      const result = await handleSpecialRequestMessage(deps, { requestId: 'sr-new', messageId: 'm1', message: message() });
      assert.deepEqual(result, { notified: true, notificationId: 'sr-sr-new-msg-m1' });
      const [n] = await notificationsOf('alice');
      assert.equal(n.type, 'specialRequestReply');
      assert.equal(n.data.route, '/special-requests/sr-new');
      assert.equal(n.body, 'We can do it in walnut.');
      assert.equal(n.titleKu, 'وەڵامێکی نوێ بۆ داواکارییەکەت');
      assert.ok(fcm.tokens().includes('tok-alice'));
      assert.deepEqual(await handleSpecialRequestMessage(deps, { requestId: 'sr-new', messageId: 'm1', message: message() }), {
        notified: false,
        reason: 'duplicate',
      });
    });

    test('customer messages, system messages and the quote message do not', async () => {
      assert.deepEqual(await handleSpecialRequestMessage(deps, { requestId: 'sr1', messageId: 'c', message: message({ role: 'customer' }) }), {
        notified: false,
        reason: 'notAdmin',
      });
      assert.deepEqual(await handleSpecialRequestMessage(deps, { requestId: 'sr1', messageId: 's', message: message({ system: true }) }), {
        notified: false,
        reason: 'system',
      });
      // The dashboard posts "Quote: …" in the same batch as the quote: quotedAt == at.
      await db.doc('special_requests/sr1').update({ quotedAt: at });
      assert.deepEqual(await handleSpecialRequestMessage(deps, { requestId: 'sr1', messageId: 'q', message: message({ text: 'Quote: 30,000 IQD' }) }), {
        notified: false,
        reason: 'quoteMessage',
      });
      // A later reply on the quoted request does notify.
      const later = message({ at: Timestamp.fromMillis(NOW + 60_000) });
      assert.equal((await handleSpecialRequestMessage(deps, { requestId: 'sr1', messageId: 'r', message: later })).notified, true);
      assert.deepEqual(await handleSpecialRequestMessage(deps, { requestId: 'gone', messageId: 'x', message: message() }), {
        notified: false,
        reason: 'missing',
      });
    });

    test('a request that becomes quoted notifies with the amount; once per event', async () => {
      const before = request({ status: 'inReview', quoteAmount: null });
      const after = request({ status: 'quoted', quoteAmount: 45000 });
      const result = await handleSpecialRequestUpdate(deps, { eventId: 'e1', requestId: 'sr1', before, after });
      assert.equal(result.notified, true);
      const [n] = await notificationsOf('alice');
      assert.match(n.body, /45,000 IQD/);
      assert.equal(n.data.route, '/special-requests/sr1');
      assert.deepEqual(await handleSpecialRequestUpdate(deps, { eventId: 'e1', requestId: 'sr1', before, after }), {
        notified: false,
        reason: 'duplicate',
      });
      assert.deepEqual(await handleSpecialRequestUpdate(deps, { eventId: 'e2', requestId: 'sr1', before: after, after }), {
        notified: false,
        reason: 'unchanged',
      });
      assert.deepEqual(
        await handleSpecialRequestUpdate(deps, { eventId: 'e3', requestId: 'sr1', before, after: request({ status: 'rejected' }) }),
        { notified: false, reason: 'unchanged' },
      );
    });
  });
});

/**
 * Phase 7 money paths of an order against the Firestore emulator (skipped
 * without it): promo codes in placeOrder (every §6.9 rule, usage counters,
 * concurrency), credits (FIFO lots) and wallet payments, and the refunds of
 * cancelOrder / onOrderStatusChange. Own demo- project, cleared before every test.
 * Every test ends with the wallet audit: each change has its transaction with the
 * right balanceAfter / creditsAfter.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { cancelOrderCore } from '../src/orders/cancelOrder';
import { handleOrderStatusChange } from '../src/orders/onOrderStatusChange';
import { orderIdFor } from '../src/orders/orderNumber';
import { placeOrderCore, type PlaceOrderDeps } from '../src/orders/placeOrder';
import { DAY_MS } from '../src/wallet/walletSettings';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { assertWalletConsistent, grantBalance, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-order-payments';
/** 2026-10-21 08:00 in Baghdad. */
const NOW = Date.UTC(2026, 9, 21, 5, 0);

async function rejectsWith(promise: Promise<unknown>, code: string, details?: Record<string, unknown>): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    if (details !== undefined) assert.deepEqual(e.details, details);
    return true;
  });
}

describe('order payments: promo, credits, wallet, refunds (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `order-payments-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  const deps: PlaceOrderDeps = { db, messaging: fcm, now: () => NOW, logger: quiet };
  const triggerDeps = { db, messaging: fcm, logger: quiet, now: () => NOW };
  let events = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const ordersOf = async (uid: string) => (await db.collection('orders').where('userId', '==', uid).get()).docs;

  const request = (over: Record<string, unknown> = {}) => ({
    clientRequestId: 'req-1',
    addressId: 'home',
    deliveryDate: '2026-10-21',
    deliverySlot: 'morning',
    isGift: false,
    giftMessage: null,
    hidePrices: false,
    paymentMethod: 'cashOnDelivery',
    promoCode: null,
    useCredits: false,
    useWallet: false,
    ...over,
  });
  const place = (uid: string, over: Record<string, unknown> = {}) => placeOrderCore(deps, request(over), uid);
  /** What the app sends for a wallet payment (useWallet follows the method). */
  const placeWithWallet = (uid: string, over: Record<string, unknown> = {}) =>
    place(uid, { paymentMethod: 'wallet', useWallet: true, ...over });

  async function seedUser(uid: string, over: DocumentData = {}): Promise<void> {
    await db.doc(`users/${uid}`).set({
      name: `User ${uid}`,
      locale: 'en',
      fcmTokens: [`tok-${uid}`],
      notificationsEnabled: true,
      totalOrders: 0,
      totalSpent: 0,
      isBlocked: false,
      isDeleted: false,
      ...over,
    });
    await db.doc(`users/${uid}/addresses/home`).set({ label: 'Home', name: uid, phone: '7501234567', city: 'erbil', area: 'A', street: 'S', isDefault: true });
  }

  /** A mug line (15,000) or a frame line (20,000, other store), as the app writes it. */
  async function addToCart(uid: string, id: string, product: 'mug' | 'frame' = 'mug', qty = 1): Promise<void> {
    const price = product === 'mug' ? 15000 : 20000;
    await db.doc(`carts/${uid}/items/${id}`).set({
      productId: product,
      storeId: product === 'mug' ? 'home' : 'other',
      titleSnapshot: product,
      unitPrice: price,
      qty,
      selections: [],
      lineTotal: price * qty,
      preparationDays: 0,
      addedAt: Timestamp.now(),
    });
  }

  async function promo(code: string, over: DocumentData = {}): Promise<void> {
    await db.doc(`promo_codes/${code}`).set({
      code,
      title: code,
      type: 'percent',
      value: 10,
      usageCount: 0,
      perUserLimit: 1,
      firstOrderOnly: false,
      categoryIds: [],
      storeIds: [],
      isPublic: true,
      isActive: true,
      expiresAt: Timestamp.fromMillis(NOW + 30 * DAY_MS),
      ...over,
    });
  }

  /** Applies `update` like the dashboard, then runs the trigger handler for it (same `eventId` = a replay). */
  async function changeAndTrigger(orderId: string, update: DocumentData | null, eventId = `evt-${++events}`) {
    const before = await read(`orders/${orderId}`);
    if (update !== null) await db.doc(`orders/${orderId}`).update(update);
    const afterDoc = await read(`orders/${orderId}`);
    return handleOrderStatusChange(triggerDeps, { eventId, orderId, before, after: afterDoc });
  }
  /** AdminOrdersRepository.changeStatus. */
  async function adminSets(orderId: string, status: string, note: string | null = null): Promise<DocumentData> {
    const order = (await read(`orders/${orderId}`))!;
    return {
      status,
      statusNote: note,
      statusUpdatedBy: 'admin-1',
      statusUpdatedByRole: 'admin',
      items: (order.items as DocumentData[]).map((i) => ({ ...i, status })),
      updatedAt: FieldValue.serverTimestamp(),
      ...(status === 'cancelledBySeller' && { cancelReason: note }),
    };
  }
  async function deliver(orderId: string): Promise<void> {
    for (const s of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery', 'delivered']) {
      await changeAndTrigger(orderId, await adminSets(orderId, s));
    }
  }
  const openLots = async (uid: string) =>
    (await db.collection(`wallets/${uid}/credit_lots`).where('open', '==', true).get()).docs.map((d) => d.data());

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    const batch = db.batch();
    batch.set(db.doc('app_settings/general'), { sameDayCutoff: '14:00', minOrder: 0 });
    batch.set(db.doc('app_settings/cities'), { items: [{ id: 'erbil', deliveryFee: 3000, isActive: true }] });
    batch.set(db.doc('app_settings/payments'), { cashOnDelivery: true, wallet: true });
    batch.set(db.doc('app_settings/referral'), { joinBonus: 5000, orderBonus: 5000, maxReferralsPerMonth: 10, creditsExpiryDays: 90 });
    batch.set(db.doc('stores/home'), { status: 'active' });
    batch.set(db.doc('stores/other'), { status: 'active' });
    batch.set(db.doc('products/mug'), { title: 'Mug', storeId: 'home', categoryIds: ['mugs', 'birthday'], price: 15000, isActive: true, stock: 50, salesCount: 0 });
    batch.set(db.doc('products/frame'), { title: 'Frame', storeId: 'other', categoryIds: ['frames'], price: 20000, isActive: true, stock: null, salesCount: 0 });
    await batch.commit();
    await seedUser('alice');
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  // ── Promo codes ──────────────────────────────────────────────────────────
  describe('promo codes', () => {
    test('a percent code: discount and code on the order, usage counted once per order', async () => {
      await promo('GOLD10');
      await addToCart('alice', 'l1', 'mug', 2);
      const placed = await place('alice', { promoCode: ' gold10 ' });
      assert.equal(placed.total, 30000 - 3000 + 3000);
      const order = (await read(`orders/${placed.orderId}`))!;
      assert.deepEqual([order.subtotal, order.discount, order.promoCode, order.total], [30000, 3000, 'GOLD10', 30000]);
      assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 1);
      assert.equal((await read('promo_codes/GOLD10/usages/alice'))?.count, 1);
      // A retry of the same checkout is the same order: nothing counted twice.
      assert.deepEqual(await place('alice', { promoCode: 'GOLD10' }), placed);
      assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 1);
    });

    test('category / store restriction: only matching lines are discounted; minOrder uses the whole cart', async () => {
      await promo('FRAMES', { categoryIds: ['frames'], minOrder: 35000, type: 'fixed', value: 25000 });
      await promo('HOME', { storeIds: ['home'], value: 20, maxDiscount: 2000 });
      await addToCart('alice', 'l1', 'mug');
      await addToCart('alice', 'l2', 'frame');
      const framed = await place('alice', { promoCode: 'FRAMES' });
      assert.equal((await read(`orders/${framed.orderId}`))?.discount, 20000); // fixed, capped at the eligible 20,000
      await addToCart('alice', 'l1', 'mug');
      await addToCart('alice', 'l2', 'frame');
      const home = await place('alice', { promoCode: 'HOME', clientRequestId: 'req-2' });
      assert.equal((await read(`orders/${home.orderId}`))?.discount, 2000); // 20 % of 15,000 = 3,000 → max 2,000
    });

    const rejections: Array<[string, DocumentData | null, () => Promise<void>]> = [
      ['notFound', null, async () => undefined],
      ['inactive', { isActive: false }, async () => undefined],
      ['expired', { expiresAt: Timestamp.fromMillis(NOW) }, async () => undefined],
      ['minOrder', { minOrder: 15001 }, async () => undefined],
      ['usageLimit', { usageLimit: 5, usageCount: 5 }, async () => undefined],
      ['perUserLimit', { perUserLimit: 2 }, async () => void (await db.doc('promo_codes/CODE/usages/alice').set({ count: 2 }))],
      ['firstOrderOnly', { firstOrderOnly: true }, async () => void (await db.doc('users/alice').update({ totalOrders: 1 }))],
      ['notApplicable', { categoryIds: ['flowers'] }, async () => undefined],
    ];
    for (const [reason, over, setup] of rejections) {
      test(`${reason} → promo_invalid with promoReason; nothing is written`, async () => {
        if (over !== null) await promo('CODE', over);
        await setup();
        await addToCart('alice', 'l1');
        await rejectsWith(place('alice', { promoCode: 'CODE' }), 'failed-precondition', { reason: 'promo_invalid', promoReason: reason });
        assert.equal((await ordersOf('alice')).length, 0);
        assert.ok(await read('carts/alice/items/l1'), 'the cart is kept');
        if (over !== null) assert.equal((await read('promo_codes/CODE'))?.usageCount, over.usageCount ?? 0);
        // Without the code the same cart goes through.
        assert.ok(await place('alice'));
      });
    }

    test('a code that cannot be a document id is simply not found', async () => {
      await addToCart('alice', 'l1');
      await rejectsWith(place('alice', { promoCode: '__X__' }), 'failed-precondition', { reason: 'promo_invalid', promoReason: 'notFound' });
      await rejectsWith(place('alice', { promoCode: 'A/B' }), 'failed-precondition', { reason: 'promo_invalid', promoReason: 'notFound' });
    });

    test('firstOrderOnly: a cancelled first order does not count; the cancel releases the usage', async () => {
      await promo('WELCOME', { firstOrderOnly: true, perUserLimit: 0 });
      await addToCart('alice', 'l1');
      const first = await place('alice', { promoCode: 'WELCOME' });
      await addToCart('alice', 'l1');
      await rejectsWith(place('alice', { promoCode: 'WELCOME', clientRequestId: 'req-2' }), 'failed-precondition', {
        reason: 'promo_invalid',
        promoReason: 'firstOrderOnly',
      });
      await cancelOrderCore(db, { orderId: first.orderId }, 'alice', { now: () => NOW });
      assert.equal((await read('promo_codes/WELCOME'))?.usageCount, 0);
      assert.equal((await read('promo_codes/WELCOME/usages/alice'))?.count, 0);
      assert.equal((await read(`orders/${first.orderId}`))?.promoReleased, true);
      const second = await place('alice', { promoCode: 'WELCOME', clientRequestId: 'req-3' });
      assert.equal((await read(`orders/${second.orderId}`))?.discount, 1500);
      assert.equal((await read('promo_codes/WELCOME'))?.usageCount, 1);
    });

    test('usageLimit 1 under concurrent checkouts: exactly one discounted order', async () => {
      const buyers = ['b1', 'b2', 'b3', 'b4'];
      await promo('ONCE', { usageLimit: 1, perUserLimit: 0 });
      for (const uid of buyers) {
        await seedUser(uid);
        await addToCart(uid, 'l1');
      }
      const results = await Promise.allSettled(buyers.map((uid) => place(uid, { promoCode: 'ONCE', clientRequestId: `race-${uid}` })));
      const won = results.filter((r) => r.status === 'fulfilled');
      assert.equal(won.length, 1);
      for (const r of results) {
        if (r.status === 'rejected') {
          assert.ok(r.reason instanceof HttpsError);
          assert.deepEqual(r.reason.details, { reason: 'promo_invalid', promoReason: 'usageLimit' });
        }
      }
      assert.equal((await read('promo_codes/ONCE'))?.usageCount, 1);
      const discounted = (await db.collection('orders').where('promoCode', '==', 'ONCE').get()).docs;
      assert.equal(discounted.length, 1);
      assert.equal(discounted[0].get('discount'), 1500);
    });
  });

  // ── Credits & wallet ─────────────────────────────────────────────────────
  describe('credits and wallet', () => {
    test('credits first, FIFO from the oldest lot; cash on delivery for the rest', async () => {
      await grantCredits(db, 'alice', 3000, { expiresAtMs: NOW + 10 * DAY_MS });
      await grantCredits(db, 'alice', 20000);
      await addToCart('alice', 'l1');
      const placed = await place('alice', { useCredits: true });
      const order = (await read(`orders/${placed.orderId}`))!;
      assert.deepEqual([order.creditsUsed, order.walletUsed, order.total, order.paymentStatus], [18000, 0, 0, 'pending']);
      const lots = await openLots('alice');
      assert.deepEqual(lots.map((l) => [l.amount, l.remaining]), [[20000, 5000]]);
      const txns = await walletTxns(db, 'alice');
      const pay = txns.find((t) => t.id === `order-${placed.orderId}-1`)!;
      assert.deepEqual(
        [pay.type, pay.amount, pay.bucket, pay.orderId, pay.title, pay.titleAr, pay.titleKu, pay.creditsAfter, pay.balanceAfter],
        ['orderPayment', -18000, 'credits', placed.orderId, `Order ${placed.orderNumber}`, `الطلب ${placed.orderNumber}`, `داواکاری ${placed.orderNumber}`, 5000, 0],
      );
      await assertWalletConsistent(db, 'alice');
    });

    test('useCredits off, or no wallet yet: nothing is spent', async () => {
      await grantCredits(db, 'alice', 5000);
      await addToCart('alice', 'l1');
      const placed = await place('alice');
      assert.equal((await read(`orders/${placed.orderId}`))?.creditsUsed, 0);
      assert.equal((await read('wallets/alice'))?.credits, 5000);
      await seedUser('nowallet');
      await addToCart('nowallet', 'l1');
      const other = await place('nowallet', { useCredits: true });
      assert.equal(other.total, 18000);
      assert.equal(await read('wallets/nowallet'), undefined);
    });

    test('wallet payment: credits, then the balance; paid at once; two transactions', async () => {
      await grantCredits(db, 'alice', 5000);
      await grantBalance(db, 'alice', 20000);
      await addToCart('alice', 'l1');
      const placed = await placeWithWallet('alice', { useCredits: true });
      const order = (await read(`orders/${placed.orderId}`))!;
      assert.deepEqual(
        [order.paymentMethod, order.creditsUsed, order.walletUsed, order.total, order.paymentStatus],
        ['wallet', 5000, 13000, 0, 'paid'],
      );
      assert.deepEqual(placed.total, 0);
      const wallet = (await read('wallets/alice'))!;
      assert.deepEqual([wallet.balance, wallet.credits], [7000, 0]);
      const mine = (await walletTxns(db, 'alice')).filter((t) => t.orderId === placed.orderId);
      assert.deepEqual(mine.map((t) => [t.id, t.bucket, t.amount, t.creditsAfter, t.balanceAfter]), [
        [`order-${placed.orderId}-1`, 'credits', -5000, 0, 20000],
        [`order-${placed.orderId}-2`, 'balance', -13000, 0, 7000],
      ]);
      await assertWalletConsistent(db, 'alice');
    });

    test('a wallet payment the wallet does not cover → insufficient_funds; nothing written', async () => {
      await grantBalance(db, 'alice', 17999);
      await addToCart('alice', 'l1');
      await rejectsWith(placeWithWallet('alice'), 'failed-precondition', { reason: 'insufficient_funds' });
      await grantCredits(db, 'alice', 1);
      await rejectsWith(placeWithWallet('alice'), 'failed-precondition', { reason: 'insufficient_funds' }); // credits off
      assert.equal((await ordersOf('alice')).length, 0);
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [17999, 1]);
      // With credits on it is exactly enough.
      const placed = await placeWithWallet('alice', { useCredits: true });
      assert.equal(placed.total, 0);
      await assertWalletConsistent(db, 'alice');
    });

    test('cash on delivery never spends the balance, even with useWallet', async () => {
      await grantBalance(db, 'alice', 50000);
      await addToCart('alice', 'l1');
      const placed = await place('alice', { useWallet: true });
      assert.equal((await read(`orders/${placed.orderId}`))?.walletUsed, 0);
      assert.equal((await read('wallets/alice'))?.balance, 50000);
    });

    test('blocked accounts cannot spend their wallet', async () => {
      await grantBalance(db, 'alice', 50000);
      await db.doc('users/alice').update({ isBlocked: true });
      await addToCart('alice', 'l1');
      await rejectsWith(placeWithWallet('alice'), 'permission-denied');
      assert.equal((await read('wallets/alice'))?.balance, 50000);
    });

    test('two devices checking out at once: one order, the credits spent once', async () => {
      await grantCredits(db, 'alice', 20000);
      await addToCart('alice', 'l1');
      // Two devices of the same customer, each with its own checkout id.
      const results = await Promise.allSettled([
        placeWithWallet('alice', { useCredits: true, clientRequestId: 'dev-1' }),
        placeWithWallet('alice', { useCredits: true, clientRequestId: 'dev-2' }),
      ]);
      // The cart is emptied by the first; the second finds it empty (or the wallet short).
      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
      assert.equal((await read('wallets/alice'))?.credits, 2000);
      await assertWalletConsistent(db, 'alice');
    });
  });

  // ── Refunds ──────────────────────────────────────────────────────────────
  describe('refunds to the wallet', () => {
    test('customer cancel: credits as a new refund lot, balance back, promo released, paymentStatus refunded — once', async () => {
      await promo('GOLD10');
      await grantCredits(db, 'alice', 4000);
      await grantBalance(db, 'alice', 30000);
      await addToCart('alice', 'l1', 'mug', 2);
      const placed = await placeWithWallet('alice', { useCredits: true, promoCode: 'GOLD10' });
      const orderId = placed.orderId;
      // 30,000 − 3,000 + 3,000 = 30,000: credits 4,000 + balance 26,000.
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [4000, 0]);

      const before = await read(`orders/${orderId}`);
      await cancelOrderCore(db, { orderId, reason: 'Changed my mind' }, 'alice', { now: () => NOW });
      const order = (await read(`orders/${orderId}`))!;
      assert.deepEqual(
        [order.status, order.refundedToWallet, order.refundedCredits, order.refundedBalance, order.paymentStatus, order.promoReleased],
        ['cancelledByBuyer', true, 4000, 26000, 'refunded', true],
      );
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [30000, 4000]);
      const lots = await openLots('alice');
      assert.equal(lots.length, 1);
      assert.deepEqual([lots[0].source, lots[0].amount, lots[0].orderId], ['refund', 4000, orderId]);
      assert.equal((lots[0].expiresAt as Timestamp).toMillis(), NOW + 90 * DAY_MS);
      assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 0);
      assert.equal((await read('promo_codes/GOLD10/usages/alice'))?.count, 0);
      const refunds = (await walletTxns(db, 'alice')).filter((t) => t.type === 'refund');
      assert.deepEqual(refunds.map((t) => [t.bucket, t.amount, t.orderId]), [
        ['credits', 4000, orderId],
        ['balance', 26000, orderId],
      ]);
      assert.equal(refunds[0].title, `Refund · Order ${placed.orderNumber}`);

      // The trigger for that cancellation, replayed, then an admin "refunded": nothing more.
      const afterCancel = await read(`orders/${orderId}`);
      await handleOrderStatusChange(triggerDeps, { eventId: 'cancel-evt', orderId, before, after: afterCancel });
      await handleOrderStatusChange(triggerDeps, { eventId: 'cancel-evt-2', orderId, before, after: afterCancel });
      await changeAndTrigger(orderId, await adminSets(orderId, 'refunded', 'Refund'));
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [30000, 4000]);
      assert.equal((await read('promo_codes/GOLD10'))?.usageCount, 0);
      await assertWalletConsistent(db, 'alice');
    });

    test('seller cancellation refunds once, also when the event replays', async () => {
      await grantCredits(db, 'alice', 6000);
      await addToCart('alice', 'l1');
      const { orderId } = await place('alice', { useCredits: true });
      const update = await adminSets(orderId, 'cancelledBySeller', 'Out of stock');
      const before = await read(`orders/${orderId}`);
      await db.doc(`orders/${orderId}`).update(update);
      const afterDoc = await read(`orders/${orderId}`);
      const event = { eventId: 'seller-cancel', orderId, before, after: afterDoc };
      await Promise.all([handleOrderStatusChange(triggerDeps, event), handleOrderStatusChange(triggerDeps, event)]);
      await handleOrderStatusChange(triggerDeps, { ...event, eventId: 'seller-cancel-other-delivery' });
      const order = (await read(`orders/${orderId}`))!;
      assert.deepEqual([order.refundedCredits, order.refundedBalance, order.paymentStatus], [6000, 0, 'pending']);
      assert.equal((await read('wallets/alice'))?.credits, 6000);
      assert.equal((await walletTxns(db, 'alice')).filter((t) => t.type === 'refund').length, 1);
      await assertWalletConsistent(db, 'alice');
    });

    test('admin refunds a delivered cash order: the cash + wallet to the balance, credits back — once', async () => {
      await grantCredits(db, 'alice', 5000);
      await addToCart('alice', 'l1');
      const { orderId } = await place('alice', { useCredits: true });
      await deliver(orderId);
      assert.equal((await read(`orders/${orderId}`))?.paymentStatus, 'paid');
      const update = await adminSets(orderId, 'refunded', 'Damaged on arrival');
      await changeAndTrigger(orderId, update, 'refund-evt');
      // Replayed, and a second "refunded" after a status correction: nothing more.
      const order = (await read(`orders/${orderId}`))!;
      await handleOrderStatusChange(triggerDeps, { eventId: 'refund-evt', orderId, before: { ...order, status: 'delivered' }, after: order });
      await changeAndTrigger(orderId, await adminSets(orderId, 'returned'));
      await changeAndTrigger(orderId, await adminSets(orderId, 'refunded'));

      const final = (await read(`orders/${orderId}`))!;
      assert.deepEqual(
        [final.paymentStatus, final.refundedCredits, final.refundedBalance, final.refundedToWallet],
        ['refunded', 5000, 13000, true],
      );
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [13000, 5000]);
      const notifications = (await db.collection('notifications').where('userId', '==', 'alice').where('type', '==', 'orderStatus').get()).docs;
      assert.ok(notifications.some((n) => String(n.get('title')).includes('refunded')));
      await assertWalletConsistent(db, 'alice');
    });

    test('an unpaid order reaching refunded only returns credits / wallet', async () => {
      await grantCredits(db, 'alice', 2000);
      await addToCart('alice', 'l1');
      const { orderId } = await place('alice', { useCredits: true });
      for (const s of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery', 'returned', 'refunded']) {
        await changeAndTrigger(orderId, await adminSets(orderId, s));
      }
      const order = (await read(`orders/${orderId}`))!;
      assert.deepEqual([order.paymentStatus, order.refundedCredits, order.refundedBalance], ['pending', 2000, 0]);
      assert.deepEqual([(await read('wallets/alice'))?.balance, (await read('wallets/alice'))?.credits], [0, 2000]);
      await assertWalletConsistent(db, 'alice');
    });

    test('an order without wallet money: cancelling writes no wallet at all', async () => {
      await addToCart('alice', 'l1');
      const { orderId } = await place('alice');
      await cancelOrderCore(db, { orderId }, 'alice', { now: () => NOW });
      const order = (await read(`orders/${orderId}`))!;
      assert.equal(order.refundedToWallet, false);
      assert.equal(await read('wallets/alice'), undefined);
      assert.equal(orderIdFor('alice', 'req-1'), orderId);
    });
  });
});

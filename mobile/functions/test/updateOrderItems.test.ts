/**
 * updateOrderItems (sellers) against the Firestore emulator (skipped without it):
 * per-line moves on a multi-vendor order, the derived order status, and the
 * timeline entry onOrderStatusChange then writes with byRole seller. Own demo-
 * project, cleared before every test. SRS Phase 8 exit: a partner "sees only their
 * own store's … order items" (and moves only those).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { cancelOrderCore } from '../src/orders/cancelOrder';
import { planLineCancellation } from '../src/orders/lineCancellation';
import { handleOrderStatusChange } from '../src/orders/onOrderStatusChange';
import { updateOrderItemsCore } from '../src/orders/updateOrderItems';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { assertWalletConsistent, walletTxns } from './walletAudit';

/** The money rule of a partial cancellation (pure; SRS §7 updateOrderItems). */
describe('planLineCancellation', () => {
  const lines = [
    { id: 'a1', storeId: 'a', lineTotal: 1000, status: 'pending' },
    { id: 'a2', storeId: 'a', lineTotal: 1000, status: 'pending' },
    { id: 'b1', storeId: 'b', lineTotal: 1000, status: 'pending' },
  ];
  test('cash on delivery, no credits: the amount to collect drops by the lines', () => {
    const plan = planLineCancellation({ items: lines, subtotal: 3000, discount: 0, deliveryFee: 500, total: 3500, paymentStatus: 'pending' }, new Set(['a1', 'a2']));
    assert.deepEqual(plan, {
      linesValue: 2000,
      discountShare: 0,
      reduction: 2000,
      creditsBack: 0,
      moneyBack: 2000,
      paid: false,
      totals: { subtotal: 1000, discount: 0, total: 1500, originalSubtotal: 3000, originalDiscount: 0 },
    });
  });
  test('a promo discount is shared in proportion; credits come back in proportion; the fee stays', () => {
    const order = { items: lines, subtotal: 3000, discount: 300, deliveryFee: 500, creditsUsed: 1000, total: 2200, paymentStatus: 'pending' };
    const plan = planLineCancellation(order, new Set(['a1', 'a2']));
    assert.equal(plan.discountShare, 200);
    assert.equal(plan.reduction, 1800);
    assert.equal(plan.creditsBack, 563); // round(1800 × 1000 / 3200)
    assert.equal(plan.moneyBack, 1237);
    assert.deepEqual(plan.totals, { subtotal: 1000, discount: 100, total: 963, originalSubtotal: 3000, originalDiscount: 300 });
    // What is left adds up: 1000 − 100 + 500 = (1000 − 563 credits) + 963 to collect.
    assert.equal(1000 - 100 + 500, 1000 - plan.creditsBack + plan.totals!.total);
  });
  test('paid with the wallet: everything back to the balance, the figures stay what was charged', () => {
    const plan = planLineCancellation({ items: lines, subtotal: 3000, deliveryFee: 0, walletUsed: 3000, total: 0, paymentStatus: 'paid' }, new Set(['b1']));
    assert.deepEqual([plan.creditsBack, plan.moneyBack, plan.paid, plan.totals], [0, 1000, true, null]);
  });
  test('a second cancellation only sees what is still on the order', () => {
    const after1 = {
      items: [{ ...lines[0], status: 'cancelledBySeller' }, lines[1], lines[2]],
      subtotal: 3000, deliveryFee: 0, creditsUsed: 0, walletUsed: 0, total: 3000, paymentStatus: 'paid', refundedBalance: 1000,
    };
    const plan = planLineCancellation(after1, new Set(['a2']));
    assert.deepEqual([plan.reduction, plan.moneyBack], [1000, 1000]);
    assert.equal(planLineCancellation(after1, new Set(['a1'])).reduction, 0, 'already cancelled lines count for nothing');
  });
  test('credits covering everything come back as credits', () => {
    const plan = planLineCancellation({ items: lines, subtotal: 3000, deliveryFee: 0, creditsUsed: 3000, total: 0, paymentStatus: 'pending' }, new Set(['a1']));
    assert.deepEqual([plan.creditsBack, plan.moneyBack, plan.totals?.total], [1000, 0, 0]);
  });
});

const PROJECT = 'demo-goldengift-seller-orders';

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    if (reason !== undefined) assert.equal((e.details as { reason?: string } | undefined)?.reason, reason);
    return true;
  });
}

describe('updateOrderItems (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `seller-orders-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  let events = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const sellerA = { uid: 'seller-a', claims: { seller: 'store-a' } };
  const sellerB = { uid: 'seller-b', claims: { seller: 'store-b' } };
  const move = (caller: { uid?: string; claims?: Record<string, unknown> }, status: string, note?: string, orderId = 'o1') =>
    updateOrderItemsCore({ db, messaging: fcm, logger: quiet }, { orderId, status, note }, caller);
  const statuses = async (orderId = 'o1') => ((await read(`orders/${orderId}`))!.items as DocumentData[]).map((i) => `${i.storeId}:${i.status}`);

  const line = (id: string, storeId: string, status = 'pending'): DocumentData => ({
    id,
    productId: `p-${id}`,
    storeId,
    titleSnapshot: id,
    unitPrice: 1000,
    qty: 1,
    selections: [],
    lineTotal: 1000,
    preparationDays: 0,
    status,
  });

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    const batch = db.batch();
    batch.set(db.doc('stores/store-a'), { name: 'A', status: 'active', ownerUid: 'seller-a' });
    batch.set(db.doc('stores/store-b'), { name: 'B', status: 'active', ownerUid: 'seller-b' });
    batch.set(db.doc('stores/store-s'), { name: 'S', status: 'suspended', ownerUid: 'seller-s' });
    batch.set(db.doc('users/alice'), { name: 'Alice', locale: 'en', fcmTokens: ['tok-alice'], notificationsEnabled: true, totalOrders: 1, totalSpent: 0 });
    batch.set(db.doc('orders/o1'), {
      orderNumber: 'GG-2610-00007',
      userId: 'alice',
      storeIds: ['store-a', 'store-b'],
      items: [line('a1', 'store-a'), line('a2', 'store-a'), line('b1', 'store-b')],
      status: 'pending',
      paymentMethod: 'cashOnDelivery',
      paymentStatus: 'pending',
      total: 3000,
      statusNote: null,
      statusUpdatedBy: 'alice',
      statusUpdatedByRole: 'customer',
      createdAt: Timestamp.now(),
    });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test("a seller moves only its own lines; the order follows the least advanced line", async () => {
    assert.deepEqual(await move(sellerA, 'confirmed', 'On it'), { status: 'pending', moved: 2 });
    assert.deepEqual(await statuses(), ['store-a:confirmed', 'store-a:confirmed', 'store-b:pending']);
    let order = (await read('orders/o1'))!;
    assert.equal(order.status, 'pending', 'store-b is still pending');
    assert.equal(order.statusUpdatedByRole, 'customer', 'no order status change, no status fields');

    const before = order;
    assert.deepEqual(await move(sellerB, 'confirmed', 'Confirmed by B'), { status: 'confirmed', moved: 1 });
    order = (await read('orders/o1'))!;
    assert.equal(order.status, 'confirmed');
    assert.equal(order.statusNote, 'Confirmed by B');
    assert.equal(order.statusUpdatedBy, 'seller-b');
    assert.equal(order.statusUpdatedByRole, 'seller');

    // onOrderStatusChange records it like any other change.
    const result = await handleOrderStatusChange({ db, messaging: fcm, logger: quiet }, { eventId: `e-${++events}`, orderId: 'o1', before, after: order });
    assert.equal(result.handled, true);
    const history = (await db.collection('orders/o1/status_history').get()).docs.map((d) => d.data());
    assert.deepEqual(history.map((h) => [h.status, h.byUid, h.byRole, h.note]), [['confirmed', 'seller-b', 'seller', 'Confirmed by B']]);
    assert.ok(fcm.tokens().includes('tok-alice'));
  });

  test('per line: lines that cannot move (or are off the flow) stay; refused only when none can', async () => {
    await db.doc('orders/o1').update({ items: [line('a1', 'store-a', 'confirmed'), line('a2', 'store-a', 'cancelledBySeller'), line('b1', 'store-b')] });
    assert.deepEqual(await move(sellerA, 'preparing'), { status: 'pending', moved: 1 });
    assert.deepEqual(await statuses(), ['store-a:preparing', 'store-a:cancelledBySeller', 'store-b:pending']);
    await rejectsWith(move(sellerA, 'delivered'), 'failed-precondition', 'not_allowed');
    await rejectsWith(move(sellerA, 'preparing'), 'failed-precondition', 'not_allowed');
    assert.deepEqual(await statuses(), ['store-a:preparing', 'store-a:cancelledBySeller', 'store-b:pending']);
  });

  test("cancelling every line cancels the order (with the seller's note as the reason)", async () => {
    await move(sellerA, 'cancelledBySeller', 'Out of wood');
    assert.equal((await read('orders/o1'))?.status, 'pending');
    assert.deepEqual(await move(sellerB, 'cancelledBySeller', 'Closed today'), { status: 'cancelledBySeller', moved: 1 });
    const order = (await read('orders/o1'))!;
    assert.equal(order.cancelReason, 'Closed today');
    assert.equal(order.statusUpdatedByRole, 'seller');
  });

  test('the flow to delivered, then returned', async () => {
    for (const s of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery', 'delivered']) {
      await move(sellerA, s);
      await move(sellerB, s);
      assert.equal((await read('orders/o1'))?.status, s);
    }
    assert.deepEqual(await move(sellerA, 'returned', 'Broken'), { status: 'delivered', moved: 2 });
    assert.deepEqual(await move(sellerB, 'returned'), { status: 'returned', moved: 1 });
  });

  describe('partial cancellation: a seller cancels its lines, the order goes on (Phase 10)', () => {
    async function seedProducts(): Promise<void> {
      const batch = db.batch();
      batch.set(db.doc('products/p-a1'), { title: 'Mug', storeId: 'store-a', price: 1000, stock: 5, salesCount: 3 });
      batch.set(db.doc('products/p-a2'), { title: 'Frame', storeId: 'store-a', price: 1000, stock: null, salesCount: 2 });
      batch.set(db.doc('products/p-b1'), { title: 'Card', storeId: 'store-b', price: 1000, stock: 3, salesCount: 1 });
      await batch.commit();
    }
    const fire = async (before: DocumentData) =>
      handleOrderStatusChange({ db, messaging: fcm, logger: quiet }, { eventId: `e-${++events}`, orderId: 'o1', before, after: (await read('orders/o1'))! });

    test('cash on delivery: stock back at once, the total recomputed, the customer told which items', async () => {
      await seedProducts();
      await db.doc('orders/o1').update({ subtotal: 3000, discount: 0, deliveryFee: 0, creditsUsed: 0, walletUsed: 0 });
      const result = await move(sellerA, 'cancelledBySeller', 'Out of wood');
      assert.equal(result.status, 'pending', 'store-b still delivers');
      assert.deepEqual(result.cancelledLines, { lineIds: ['a1', 'a2'], creditsBack: 0, moneyBack: 2000, notificationId: 'o1-itemsCancelled-1' });

      const order = (await read('orders/o1'))!;
      assert.deepEqual(await statuses(), ['store-a:cancelledBySeller', 'store-a:cancelledBySeller', 'store-b:pending']);
      assert.deepEqual(order.items.map((i: DocumentData) => i.stockReleased ?? false), [true, true, false]);
      assert.deepEqual([order.subtotal, order.discount, order.total, order.originalSubtotal], [1000, 0, 1000, 3000]);
      assert.equal(order.status, 'pending');
      assert.equal(order.lineCancellations, 1);
      assert.deepEqual([(await read('products/p-a1'))?.stock, (await read('products/p-a1'))?.salesCount], [6, 2]);
      assert.deepEqual([(await read('products/p-a2'))?.stock, (await read('products/p-a2'))?.salesCount], [null, 1]);

      const notice = (await read('notifications/o1-itemsCancelled-1'))!;
      assert.equal(notice.userId, 'alice');
      assert.equal(notice.data.route, '/orders/o1');
      assert.match(notice.body, /a1, a2/);
      assert.match(notice.body, /Out of wood/);
      assert.match(notice.body, /2,000 IQD lower/);
      assert.ok(fcm.tokens().includes('tok-alice'), 'pushed');

      // A retry finds nothing left to cancel; the last store cancelling cancels the order —
      // only its own line's stock goes back (no double release).
      await rejectsWith(move(sellerA, 'cancelledBySeller'), 'failed-precondition', 'not_allowed');
      const before = (await read('orders/o1'))!;
      assert.equal((await move(sellerB, 'cancelledBySeller', 'Closed')).status, 'cancelledBySeller');
      await fire(before);
      assert.equal((await read('products/p-a1'))?.stock, 6);
      assert.equal((await read('products/p-b1'))?.stock, 4);
    });

    test('credits and a promo: credits back in proportion, the rest off the amount to collect; a later full cancellation returns only the rest', async () => {
      await seedProducts();
      await db.doc('wallets/alice').set({ balance: 0, credits: 0, currency: 'IQD' });
      await db.doc('orders/o1').update({ subtotal: 3000, discount: 300, promoCode: null, deliveryFee: 500, creditsUsed: 1000, walletUsed: 0, total: 2200 });
      const result = await move(sellerA, 'cancelledBySeller');
      assert.deepEqual([result.cancelledLines?.creditsBack, result.cancelledLines?.moneyBack], [563, 1237]);
      let order = (await read('orders/o1'))!;
      assert.deepEqual([order.subtotal, order.discount, order.total, order.refundedCredits, order.originalDiscount], [1000, 100, 963, 563, 300]);
      assert.equal((await walletTxns(db, 'alice'))[0].id, 'orderItems-o1-1-1');
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 0, credits: 563 });

      // The dashboard moves the whole order (it rewrites every line): the cancelled lines stay cancelled.
      const before = (await read('orders/o1'))!;
      await db.doc('orders/o1').update({
        status: 'confirmed',
        statusUpdatedBy: 'admin-1',
        statusUpdatedByRole: 'admin',
        items: (before.items as DocumentData[]).map((i) => ({ ...i, status: 'confirmed' })),
      });
      await fire(before);
      assert.deepEqual(await statuses(), ['store-a:cancelledBySeller', 'store-a:cancelledBySeller', 'store-b:confirmed']);

      // The customer cancels the rest: the other 437 credits come back, no stock twice.
      await cancelOrderCore(db, { orderId: 'o1', reason: null }, 'alice');
      order = (await read('orders/o1'))!;
      assert.equal(order.refundedCredits, 1000);
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 0, credits: 1000 });
      assert.deepEqual([(await read('products/p-a1'))?.stock, (await read('products/p-b1'))?.stock], [6, 4]);
    });

    test('paid (wallet): the lines\' share to the balance; the last cancellation returns the rest — never more than was paid', async () => {
      await seedProducts();
      await db.doc('wallets/alice').set({ balance: 0, credits: 0, currency: 'IQD' });
      await db.doc('orders/o1').update({ subtotal: 3000, discount: 0, deliveryFee: 0, creditsUsed: 0, walletUsed: 3000, total: 0, paymentMethod: 'wallet', paymentStatus: 'paid' });
      const result = await move(sellerB, 'cancelledBySeller');
      assert.deepEqual([result.cancelledLines?.creditsBack, result.cancelledLines?.moneyBack], [0, 1000]);
      let order = (await read('orders/o1'))!;
      assert.deepEqual([order.subtotal, order.total, order.refundedBalance, order.paymentStatus], [3000, 0, 1000, 'paid']);
      assert.match((await read('notifications/o1-itemsCancelled-1'))!.body, /1,000 IQD went back to your wallet/);

      const before = (await read('orders/o1'))!;
      await move(sellerA, 'cancelledBySeller');
      await fire(before);
      order = (await read('orders/o1'))!;
      assert.deepEqual([order.status, order.refundedBalance, order.paymentStatus], ['cancelledBySeller', 3000, 'refunded']);
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 3000, credits: 0 });
    });

    test('paid online: the money part is not counted as spent when the rest is delivered', async () => {
      await db.doc('wallets/alice').set({ balance: 0, credits: 0, currency: 'IQD' });
      await db.doc('orders/o1').update({ subtotal: 3000, deliveryFee: 0, creditsUsed: 0, walletUsed: 0, total: 3000, paymentMethod: 'zainCash', paymentStatus: 'paid' });
      await move(sellerA, 'cancelledBySeller');
      for (const s of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery']) await move(sellerB, s);
      const before = (await read('orders/o1'))!;
      await move(sellerB, 'delivered');
      await fire(before);
      assert.equal((await read('users/alice'))?.totalSpent, 1000);
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 2000, credits: 0 });
    });

    test('an order still waiting for its online payment cannot lose lines', async () => {
      await db.doc('orders/o1').update({ paymentMethod: 'zainCash', paymentStatus: 'pending', total: 3000 });
      await rejectsWith(move(sellerA, 'cancelledBySeller'), 'failed-precondition', 'awaiting_payment');
      assert.deepEqual(await statuses(), ['store-a:pending', 'store-a:pending', 'store-b:pending']);
      // Moving forward is fine.
      assert.equal((await move(sellerA, 'confirmed')).moved, 2);
    });

    test("a claim for a store the caller no longer owns moves nothing", async () => {
      await db.doc('stores/store-a').update({ ownerUid: 'someone-else' });
      await rejectsWith(move(sellerA, 'confirmed'), 'permission-denied');
      assert.deepEqual(await statuses(), ['store-a:pending', 'store-a:pending', 'store-b:pending']);
    });
  });

  test('who may call', async () => {
    await rejectsWith(move({ uid: 'alice', claims: {} }, 'confirmed'), 'permission-denied');
    await rejectsWith(move({ uid: 'admin-1', claims: { admin: true } }, 'confirmed'), 'permission-denied');
    await rejectsWith(move({}, 'confirmed'), 'unauthenticated');
    await rejectsWith(move({ uid: 'seller-s', claims: { seller: 'store-s' } }, 'confirmed'), 'permission-denied');
    await rejectsWith(move({ uid: 'seller-c', claims: { seller: 'store-c' } }, 'confirmed'), 'permission-denied');
    await db.doc('stores/store-c').set({ status: 'active' });
    await rejectsWith(move({ uid: 'seller-c', claims: { seller: 'store-c' } }, 'confirmed'), 'permission-denied');
    await rejectsWith(move(sellerA, 'refunded'), 'invalid-argument');
    await rejectsWith(move(sellerA, 'confirmed', undefined, 'missing'), 'not-found');
    assert.deepEqual(await statuses(), ['store-a:pending', 'store-a:pending', 'store-b:pending']);
  });
});

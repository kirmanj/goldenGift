/**
 * cancelOrder, onOrderStatusChange (its handler) and notifyUser against the
 * Firestore emulator; skipped without it. Own demo- project, cleared before
 * every test. Orders are created with the real placeOrder.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { notifyUser } from '../src/notifications/notifyUser';
import { orderStatusNotification } from '../src/notifications/orderMessages';
import { cancelOrderCore } from '../src/orders/cancelOrder';
import { handleOrderStatusChange, statusChangeKey } from '../src/orders/onOrderStatusChange';
import { placeOrderCore } from '../src/orders/placeOrder';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';

const PROJECT = 'demo-goldengift-order-lifecycle';
const OCT_21_8AM = Date.UTC(2026, 9, 21, 5, 0);

async function rejectsWith(promise: Promise<unknown>, code: string, reason?: string): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal(e.code, code, e.message);
    if (reason !== undefined) assert.equal((e.details as { reason?: string } | undefined)?.reason, reason);
    return true;
  });
}

describe('order lifecycle (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `order-lifecycle-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  const notifyDeps = { db, messaging: fcm, logger: quiet };
  let events = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const history = async (orderId: string) =>
    (await db.collection(`orders/${orderId}/status_history`).orderBy('at').get()).docs.map((d) => d.data());

  /** Places a COD order for `uid`: 2 × mug (stock 10 → 8). */
  async function placeMugOrder(uid = 'alice', clientRequestId = 'req-1'): Promise<string> {
    await db.doc(`carts/${uid}/items/l1`).set({
      productId: 'mug',
      storeId: 'home',
      titleSnapshot: 'Mug',
      unitPrice: 15000,
      qty: 2,
      selections: [{ groupId: 'size', type: 'textVariant', label: 'Size', valueId: 'big', priceDelta: 0 }],
      lineTotal: 30000,
      preparationDays: 0,
    });
    const placed = await placeOrderCore(
      { db, messaging: fcm, now: () => OCT_21_8AM, logger: quiet },
      { clientRequestId, addressId: 'home', deliveryDate: '2026-10-21', deliverySlot: 'morning', paymentMethod: 'cashOnDelivery' },
      uid,
    );
    return placed.orderId;
  }

  /** Applies `update` to the order like the dashboard / cancelOrder would, then runs the trigger handler for it. */
  async function changeAndTrigger(orderId: string, update: DocumentData | null, eventId = `evt-${++events}`) {
    const before = await read(`orders/${orderId}`);
    if (update !== null) await db.doc(`orders/${orderId}`).update(update);
    const after = await read(`orders/${orderId}`);
    return { eventId, before, after, result: await handleOrderStatusChange(notifyDeps, { eventId, orderId, before, after }) };
  }

  /** Exactly what AdminOrdersRepository.changeStatus writes. */
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

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    const batch = db.batch();
    batch.set(db.doc('app_settings/cities'), { items: [{ id: 'erbil', deliveryFee: 3000, isActive: true }] });
    batch.set(db.doc('stores/home'), { status: 'active' });
    batch.set(db.doc('products/mug'), {
      title: 'Mug',
      storeId: 'home',
      price: 15000,
      isActive: true,
      stock: 10,
      salesCount: 5,
      optionGroups: [{ id: 'size', type: 'textVariant', label: 'Size', values: [{ id: 'big', label: 'Big', priceDelta: 0, stock: 4 }] }],
    });
    for (const [uid, locale] of [['alice', 'ckb'], ['bob', 'en']]) {
      batch.set(db.doc(`users/${uid}`), {
        name: uid,
        locale,
        fcmTokens: [`tok-${uid}`],
        notificationsEnabled: true,
        totalOrders: 0,
        totalSpent: 0,
      });
      batch.set(db.doc(`users/${uid}/addresses/home`), { label: 'Home', name: uid, phone: '7501234567', city: 'erbil', area: 'A', street: 'S', isDefault: true });
    }
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  // ── cancelOrder ──────────────────────────────────────────────────────────
  describe('cancelOrder', () => {
    test('the owner cancels a pending order: status, lines, reason, stock and totals', async () => {
      const orderId = await placeMugOrder();
      assert.equal((await read('products/mug'))?.stock, 8);
      assert.deepEqual(await cancelOrderCore(db, { orderId, reason: '  Wrong date  ' }, 'alice'), { ok: true });

      const order = (await read(`orders/${orderId}`))!;
      assert.equal(order.status, 'cancelledByBuyer');
      assert.equal(order.cancelReason, 'Wrong date');
      assert.equal(order.statusNote, 'Wrong date');
      assert.equal(order.statusUpdatedBy, 'alice');
      assert.equal(order.statusUpdatedByRole, 'customer');
      assert.deepEqual((order.items as DocumentData[]).map((i) => i.status), ['cancelledByBuyer']);
      const mug = await read('products/mug');
      assert.equal(mug?.stock, 10);
      assert.equal(mug?.salesCount, 5);
      assert.equal((mug?.optionGroups as DocumentData[])[0].values[0].stock, 4);
      assert.equal((await read('users/alice'))?.totalOrders, 0);
      // cancelOrder writes no timeline entry — the trigger does.
      assert.deepEqual((await history(orderId)).map((h) => h.status), ['pending']);
    });

    test('a confirmed order can be cancelled; without a reason', async () => {
      const orderId = await placeMugOrder();
      await db.doc(`orders/${orderId}`).update({ status: 'confirmed' });
      await cancelOrderCore(db, { orderId }, 'alice');
      const order = await read(`orders/${orderId}`);
      assert.equal(order?.status, 'cancelledByBuyer');
      assert.equal(order?.cancelReason, null);
    });

    for (const status of ['preparing', 'readyForDelivery', 'outForDelivery', 'delivered', 'cancelledBySeller', 'refunded']) {
      test(`${status} → not_cancellable`, async () => {
        const orderId = await placeMugOrder();
        await db.doc(`orders/${orderId}`).update({ status });
        await rejectsWith(cancelOrderCore(db, { orderId }, 'alice'), 'failed-precondition', 'not_cancellable');
        assert.equal((await read('products/mug'))?.stock, 8);
      });
    }

    test('twice → the second is not_cancellable and restocks nothing', async () => {
      const orderId = await placeMugOrder();
      await cancelOrderCore(db, { orderId }, 'alice');
      await rejectsWith(cancelOrderCore(db, { orderId }, 'alice'), 'failed-precondition', 'not_cancellable');
      assert.equal((await read('products/mug'))?.stock, 10);
    });

    test('only the owner, signed in, on an existing order', async () => {
      const orderId = await placeMugOrder();
      await rejectsWith(cancelOrderCore(db, { orderId }, 'bob'), 'permission-denied');
      await rejectsWith(cancelOrderCore(db, { orderId }, undefined), 'unauthenticated');
      await rejectsWith(cancelOrderCore(db, { orderId: 'nope' }, 'alice'), 'not-found');
      await rejectsWith(cancelOrderCore(db, { orderId, reason: 'x'.repeat(301) }, 'alice'), 'invalid-argument');
      assert.equal((await read(`orders/${orderId}`))?.status, 'pending');
    });

    test('a product deleted since is skipped; unlimited stock stays unlimited', async () => {
      const orderId = await placeMugOrder();
      await db.doc('products/mug').update({ stock: null });
      await cancelOrderCore(db, { orderId }, 'alice');
      assert.equal((await read('products/mug'))?.stock, null);
      const other = await placeMugOrder('bob', 'req-b');
      await db.doc('products/mug').delete();
      assert.deepEqual(await cancelOrderCore(db, { orderId: other }, 'bob'), { ok: true });
      assert.equal(await read('products/mug'), undefined);
    });
  });

  // ── onOrderStatusChange ──────────────────────────────────────────────────
  describe('onOrderStatusChange', () => {
    test('a dashboard status change → one timeline entry from statusNote / statusUpdatedBy, and a notification', async () => {
      const orderId = await placeMugOrder();
      fcm.reset();
      const { result } = await changeAndTrigger(orderId, await adminSets(orderId, 'confirmed', 'Called the customer'));
      assert.deepEqual(result, { handled: true, status: 'confirmed', applied: true, notified: true });

      const entries = await history(orderId);
      assert.deepEqual(entries.map((h) => [h.status, h.byUid, h.byRole, h.note]), [
        ['pending', 'alice', 'customer', null],
        ['confirmed', 'admin-1', 'admin', 'Called the customer'],
      ]);
      assert.ok(entries[1].at instanceof Timestamp);

      const order = await read(`orders/${orderId}`);
      const notifications = await db.collection('notifications').where('userId', '==', 'alice').where('type', '==', 'orderStatus').get();
      const confirmed = notifications.docs.map((d) => d.data()).find((n) => String(n.title).includes('confirmed'));
      assert.ok(confirmed);
      assert.ok(String(confirmed.titleKu).includes(String(order?.orderNumber)));
      assert.deepEqual(confirmed.data, { route: `/orders/${orderId}`, id: orderId });
      // One push, in Kurdish (users.locale = ckb).
      assert.equal(fcm.calls.length, 1);
      assert.equal(fcm.calls[0].notification?.title, confirmed.titleKu);
    });

    test('the same event replayed → no second entry, no second notification', async () => {
      const orderId = await placeMugOrder();
      const first = await changeAndTrigger(orderId, await adminSets(orderId, 'confirmed'));
      fcm.reset();
      const replay = await handleOrderStatusChange(notifyDeps, {
        eventId: first.eventId,
        orderId,
        before: first.before,
        after: first.after,
      });
      assert.deepEqual(replay, { handled: true, status: 'confirmed', applied: false, notified: false });
      assert.equal((await history(orderId)).length, 2);
      assert.equal(fcm.calls.length, 0);
      assert.ok(await read(`function_runs/${statusChangeKey(orderId, first.eventId)}`));
    });

    test('concurrent deliveries of one event apply it once', async () => {
      const orderId = await placeMugOrder();
      const before = await read(`orders/${orderId}`);
      await db.doc(`orders/${orderId}`).update(await adminSets(orderId, 'confirmed'));
      const after = await read(`orders/${orderId}`);
      const results = await Promise.all(
        [1, 2, 3].map(() => handleOrderStatusChange(notifyDeps, { eventId: 'evt-same', orderId, before, after })),
      );
      assert.equal(results.filter((r) => r.handled && r.applied).length, 1);
      assert.equal((await history(orderId)).length, 2);
      const confirmed = await db.collection('notifications').where('userId', '==', 'alice').get();
      assert.equal(confirmed.docs.filter((d) => String(d.get('title')).includes('confirmed')).length, 1);
    });

    test('an update that does not change status does nothing', async () => {
      const orderId = await placeMugOrder();
      const { result } = await changeAndTrigger(orderId, { updatedAt: FieldValue.serverTimestamp(), statusNote: 'typo' });
      assert.deepEqual(result, { handled: false, reason: 'unchanged' });
      assert.equal((await history(orderId)).length, 1);
    });

    test('customer cancellation: the entry says customer + reason, and the customer is told', async () => {
      const orderId = await placeMugOrder();
      const before = await read(`orders/${orderId}`);
      await cancelOrderCore(db, { orderId, reason: 'Changed my mind' }, 'alice');
      const after = await read(`orders/${orderId}`);
      fcm.reset();
      const result = await handleOrderStatusChange(notifyDeps, { eventId: 'evt-cancel', orderId, before, after });
      assert.deepEqual(result, { handled: true, status: 'cancelledByBuyer', applied: true, notified: true });
      assert.deepEqual((await history(orderId)).map((h) => [h.status, h.byUid, h.byRole, h.note]), [
        ['pending', 'alice', 'customer', null],
        ['cancelledByBuyer', 'alice', 'customer', 'Changed my mind'],
      ]);
      // Stock was released by cancelOrder, not again by the trigger.
      assert.equal((await read('products/mug'))?.stock, 10);
      assert.equal(fcm.calls.length, 1);
    });

    test('every status of the main path, then delivered: COD paid + totalSpent once', async () => {
      const orderId = await placeMugOrder();
      for (const status of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery', 'delivered']) {
        await changeAndTrigger(orderId, await adminSets(orderId, status));
      }
      const order = await read(`orders/${orderId}`);
      assert.equal(order?.paymentStatus, 'paid');
      assert.equal((await read('users/alice'))?.totalSpent, 33000);
      assert.deepEqual((await history(orderId)).map((h) => h.status), [
        'pending',
        'confirmed',
        'preparing',
        'readyForDelivery',
        'outForDelivery',
        'delivered',
      ]);
      // The trigger's own paymentStatus write is an update without a status change.
      const { result } = await changeAndTrigger(orderId, null);
      assert.deepEqual(result, { handled: false, reason: 'unchanged' });
      const titles = (await db.collection('notifications').where('userId', '==', 'alice').get()).docs.map((d) => String(d.get('title')));
      assert.equal(titles.length, 6); // received + 5 status changes
      assert.equal((await read('users/alice'))?.totalSpent, 33000);
    });

    test('seller cancellation releases the stock, lowers totalOrders and tells the reason', async () => {
      const orderId = await placeMugOrder();
      assert.equal((await read('users/alice'))?.totalOrders, 1);
      fcm.reset();
      await changeAndTrigger(orderId, await adminSets(orderId, 'cancelledBySeller', 'Out of mugs'));
      const mug = await read('products/mug');
      assert.equal(mug?.stock, 10);
      assert.equal(mug?.salesCount, 5);
      assert.equal((mug?.optionGroups as DocumentData[])[0].values[0].stock, 4);
      assert.equal((await read('users/alice'))?.totalOrders, 0);
      assert.ok(String(fcm.calls[0].notification?.body).includes('Out of mugs'));
      // cancelled → refunded does not release anything again.
      await changeAndTrigger(orderId, await adminSets(orderId, 'refunded'));
      assert.equal((await read('products/mug'))?.stock, 10);
    });

    test('notificationsEnabled == false: in-app document only, no push; dead tokens are pruned', async () => {
      const orderId = await placeMugOrder();
      await db.doc('users/alice').update({ notificationsEnabled: false });
      fcm.reset();
      const { result } = await changeAndTrigger(orderId, await adminSets(orderId, 'confirmed'));
      assert.ok(result.handled && result.notified);
      assert.equal(fcm.calls.length, 0);

      await db.doc('users/alice').update({ notificationsEnabled: true, fcmTokens: ['tok-alice', 'tok-dead'] });
      fcm.dead.add('tok-dead');
      await changeAndTrigger(orderId, await adminSets(orderId, 'preparing'));
      assert.deepEqual(fcm.calls[0].tokens, ['tok-alice', 'tok-dead']);
      assert.deepEqual((await read('users/alice'))?.fcmTokens, ['tok-alice']);
    });

    test('an unknown status or a deleted document is ignored', async () => {
      const orderId = await placeMugOrder();
      const { result } = await changeAndTrigger(orderId, { status: 'lost' });
      assert.deepEqual(result, { handled: false, reason: 'unknownStatus' });
      assert.deepEqual(
        await handleOrderStatusChange(notifyDeps, { eventId: 'x', orderId, before: undefined, after: {} }),
        { handled: false, reason: 'missing' },
      );
    });
  });

  // ── notifyUser ───────────────────────────────────────────────────────────
  describe('notifyUser', () => {
    const message = orderStatusNotification('confirmed', { orderId: 'o1', orderNumber: 'GG-2610-00001' });

    test('writes the §6.13 document and pushes once in the user language', async () => {
      const r = await notifyUser(notifyDeps, 'bob', message);
      assert.equal(r.created, true);
      assert.equal(r.sent, 1);
      const doc = await read(`notifications/${r.notificationId}`);
      assert.deepEqual(
        { ...doc, createdAt: undefined, updatedAt: undefined },
        {
          userId: 'bob',
          title: message.title.en,
          titleAr: message.title.ar,
          titleKu: message.title.ku,
          body: message.body.en,
          bodyAr: message.body.ar,
          bodyKu: message.body.ku,
          type: 'orderStatus',
          data: { route: '/orders/o1', id: 'o1' },
          isRead: false,
          createdAt: undefined,
          updatedAt: undefined,
        },
      );
      assert.equal(fcm.calls[0].notification?.title, message.title.en);
      assert.equal(fcm.calls[0].data?.notificationId, r.notificationId);
    });

    test('a fixed notificationId is written and pushed once', async () => {
      const first = await notifyUser(notifyDeps, 'bob', message, { notificationId: 'n-fixed' });
      const second = await notifyUser(notifyDeps, 'bob', message, { notificationId: 'n-fixed' });
      assert.deepEqual([first.created, second.created], [true, false]);
      assert.equal(fcm.calls.length, 1);
    });

    test('no push without messaging, tokens or a user doc; FCM failures are swallowed', async () => {
      assert.equal((await notifyUser({ db, messaging: null }, 'bob', message)).sent, 0);
      await db.doc('users/bob').update({ fcmTokens: [] });
      assert.equal((await notifyUser(notifyDeps, 'bob', message)).sent, 0);
      assert.equal((await notifyUser(notifyDeps, 'ghost', message)).sent, 0);
      await db.doc('users/bob').update({ fcmTokens: ['tok-bob'] });
      fcm.failWith = new Error('FCM down');
      const r = await notifyUser(notifyDeps, 'bob', message);
      assert.equal(r.created, true);
      assert.equal(r.sent, 0);
      assert.deepEqual((await read('users/bob'))?.fcmTokens, ['tok-bob']);
      assert.equal(fcm.calls.length, 0);
    });
  });
});

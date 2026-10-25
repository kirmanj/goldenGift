/**
 * placeOrder against the Firestore (+ Storage) emulators; skipped without them
 * (see ./emulators.ts). Own demo- project, cleared before every test.
 */
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { getDownloadURL, getStorage } from 'firebase-admin/storage';
import { HttpsError } from 'firebase-functions/v2/https';
import { orderIdFor } from '../src/orders/orderNumber';
import { placeOrderCore, type PlaceOrderDeps } from '../src/orders/placeOrder';
import { allowAllStorageEmulatorRules, clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';

const PROJECT = 'demo-goldengift-place-order';
const BUCKET = `${PROJECT}.appspot.com`;
/** 2026-10-21 08:00 in Baghdad (05:00 UTC): before the 14:00 cut-off, the morning slot is still open. */
const OCT_21_8AM = Date.UTC(2026, 9, 21, 5, 0);
const storageSkip = needsEnv('FIREBASE_STORAGE_EMULATOR_HOST');

/** Asserts `promise` rejects with an HttpsError of `code` (and, for failed-precondition, `reason` / `productIds`). */
async function rejectsWith(
  promise: Promise<unknown>,
  code: string,
  reason?: string,
  productIds?: string[],
): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    const details = e.details as { reason?: string; productIds?: string[] } | undefined;
    if (reason !== undefined) assert.equal(details?.reason, reason);
    if (productIds !== undefined) assert.deepEqual(details?.productIds, productIds);
    return true;
  });
}

describe('placeOrder (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT, storageBucket: BUCKET }, `place-order-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  let clock = OCT_21_8AM;
  const deps: PlaceOrderDeps = {
    db,
    messaging: fcm,
    now: () => clock,
    logger: { warn: () => undefined, info: () => undefined },
  };

  const read = async (path: string) => (await db.doc(path).get()).data();
  const count = async (path: string) => (await db.collection(path).count().get()).data().count;
  const ordersOf = async (uid: string) => (await db.collection('orders').where('userId', '==', uid).get()).docs;

  /** What the app sends (PlaceOrderRequest.toMap()). */
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

  async function seedUser(uid: string, over: DocumentData = {}): Promise<void> {
    await db.doc(`users/${uid}`).set({
      name: `User ${uid}`,
      phone: '7501234567',
      countryCode: '+964',
      locale: 'en',
      fcmTokens: [`tok-${uid}`],
      notificationsEnabled: true,
      totalOrders: 0,
      totalSpent: 0,
      isBlocked: false,
      isDeleted: false,
      ...over,
    });
    await db.doc(`users/${uid}/addresses/home`).set({
      label: 'Home',
      name: 'Sara Ahmed',
      phone: '7501234567',
      city: 'erbil',
      area: 'Ankawa',
      street: '100m Rd',
      building: '12',
      floor: '3',
      notes: 'Ring twice',
      lat: null,
      lng: null,
      isDefault: true,
    });
  }

  /** A cart line exactly as the app writes it (CartItemModel.toMap + addedAt). */
  async function addToCart(uid: string, id: string, over: DocumentData = {}): Promise<void> {
    await db.doc(`carts/${uid}/items/${id}`).set({
      productId: 'mug',
      storeId: 'home',
      titleSnapshot: 'Mug',
      imageSnapshot: null,
      unitPrice: 15000,
      qty: 1,
      selections: [],
      lineTotal: 15000,
      preparationDays: 0,
      addedAt: Timestamp.now(),
      ...over,
    });
  }

  const frameLine = (over: DocumentData = {}): DocumentData => ({
    productId: 'frame',
    titleSnapshot: 'Frame',
    unitPrice: 25000,
    lineTotal: 25000,
    preparationDays: 1,
    selections: [{ groupId: 'frame', type: 'imageVariant', label: 'Frame', valueId: 'walnut', valueLabel: 'Walnut', priceDelta: 5000 }],
    ...over,
  });

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    clock = OCT_21_8AM;
    const batch = db.batch();
    batch.set(db.doc('app_settings/general'), { sameDayCutoff: '14:00', minOrder: 0 });
    batch.set(db.doc('app_settings/cities'), {
      items: [
        { id: 'erbil', name: 'Erbil', deliveryFee: 3000, isActive: true },
        { id: 'duhok', name: 'Duhok', deliveryFee: 4000, isActive: true },
        { id: 'mosul', name: 'Mosul', deliveryFee: 5000, isActive: false },
      ],
    });
    batch.set(db.doc('app_settings/payments'), { cashOnDelivery: true, wallet: true, card: false, fastPay: false, zainCash: false });
    batch.set(db.doc('stores/home'), { name: 'Golden Gift Home', status: 'active' });
    batch.set(db.doc('stores/closed'), { name: 'Closed', status: 'suspended' });
    batch.set(db.doc('products/mug'), {
      title: 'Mug',
      titleAr: 'كوب',
      titleKu: 'کوپ',
      storeId: 'home',
      images: ['https://img/mug.jpg'],
      price: 15000,
      isActive: true,
      availability: 'sameDay',
      preparationDays: 0,
      availableCities: [],
      stock: 10,
      salesCount: 0,
    });
    batch.set(db.doc('products/frame'), {
      title: 'Frame',
      storeId: 'home',
      images: [],
      price: 20000,
      isActive: true,
      availability: 'preparationDays',
      preparationDays: 1,
      availableCities: [],
      stock: null,
      salesCount: 4,
      optionGroups: [
        { id: 'frame', type: 'imageVariant', label: 'Frame', required: true, values: [{ id: 'walnut', label: 'Walnut', priceDelta: 5000 }, { id: 'oak', label: 'Oak', priceDelta: 0, stock: 1 }] },
      ],
    });
    batch.set(db.doc('products/last'), { title: 'Last one', storeId: 'home', price: 10000, isActive: true, stock: 1, salesCount: 0 });
    batch.set(db.doc('products/duhokOnly'), { title: 'Klecha', storeId: 'home', price: 8000, isActive: true, availableCities: ['duhok'], stock: null });
    await batch.commit();
    await seedUser('alice', { locale: 'ar' });
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('places a cash-on-delivery order end to end', async () => {
    await addToCart('alice', 'l1', { qty: 2, lineTotal: 30000 });
    await addToCart('alice', 'l2', frameLine());

    const placed = await place('alice', { deliveryDate: '2026-10-22' });
    const orderId = orderIdFor('alice', 'req-1');
    assert.deepEqual(placed, { orderId, orderNumber: 'GG-2610-00001', total: 58000, deliveryDate: '2026-10-22' });

    const order = await read(`orders/${orderId}`);
    assert.ok(order);
    assert.equal(order.userId, 'alice');
    assert.deepEqual(order.storeIds, ['home']);
    assert.equal(order.subtotal, 55000);
    assert.equal(order.discount, 0);
    assert.equal(order.creditsUsed, 0);
    assert.equal(order.walletUsed, 0);
    assert.equal(order.deliveryFee, 3000);
    assert.equal(order.total, 58000);
    assert.equal(order.promoCode, null);
    assert.equal(order.paymentMethod, 'cashOnDelivery');
    assert.equal(order.paymentStatus, 'pending');
    assert.equal(order.paymentRef, null);
    assert.equal(order.status, 'pending');
    assert.equal(order.orderType, 'standard');
    assert.equal(order.referralCredited, false);
    assert.equal(order.refundedToWallet, false);
    assert.deepEqual(order.rewards, {});
    assert.equal(order.deliveryDate, '2026-10-22');
    assert.equal(order.deliverySlot, 'morning');
    assert.equal(order.isGift, false);
    assert.equal(order.giftMessage, null);
    assert.equal(order.hidePrices, false);
    assert.equal(order.cancelReason, null);
    assert.equal(order.statusNote, null);
    assert.equal(order.statusUpdatedBy, 'alice');
    assert.equal(order.statusUpdatedByRole, 'customer');
    assert.equal(order.clientRequestId, 'req-1');
    assert.ok(order.createdAt instanceof Timestamp);
    assert.ok(order.updatedAt instanceof Timestamp);
    assert.deepEqual(order.address, {
      label: 'Home',
      name: 'Sara Ahmed',
      phone: '7501234567',
      city: 'erbil',
      area: 'Ankawa',
      street: '100m Rd',
      building: '12',
      floor: '3',
      notes: 'Ring twice',
      lat: null,
      lng: null,
    });
    const items = order.items as DocumentData[];
    assert.deepEqual(items.map((i) => [i.id, i.productId, i.qty, i.unitPrice, i.lineTotal, i.status, i.storeId]).sort(), [
      ['l1', 'mug', 2, 15000, 30000, 'pending', 'home'],
      ['l2', 'frame', 1, 25000, 25000, 'pending', 'home'],
    ]);
    const mug = items.find((i) => i.id === 'l1')!;
    assert.equal(mug.titleSnapshot, 'Mug');
    assert.equal(mug.titleSnapshotAr, 'كوب');
    assert.equal(mug.imageSnapshot, 'https://img/mug.jpg');

    // The first (and only) timeline entry.
    const history = await db.collection(`orders/${orderId}/status_history`).get();
    assert.equal(history.size, 1);
    const entry = history.docs[0].data();
    assert.deepEqual({ ...entry, at: undefined }, { status: 'pending', byUid: 'alice', byRole: 'customer', note: null, at: undefined });
    assert.ok(entry.at instanceof Timestamp);

    // Cart emptied, stock reserved, counters moved.
    assert.equal(await count('carts/alice/items'), 0);
    assert.deepEqual([(await read('products/mug'))?.stock, (await read('products/mug'))?.salesCount], [8, 2]);
    assert.deepEqual([(await read('products/frame'))?.stock, (await read('products/frame'))?.salesCount], [null, 5]);
    assert.equal((await read('users/alice'))?.totalOrders, 1);
    assert.equal((await read('users/alice'))?.totalSpent, 0);
    assert.equal((await read('counters/orders-2610'))?.next, 2);

    // "Order received" — in-app document + one push in the user's language (Arabic).
    const notification = await read(`notifications/${orderId}-placed`);
    assert.ok(notification);
    assert.equal(notification.userId, 'alice');
    assert.equal(notification.type, 'orderStatus');
    assert.ok(String(notification.title).includes('GG-2610-00001'));
    assert.ok(String(notification.titleAr).includes('GG-2610-00001'));
    assert.ok(String(notification.titleKu).includes('GG-2610-00001'));
    assert.deepEqual(notification.data, { route: `/orders/${orderId}`, id: orderId });
    assert.equal(notification.isRead, false);
    assert.equal(fcm.calls.length, 1);
    assert.deepEqual(fcm.calls[0].tokens, ['tok-alice']);
    assert.equal(fcm.calls[0].notification?.title, notification.titleAr);
    assert.deepEqual(fcm.calls[0].data, {
      route: `/orders/${orderId}`,
      id: orderId,
      type: 'orderStatus',
      notificationId: `${orderId}-placed`,
    });
  });

  test('same clientRequestId again → the same order, no second order or side effect', async () => {
    await addToCart('alice', 'l1');
    const first = await place('alice');
    await addToCart('alice', 'l9'); // even with a new cart, a retry must not order again
    const second = await place('alice');
    assert.deepEqual(second, first);
    assert.equal((await ordersOf('alice')).length, 1);
    assert.equal((await read('counters/orders-2610'))?.next, 2);
    assert.equal((await read('products/mug'))?.stock, 9);
    assert.equal(await count('carts/alice/items'), 1);
    assert.equal(fcm.calls.length, 1);
  });

  test('concurrent retries of one checkout create one order', async () => {
    await addToCart('alice', 'l1');
    const results = await Promise.all([place('alice'), place('alice'), place('alice')]);
    assert.deepEqual(results[1], results[0]);
    assert.deepEqual(results[2], results[0]);
    assert.equal((await ordersOf('alice')).length, 1);
    assert.equal((await read('products/mug'))?.stock, 9);
  });

  test('order numbers count up within a month and restart in the next', async () => {
    const numbers: string[] = [];
    for (const req of ['r1', 'r2', 'r3']) {
      await addToCart('alice', `line-${req}`);
      numbers.push((await place('alice', { clientRequestId: req })).orderNumber);
    }
    assert.deepEqual(numbers, ['GG-2610-00001', 'GG-2610-00002', 'GG-2610-00003']);

    clock = Date.UTC(2026, 10, 2, 5, 0); // 2 November, 08:00 Baghdad
    await addToCart('alice', 'line-nov');
    const nov = await place('alice', { clientRequestId: 'r4', deliveryDate: '2026-11-02' });
    assert.equal(nov.orderNumber, 'GG-2611-00001');
    assert.equal((await read('counters/orders-2610'))?.next, 4);
    assert.equal((await read('counters/orders-2611'))?.next, 2);
  });

  test('the month and "today" are Iraq time, not UTC', async () => {
    clock = Date.UTC(2026, 9, 31, 21, 30); // 31 Oct 21:30 UTC = 1 Nov 00:30 Baghdad
    await addToCart('alice', 'l1');
    const placed = await place('alice', { deliveryDate: '2026-11-01' });
    assert.equal(placed.orderNumber, 'GG-2611-00001');
  });

  test('gift options are stored', async () => {
    await addToCart('alice', 'l1');
    const placed = await place('alice', { isGift: true, giftMessage: '  Happy birthday, Mum!  ', hidePrices: true });
    const order = await read(`orders/${placed.orderId}`);
    assert.equal(order?.isGift, true);
    assert.equal(order?.giftMessage, 'Happy birthday, Mum!');
    assert.equal(order?.hidePrices, true);
  });

  test('empty cart → empty_cart', async () => {
    await rejectsWith(place('alice'), 'failed-precondition', 'empty_cart');
  });

  test('price changed → cart_changed; the cart line is refreshed and the next try goes through', async () => {
    await addToCart('alice', 'l1', { qty: 2, lineTotal: 30000 });
    await db.doc('products/mug').update({ price: 16000 });

    await rejectsWith(place('alice'), 'failed-precondition', 'cart_changed', ['mug']);
    assert.equal((await ordersOf('alice')).length, 0);
    assert.equal((await read('products/mug'))?.stock, 10);
    const line = await read('carts/alice/items/l1');
    assert.equal(line?.unitPrice, 16000);
    assert.equal(line?.lineTotal, 32000);

    const placed = await place('alice');
    assert.equal(placed.total, 32000 + 3000);
  });

  test('unavailable lines → cart_changed with their product ids; nothing is written', async () => {
    await db.doc('products/inactive').set({ title: 'Old', storeId: 'home', price: 1000, isActive: false });
    await db.doc('products/fromClosed').set({ title: 'Closed', storeId: 'closed', price: 1000, isActive: true });
    await db.doc('products/soldOut').set({ title: 'Sold out', storeId: 'home', price: 1000, isActive: true, availability: 'outOfStock' });
    await addToCart('alice', 'ok', { qty: 1 });
    await addToCart('alice', 'ghost', { productId: 'ghost', unitPrice: 1000, lineTotal: 1000 });
    await addToCart('alice', 'inactive', { productId: 'inactive', unitPrice: 1000, lineTotal: 1000 });
    await addToCart('alice', 'closed', { productId: 'fromClosed', unitPrice: 1000, lineTotal: 1000 });
    await addToCart('alice', 'soldOut', { productId: 'soldOut', unitPrice: 1000, lineTotal: 1000 });
    await addToCart('alice', 'oldValue', frameLine({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'gone', priceDelta: 5000 }] }));

    await rejectsWith(place('alice'), 'failed-precondition', 'cart_changed', ['fromClosed', 'frame', 'ghost', 'inactive', 'soldOut'].sort());
    assert.equal((await ordersOf('alice')).length, 0);
    assert.equal(await count('carts/alice/items'), 6);
    assert.equal((await read('products/mug'))?.stock, 10);
    assert.equal((await read('counters/orders-2610')), undefined);
  });

  test('a product limited to other cities → city_not_allowed with its id', async () => {
    await addToCart('alice', 'l1');
    await addToCart('alice', 'l2', { productId: 'duhokOnly', unitPrice: 8000, lineTotal: 8000 });
    await rejectsWith(place('alice'), 'failed-precondition', 'city_not_allowed', ['duhokOnly']);
  });

  test('an address in an inactive or unknown city → city_not_allowed for every line', async () => {
    await addToCart('alice', 'l1');
    await addToCart('alice', 'l2', frameLine());
    await db.doc('users/alice/addresses/home').update({ city: 'mosul' });
    await rejectsWith(place('alice', { deliveryDate: '2026-10-22' }), 'failed-precondition', 'city_not_allowed', ['frame', 'mug']);
    await db.doc('users/alice/addresses/home').update({ city: 'atlantis' });
    await rejectsWith(place('alice', { deliveryDate: '2026-10-22' }), 'failed-precondition', 'city_not_allowed', ['frame', 'mug']);
  });

  test('more than the stock → out_of_stock (summed over lines; also per option value)', async () => {
    await addToCart('alice', 'l1', { productId: 'last', unitPrice: 10000, lineTotal: 10000 });
    await addToCart('alice', 'l2', { productId: 'last', unitPrice: 10000, lineTotal: 10000, selections: [] });
    await rejectsWith(place('alice'), 'failed-precondition', 'out_of_stock', ['last']);
    assert.equal((await read('products/last'))?.stock, 1);

    await db.doc('carts/alice/items/l1').delete();
    await db.doc('carts/alice/items/l2').delete();
    await addToCart('alice', 'oak', frameLine({ qty: 2, unitPrice: 20000, lineTotal: 40000, selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'oak', priceDelta: 0 }] }));
    await rejectsWith(place('alice', { deliveryDate: '2026-10-22' }), 'failed-precondition', 'out_of_stock', ['frame']);
  });

  test('a stocked option value is reserved in optionGroups', async () => {
    await addToCart('alice', 'oak', frameLine({ unitPrice: 20000, lineTotal: 20000, selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'oak', priceDelta: 0 }] }));
    await place('alice', { deliveryDate: '2026-10-22' });
    const groups = (await read('products/frame'))?.optionGroups as Array<{ values: Array<{ id: string; stock?: number }> }>;
    assert.equal(groups[0].values.find((v) => v.id === 'oak')?.stock, 0);
    assert.equal(groups[0].values.find((v) => v.id === 'walnut')?.stock, undefined);
  });

  test('below the minimum order → min_order', async () => {
    await db.doc('app_settings/general').update({ minOrder: 20000 });
    await addToCart('alice', 'l1');
    await rejectsWith(place('alice'), 'failed-precondition', 'min_order');
    await db.doc('carts/alice/items/l1').update({ qty: 2, lineTotal: 30000 });
    assert.ok(await place('alice'));
  });

  test('delivery date and slot follow the checkout rules', async () => {
    await addToCart('alice', 'l1');
    await addToCart('alice', 'l2', frameLine()); // 1 preparation day → earliest 22 Oct
    await rejectsWith(place('alice', { deliveryDate: '2026-10-21' }), 'invalid-argument');
    await rejectsWith(place('alice', { deliveryDate: '2026-11-05' }), 'invalid-argument'); // earliest + 14
    await rejectsWith(place('alice', { deliveryDate: '2026-10-22', deliverySlot: 'midnight' }), 'invalid-argument');
    assert.ok(await place('alice', { deliveryDate: '2026-11-04', deliverySlot: 'evening' })); // earliest + 13
  });

  test("today's slots close when they start; after the cut-off today is gone", async () => {
    await addToCart('alice', 'l1');
    clock = Date.UTC(2026, 9, 21, 7, 30); // 10:30 Baghdad: morning has started
    await rejectsWith(place('alice', { deliverySlot: 'morning' }), 'invalid-argument');
    clock = Date.UTC(2026, 9, 21, 11, 0); // 14:00 Baghdad: cut-off
    await rejectsWith(place('alice', { deliverySlot: 'evening' }), 'invalid-argument');
    assert.ok(await place('alice', { deliveryDate: '2026-10-22', deliverySlot: 'morning' }));
  });

  test('custom delivery slots from app_settings/general', async () => {
    await db.doc('app_settings/general').update({ deliverySlots: [{ id: 'late', label: 'Late', from: '20:00', to: '23:00' }] });
    await addToCart('alice', 'l1');
    await rejectsWith(place('alice', { deliverySlot: 'morning' }), 'invalid-argument');
    assert.ok(await place('alice', { deliverySlot: 'late' }));
  });

  test('payment: only enabled methods; cash on delivery and wallet until Phase 9', async () => {
    await addToCart('alice', 'l1');
    await rejectsWith(place('alice', { paymentMethod: 'card' }), 'invalid-argument');
    // Wallet is accepted — an empty wallet just does not cover it (orderPayments.test.ts).
    await rejectsWith(place('alice', { paymentMethod: 'wallet', useWallet: true }), 'failed-precondition', 'insufficient_funds');
    await db.doc('app_settings/payments').update({ wallet: false });
    await rejectsWith(place('alice', { paymentMethod: 'wallet', useWallet: true }), 'invalid-argument');
    await db.doc('app_settings/payments').update({ cashOnDelivery: false });
    await rejectsWith(place('alice'), 'invalid-argument');
    assert.equal((await ordersOf('alice')).length, 0);
  });

  test('an unknown promo code is rejected (every rule: orderPayments.test.ts); credits without a wallet change nothing', async () => {
    await addToCart('alice', 'l1');
    await rejectsWith(place('alice', { promoCode: 'EID10' }), 'failed-precondition', 'promo_invalid');
    const placed = await place('alice', { useCredits: true });
    const order = await read(`orders/${placed.orderId}`);
    assert.deepEqual([order?.discount, order?.creditsUsed, order?.walletUsed, order?.total], [0, 0, 0, 18000]);
  });

  test('missing address → invalid-argument', async () => {
    await addToCart('alice', 'l1');
    await rejectsWith(place('alice', { addressId: 'work' }), 'invalid-argument');
  });

  test('who may order', async () => {
    await rejectsWith(placeOrderCore(deps, request(), undefined), 'unauthenticated');
    await rejectsWith(place('nobody'), 'failed-precondition'); // signed in, no profile yet
    await seedUser('blocked', { isBlocked: true });
    await addToCart('blocked', 'l1');
    await rejectsWith(place('blocked'), 'permission-denied');
    await seedUser('deleted', { isDeleted: true });
    await addToCart('deleted', 'l1');
    await rejectsWith(place('deleted'), 'permission-denied');
  });

  test('a push failure never fails the order', async () => {
    fcm.failWith = new Error('FCM down');
    await addToCart('alice', 'l1');
    const placed = await place('alice');
    assert.ok(await read(`orders/${placed.orderId}`));
    assert.ok(await read(`notifications/${placed.orderId}-placed`));
  });

  test('concurrent orders on the last units never oversell or leave a partial order', async () => {
    const buyers = ['b1', 'b2', 'b3', 'b4', 'b5', 'b6'];
    await db.doc('products/last').update({ stock: 2 });
    for (const uid of buyers) {
      await seedUser(uid);
      await addToCart(uid, 'l1', { productId: 'last', unitPrice: 10000, lineTotal: 10000 });
      await addToCart(uid, 'l2'); // a second, plentiful line: never ordered without the first
    }
    const results = await Promise.allSettled(buyers.map((uid) => place(uid, { clientRequestId: `race-${uid}` })));

    const won = buyers.filter((_, i) => results[i].status === 'fulfilled');
    const lost = buyers.filter((_, i) => results[i].status === 'rejected');
    assert.equal(won.length, 2);
    for (const r of results) {
      if (r.status === 'rejected') {
        assert.ok(r.reason instanceof HttpsError);
        assert.equal(r.reason.code, 'failed-precondition');
        assert.deepEqual(r.reason.details, { reason: 'out_of_stock', productIds: ['last'] });
      }
    }
    const last = await read('products/last');
    assert.equal(last?.stock, 0);
    assert.equal(last?.salesCount, 2);
    assert.equal((await read('products/mug'))?.stock, 8);
    const numbers = results.flatMap((r) => (r.status === 'fulfilled' ? [r.value.orderNumber] : [])).sort();
    assert.deepEqual(numbers, ['GG-2610-00001', 'GG-2610-00002']);
    assert.equal((await read('counters/orders-2610'))?.next, 3);
    for (const uid of won) {
      const orders = await ordersOf(uid);
      assert.equal(orders.length, 1);
      assert.equal((orders[0].get('items') as unknown[]).length, 2);
      assert.equal(await count(`carts/${uid}/items`), 0);
      assert.equal((await read(`users/${uid}`))?.totalOrders, 1);
    }
    for (const uid of lost) {
      assert.equal((await ordersOf(uid)).length, 0);
      assert.equal(await count(`carts/${uid}/items`), 2);
      assert.equal((await read(`users/${uid}`))?.totalOrders, 0);
    }
  });

  describe('customer photos (Storage emulator)', { skip: storageSkip }, () => {
    before(allowAllStorageEmulatorRules);
    const bucket = () => getStorage(app).bucket(BUCKET);
    const photoDeps = (): PlaceOrderDeps => ({ ...deps, bucket });

    async function upload(path: string): Promise<string> {
      const file = bucket().file(path);
      await file.save(Buffer.from('fake-jpeg'), {
        contentType: 'image/jpeg',
        metadata: { metadata: { firebaseStorageDownloadTokens: `token-${runId()}` } },
      });
      return getDownloadURL(file);
    }

    test('photos are copied to orders/{orderId}/{lineId}/{n}.jpg and the order points at the copies', async () => {
      await db.doc('products/photoMug').set({
        title: 'Photo mug',
        storeId: 'home',
        price: 12000,
        isActive: true,
        stock: null,
        optionGroups: [{ id: 'photos', type: 'photoUpload', label: 'Photos', required: true, minPhotos: 1, maxPhotos: 3 }],
      });
      const own1 = await upload('uploads/alice/line-p/1.jpg');
      const own2 = await upload('uploads/alice/line-p/2.jpg');
      const foreign = await upload('uploads/mallory/x/1.jpg');
      await addToCart('alice', 'line-p', {
        productId: 'photoMug',
        unitPrice: 12000,
        lineTotal: 12000,
        selections: [{ groupId: 'photos', type: 'photoUpload', label: 'Photos', urls: [own1, own2, foreign], priceDelta: 0 }],
      });

      const placed = await placeOrderCore(photoDeps(), request(), 'alice');
      const order = await read(`orders/${placed.orderId}`);
      const urls = ((order?.items as DocumentData[])[0].selections as DocumentData[])[0].urls as string[];
      assert.equal(urls.length, 3);
      assert.ok(urls[0].includes(encodeURIComponent(`orders/${placed.orderId}/line-p/1.jpg`)), urls[0]);
      assert.ok(urls[1].includes(encodeURIComponent(`orders/${placed.orderId}/line-p/2.jpg`)), urls[1]);
      assert.equal(urls[2], foreign); // not the customer's own upload: left as it was
      const [exists] = await bucket().file(`orders/${placed.orderId}/line-p/1.jpg`).exists();
      assert.equal(exists, true);
      const res = await fetch(urls[0]);
      assert.equal(res.status, 200);
      assert.equal(await res.text(), 'fake-jpeg');
      // Originals are kept (see orderPhotos.ts).
      assert.equal((await bucket().file('uploads/alice/line-p/1.jpg').exists())[0], true);
    });

    test('no bucket configured: the order still succeeds with the upload URLs', async () => {
      await db.doc('products/photoMug').set({
        title: 'Photo mug',
        storeId: 'home',
        price: 12000,
        isActive: true,
        optionGroups: [{ id: 'photos', type: 'photoUpload', label: 'Photos', required: true }],
      });
      const url = await upload('uploads/alice/line-q/1.jpg');
      await addToCart('alice', 'line-q', {
        productId: 'photoMug',
        unitPrice: 12000,
        lineTotal: 12000,
        selections: [{ groupId: 'photos', type: 'photoUpload', urls: [url], priceDelta: 0 }],
      });
      const broken: PlaceOrderDeps = {
        ...deps,
        bucket: () => {
          throw new Error('Bucket name not specified or invalid.');
        },
      };
      const placed = await placeOrderCore(broken, request(), 'alice');
      const order = await read(`orders/${placed.orderId}`);
      assert.deepEqual(((order?.items as DocumentData[])[0].selections as DocumentData[])[0].urls, [url]);
    });
  });
});

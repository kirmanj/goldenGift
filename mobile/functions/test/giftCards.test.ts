/**
 * Gift cards end to end against the Firestore emulator (skipped without it):
 * purchaseGiftCard (wallet / cash on delivery) → onGiftCardOrderPaid (its
 * handler) → notifications → redeemGiftCard → wallet credits; scheduled sending,
 * expiry, reversal, linking new users, adminIssueGiftCard. Own demo- project,
 * cleared before every test; wallets are checked with the Phase 7 wallet audit.
 * SRS Phase 8 exit: "a gift card is bought → received → redeemed".
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { adminIssueGiftCardCore } from '../src/giftCards/adminIssueGiftCard';
import { isGiftCardCode } from '../src/giftCards/giftCardRules';
import { handleGiftCardOrderWrite, linkGiftCardsToNewUser } from '../src/giftCards/issueGiftCard';
import { purchaseGiftCardCore } from '../src/giftCards/purchaseGiftCard';
import { REDEEM_WRONG_CODE_LIMIT, redeemGiftCardCore } from '../src/giftCards/redeemGiftCard';
import { expireGiftCards, sendDueGiftCards } from '../src/giftCards/scheduledGiftCards';
import { handleOrderStatusChange } from '../src/orders/onOrderStatusChange';
import { epochMillis } from '../src/shared/firestoreParse';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { FakeRecipients } from './fakeRecipients';
import { assertWalletConsistent, grantBalance, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-gift-cards';
/** 2026-10-21 08:00 in Baghdad. */
const NOW = Date.UTC(2026, 9, 21, 5, 0);
const DAY = 86_400_000;

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

describe('gift cards (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `gift-cards-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  let clock = NOW;
  /** Firebase Auth's verified phones / emails (the only thing recipients are matched on). */
  const recipients = new FakeRecipients();
  const deps = { db, messaging: fcm, now: () => clock, logger: quiet, recipients };
  let events = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const notificationsOf = async (uid: string) =>
    (await db.collection('notifications').where('userId', '==', uid).get()).docs.map((d) => ({ id: d.id, ...d.data() }) as DocumentData);

  const purchaseData = (over: Record<string, unknown> = {}) => ({
    clientRequestId: 'req-1',
    templateId: 't1',
    amount: 25000,
    recipientName: 'Bob',
    recipientPhone: '+9647701234567',
    recipientEmail: null,
    message: 'Happy birthday!',
    photoUrl: null,
    scheduledAt: null,
    paymentMethod: 'wallet',
    addressId: null,
    ...over,
  });
  const purchase = (uid: string, over: Record<string, unknown> = {}) => purchaseGiftCardCore(deps, purchaseData(over), uid);

  /** Runs the onGiftCardOrderPaid handler for the order as it is now (after `before`). */
  async function fire(orderId: string, before: DocumentData | undefined) {
    const after = await read(`orders/${orderId}`);
    return handleGiftCardOrderWrite(deps, { eventId: `evt-${++events}`, orderId, before, after });
  }

  /** Applies `update` like the dashboard, then runs onOrderStatusChange's handler for it. */
  async function adminSets(orderId: string, status: string): Promise<{ before: DocumentData; afterTrigger: DocumentData }> {
    const before = (await read(`orders/${orderId}`))!;
    await db.doc(`orders/${orderId}`).update({
      status,
      statusNote: null,
      statusUpdatedBy: 'admin-ops',
      statusUpdatedByRole: 'admin',
      items: (before.items as DocumentData[]).map((i) => ({ ...i, status })),
      updatedAt: FieldValue.serverTimestamp(),
    });
    const after = (await read(`orders/${orderId}`))!;
    await handleOrderStatusChange({ db, messaging: fcm, logger: quiet, now: () => clock }, {
      eventId: `evt-${++events}`,
      orderId,
      before,
      after,
    });
    return { before: after, afterTrigger: (await read(`orders/${orderId}`))! };
  }

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
  }

  /** A wallet purchase issued by the trigger; returns the order and card ids. */
  async function boughtAndIssued(over: Record<string, unknown> = {}): Promise<{ orderId: string; giftCardId: string }> {
    const placed = await purchase('alice', over);
    const result = await fire(placed.orderId, undefined);
    assert.equal(result.action, 'issued', JSON.stringify(result));
    return { orderId: placed.orderId, giftCardId: (result as { giftCardId: string }).giftCardId };
  }

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
    batch.set(db.doc('gift_card_templates/t1'), {
      name: 'Eid',
      nameAr: 'عيد',
      nameKu: 'جەژن',
      artworkUrl: 'https://img/eid.jpg',
      gradientStart: '#9C7A14',
      gradientEnd: '#E3C04A',
      presetAmounts: [25000, 50000],
      minAmount: 10000,
      maxAmount: 200000,
      isActive: true,
    });
    batch.set(db.doc('gift_card_templates/t-off'), { name: 'Old', presetAmounts: [25000], isActive: false });
    for (const [uid, role] of [['admin-super', 'super'], ['admin-ops', 'ops'], ['admin-fin', 'finance'], ['admin-content', 'content']]) {
      batch.set(db.doc(`admins/${uid}`), { name: uid, role, permissions: [] });
    }
    await batch.commit();
    recipients
      .reset()
      .verify('alice', { phone: '+9647501234567' })
      .verify('bob', { phone: '+9647701234567' })
      .verify('carol', { phone: '+9647801234567', email: 'carol@example.com' });
    await seedUser('alice', { phone: '7501234567', countryCode: '+964' });
    await db.doc('users/alice/addresses/home').set({ label: 'Home', name: 'Alice', phone: '7501234567', city: 'erbil', area: 'A', street: 'S' });
    await db.doc('users/alice/addresses/far').set({ label: 'Far', name: 'Alice', phone: '7501234567', city: 'mosul' });
    await seedUser('bob', { phone: '7701234567', countryCode: '+964', locale: 'ar' });
    await seedUser('carol', { email: 'carol@example.com', phone: '7801234567', countryCode: '+964', locale: 'ckb' });
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  describe('bought → received → redeemed (wallet)', () => {
    test('the purchase: one paid giftCard order, the balance debited', async () => {
      await grantBalance(db, 'alice', 30000);
      await grantCredits(db, 'alice', 50000); // credits never buy gift cards
      const placed = await purchase('alice');
      assert.deepEqual(placed, { orderId: placed.orderId, orderNumber: 'GG-2610-00001', total: 0, deliveryDate: null });

      const order = (await read(`orders/${placed.orderId}`))!;
      assert.equal(order.orderType, 'giftCard');
      assert.equal(order.userId, 'alice');
      assert.equal(order.status, 'pending');
      assert.equal(order.paymentMethod, 'wallet');
      assert.equal(order.paymentStatus, 'paid');
      assert.equal(order.subtotal, 25000);
      assert.equal(order.walletUsed, 25000);
      assert.equal(order.creditsUsed, 0);
      assert.equal(order.deliveryFee, 0);
      assert.equal(order.total, 0);
      assert.equal(order.address, null);
      assert.equal(order.giftCardId, null);
      assert.deepEqual(order.storeIds, ['golden-gift-home']);
      assert.equal(order.items.length, 1);
      assert.deepEqual(
        { ...order.items[0], selections: undefined },
        {
          id: 'gift-card',
          productId: '',
          storeId: 'golden-gift-home',
          titleSnapshot: 'Eid',
          titleSnapshotAr: 'عيد',
          titleSnapshotKu: 'جەژن',
          imageSnapshot: 'https://img/eid.jpg',
          unitPrice: 25000,
          qty: 1,
          selections: undefined,
          lineTotal: 25000,
          preparationDays: 0,
          status: 'pending',
        },
      );
      assert.equal(order.items[0].selections[0].text, 'Bob');
      assert.deepEqual(order.giftCard, {
        templateId: 't1',
        amount: 25000,
        recipientName: 'Bob',
        recipientPhone: '+9647701234567',
        recipientEmail: null,
        message: 'Happy birthday!',
        photoUrl: null,
        scheduledAt: null,
      });
      assert.equal((await db.collection(`orders/${placed.orderId}/status_history`).get()).size, 1);
      assert.equal((await read('users/alice'))?.totalOrders, 1);
      assert.equal((await read('counters/orders-2610'))?.next, 2);

      const wallet = await assertWalletConsistent(db, 'alice');
      assert.deepEqual(wallet, { balance: 5000, credits: 50000 });
      const payment = (await walletTxns(db, 'alice')).find((t) => t.type === 'orderPayment')!;
      assert.equal(payment.id, `order-${placed.orderId}-1`);
      assert.equal(payment.amount, -25000);
      assert.equal(payment.bucket, 'balance');
      assert.equal(payment.orderId, placed.orderId);
      assert.equal(payment.title, 'Order GG-2610-00001');
      assert.ok((await notificationsOf('alice')).some((n) => n.id === `${placed.orderId}-placed`));
    });

    test('the trigger issues the card, links it, delivers the order and notifies both', async () => {
      await grantBalance(db, 'alice', 25000);
      const { orderId, giftCardId } = await boughtAndIssued();

      const card = (await read(`gift_cards/${giftCardId}`))!;
      assert.ok(isGiftCardCode(card.code), card.code);
      assert.equal(card.amount, 25000);
      assert.equal(card.balance, 25000);
      assert.equal(card.purchaserUid, 'alice');
      assert.equal(card.recipientUid, 'bob', 'matched by the national phone + countryCode');
      assert.equal(card.status, 'sent');
      assert.ok(card.sentAt);
      assert.ok(card.createdAt);
      assert.equal(card.orderId, orderId);
      assert.equal(epochMillis(card.expiresAt), NOW + 365 * DAY);
      assert.equal(card.templateName, 'Eid');
      assert.equal(card.templateNameAr, 'عيد');
      assert.equal(card.gradientStart, '#9C7A14');
      assert.equal(card.message, 'Happy birthday!');

      const order = (await read(`orders/${orderId}`))!;
      assert.equal(order.giftCardId, giftCardId);
      assert.equal(order.status, 'delivered', 'a wallet order cannot be cancelled once its card exists');
      assert.deepEqual(order.items.map((i: DocumentData) => i.status), ['delivered']);
      assert.equal(order.statusUpdatedByRole, 'admin');

      const bobs = await notificationsOf('bob');
      assert.equal(bobs.length, 1);
      assert.equal(bobs[0].type, 'giftCardReceived');
      assert.equal(bobs[0].data.route, '/gift-cards');
      assert.match(bobs[0].body, /User alice sent you a 25,000 IQD gift card/);
      assert.ok(fcm.calls.some((c) => c.tokens.includes('tok-bob') && /بطاقة هدية/.test(c.notification?.title ?? '')), 'pushed in Arabic');
      assert.ok((await notificationsOf('alice')).some((n) => n.type === 'giftCardSent'));

      // Replays and the order's own later updates issue nothing more.
      assert.deepEqual(await fire(orderId, undefined), { action: 'skipped', reason: 'alreadyIssued' });
      assert.equal((await db.collection('gift_cards').get()).size, 1);
    });

    test('the recipient redeems it into wallet credits (lot expiring with the card)', async () => {
      await grantBalance(db, 'alice', 25000);
      await grantBalance(db, 'bob', 1000);
      const { giftCardId } = await boughtAndIssued();
      const { code } = (await read(`gift_cards/${giftCardId}`))!;

      const typed = `${code.slice(0, 4).toLowerCase()}-${code.slice(4, 8)} ${code.slice(8)}`;
      const result = await redeemGiftCardCore({ db, now: () => clock }, { code: typed }, 'bob');
      assert.deepEqual(result, { giftCardId, amount: 25000, credits: 25000 });

      const card = (await read(`gift_cards/${giftCardId}`))!;
      assert.equal(card.status, 'redeemed');
      assert.equal(card.balance, 0);
      assert.ok(card.redeemedAt);
      assert.equal(card.recipientUid, 'bob');

      assert.deepEqual(await assertWalletConsistent(db, 'bob'), { balance: 1000, credits: 25000 });
      const txn = (await walletTxns(db, 'bob')).find((t) => t.type === 'giftCardRedeem')!;
      assert.equal(txn.id, `giftCard-${giftCardId}-1`);
      assert.equal(txn.bucket, 'credits');
      assert.equal(txn.amount, 25000);
      assert.equal(txn.giftCardId, giftCardId);
      assert.equal(txn.title, 'Gift card redeemed');
      assert.equal(txn.titleKu, 'کارتی دیاری بەکارهێنرا');
      const lots = (await db.collection('wallets/bob/credit_lots').get()).docs.map((d) => d.data());
      assert.equal(lots.length, 1);
      assert.equal(lots[0].source, 'giftCard');
      assert.equal(lots[0].giftCardId, giftCardId);
      assert.equal(lots[0].remaining, 25000);
      assert.equal(epochMillis(lots[0].expiresAt), epochMillis(card.expiresAt));

      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code }, 'bob'), 'failed-precondition', 'redeemed');
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code }, 'carol'), 'failed-precondition', 'redeemed');
      await assertWalletConsistent(db, 'alice');
    });

    test('anyone holding the code may redeem it (the card becomes theirs)', async () => {
      await grantBalance(db, 'alice', 25000);
      const { giftCardId } = await boughtAndIssued({ recipientPhone: '+9647509990000' });
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientUid, null);
      const { code } = (await read(`gift_cards/${giftCardId}`))!;
      await redeemGiftCardCore({ db, now: () => clock }, { code }, 'carol');
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientUid, 'carol');
      assert.deepEqual(await assertWalletConsistent(db, 'carol'), { balance: 0, credits: 25000 });
    });
  });

  describe('purchaseGiftCard', () => {
    test('the same clientRequestId is the same order — charged once', async () => {
      await grantBalance(db, 'alice', 100000);
      const first = await purchase('alice');
      const again = await purchase('alice');
      assert.deepEqual(again, first);
      const second = await purchase('alice', { clientRequestId: 'req-2', amount: 50000 });
      assert.equal(second.orderNumber, 'GG-2610-00002');
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 25000, credits: 0 });
    });

    test('a wallet payment needs the BALANCE to cover it', async () => {
      await grantBalance(db, 'alice', 10000);
      await grantCredits(db, 'alice', 100000);
      await rejectsWith(purchase('alice'), 'failed-precondition', 'insufficient_funds');
      assert.equal((await db.collection('orders').get()).size, 0);
      assert.deepEqual(await assertWalletConsistent(db, 'alice'), { balance: 10000, credits: 100000 });
    });

    test('template and amount: active templates, presets or the custom range', async () => {
      await grantBalance(db, 'alice', 1_000_000);
      await purchase('alice', { clientRequestId: 'c-1', amount: 12345 });
      await rejectsWith(purchase('alice', { clientRequestId: 'c-2', amount: 9000 }), 'invalid-argument');
      await rejectsWith(purchase('alice', { clientRequestId: 'c-3', amount: 300000 }), 'invalid-argument');
      await rejectsWith(purchase('alice', { clientRequestId: 'c-4', templateId: 't-off' }), 'invalid-argument');
      await rejectsWith(purchase('alice', { clientRequestId: 'c-5', templateId: 'missing' }), 'invalid-argument');
    });

    test('payment methods follow app_settings/payments', async () => {
      await grantBalance(db, 'alice', 100000);
      await db.doc('app_settings/payments').set({ cashOnDelivery: false, wallet: true });
      await rejectsWith(purchase('alice', { paymentMethod: 'cashOnDelivery', addressId: 'home' }), 'invalid-argument');
      await purchase('alice');
    });

    test('blocked accounts and signed-out callers cannot buy', async () => {
      await rejectsWith(purchaseGiftCardCore(deps, purchaseData(), undefined), 'unauthenticated');
      await seedUser('mallory', { isBlocked: true });
      await rejectsWith(purchase('mallory'), 'permission-denied');
    });
  });

  describe('cash on delivery: issued when ops deliver (collected)', () => {
    test("the buyer's address, no fee, the card after delivery + paid", async () => {
      const placed = await purchase('alice', {
        paymentMethod: 'cashOnDelivery',
        addressId: 'home',
        recipientPhone: null,
        recipientEmail: 'Carol@Example.com',
      });
      assert.equal(placed.total, 25000);
      assert.equal(placed.deliveryDate, '2026-10-21');
      let order = (await read(`orders/${placed.orderId}`))!;
      assert.equal(order.paymentStatus, 'pending');
      assert.equal(order.deliveryFee, 0);
      assert.equal(order.address.city, 'erbil');
      assert.equal(order.giftCard.recipientEmail, 'carol@example.com');
      assert.deepEqual(await fire(placed.orderId, undefined), { action: 'skipped', reason: 'notPaid' });

      for (const status of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery']) {
        const { before } = await adminSets(placed.orderId, status);
        assert.equal((await fire(placed.orderId, before)).action, 'skipped');
      }
      const delivered = await adminSets(placed.orderId, 'delivered');
      order = delivered.afterTrigger;
      assert.equal(order.paymentStatus, 'paid', 'onOrderStatusChange marks cash on delivery paid');
      const result = await fire(placed.orderId, delivered.before);
      assert.equal(result.action, 'issued');
      const card = (await read(`gift_cards/${(result as { giftCardId: string }).giftCardId}`))!;
      assert.equal(card.recipientUid, 'carol', 'matched by email');
      assert.equal(card.status, 'sent');
      assert.equal((await read(`orders/${placed.orderId}`))?.status, 'delivered');
      assert.ok((await notificationsOf('carol')).some((n) => n.type === 'giftCardReceived'));
    });

    test('the address must exist and its city be served', async () => {
      await rejectsWith(purchase('alice', { paymentMethod: 'cashOnDelivery', addressId: 'far' }), 'failed-precondition', 'city_not_allowed');
      await rejectsWith(purchase('alice', { paymentMethod: 'cashOnDelivery', addressId: 'nowhere' }), 'invalid-argument');
    });

    test('a cancelled order never gets a card', async () => {
      const placed = await purchase('alice', { paymentMethod: 'cashOnDelivery', addressId: 'home' });
      await db.doc(`orders/${placed.orderId}`).update({ status: 'cancelledByBuyer', paymentStatus: 'paid' });
      assert.deepEqual(await fire(placed.orderId, undefined), { action: 'skipped', reason: 'cancelled' });
      assert.equal((await db.collection('gift_cards').get()).size, 0);
    });
  });

  describe('scheduled cards and expiry', () => {
    test('a scheduled card stays pending until its day, then goes out', async () => {
      await grantBalance(db, 'alice', 25000);
      const sendAt = NOW + 2 * DAY;
      const { giftCardId } = await boughtAndIssued({ scheduledAt: new Date(sendAt).toISOString() });
      let card = (await read(`gift_cards/${giftCardId}`))!;
      assert.equal(card.status, 'pending');
      assert.equal(card.sentAt, null);
      assert.equal(epochMillis(card.scheduledAt), sendAt);
      assert.equal((await notificationsOf('bob')).length, 0, 'the recipient hears nothing yet');
      assert.ok((await notificationsOf('alice')).some((n) => n.id === `giftCard-${giftCardId}-scheduled` && /2026-10-23/.test(n.body)));
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: card.code }, 'bob'), 'failed-precondition', 'not_sent');

      assert.deepEqual(await sendDueGiftCards(deps, NOW + DAY), { sent: [] });
      assert.deepEqual(await sendDueGiftCards(deps, sendAt + 60_000), { sent: [giftCardId] });
      assert.deepEqual(await sendDueGiftCards(deps, sendAt + 120_000), { sent: [] }, 'sent once');
      card = (await read(`gift_cards/${giftCardId}`))!;
      assert.equal(card.status, 'sent');
      assert.ok(card.sentAt);
      const bobs = await notificationsOf('bob');
      assert.equal(bobs.length, 1);
      assert.equal(bobs[0].type, 'giftCardReceived');
      assert.ok((await notificationsOf('alice')).some((n) => n.id === `giftCard-${giftCardId}-sent`));
    });

    test('cards past expiresAt become expired and cannot be redeemed', async () => {
      await grantBalance(db, 'alice', 25000);
      const { giftCardId } = await boughtAndIssued();
      const { code } = (await read(`gift_cards/${giftCardId}`))!;
      clock = NOW + 366 * DAY;
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code }, 'bob'), 'failed-precondition', 'expired');
      assert.deepEqual(await expireGiftCards({ db }, NOW + 100 * DAY), { expired: [] });
      assert.deepEqual(await expireGiftCards({ db }, clock), { expired: [giftCardId] });
      assert.equal((await read(`gift_cards/${giftCardId}`))?.status, 'expired');
      assert.deepEqual(await expireGiftCards({ db }, clock), { expired: [] });
    });

    test('an order refunded after issue disables its unredeemed card', async () => {
      await grantBalance(db, 'alice', 25000);
      const { orderId, giftCardId } = await boughtAndIssued();
      const before = (await read(`orders/${orderId}`))!;
      await db.doc(`orders/${orderId}`).update({ status: 'refunded' });
      assert.deepEqual(await fire(orderId, before), { action: 'disabled', giftCardId });
      const card = (await read(`gift_cards/${giftCardId}`))!;
      assert.equal(card.status, 'disabled');
      assert.match(card.disabledReason, /GG-2610-00001 was refunded/);
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: card.code }, 'bob'), 'failed-precondition', 'disabled');
    });
  });

  describe('redeemGiftCard limits', () => {
    test('a wrong code is not-found with a message; 10 per hour, then resource-exhausted', async () => {
      await grantBalance(db, 'alice', 25000);
      const { giftCardId } = await boughtAndIssued();
      const { code } = (await read(`gift_cards/${giftCardId}`))!;
      const e = await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: 'AAAAAAAAAAAA' }, 'bob'), 'not-found');
      assert.equal(e.message, 'No gift card matches this code.');
      assert.equal(e.details, undefined);
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: 'short' }, 'bob'), 'not-found');
      for (let i = 2; i < REDEEM_WRONG_CODE_LIMIT; i++) {
        await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: 'AAAAAAAAAAAA' }, 'bob'), 'not-found');
      }
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code }, 'bob'), 'resource-exhausted');
      // Another user is not limited; an hour later bob may try again.
      await rejectsWith(redeemGiftCardCore({ db, now: () => clock }, { code: 'AAAAAAAAAAAA' }, 'carol'), 'not-found');
      clock = NOW + 61 * 60_000;
      assert.equal((await redeemGiftCardCore({ db, now: () => clock }, { code }, 'bob')).amount, 25000);
    });

    test('signed out / malformed data', async () => {
      await rejectsWith(redeemGiftCardCore({ db }, { code: 'AAAAAAAAAAAA' }, undefined), 'unauthenticated');
      await rejectsWith(redeemGiftCardCore({ db }, {}, 'bob'), 'invalid-argument');
    });
  });

  describe('new accounts', () => {
    test('a card sent to a number without an account shows up once that person signs up', async () => {
      await grantBalance(db, 'alice', 25000);
      const { giftCardId } = await boughtAndIssued({ recipientPhone: '0750 999 8877', recipientName: 'Dave' });
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientPhone, '+9647509998877');
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientUid, null);
      await seedUser('dave', { phone: '7509998877', countryCode: '+964' });
      recipients.verify('dave', { phone: '+9647509998877' }); // verifyOtp proved it at sign-up
      assert.deepEqual(await linkGiftCardsToNewUser(deps, 'dave', await read('users/dave')), { linked: [giftCardId] });
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientUid, 'dave');
      assert.ok((await notificationsOf('dave')).some((n) => n.type === 'giftCardReceived'));
      assert.deepEqual(await linkGiftCardsToNewUser(deps, 'dave', await read('users/dave')), { linked: [] });
    });
  });

  describe('recipients are matched on VERIFIED identities only (Phase 10)', () => {
    test("a profile that claims somebody else's phone or email never receives their card", async () => {
      // mallory typed bob's number and carol's email into her profile; Auth knows better.
      await seedUser('mallory', { phone: '7701234567', countryCode: '+964', email: 'carol@example.com' });
      recipients.verify('mallory', { phone: '+9647709990000' });
      await grantBalance(db, 'alice', 50000);
      const toBob = await boughtAndIssued();
      assert.equal((await read(`gift_cards/${toBob.giftCardId}`))?.recipientUid, 'bob');
      const toCarol = await boughtAndIssued({ clientRequestId: 'req-2', recipientPhone: null, recipientEmail: 'carol@example.com', recipientName: 'Carol' });
      assert.equal((await read(`gift_cards/${toCarol.giftCardId}`))?.recipientUid, 'carol');
      assert.deepEqual(await linkGiftCardsToNewUser(deps, 'mallory', await read('users/mallory')), { linked: [] });
      assert.equal((await notificationsOf('mallory')).length, 0);
    });

    test('an unverified email (typed at sign-up) is not matched: the card waits for its code', async () => {
      await grantBalance(db, 'alice', 25000);
      const { giftCardId } = await boughtAndIssued({ recipientPhone: null, recipientEmail: 'nobody@example.com', recipientName: 'Nobody' });
      assert.equal((await read(`gift_cards/${giftCardId}`))?.recipientUid, null);
      await seedUser('nobody', { email: 'nobody@example.com' });
      recipients.verify('nobody', { phone: '+9647500000001' }); // email never verified
      assert.deepEqual(await linkGiftCardsToNewUser(deps, 'nobody', await read('users/nobody')), { linked: [] });
    });

    test('without a lookup nobody is matched (never a fallback to profile fields)', async () => {
      await grantBalance(db, 'alice', 25000);
      const placed = await purchase('alice');
      const after = await read(`orders/${placed.orderId}`);
      const result = await handleGiftCardOrderWrite({ db, messaging: fcm, now: () => clock, logger: quiet }, { eventId: 'evt-nolookup', orderId: placed.orderId, before: undefined, after });
      assert.equal(result.action, 'issued');
      assert.equal((await read(`gift_cards/${(result as { giftCardId: string }).giftCardId}`))?.recipientUid, null);
    });

    test('the photo must be the buyer\'s own upload', async () => {
      await grantBalance(db, 'alice', 25000);
      const own = 'https://firebasestorage.googleapis.com/v0/b/goldengift-iq.appspot.com/o/gift_cards%2Falice%2Freq-p%2F1.jpg?alt=media&token=t';
      for (const photoUrl of [
        'https://evil.example/pixel.jpg',
        'https://firebasestorage.googleapis.com/v0/b/goldengift-iq.appspot.com/o/gift_cards%2Fbob%2Freq%2F1.jpg?alt=media',
        'https://firebasestorage.googleapis.com/v0/b/goldengift-iq.appspot.com/o/gift_cards%2Falice%2F..%2Fbob%2F1.jpg?alt=media',
      ]) {
        await rejectsWith(purchase('alice', { clientRequestId: `req-${photoUrl.length}`, photoUrl }), 'invalid-argument');
      }
      const placed = await purchase('alice', { clientRequestId: 'req-p', photoUrl: own });
      assert.equal((await read(`orders/${placed.orderId}`))?.giftCard.photoUrl, own);
    });
  });

  describe('adminIssueGiftCard', () => {
    const issue = (uid: string, data: Record<string, unknown>, claims: Record<string, unknown> = { admin: true }) =>
      adminIssueGiftCardCore(deps, data, { uid, claims });
    const base = { templateId: 't1', amount: 50000, recipientName: 'Bob', recipientPhone: '07701234567', message: 'Sorry!' };

    test('ops / finance issue a template amount: a sent card, audited, recipient notified', async () => {
      const { giftCardId, code } = await issue('admin-ops', base);
      assert.ok(isGiftCardCode(code));
      const card = (await read(`gift_cards/${giftCardId}`))!;
      assert.equal(card.code, code);
      assert.equal(card.status, 'sent');
      assert.equal(card.purchaserUid, null);
      assert.equal(card.issuedBy, 'admin-ops');
      assert.equal(card.orderId, null);
      assert.equal(card.recipientPhone, '+9647701234567');
      assert.equal(card.recipientUid, 'bob');
      assert.ok(card.createdAt);
      assert.equal(epochMillis(card.expiresAt), NOW + 365 * DAY);
      const audit = (await db.collection('admin_audit_log').get()).docs.map((d) => d.data());
      assert.equal(audit.length, 1);
      assert.equal(audit[0].action, 'giftCard.issue');
      assert.equal(audit[0].adminUid, 'admin-ops');
      assert.equal(audit[0].target, `gift_cards/${giftCardId}`);
      assert.ok(!JSON.stringify(audit[0]).includes(code), 'the code is not logged');
      assert.ok((await notificationsOf('bob')).some((n) => n.type === 'giftCardReceived'));
      await issue('admin-fin', { ...base, amount: 12000, recipientPhone: null });
    });

    test('custom expiry; off-template amounts only for super admins (1,000–10,000,000)', async () => {
      const expiresAt = new Date(NOW + 30 * DAY).toISOString();
      const { giftCardId } = await issue('admin-super', { ...base, amount: 7500, expiresAt });
      assert.equal(epochMillis((await read(`gift_cards/${giftCardId}`))?.expiresAt), Date.parse(expiresAt));
      await rejectsWith(issue('admin-ops', { ...base, amount: 7500 }), 'invalid-argument');
      await rejectsWith(issue('admin-super', { ...base, amount: 999 }), 'invalid-argument');
      await issue('admin-super', { ...base, amount: 10_000_000 });
    });

    test('who may issue', async () => {
      await rejectsWith(issue('admin-content', base), 'permission-denied');
      await rejectsWith(issue('admin-ops', base, {}), 'permission-denied');
      await rejectsWith(issue('nobody', base), 'permission-denied');
      await rejectsWith(adminIssueGiftCardCore(deps, base, {}), 'unauthenticated');
      const e = await rejectsWith(issue('admin-ops', { ...base, templateId: 'missing' }), 'not-found');
      assert.equal(e.message, 'Gift card template not found.');
    });
  });
});

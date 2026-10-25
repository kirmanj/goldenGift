/**
 * Referral rewards against the Firestore emulator (skipped without it): the join
 * bonus and monthly cap of onUserCreate (processNewUser) and the orderBonus of
 * onOrderStatusChange — paid exactly once however events replay. Own demo-
 * project, cleared before every test.
 */
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { handleOrderStatusChange } from '../src/orders/onOrderStatusChange';
import { placeOrderCore } from '../src/orders/placeOrder';
import { REFERRAL_NOT_APPLIED } from '../src/users/referralNotice';
import { processNewUser } from '../src/users/processNewUser';
import { DAY_MS } from '../src/wallet/walletSettings';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';
import { assertWalletConsistent, grantCredits, walletTxns } from './walletAudit';

const PROJECT = 'demo-goldengift-referrals';
const ORDER_NOW = Date.UTC(2026, 9, 21, 5, 0);

describe('referral rewards (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `referrals-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  const now = Date.now();
  const triggerDeps = { db, messaging: fcm, logger: quiet, now: () => now };
  let n = 0;
  let events = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const notificationsOf = async (uid: string) =>
    (await db.collection('notifications').where('userId', '==', uid).get()).docs.map(
      (d): DocumentData & { id: string } => ({ id: d.id, ...d.data() }),
    );

  /** The app's sign-up doc, then the trigger's work. */
  async function signUp(label: string, over: DocumentData = {}) {
    const uid = `${label}-${++n}`;
    await db.doc(`users/${uid}`).set({
      name: 'Test User',
      email: null,
      phone: '7501234567',
      countryCode: '+964',
      locale: 'en',
      referralCodeEntered: null,
      deviceId: randomUUID(),
      photoUrl: null,
      notificationsEnabled: true,
      profileCompleted: false,
      fcmTokens: [`tok-${uid}`],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      ...over,
    });
    const result = await processNewUser(db, uid, { now: () => now });
    return { uid, result, code: (await read(`users/${uid}`))!.referralCode as string };
  }

  async function setReferralSettings(over: DocumentData = {}): Promise<void> {
    await db.doc('app_settings/referral').set({ joinBonus: 5000, orderBonus: 7000, maxReferralsPerMonth: 2, creditsExpiryDays: 90, ...over });
  }

  /** A COD order for `uid` (mug 15,000 + delivery 3,000). */
  async function order(uid: string, clientRequestId: string, over: Record<string, unknown> = {}): Promise<string> {
    await db.doc(`users/${uid}/addresses/home`).set({ label: 'Home', name: uid, phone: '7501234567', city: 'erbil', area: 'A', street: 'S' });
    await db.doc(`carts/${uid}/items/l1`).set({ productId: 'mug', storeId: 'home', unitPrice: 15000, qty: 1, selections: [], lineTotal: 15000, preparationDays: 0 });
    const placed = await placeOrderCore(
      { db, messaging: null, now: () => ORDER_NOW, logger: quiet },
      { clientRequestId, addressId: 'home', deliveryDate: '2026-10-21', deliverySlot: 'morning', paymentMethod: 'cashOnDelivery', ...over },
      uid,
    );
    return placed.orderId;
  }

  async function setStatus(orderId: string, status: string, eventId = `evt-${++events}`) {
    const before = await read(`orders/${orderId}`);
    const items = (before!.items as DocumentData[]).map((i) => ({ ...i, status }));
    await db.doc(`orders/${orderId}`).update({ status, items, statusUpdatedBy: 'admin-1', statusUpdatedByRole: 'admin', statusNote: null });
    const afterDoc = await read(`orders/${orderId}`);
    const event = { eventId, orderId, before, after: afterDoc };
    return { event, result: await handleOrderStatusChange(triggerDeps, event) };
  }
  async function deliver(orderId: string) {
    for (const s of ['confirmed', 'preparing', 'readyForDelivery', 'outForDelivery']) await setStatus(orderId, s);
    return setStatus(orderId, 'delivered');
  }

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    await setReferralSettings();
    const batch = db.batch();
    batch.set(db.doc('app_settings/cities'), { items: [{ id: 'erbil', deliveryFee: 3000, isActive: true }] });
    batch.set(db.doc('stores/home'), { status: 'active' });
    batch.set(db.doc('products/mug'), { title: 'Mug', storeId: 'home', price: 15000, isActive: true, stock: null });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  // ── joinBonus ────────────────────────────────────────────────────────────
  describe('join bonus (onUserCreate)', () => {
    test('the new user gets a credit lot, a referralCredit transaction and a welcome notice', async () => {
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { name: '  Sara  Ahmed ', referralCodeEntered: referrer.code });
      assert.equal(friend.result.referral, 'accepted');
      assert.deepEqual(friend.result.joinBonus, { status: 'paid', amount: 5000 });

      const referral = (await read(`referrals/${friend.uid}`))!;
      assert.deepEqual(
        [referral.status, referral.joinBonusPaid, referral.orderBonusPaid, referral.referredName, referral.flags],
        ['pending', true, false, 'Sara', []],
      );
      assert.deepEqual([(await read(`wallets/${friend.uid}`))?.credits, (await read(`wallets/${friend.uid}`))?.balance], [5000, 0]);
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);

      const lots = (await db.collection(`wallets/${friend.uid}/credit_lots`).get()).docs.map((d) => d.data());
      assert.equal(lots.length, 1);
      assert.deepEqual([lots[0].source, lots[0].amount, lots[0].remaining, lots[0].open, lots[0].referralId], ['referral', 5000, 5000, true, friend.uid]);
      assert.equal((lots[0].expiresAt as Timestamp).toMillis(), now + 90 * DAY_MS);

      const txns = await walletTxns(db, friend.uid);
      assert.deepEqual(txns.map((t) => [t.id, t.type, t.amount, t.bucket, t.referralId, t.title]), [
        [`joinBonus-${friend.uid}-1`, 'referralCredit', 5000, 'credits', friend.uid, 'Welcome bonus'],
      ]);
      const notes = await notificationsOf(friend.uid);
      assert.equal(notes.length, 1);
      assert.deepEqual([notes[0].id, notes[0].type, (notes[0].data as DocumentData).route], [`${friend.uid}-joinBonus`, 'referralCredited', '/wallet']);
      assert.ok(String(notes[0].title).includes('5,000 IQD'));
      assert.ok(String(notes[0].titleAr).length > 0 && String(notes[0].titleKu).length > 0);
      await assertWalletConsistent(db, friend.uid);
    });

    test('replays (also concurrent) pay it once', async () => {
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      const replays = await Promise.all([1, 2, 3].map(() => processNewUser(db, friend.uid, { now: () => now })));
      for (const r of replays) assert.deepEqual(r, { processed: false });
      assert.equal((await read(`wallets/${friend.uid}`))?.credits, 5000);
      assert.equal((await walletTxns(db, friend.uid)).length, 1);
      assert.equal((await notificationsOf(friend.uid)).length, 1);
    });

    test('a crash between sign-up and the bonus is completed by the retry', async () => {
      const referrer = await signUp('referrer');
      // As if the first step committed and the function died before the bonus.
      const uid = `crashed-${++n}`;
      await db.doc(`users/${uid}`).set({ name: 'Lana Omar', referralCode: 'LANA23', referredBy: referrer.uid, deviceId: 'd-lana' });
      await db.doc(`wallets/${uid}`).set({ balance: 0, credits: 0, currency: 'IQD' });
      await db.doc(`referrals/${uid}`).set({
        referrerUid: referrer.uid,
        referredUid: uid,
        code: referrer.code,
        status: 'pending',
        joinBonusPaid: false,
        orderBonusPaid: false,
        createdAt: FieldValue.serverTimestamp(),
      });
      await db.doc(`function_runs/onUserCreate:${uid}`).set({ key: `onUserCreate:${uid}` });
      const result = await processNewUser(db, uid, { now: () => now });
      assert.deepEqual(result, { processed: false, joinBonus: { status: 'paid', amount: 5000 } });
      assert.equal((await read(`wallets/${uid}`))?.credits, 5000);
    });

    test('beyond maxReferralsPerMonth: cancelled with monthlyCap, no bonus, the not-applied notice', async () => {
      const referrer = await signUp('referrer');
      const f1 = await signUp('f1', { referralCodeEntered: referrer.code });
      const f2 = await signUp('f2', { referralCodeEntered: referrer.code });
      const f3 = await signUp('f3', { referralCodeEntered: referrer.code });
      assert.deepEqual([f1.result.joinBonus, f2.result.joinBonus], [{ status: 'paid', amount: 5000 }, { status: 'paid', amount: 5000 }]);
      assert.deepEqual(f3.result.joinBonus, { status: 'monthlyCap' });
      const capped = (await read(`referrals/${f3.uid}`))!;
      assert.deepEqual([capped.status, capped.flags, capped.joinBonusPaid], ['cancelled', ['monthlyCap'], false]);
      assert.equal((await read(`wallets/${f3.uid}`))?.credits, 0);
      assert.equal((await read(`users/${f3.uid}`))?.referredBy, referrer.uid);
      const notes = await notificationsOf(f3.uid);
      assert.deepEqual(notes.map((x) => x.type), [REFERRAL_NOT_APPLIED]);
    });

    test('the cap counts this Iraq month and only non-cancelled referrals', async () => {
      const referrer = await signUp('referrer');
      await db.doc('referrals/old-1').set({ referrerUid: referrer.uid, referredUid: 'old-1', status: 'completed', createdAt: Timestamp.fromMillis(now - 40 * DAY_MS) });
      await db.doc('referrals/old-2').set({ referrerUid: referrer.uid, referredUid: 'old-2', status: 'pending', createdAt: Timestamp.fromMillis(now - 35 * DAY_MS) });
      await db.doc('referrals/gone').set({ referrerUid: referrer.uid, referredUid: 'gone', status: 'cancelled', createdAt: Timestamp.fromMillis(now - 1000) });
      // 35+ days ago is always an earlier Iraq month; 'gone' is this month but cancelled.
      const f1 = await signUp('f1', { referralCodeEntered: referrer.code });
      const f2 = await signUp('f2', { referralCodeEntered: referrer.code });
      assert.equal(f1.result.joinBonus?.status, 'paid');
      assert.equal(f2.result.joinBonus?.status, 'paid');
      await setReferralSettings({ maxReferralsPerMonth: 0 }); // 0 = no limit
      const f3 = await signUp('f3', { referralCodeEntered: referrer.code });
      assert.equal(f3.result.joinBonus?.status, 'paid');
    });

    test('simultaneous sign-ups at the cap: exactly the cap is rewarded', async () => {
      const referrer = await signUp('referrer');
      const uids = [1, 2, 3, 4, 5].map((i) => `rush-${i}-${++n}`);
      for (const uid of uids) {
        await db.doc(`users/${uid}`).set({ name: 'Rush', locale: 'en', deviceId: randomUUID(), referralCodeEntered: referrer.code, createdAt: FieldValue.serverTimestamp() });
      }
      const results = await Promise.all(uids.map((uid) => processNewUser(db, uid, { now: () => now })));
      assert.equal(results.filter((r) => r.joinBonus?.status === 'paid').length, 2);
      assert.equal(results.filter((r) => r.joinBonus?.status === 'monthlyCap').length, 3);
      const referrals = (await db.collection('referrals').where('referrerUid', '==', referrer.uid).get()).docs;
      assert.equal(referrals.filter((d) => d.get('status') === 'pending').length, 2);
      // The two rewarded are the two created first.
      const byTime = referrals.sort((a, b) => (a.get('createdAt') as Timestamp).toMillis() - (b.get('createdAt') as Timestamp).toMillis() || (a.id < b.id ? -1 : 1));
      assert.deepEqual(byTime.map((d) => d.get('status')), ['pending', 'pending', 'cancelled', 'cancelled', 'cancelled']);
    });

    test('joinBonus 0: no payment, the referral stays pending for the order bonus', async () => {
      await setReferralSettings({ joinBonus: 0 });
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      assert.deepEqual(friend.result.joinBonus, { status: 'noBonus' });
      const referral = (await read(`referrals/${friend.uid}`))!;
      assert.deepEqual([referral.status, referral.joinBonusPaid], ['pending', false]);
      assert.equal((await read(`wallets/${friend.uid}`))?.credits, 0);
    });
  });

  // ── orderBonus ───────────────────────────────────────────────────────────
  describe('order bonus (onOrderStatusChange)', () => {
    test("the friend's first delivered + paid order pays the referrer once, notified in their language", async () => {
      const referrer = await signUp('referrer', { locale: 'ar' });
      const friend = await signUp('friend', { name: 'Sara Ahmed', referralCodeEntered: referrer.code });
      const orderId = await order(friend.uid, 'first');
      fcm.reset();
      const { result } = await deliver(orderId);
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'paid', referralId: friend.uid, amount: 7000, notified: true });

      const referral = (await read(`referrals/${friend.uid}`))!;
      assert.deepEqual([referral.status, referral.orderBonusPaid, referral.firstOrderId], ['completed', true, orderId]);
      assert.ok(referral.completedAt instanceof Timestamp);
      assert.equal((await read(`orders/${orderId}`))?.referralCredited, true);
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 7000);
      const txns = await walletTxns(db, referrer.uid);
      assert.deepEqual(txns.map((t) => [t.id, t.type, t.amount, t.referralId, t.orderId]), [
        [`orderBonus-${friend.uid}-1`, 'referralCredit', 7000, friend.uid, orderId],
      ]);
      const lot = (await db.collection(`wallets/${referrer.uid}/credit_lots`).get()).docs[0].data();
      assert.deepEqual([lot.source, lot.amount, lot.referralId, lot.orderId], ['referral', 7000, friend.uid, orderId]);

      const note = (await read(`notifications/referral-${friend.uid}-orderBonus`))!;
      assert.deepEqual([note.userId, note.type, note.data], [referrer.uid, 'referralCredited', { route: '/invite', id: friend.uid }]);
      assert.ok(String(note.body).includes('Sara'));
      const push = fcm.calls.find((c) => c.tokens.includes(`tok-${referrer.uid}`))!;
      assert.equal(push.notification?.title, 'ربحت 7,000 IQD مكافآت');
      assert.equal(push.data?.route, '/invite');
      await assertWalletConsistent(db, referrer.uid);
    });

    test('replayed events and a second order never pay twice', async () => {
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      const first = await order(friend.uid, 'first');
      const { event } = await deliver(first);
      await Promise.all([handleOrderStatusChange(triggerDeps, event), handleOrderStatusChange(triggerDeps, event)]);
      await handleOrderStatusChange(triggerDeps, { ...event, eventId: 'another-delivery-of-the-same-change' });
      const second = await order(friend.uid, 'second');
      const { result } = await deliver(second);
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'notDue' });
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 7000);
      assert.equal((await walletTxns(db, referrer.uid)).length, 1);
      assert.equal((await read(`orders/${second}`))?.referralCredited, false);
      assert.equal((await notificationsOf(referrer.uid)).filter((x) => x.type === 'referralCredited').length, 1);
    });

    test('not due yet: an order paid only with credits; the next one paid with money completes it', async () => {
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      await grantCredits(db, friend.uid, 20000);
      const free = await order(friend.uid, 'free', { useCredits: true });
      assert.equal((await read(`orders/${free}`))?.total, 0);
      const { result } = await deliver(free);
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'notDue' });
      assert.equal((await read(`referrals/${friend.uid}`))?.status, 'pending');
      assert.equal(await read(`function_runs/orderBonus:${friend.uid}`), undefined);

      const paid = await order(friend.uid, 'paid');
      await setStatus(paid, 'outForDelivery'); // not delivered: nothing
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);
      await setStatus(paid, 'delivered');
      const referral = (await read(`referrals/${friend.uid}`))!;
      assert.deepEqual([referral.status, referral.firstOrderId], ['completed', paid]);
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 7000);
      await assertWalletConsistent(db, friend.uid);
    });

    test('abuse at payout: same device → cancelled with sameDevice, nothing paid, never again', async () => {
      const referrer = await signUp('referrer', { deviceId: 'device-r' });
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      await db.doc(`users/${friend.uid}`).update({ deviceId: 'device-r' }); // signed in on the referrer's phone since
      const { result } = await deliver(await order(friend.uid, 'first'));
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'cancelled', referralId: friend.uid, flag: 'sameDevice' });
      const referral = (await read(`referrals/${friend.uid}`))!;
      assert.deepEqual([referral.status, referral.flags, referral.orderBonusPaid], ['cancelled', ['sameDevice'], false]);
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);
      await db.doc(`users/${friend.uid}`).update({ deviceId: 'device-f' });
      await deliver(await order(friend.uid, 'second'));
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);
    });

    test('abuse at payout: a blocked referrer → cancelled with blocked', async () => {
      const referrer = await signUp('referrer');
      const friend = await signUp('friend', { referralCodeEntered: referrer.code });
      await db.doc(`users/${referrer.uid}`).update({ isBlocked: true });
      const { result } = await deliver(await order(friend.uid, 'first'));
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'cancelled', referralId: friend.uid, flag: 'blocked' });
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);
    });

    test('a capped referral never pays the order bonus', async () => {
      await setReferralSettings({ maxReferralsPerMonth: 1 });
      const referrer = await signUp('referrer');
      await signUp('f1', { referralCodeEntered: referrer.code });
      const f2 = await signUp('f2', { referralCodeEntered: referrer.code });
      const { result } = await deliver(await order(f2.uid, 'first'));
      assert.ok(result.handled);
      assert.deepEqual(result.orderBonus, { status: 'notDue' });
      assert.equal((await read(`wallets/${referrer.uid}`))?.credits, 0);
    });
  });
});

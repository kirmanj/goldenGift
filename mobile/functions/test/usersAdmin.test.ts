/**
 * adjustWallet and setUserBlocked against the Auth + Firestore emulators
 * (skipped without them). Auth runs in goldengift-iq with unique uids per run;
 * Firestore uses this suite's own demo- project, cleared before every test.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { adjustWalletCore } from '../src/admin/adjustWallet';
import type { AdminCaller } from '../src/admin/setAdminClaim';
import { BLOCK_ADMIN_MESSAGE, setUserBlockedCore } from '../src/admin/setUserBlocked';
import { placeOrderCore } from '../src/orders/placeOrder';
import { DAY_MS } from '../src/wallet/walletSettings';
import { PROJECT_ID, clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { assertWalletConsistent, grantCredits, walletTxns } from './walletAudit';

const FIRESTORE_PROJECT = 'demo-goldengift-users-admin';
const NOW = Date.UTC(2026, 9, 21, 5, 0);

async function rejectsWith(promise: Promise<unknown>, code: string, check?: (e: HttpsError) => void): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    check?.(e);
    return true;
  });
}

describe('users admin: adjustWallet / setUserBlocked (Auth + Firestore emulators)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') }, () => {
  const run = runId();
  const authApp = initializeApp({ projectId: PROJECT_ID }, `users-admin-auth-${run}`);
  const dbApp = initializeApp({ projectId: FIRESTORE_PROJECT }, `users-admin-db-${run}`);
  const auth = getAuth(authApp);
  const db = getFirestore(dbApp);
  const uids: string[] = [];
  let n = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const audit = async (target: string): Promise<DocumentData[]> =>
    (await db.collection('admin_audit_log').where('target', '==', target).get()).docs
      .map((d) => d.data())
      .sort((a, b) => (a.at as Timestamp).toMillis() - (b.at as Timestamp).toMillis());

  /** An Auth account + its users doc. */
  async function customer(label: string, over: DocumentData = {}): Promise<string> {
    const uid = `ua-${run}-${++n}-${label}`;
    uids.push(uid);
    await auth.createUser({ uid });
    await db.doc(`users/${uid}`).set({ name: label, locale: 'en', isBlocked: false, isDeleted: false, totalOrders: 0, ...over });
    return uid;
  }
  /** The caller as the callable sees an admin: claim in the token + admins doc. */
  async function admin(role: string): Promise<AdminCaller & { uid: string }> {
    const uid = `ua-${run}-${++n}-admin-${role}`;
    uids.push(uid);
    await auth.createUser({ uid, email: `${uid}@example.com` });
    await auth.setCustomUserClaims(uid, { admin: true });
    await db.doc(`admins/${uid}`).set({ name: `Admin ${role}`, role, permissions: [] });
    return { uid, claims: { admin: true } };
  }
  const adjust = (caller: AdminCaller, data: unknown) => adjustWalletCore({ db, now: () => NOW }, data, caller);
  const block = (caller: AdminCaller, data: unknown) => setUserBlockedCore({ db, auth }, data, caller);

  beforeEach(async () => {
    await clearEmulatorFirestore(FIRESTORE_PROJECT);
    await db.doc('app_settings/referral').set({ joinBonus: 5000, orderBonus: 5000, maxReferralsPerMonth: 10, creditsExpiryDays: 90 });
  });
  after(async () => {
    await clearEmulatorFirestore(FIRESTORE_PROJECT);
    await auth.deleteUsers(uids);
    await Promise.all([deleteApp(authApp), deleteApp(dbApp)]);
  });

  // ── adjustWallet ────────────────────────────────────────────────────────
  describe('adjustWallet', () => {
    test('finance adds balance: wallet created, adminAdjustment transaction, audit entry', async () => {
      const finance = await admin('finance');
      const uid = await customer('alice');
      const result = await adjust(finance, { uid, bucket: 'balance', amount: 25000, reason: ' Refund for late delivery ' });
      assert.deepEqual([result.balance, result.credits], [25000, 0]);
      const txn = (await read(`wallets/${uid}/transactions/${result.txnId}`))!;
      assert.deepEqual(
        [txn.type, txn.amount, txn.bucket, txn.byUid, txn.reason, txn.balanceAfter, txn.creditsAfter, txn.title],
        ['adminAdjustment', 25000, 'balance', finance.uid, 'Refund for late delivery', 25000, 0, 'Balance adjustment'],
      );
      const [entry] = await audit(`wallets/${uid}`);
      assert.deepEqual([entry.adminUid, entry.action], [finance.uid, 'wallet.adjust']);
      assert.deepEqual(entry.before, { balance: 0, credits: 0 });
      assert.deepEqual(entry.after, { balance: 25000, credits: 0, txnId: result.txnId, bucket: 'balance', amount: 25000, reason: 'Refund for late delivery' });
      assert.ok(entry.at instanceof Timestamp);
      await assertWalletConsistent(db, uid);
    });

    test('credits: + is a lot (source admin, expiring per settings); − is taken FIFO', async () => {
      const superAdmin = await admin('super');
      const uid = await customer('alice');
      await grantCredits(db, uid, 3000);
      const added = await adjust(superAdmin, { uid, bucket: 'credits', amount: 4000, reason: 'Goodwill' });
      assert.equal(added.credits, 7000);
      const lot = (await db.collection(`wallets/${uid}/credit_lots`).where('txnId', '==', added.txnId).get()).docs[0].data();
      assert.deepEqual([lot.source, lot.amount], ['admin', 4000]);
      assert.equal((lot.expiresAt as Timestamp).toMillis(), NOW + 90 * DAY_MS);
      const taken = await adjust(superAdmin, { uid, bucket: 'credits', amount: -5000, reason: 'Fraud reversal' });
      assert.equal(taken.credits, 2000);
      const open = (await db.collection(`wallets/${uid}/credit_lots`).where('open', '==', true).get()).docs.map((d) => d.data());
      assert.deepEqual(open.map((l) => [l.amount, l.remaining]), [[4000, 2000]]); // the older 3,000 went first
      await assertWalletConsistent(db, uid);
    });

    test('never below zero → failed-precondition insufficient_funds; nothing written', async () => {
      const finance = await admin('finance');
      const uid = await customer('alice');
      await adjust(finance, { uid, bucket: 'balance', amount: 1000, reason: 'Seed' });
      await rejectsWith(adjust(finance, { uid, bucket: 'balance', amount: -1001, reason: 'Too much' }), 'failed-precondition', (e) =>
        assert.deepEqual(e.details, { reason: 'insufficient_funds' }),
      );
      await rejectsWith(adjust(finance, { uid, bucket: 'credits', amount: -1, reason: 'No credits' }), 'failed-precondition');
      assert.equal((await read(`wallets/${uid}`))?.balance, 1000);
      assert.equal((await walletTxns(db, uid)).length, 1);
      assert.equal((await audit(`wallets/${uid}`)).length, 1);
    });

    test('who may call: super and finance only; unknown user → not-found with a message', async () => {
      const uid = await customer('alice');
      const ops = await admin('ops');
      const content = await admin('content');
      const data = { uid, bucket: 'balance', amount: 100, reason: 'Test' };
      await rejectsWith(adjust({}, data), 'unauthenticated');
      await rejectsWith(adjust({ uid, claims: {} }, data), 'permission-denied');
      await rejectsWith(adjust(ops, data), 'permission-denied');
      await rejectsWith(adjust(content, data), 'permission-denied');
      await rejectsWith(adjust({ uid: ops.uid, claims: {} }, data), 'permission-denied');
      const finance = await admin('finance');
      await rejectsWith(adjust(finance, { ...data, uid: 'nobody' }), 'not-found', (e) => assert.equal(e.message, 'No user with that uid.'));
      await rejectsWith(adjust(finance, { ...data, amount: 0 }), 'invalid-argument');
      assert.equal(await read(`wallets/${uid}`), undefined);
    });

    test('a retried call with the same requestId adjusts once', async () => {
      const finance = await admin('finance');
      const uid = await customer('alice');
      const data = { uid, bucket: 'balance', amount: 500, reason: 'Retry test', requestId: `req-${run}` };
      const [a, b] = await Promise.all([adjust(finance, data), adjust(finance, data)]);
      assert.deepEqual(a, b);
      assert.deepEqual(await adjust(finance, data), a);
      assert.equal((await read(`wallets/${uid}`))?.balance, 500);
      assert.equal((await walletTxns(db, uid)).length, 1);
    });
  });

  // ── setUserBlocked ──────────────────────────────────────────────────────
  describe('setUserBlocked', () => {
    test('ops blocks: isBlocked, Auth disabled, sessions revoked, audited; unblock reverses', async () => {
      const ops = await admin('ops');
      const uid = await customer('alice');
      const before = await auth.getUser(uid);
      assert.deepEqual(await block(ops, { uid, blocked: true, reason: ' Chargeback fraud ' }), { uid, blocked: true });
      assert.equal((await read(`users/${uid}`))?.isBlocked, true);
      const blocked = await auth.getUser(uid);
      assert.equal(blocked.disabled, true);
      assert.ok(Date.parse(blocked.tokensValidAfterTime!) >= Date.parse(before.tokensValidAfterTime ?? '1970-01-01'));

      // Blocked accounts cannot order.
      await db.doc(`users/${uid}/addresses/home`).set({ city: 'erbil' });
      await db.doc(`carts/${uid}/items/l1`).set({ productId: 'mug', qty: 1, unitPrice: 1, selections: [] });
      await rejectsWith(
        placeOrderCore(
          { db, messaging: null, now: () => NOW },
          { clientRequestId: 'r1', addressId: 'home', deliveryDate: '2026-10-21', deliverySlot: 'morning' },
          uid,
        ),
        'permission-denied',
      );

      // Repeating is a no-op (no second audit entry).
      await block(ops, { uid, blocked: true });
      assert.deepEqual(await block(ops, { uid, blocked: false }), { uid, blocked: false });
      assert.equal((await read(`users/${uid}`))?.isBlocked, false);
      assert.equal((await auth.getUser(uid)).disabled, false);
      const entries = await audit(`users/${uid}`);
      assert.deepEqual(entries.map((e) => e.action), ['user.block', 'user.unblock']);
      assert.deepEqual(entries[0].before, { isBlocked: false, authDisabled: false });
      assert.deepEqual(entries[0].after, { isBlocked: true, authDisabled: true, reason: 'Chargeback fraud' });
      assert.equal(entries[0].adminUid, ops.uid);
    });

    test('a half-done block (Firestore only) is finished by the repeat call', async () => {
      const superAdmin = await admin('super');
      const uid = await customer('alice', { isBlocked: true }); // Auth still enabled
      await block(superAdmin, { uid, blocked: true });
      assert.equal((await auth.getUser(uid)).disabled, true);
      assert.equal((await audit(`users/${uid}`)).length, 0);
    });

    test('no Auth account (deleted there): Firestore is still updated', async () => {
      const ops = await admin('ops');
      const uid = `ua-${run}-${++n}-firestore-only`;
      await db.doc(`users/${uid}`).set({ name: 'Ghost', isBlocked: false });
      assert.deepEqual(await block(ops, { uid, blocked: true }), { uid, blocked: true });
      assert.equal((await read(`users/${uid}`))?.isBlocked, true);
    });

    test('who may call, and what cannot be blocked', async () => {
      const uid = await customer('alice');
      const finance = await admin('finance');
      const ops = await admin('ops');
      await rejectsWith(block({}, { uid, blocked: true }), 'unauthenticated');
      await rejectsWith(block(finance, { uid, blocked: true }), 'permission-denied');
      await rejectsWith(block({ uid, claims: {} }, { uid, blocked: true }), 'permission-denied');
      await rejectsWith(block(ops, { uid: 'nobody', blocked: true }), 'not-found', (e) => assert.equal(e.message, 'No user with that uid.'));
      await rejectsWith(block(ops, { uid: ops.uid, blocked: true }), 'failed-precondition');
      const other = await admin('content');
      await db.doc(`users/${other.uid}`).set({ name: 'Content admin', isBlocked: false });
      await rejectsWith(block(ops, { uid: other.uid, blocked: true }), 'failed-precondition', (e) => assert.equal(e.message, BLOCK_ADMIN_MESSAGE));
      await rejectsWith(block(ops, { uid, blocked: 'yes' }), 'invalid-argument');
      assert.equal((await read(`users/${uid}`))?.isBlocked, false);
      assert.equal((await auth.getUser(uid)).disabled, false);
    });
  });
});

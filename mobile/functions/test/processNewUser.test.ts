import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { FieldValue, Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { generateReferralCode, isReferralCode } from '../src/users/referralCode';
import { REFERRAL_NOT_APPLIED, REFERRAL_NOT_APPLIED_TEXT } from '../src/users/referralNotice';
import { MAX_CODE_ATTEMPTS, processNewUser, type ReferralOutcome } from '../src/users/processNewUser';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';

/**
 * Own demo- project: no seeded app_settings/referral here, so no join bonus is
 * paid (referrals.test.ts covers the bonuses and the monthly cap).
 */
const PROJECT = 'demo-goldengift-new-user';

describe('processNewUser (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `process-new-user-test-${runId()}`);
  const db = getFirestore(app);
  const run = runId();
  let n = 0;

  const newUid = (label: string) => {
    const uid = `pnu-${run}-${label}-${n++}`;
    return uid;
  };
  const userDoc = (uid: string) => db.collection('users').doc(uid);
  const read = async (path: string) => (await db.doc(path).get()).data();
  const notificationsOf = async (uid: string) =>
    (await db.collection('notifications').where('userId', '==', uid).get()).docs.map((d) => d.data());

  /** Exactly the keys the app writes at sign-up (SRS AUTH-3). */
  const appCreateDoc = (over: DocumentData = {}): DocumentData => ({
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
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    ...over,
  });

  /** Signs a user up the way the app + trigger would; returns uid and code. */
  async function signUp(label: string, over: DocumentData = {}) {
    const uid = newUid(label);
    await userDoc(uid).set(appCreateDoc(over));
    const result = await processNewUser(db, uid);
    return { uid, result, code: result.referralCode! };
  }

  /** A well-formed code no user has. */
  async function unusedCode(): Promise<string> {
    for (;;) {
      const code = generateReferralCode();
      const taken = await db.collection('users').where('referralCode', '==', code).limit(1).get();
      if (taken.empty) return code;
    }
  }

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('new user: unique referral code, wallet and server defaults', async () => {
    const { uid, result, code } = await signUp('plain');
    assert.deepEqual(result, { processed: true, referralCode: code, referral: 'none' });
    assert.ok(isReferralCode(code), code);

    const user = (await read(`users/${uid}`))!;
    assert.equal(user.referralCode, code);
    assert.equal(user.role, 'customer');
    assert.deepEqual(user.storeIds, []);
    assert.equal(user.totalOrders, 0);
    assert.equal(user.totalSpent, 0);
    assert.equal(user.isBlocked, false);
    assert.equal(user.isDeleted, false);
    assert.equal(user.referredBy, null);
    assert.ok(user.updatedAt instanceof Timestamp);
    // The app's fields are untouched.
    assert.equal(user.name, 'Test User');
    assert.equal(user.phone, '7501234567');
    assert.ok(user.createdAt instanceof Timestamp);

    const holders = await db.collection('users').where('referralCode', '==', code).get();
    assert.equal(holders.size, 1);

    const wallet = (await read(`wallets/${uid}`))!;
    assert.equal(wallet.balance, 0);
    assert.equal(wallet.credits, 0);
    assert.equal(wallet.currency, 'IQD');
    assert.ok(wallet.createdAt instanceof Timestamp);
    assert.ok(wallet.updatedAt instanceof Timestamp);

    assert.equal(await read(`referrals/${uid}`), undefined);
    assert.deepEqual(await notificationsOf(uid), []);
    assert.ok(await read(`function_runs/onUserCreate:${uid}`));
  });

  test('valid referral code → referredBy + pending referral, no notification', async () => {
    const referrer = await signUp('referrer');
    const { uid, result } = await signUp('referred', { referralCodeEntered: referrer.code });
    assert.equal(result.referral, 'accepted');

    const user = (await read(`users/${uid}`))!;
    assert.equal(user.referredBy, referrer.uid);
    assert.notEqual(user.referralCode, referrer.code);

    const referral = (await read(`referrals/${uid}`))!;
    assert.equal(referral.referrerUid, referrer.uid);
    assert.equal(referral.referredUid, uid);
    assert.equal(referral.code, referrer.code);
    assert.equal(referral.status, 'pending');
    assert.equal(referral.joinBonusPaid, false);
    assert.equal(referral.orderBonusPaid, false);
    assert.equal(referral.referredName, 'Test');
    assert.deepEqual(referral.flags, []);
    assert.ok(referral.createdAt instanceof Timestamp);
    assert.deepEqual(result.joinBonus, { status: 'noBonus' });

    assert.deepEqual(await notificationsOf(uid), []);
    // No app_settings/referral in this project → joinBonus 0: nothing paid.
    assert.equal((await read(`wallets/${uid}`))!.credits, 0);
    assert.equal((await read(`wallets/${referrer.uid}`))!.credits, 0);
  });

  test('entered code is matched case- and space-insensitively', async () => {
    const referrer = await signUp('referrer-lc');
    const { result } = await signUp('referred-lc', { referralCodeEntered: ` ${referrer.code.toLowerCase()} ` });
    assert.equal(result.referral, 'accepted');
  });

  const rejected: Array<[string, ReferralOutcome, () => Promise<DocumentData>]> = [
    ['unknown code', 'notFound', async () => ({ referralCodeEntered: await unusedCode() })],
    ['malformed code', 'notFound', async () => ({ referralCodeEntered: 'ABC' })],
    [
      'code from the same device',
      'sameDevice',
      async () => {
        const deviceId = randomUUID();
        const referrer = await signUp('same-device-referrer', { deviceId });
        return { referralCodeEntered: referrer.code, deviceId };
      },
    ],
    [
      'blocked referrer',
      'referrerInactive',
      async () => {
        const referrer = await signUp('blocked-referrer');
        await userDoc(referrer.uid).update({ isBlocked: true });
        return { referralCodeEntered: referrer.code };
      },
    ],
    [
      'deleted referrer',
      'referrerInactive',
      async () => {
        const referrer = await signUp('deleted-referrer');
        await userDoc(referrer.uid).update({ isDeleted: true });
        return { referralCodeEntered: referrer.code };
      },
    ],
  ];

  for (const [label, outcome, setup] of rejected) {
    test(`${label} → rejected with a notification, no referral`, async () => {
      const { uid, result } = await signUp('rejected', await setup());
      assert.equal(result.referral, outcome);

      const user = (await read(`users/${uid}`))!;
      assert.equal(user.referredBy, null);
      assert.ok(isReferralCode(user.referralCode));
      assert.ok(await read(`wallets/${uid}`), 'sign-up still succeeds');
      assert.equal(await read(`referrals/${uid}`), undefined);

      const notes = await notificationsOf(uid);
      assert.equal(notes.length, 1);
      const note = notes[0];
      assert.equal(note.type, REFERRAL_NOT_APPLIED);
      assert.equal(note.isRead, false);
      assert.deepEqual(note.data, { route: null, id: null });
      for (const [key, text] of Object.entries(REFERRAL_NOT_APPLIED_TEXT)) assert.equal(note[key], text, key);
      assert.ok(note.createdAt instanceof Timestamp);
    });
  }

  test('own code (doc already carries it) → ownCode', async () => {
    const uid = newUid('own');
    const code = await unusedCode();
    await userDoc(uid).set(appCreateDoc({ referralCode: code, referralCodeEntered: code }));
    const result = await processNewUser(db, uid);
    assert.deepEqual(result, { processed: true, referralCode: code, referral: 'ownCode' });
    assert.equal((await notificationsOf(uid)).length, 1);
    assert.equal(await read(`referrals/${uid}`), undefined);
  });

  test('existing wallet and server-owned fields are never overwritten', async () => {
    const uid = newUid('existing');
    await db.doc(`wallets/${uid}`).set({ balance: 2500, credits: 1000, currency: 'IQD' });
    await userDoc(uid).set(appCreateDoc({ role: 'seller', storeIds: ['store-1'], totalOrders: 4 }));
    await processNewUser(db, uid);

    const wallet = (await read(`wallets/${uid}`))!;
    assert.equal(wallet.balance, 2500);
    assert.equal(wallet.credits, 1000);
    const user = (await read(`users/${uid}`))!;
    assert.equal(user.role, 'seller');
    assert.deepEqual(user.storeIds, ['store-1']);
    assert.equal(user.totalOrders, 4);
    assert.equal(user.totalSpent, 0);
  });

  test('running twice changes nothing (idempotent)', async () => {
    const { uid } = await signUp('twice', { referralCodeEntered: await unusedCode() });
    const before = {
      user: await read(`users/${uid}`),
      wallet: await read(`wallets/${uid}`),
      notes: await notificationsOf(uid),
    };
    assert.deepEqual(await processNewUser(db, uid), { processed: false });
    assert.deepEqual(await read(`users/${uid}`), before.user);
    assert.deepEqual(await read(`wallets/${uid}`), before.wallet);
    assert.deepEqual(await notificationsOf(uid), before.notes);
  });

  test('concurrent replays apply once', async () => {
    const referrer = await signUp('concurrent-referrer');
    const uid = newUid('concurrent');
    await userDoc(uid).set(appCreateDoc({ referralCodeEntered: referrer.code }));
    const results = await Promise.all([1, 2, 3].map(() => processNewUser(db, uid)));
    assert.equal(results.filter((r) => r.processed).length, 1);
    const user = (await read(`users/${uid}`))!;
    assert.equal(results.find((r) => r.processed)!.referralCode, user.referralCode);
    assert.equal(user.referredBy, referrer.uid);
  });

  test('a code that is already taken is replaced by a fresh one', async () => {
    const taken = await signUp('taken');
    const fresh = await unusedCode();
    const codes = [taken.code, taken.code, fresh];
    const uid = newUid('collision');
    await userDoc(uid).set(appCreateDoc());
    const result = await processNewUser(db, uid, { generateCode: () => codes.shift()! });
    assert.equal(result.referralCode, fresh);
    assert.equal(codes.length, 0);
  });

  test('no free code → fails without writing anything; a later run succeeds', async () => {
    const taken = await signUp('taken-always');
    const uid = newUid('exhausted');
    await userDoc(uid).set(appCreateDoc({ referralCodeEntered: await unusedCode() }));
    let calls = 0;
    await assert.rejects(
      processNewUser(db, uid, { generateCode: () => (calls++, taken.code) }),
      /no free referral code/,
    );
    assert.ok(calls >= MAX_CODE_ATTEMPTS);
    assert.equal(await read(`wallets/${uid}`), undefined);
    assert.equal(await read(`function_runs/onUserCreate:${uid}`), undefined);
    assert.equal((await read(`users/${uid}`))!.referralCode, undefined);
    assert.deepEqual(await notificationsOf(uid), []);

    const retry = await processNewUser(db, uid);
    assert.equal(retry.processed, true);
    assert.ok(await read(`wallets/${uid}`));
  });

  test('missing or already deleted user doc → nothing is created', async () => {
    const missing = newUid('missing');
    assert.deepEqual(await processNewUser(db, missing), { processed: false });
    assert.equal(await read(`wallets/${missing}`), undefined);

    const deleted = newUid('deleted');
    await userDoc(deleted).set(appCreateDoc({ isDeleted: true }));
    assert.deepEqual(await processNewUser(db, deleted), { processed: false });
    assert.equal(await read(`wallets/${deleted}`), undefined);
  });
});

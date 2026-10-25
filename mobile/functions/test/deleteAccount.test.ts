import assert from 'node:assert/strict';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { deleteUserAccount, type DeleteAccountDeps } from '../src/users/deleteAccount';
import { PROJECT_ID, needsEnv, runId } from './emulators';

const BUCKET = `${PROJECT_ID}.appspot.com`;
const storageSkip = needsEnv('FIREBASE_STORAGE_EMULATOR_HOST');

describe(
  'deleteUserAccount (Firestore + Auth emulators)',
  { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') },
  () => {
    const app = initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET }, 'delete-account-test');
    // Like goldengift-iq today: no Storage bucket configured.
    const appWithoutBucket = initializeApp({ projectId: PROJECT_ID }, 'delete-account-test-no-bucket');
    const db = getFirestore(app);
    const auth = getAuth(app);
    const run = runId();
    const cleanup: string[] = [];

    const deps = (withStorage = !storageSkip): DeleteAccountDeps => ({
      db,
      auth,
      bucket: withStorage ? () => getStorage(app).bucket() : () => getStorage(appWithoutBucket).bucket(),
    });
    const read = async (path: string) => (await db.doc(path).get()).data();
    const count = async (path: string) => (await db.collection(path).count().get()).data().count;

    /** A signed-up user with everything deleteAccount touches or must keep. */
    async function seedUser(label: string): Promise<string> {
      const uid = `del-${run}-${label}`;
      cleanup.push(`users/${uid}`, `wallets/${uid}`, `referrals/${uid}`, `orders/order-${uid}`);
      await auth.createUser({ uid, email: `${uid}@example.com`, displayName: 'Ava Test' });
      const now = FieldValue.serverTimestamp();
      await db.doc(`users/${uid}`).set({
        name: 'Ava Test',
        email: `${uid}@example.com`,
        phone: '7501234567',
        countryCode: '+964',
        locale: 'ar',
        referralCodeEntered: 'K7QX2M',
        deviceId: 'device-1',
        photoUrl: `https://example.com/${uid}.jpg`,
        birthday: Timestamp.fromDate(new Date('1995-04-01')),
        gender: 'female',
        city: 'erbil',
        notificationsEnabled: true,
        profileCompleted: true,
        fcmTokens: ['token-1'],
        role: 'customer',
        storeIds: [],
        referralCode: 'ZZ23AB',
        referredBy: 'someone',
        totalOrders: 3,
        totalSpent: 75000,
        isBlocked: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
      });
      const writes = db.batch();
      for (const id of ['home', 'work', 'mum']) writes.set(db.doc(`users/${uid}/addresses/${id}`), { label: id });
      writes.set(db.doc(`users/${uid}/saved_cards/card-1`), { last4: '4242' });
      for (const id of ['i1', 'i2']) writes.set(db.doc(`carts/${uid}/items/${id}`), { qty: 1 });
      for (const id of ['p1', 'p2']) writes.set(db.doc(`wishlists/${uid}/items/${id}`), { listId: 'default' });
      writes.set(db.doc(`wallets/${uid}`), { balance: 1000, credits: 500, currency: 'IQD' });
      writes.set(db.doc(`orders/order-${uid}`), { userId: uid, total: 25000 });
      writes.set(db.doc(`referrals/${uid}`), { referrerUid: 'someone', referredUid: uid, status: 'pending' });
      await writes.commit();
      return uid;
    }

    after(async () => {
      await Promise.all(cleanup.map((p) => db.doc(p).delete()));
      await Promise.all([deleteApp(app), deleteApp(appWithoutBucket)]);
    });

    test('anonymizes the profile, deletes personal data and the Auth user, keeps accounting', async () => {
      const uid = await seedUser('main');
      const result = await deleteUserAccount(deps(), uid);
      assert.deepEqual(result, {
        anonymized: true,
        deletedDocs: 8,
        deletedFiles: storageSkip ? null : 0,
        deletedAuthUser: true,
      });

      const user = (await read(`users/${uid}`))!;
      assert.equal(user.name, 'Deleted user');
      for (const key of ['email', 'phone', 'photoUrl', 'birthday', 'gender', 'city', 'referralCodeEntered']) {
        assert.equal(user[key], null, key);
      }
      assert.deepEqual(user.fcmTokens, []);
      assert.equal(user.notificationsEnabled, false);
      assert.equal(user.isDeleted, true);
      assert.ok(user.deletedAt instanceof Timestamp);
      assert.ok(user.updatedAt instanceof Timestamp);
      // Kept: order totals, referral bookkeeping, role.
      assert.equal(user.totalOrders, 3);
      assert.equal(user.referralCode, 'ZZ23AB');
      assert.equal(user.referredBy, 'someone');

      for (const sub of [`users/${uid}/addresses`, `users/${uid}/saved_cards`, `carts/${uid}/items`, `wishlists/${uid}/items`]) {
        assert.equal(await count(sub), 0, sub);
      }
      assert.equal((await read(`wallets/${uid}`))!.balance, 1000);
      assert.ok(await read(`orders/order-${uid}`));
      assert.ok(await read(`referrals/${uid}`));

      await assert.rejects(auth.getUser(uid), { code: 'auth/user-not-found' });
    });

    test('a second call succeeds and keeps the first deletedAt', async () => {
      const uid = await seedUser('twice');
      await deleteUserAccount(deps(), uid);
      const first = (await read(`users/${uid}`))!;

      const again = await deleteUserAccount(deps(), uid);
      assert.equal(again.deletedAuthUser, false, 'auth/user-not-found counts as done');
      assert.equal(again.deletedDocs, 0);
      const second = (await read(`users/${uid}`))!;
      assert.ok((second.deletedAt as Timestamp).isEqual(first.deletedAt as Timestamp));
      assert.equal(second.isDeleted, true);
    });

    test('no Storage bucket configured → still succeeds', async () => {
      const uid = await seedUser('no-bucket');
      const result = await deleteUserAccount(deps(false), uid);
      assert.equal(result.deletedFiles, null);
      assert.equal(result.deletedAuthUser, true);
    });

    test('an Auth user without a users doc → succeeds and creates no doc', async () => {
      const uid = `del-${run}-no-doc`;
      await auth.createUser({ uid });
      const result = await deleteUserAccount(deps(), uid);
      assert.equal(result.anonymized, false);
      assert.equal(result.deletedAuthUser, true);
      assert.equal(await read(`users/${uid}`), undefined, 'would fire onUserCreate');
    });

    test('deletes Storage files under users/{uid}/ only', { skip: storageSkip }, async () => {
      const uid = await seedUser('storage');
      const bucket = getStorage(app).bucket();
      const own = [`users/${uid}/avatar.jpg`, `users/${uid}/old/avatar.jpg`];
      const others = [`users/${uid}x/avatar.jpg`, `products/${uid}/1.jpg`];
      for (const path of [...own, ...others]) {
        await bucket.file(path).save(Buffer.from('jpeg'), { contentType: 'image/jpeg', resumable: false });
      }

      const result = await deleteUserAccount(deps(true), uid);
      assert.equal(result.deletedFiles, 2);
      for (const path of own) assert.equal((await bucket.file(path).exists())[0], false, path);
      for (const path of others) {
        assert.equal((await bucket.file(path).exists())[0], true, path);
        await bucket.file(path).delete();
      }
    });
  },
);

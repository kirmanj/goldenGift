/**
 * Partners against the Auth + Firestore emulators (skipped without them):
 * submitPartnerApplication → reviewPartner (approve / reject) → setStoreStatus.
 * Auth runs in goldengift-iq with unique uids per run (deleted after); Firestore
 * uses this suite's own demo- project, cleared before every test.
 * SRS Phase 8 exit: "an approved partner signs into the dashboard" — the seller
 * claim (never `admin`) + `admins/{uid}` role seller are what the dashboard's
 * resolveAdminClaims needs.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { reviewPartnerCore, setStoreStatusCore } from '../src/partners/reviewPartner';
import { submitPartnerApplicationCore } from '../src/partners/submitPartnerApplication';
import { PROJECT_ID, clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';

const FIRESTORE_PROJECT = 'demo-goldengift-partners';

async function rejectsWith(promise: Promise<unknown>, code: string): Promise<HttpsError> {
  let error: HttpsError | undefined;
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, `expected HttpsError, got ${String(e)}`);
    assert.equal(e.code, code, e.message);
    error = e;
    return true;
  });
  return error!;
}

describe('partners (Auth + Firestore emulators)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') }, () => {
  const run = runId();
  const authApp = initializeApp({ projectId: PROJECT_ID }, `partners-auth-${run}`);
  const dbApp = initializeApp({ projectId: FIRESTORE_PROJECT }, `partners-db-${run}`);
  const auth = getAuth(authApp);
  const db = getFirestore(dbApp);
  const fcm = new FakeMessaging();
  const quiet = { warn: () => undefined, info: () => undefined };
  const deps = { db, auth, messaging: fcm, logger: quiet };
  const uids: string[] = [];
  let n = 0;

  const read = async (path: string) => (await db.doc(path).get()).data();
  const notificationsOf = async (uid: string) =>
    (await db.collection('notifications').where('userId', '==', uid).get()).docs.map((d) => d.data());
  const auditOf = async (storeId: string) =>
    (await db.collection('admin_audit_log').where('target', '==', `stores/${storeId}`).get()).docs.map((d) => d.data());

  /** A customer account with a profile (and optional extra claims). */
  async function customer(label: string, claims?: Record<string, unknown>): Promise<string> {
    const uid = `ptn-${run}-${++n}-${label}`;
    uids.push(uid);
    await auth.createUser({ uid, displayName: `Owner ${label}` });
    if (claims) await auth.setCustomUserClaims(uid, claims);
    await db.doc(`users/${uid}`).set({ name: `Owner ${label}`, locale: 'en', fcmTokens: [`tok-${uid}`], notificationsEnabled: true, role: 'customer', storeIds: [] });
    return uid;
  }
  const admin = (uid: string) => ({ uid, claims: { admin: true } });
  const application = (over: Record<string, unknown> = {}) => ({
    storeName: 'Rose Corner',
    ownerName: 'Sara Ahmed',
    phone: '+9647501234567',
    city: 'erbil',
    category: 'Flowers',
    instagram: 'rose.corner',
    samplePhotos: [],
    ...over,
  });
  /** A download URL of the caller's own upload (partner_applications/{uid}/n.jpg). */
  const ownPhoto = (uid: string, n: number) =>
    `https://firebasestorage.googleapis.com/v0/b/goldengift-iq.appspot.com/o/partner_applications%2F${uid}%2F${n}.jpg?alt=media&token=t${n}`;

  beforeEach(async () => {
    await clearEmulatorFirestore(FIRESTORE_PROJECT);
    fcm.reset();
    const batch = db.batch();
    batch.set(db.doc('app_settings/cities'), { items: [{ id: 'erbil', deliveryFee: 3000, isActive: true }, { id: 'mosul', isActive: false }] });
    for (const [uid, role] of [['ops-1', 'ops'], ['super-1', 'super'], ['content-1', 'content'], ['finance-1', 'finance']]) {
      batch.set(db.doc(`admins/${uid}`), { name: uid, role, permissions: [] });
    }
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(FIRESTORE_PROJECT);
    await auth.deleteUsers(uids);
    await Promise.all([deleteApp(authApp), deleteApp(dbApp)]);
  });

  describe('submitPartnerApplication', () => {
    test('creates the pending store and its private application', async () => {
      const uid = await customer('sara');
      const photos = [ownPhoto(uid, 1), ownPhoto(uid, 2)];
      const { storeId } = await submitPartnerApplicationCore(db, application({ instagram: '@rose.corner', samplePhotos: photos }), uid);
      const store = (await read(`stores/${storeId}`))!;
      assert.deepEqual(
        { ...store, createdAt: undefined, updatedAt: undefined },
        {
          name: 'Rose Corner',
          nameAr: 'Rose Corner',
          nameKu: 'Rose Corner',
          description: '',
          logoUrl: null,
          coverUrl: null,
          ownerUid: uid,
          phone: '+9647501234567',
          city: 'erbil',
          status: 'pendingApproval',
          ratingAvg: 0,
          ratingCount: 0,
          productCount: 0,
          ordersCount: 0,
          commissionPercent: 0,
          createdAt: undefined,
          updatedAt: undefined,
        },
      );
      assert.ok(store.createdAt);
      const app = (await read(`stores/${storeId}/private/application`))!;
      assert.equal(app.ownerUid, uid);
      assert.equal(app.ownerName, 'Sara Ahmed');
      assert.equal(app.instagram, 'rose.corner');
      assert.equal(app.category, 'Flowers');
      assert.deepEqual(app.samplePhotos, photos);
      assert.ok(app.submittedAt);
    });

    test("sample photos must be the applicant's own uploads", async () => {
      const uid = await customer('photos');
      for (const samplePhotos of [
        ['https://img/1.jpg'],
        [ownPhoto('someone-else', 1)],
        [ownPhoto(uid, 1).replace('partner_applications', 'gift_cards')],
        [ownPhoto(uid, 1).replace(`${uid}%2F1`, `${uid}%2F..%2Fx%2F1`)],
      ]) {
        await rejectsWith(submitPartnerApplicationCore(db, application({ samplePhotos }), uid), 'invalid-argument');
      }
      assert.ok((await submitPartnerApplicationCore(db, application({ samplePhotos: [ownPhoto(uid, 1)] }), uid)).storeId);
    });

    test('at most 5 applications per account per day', async () => {
      const uid = await customer('spam');
      await submitPartnerApplicationCore(db, application(), uid);
      for (let i = 0; i < 4; i++) await rejectsWith(submitPartnerApplicationCore(db, application(), uid), 'already-exists');
      assert.equal(((await rejectsWith(submitPartnerApplicationCore(db, application(), uid), 'resource-exhausted')).details as { reason?: string } | undefined)?.reason, 'rate_limited');
    });

    test('one store per owner; the city must be served', async () => {
      const uid = await customer('twice');
      await submitPartnerApplicationCore(db, application(), uid);
      const again = await rejectsWith(submitPartnerApplicationCore(db, application({ storeName: 'Other' }), uid), 'already-exists');
      assert.match(again.message, /already/);
      await rejectsWith(submitPartnerApplicationCore(db, application({ city: 'mosul' }), await customer('mosul')), 'invalid-argument');
      await rejectsWith(submitPartnerApplicationCore(db, application(), undefined), 'unauthenticated');
    });

    test('concurrent submissions create one store', async () => {
      const uid = await customer('race');
      const results = await Promise.allSettled([1, 2, 3].map((i) => submitPartnerApplicationCore(db, application({ storeName: `Race ${i}` }), uid)));
      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
      assert.equal((await db.collection('stores').where('ownerUid', '==', uid).get()).size, 1);
    });
  });

  describe('reviewPartner', () => {
    test('approve: active + commission, seller claim (no admin), admins doc, users role, audit, notification', async () => {
      const owner = await customer('approve', { referral: 'kept' });
      const { storeId } = await submitPartnerApplicationCore(db, application(), owner);
      assert.deepEqual(await reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 12.5 }, admin('ops-1')), {
        storeId,
        status: 'active',
      });

      const store = (await read(`stores/${storeId}`))!;
      assert.equal(store.status, 'active');
      assert.equal(store.commissionPercent, 12.5);
      assert.equal(store.approvedBy, 'ops-1');

      const claims = (await auth.getUser(owner)).customClaims ?? {};
      assert.equal(claims.seller, storeId);
      assert.equal(claims.admin, undefined, 'sellers never get the admin claim');
      assert.equal(claims.referral, 'kept');

      const adminDoc = (await read(`admins/${owner}`))!;
      assert.equal(adminDoc.role, 'seller');
      assert.equal(adminDoc.storeId, storeId);
      assert.equal(adminDoc.name, 'Sara Ahmed');
      assert.deepEqual(adminDoc.permissions, []);
      assert.ok(adminDoc.createdAt);

      const user = (await read(`users/${owner}`))!;
      assert.equal(user.role, 'seller');
      assert.deepEqual(user.storeIds, [storeId]);

      const audit = await auditOf(storeId);
      assert.equal(audit.length, 1);
      assert.equal(audit[0].action, 'store.approve');
      assert.equal(audit[0].adminUid, 'ops-1');
      assert.deepEqual(audit[0].after, { status: 'active', commissionPercent: 12.5, ownerUid: owner });

      const [note] = await notificationsOf(owner);
      assert.equal(note.type, 'partnerStatus');
      assert.equal(note.data.route, '/become-partner');

      // A repeat (e.g. after a failed claim write) repairs without a second audit / notification.
      await reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 20 }, admin('super-1'));
      assert.equal((await read(`stores/${storeId}`))?.commissionPercent, 12.5);
      assert.equal((await auditOf(storeId)).length, 1);
      assert.equal((await notificationsOf(owner)).length, 1);
    });

    test('reject: archived application, store deleted, owner told the reason, may apply again', async () => {
      const owner = await customer('reject');
      const { storeId } = await submitPartnerApplicationCore(db, application(), owner);
      assert.deepEqual(
        await reviewPartnerCore(deps, { storeId, decision: 'reject', reason: 'Please add product photos.' }, admin('super-1')),
        { storeId, status: 'rejected' },
      );
      assert.equal(await read(`stores/${storeId}`), undefined);
      const archive = (await read(`stores/${storeId}/private/application`))!;
      assert.equal(archive.ownerUid, owner);
      assert.equal(archive.rejectReason, 'Please add product photos.');
      assert.equal(archive.rejectedBy, 'super-1');
      assert.ok(archive.rejectedAt);
      assert.equal(archive.store.name, 'Rose Corner');
      assert.equal(archive.ownerName, 'Sara Ahmed', 'the original application is kept');
      assert.equal((await auditOf(storeId))[0].action, 'store.reject');
      const [note] = await notificationsOf(owner);
      assert.match(note.body, /Please add product photos\./);
      assert.equal((await auth.getUser(owner)).customClaims?.seller, undefined);
      // retry is harmless; the owner can apply again
      assert.equal((await reviewPartnerCore(deps, { storeId, decision: 'reject', reason: 'Again' }, admin('super-1'))).status, 'rejected');
      assert.ok((await submitPartnerApplicationCore(db, application(), owner)).storeId);
    });

    test('only pending applications; only super / ops', async () => {
      const owner = await customer('roles');
      const { storeId } = await submitPartnerApplicationCore(db, application(), owner);
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, admin('content-1')), 'permission-denied');
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, admin('finance-1')), 'permission-denied');
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, { uid: 'ops-1', claims: {} }), 'permission-denied');
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, { uid: owner, claims: { seller: storeId } }), 'permission-denied');
      const missing = await rejectsWith(reviewPartnerCore(deps, { storeId: 'nope', decision: 'reject', reason: 'xxxx' }, admin('ops-1')), 'not-found');
      assert.equal(missing.message, 'Store not found.');
      await reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, admin('ops-1'));
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'reject', reason: 'Too late' }, admin('ops-1')), 'failed-precondition');
    });

    test('an admin account cannot become a seller', async () => {
      const owner = await customer('staff', { admin: true });
      const { storeId } = await submitPartnerApplicationCore(db, application(), owner);
      await rejectsWith(reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 10 }, admin('ops-1')), 'failed-precondition');
      assert.equal((await read(`stores/${storeId}`))?.status, 'pendingApproval');
    });
  });

  describe('setStoreStatus', () => {
    test('suspend and reactivate an approved store (audit + owner notified; claim kept)', async () => {
      const owner = await customer('suspend');
      const { storeId } = await submitPartnerApplicationCore(db, application(), owner);
      await rejectsWith(setStoreStatusCore(deps, { storeId, status: 'suspended', reason: 'Late orders' }, admin('ops-1')), 'failed-precondition');
      await reviewPartnerCore(deps, { storeId, decision: 'approve', commissionPercent: 15 }, admin('ops-1'));

      assert.deepEqual(await setStoreStatusCore(deps, { storeId, status: 'suspended', reason: 'Late orders' }, admin('ops-1')), {
        storeId,
        status: 'suspended',
      });
      let store = (await read(`stores/${storeId}`))!;
      assert.equal(store.status, 'suspended');
      assert.equal(store.statusReason, 'Late orders');
      assert.equal((await auth.getUser(owner)).customClaims?.seller, storeId);
      await setStoreStatusCore(deps, { storeId, status: 'suspended', reason: 'Again' }, admin('ops-1')); // no-op
      await setStoreStatusCore(deps, { storeId, status: 'active', reason: 'Fixed' }, admin('super-1'));
      store = (await read(`stores/${storeId}`))!;
      assert.equal(store.status, 'active');
      assert.deepEqual((await auditOf(storeId)).map((a: DocumentData) => a.action).sort(), ['store.approve', 'store.reactivate', 'store.suspend']);
      const notes = (await notificationsOf(owner)).map((x) => x.title).sort();
      assert.equal(notes.length, 3);
      await rejectsWith(setStoreStatusCore(deps, { storeId, status: 'active', reason: 'xxx' }, admin('finance-1')), 'permission-denied');
    });
  });
});

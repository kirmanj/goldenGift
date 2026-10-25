/**
 * sendBroadcast against the Firestore emulator; skipped without it. Own demo-
 * project, cleared before every test (the throttle is platform-wide).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import {
  AUDIT_ACTION_BROADCAST,
  BROADCAST_THROTTLE_KEY,
  sendBroadcastCore,
  type BroadcastCaller,
  type BroadcastDeps,
} from '../src/notifications/sendBroadcast';
import { clearEmulatorFirestore, needsEnv, runId } from './emulators';
import { FakeMessaging } from './fakeMessaging';

const PROJECT = 'demo-goldengift-broadcast';
const T0 = Date.UTC(2026, 9, 21, 9, 0);

/** BroadcastRepository.payload in the dashboard. */
const payload = (over: Record<string, unknown> = {}) => ({
  title: { en: 'Eid sale', ar: 'تخفيضات العيد', ku: 'داشکاندنی جەژن' },
  body: { en: '20% off all frames', ar: 'خصم 20% على كل الإطارات', ku: null },
  route: '/products?category=frames',
  ...over,
});

async function rejectsWith(promise: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(promise, (e: unknown) => {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal(e.code, code, e.message);
    return true;
  });
}

describe('sendBroadcast (Firestore emulator)', { skip: needsEnv('FIRESTORE_EMULATOR_HOST') }, () => {
  const app = initializeApp({ projectId: PROJECT }, `broadcast-${runId()}`);
  const db = getFirestore(app);
  const fcm = new FakeMessaging();
  let clock = T0;
  const deps = (over: Partial<BroadcastDeps> = {}): BroadcastDeps => ({
    db,
    messaging: fcm,
    now: () => clock,
    logger: { warn: () => undefined },
    pageSize: 2,
    ...over,
  });
  const ops: BroadcastCaller = { uid: 'ops-1', claims: { admin: true } };
  const read = async (path: string) => (await db.doc(path).get()).data();

  beforeEach(async () => {
    await clearEmulatorFirestore(PROJECT);
    fcm.reset();
    clock = T0;
    const batch = db.batch();
    for (const [uid, role] of [['ops-1', 'ops'], ['super-1', 'super'], ['content-1', 'content'], ['finance-1', 'finance']]) {
      batch.set(db.doc(`admins/${uid}`), { name: uid, role, permissions: [] });
    }
    const users: Array<[string, DocumentData]> = [
      ['u-en', { locale: 'en', fcmTokens: ['t-en-1', 't-en-2'] }],
      ['u-ar', { locale: 'ar', fcmTokens: ['t-ar'] }],
      ['u-ku', { locale: 'ckb', fcmTokens: ['t-ku', 't-dead'] }],
      ['u-default', { fcmTokens: ['t-default'] }], // no locale → English
      ['u-off', { locale: 'en', fcmTokens: ['t-off'], notificationsEnabled: false }],
      ['u-deleted', { locale: 'en', fcmTokens: ['t-deleted'], isDeleted: true }],
      ['u-blocked', { locale: 'ar', fcmTokens: ['t-blocked'], isBlocked: true }],
      ['u-none', { locale: 'en', fcmTokens: [] }],
      ['u-shared', { locale: 'en', fcmTokens: ['t-en-1'] }], // a device that changed accounts
    ];
    for (const [uid, data] of users) batch.set(db.doc(`users/${uid}`), { name: uid, notificationsEnabled: true, ...data });
    await batch.commit();
  });

  after(async () => {
    await clearEmulatorFirestore(PROJECT);
    await deleteApp(app);
  });

  test('pushes to every opted-in device in its language, records the broadcast and the audit entry', async () => {
    fcm.dead.add('t-dead');
    const result = await sendBroadcastCore(deps(), payload(), ops);

    // Every device once; nobody opted out, deleted or blocked.
    assert.deepEqual(fcm.tokens().sort(), ['t-ar', 't-dead', 't-default', 't-en-1', 't-en-2', 't-ku']);
    const titleOf = (token: string) => fcm.calls.find((c) => c.tokens.includes(token))?.notification?.title;
    assert.equal(titleOf('t-en-1'), 'Eid sale');
    assert.equal(titleOf('t-default'), 'Eid sale');
    assert.equal(titleOf('t-ar'), 'تخفيضات العيد');
    assert.equal(titleOf('t-ku'), 'داشکاندنی جەژن');
    // Missing Kurdish body → English.
    assert.equal(fcm.calls.find((c) => c.tokens.includes('t-ku'))?.notification?.body, '20% off all frames');
    for (const call of fcm.calls) {
      assert.deepEqual(call.data, { route: '/products?category=frames', type: 'broadcast', notificationId: result.notificationId });
    }
    assert.equal(result.sent, 5);

    const doc = await read(`notifications/${result.notificationId}`);
    assert.ok(doc);
    assert.equal(doc.userId, 'all');
    assert.equal(doc.title, 'Eid sale');
    assert.equal(doc.titleAr, 'تخفيضات العيد');
    assert.equal(doc.titleKu, 'داشکاندنی جەژن');
    assert.equal(doc.body, '20% off all frames');
    assert.equal(doc.bodyKu, null);
    assert.equal(doc.type, 'broadcast');
    assert.deepEqual(doc.data, { route: '/products?category=frames', id: null });
    assert.equal(doc.isRead, false);
    assert.equal(doc.sentBy, 'ops-1');
    assert.equal(doc.sentCount, 5);
    assert.ok(doc.createdAt instanceof Timestamp);
    assert.equal('imageUrl' in doc, false);

    assert.deepEqual((await read('users/u-ku'))?.fcmTokens, ['t-ku']);

    const audit = (await db.collection('admin_audit_log').get()).docs.map((d) => d.data());
    assert.equal(audit.length, 1);
    assert.deepEqual({ ...audit[0], at: undefined }, {
      adminUid: 'ops-1',
      action: AUDIT_ACTION_BROADCAST,
      target: `notifications/${result.notificationId}`,
      before: null,
      after: { title: 'Eid sale', route: '/products?category=frames', sentCount: 5 },
      at: undefined,
    });
  });

  test('image and no route', async () => {
    const result = await sendBroadcastCore(
      deps(),
      payload({ route: undefined, imageUrl: 'https://cdn.example.com/eid.jpg' }),
      { uid: 'content-1', claims: { admin: true } },
    );
    const doc = await read(`notifications/${result.notificationId}`);
    assert.equal(doc?.imageUrl, 'https://cdn.example.com/eid.jpg');
    assert.deepEqual(doc?.data, { route: null, id: null });
    assert.equal(fcm.calls[0].notification?.imageUrl, 'https://cdn.example.com/eid.jpg');
    assert.equal('route' in (fcm.calls[0].data ?? {}), false);
  });

  test('one broadcast per minute, platform-wide', async () => {
    await sendBroadcastCore(deps(), payload(), ops);
    clock = T0 + 59_000;
    await rejectsWith(sendBroadcastCore(deps(), payload(), { uid: 'super-1', claims: { admin: true } }), 'resource-exhausted');
    assert.equal((await db.collection('notifications').get()).size, 1);
    clock = T0 + 60_000;
    assert.ok(await sendBroadcastCore(deps(), payload(), { uid: 'super-1', claims: { admin: true } }));
    assert.equal((await db.collection('notifications').get()).size, 2);
    assert.equal((await read(`function_runs/${BROADCAST_THROTTLE_KEY}`))?.lastBy, 'super-1');
  });

  test('invalid data does not use up the minute', async () => {
    await rejectsWith(sendBroadcastCore(deps(), payload({ title: { en: '' } }), ops), 'invalid-argument');
    assert.ok(await sendBroadcastCore(deps(), payload(), ops));
  });

  test('admins with role super / ops / content only', async () => {
    await rejectsWith(sendBroadcastCore(deps(), payload(), {}), 'unauthenticated');
    await rejectsWith(sendBroadcastCore(deps(), payload(), { uid: 'u-en', claims: {} }), 'permission-denied');
    await rejectsWith(sendBroadcastCore(deps(), payload(), { uid: 'ops-1', claims: {} }), 'permission-denied'); // doc, no claim
    await rejectsWith(sendBroadcastCore(deps(), payload(), { uid: 'nobody', claims: { admin: true } }), 'permission-denied'); // claim, no doc
    await rejectsWith(sendBroadcastCore(deps(), payload(), { uid: 'finance-1', claims: { admin: true } }), 'permission-denied');
    assert.equal((await db.collection('notifications').get()).size, 0);
    assert.equal(fcm.calls.length, 0);
  });

  test('FCM down: the in-app broadcast stays, sentCount 0', async () => {
    fcm.failWith = new Error('FCM down');
    const result = await sendBroadcastCore(deps(), payload(), ops);
    assert.equal(result.sent, 0);
    assert.equal((await read(`notifications/${result.notificationId}`))?.sentCount, 0);
    assert.equal((await db.collection('admin_audit_log').get()).size, 1);
  });

  test('no messaging (in-app only)', async () => {
    const result = await sendBroadcastCore(deps({ messaging: null }), payload(), ops);
    assert.equal(result.sent, 0);
    assert.ok(await read(`notifications/${result.notificationId}`));
  });

  test('default page size reaches every user too', async () => {
    const result = await sendBroadcastCore(deps({ pageSize: undefined }), payload(), ops);
    assert.equal(result.sent, 6);
  });
});

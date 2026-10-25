/**
 * setAdminClaim against the Auth + Firestore emulators (skipped without them, see
 * ./emulators.ts).
 *
 * Auth runs in goldengift-iq with unique uids per run. Firestore uses this suite's
 * own demo- project, cleared before every test: the "last super admin" guard counts
 * every super admin in the project, so no other suite (running in parallel) and no
 * dev data may share it.
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore, type DocumentData } from 'firebase-admin/firestore';
import {
  AUDIT_ACTION_GRANT,
  AUDIT_ACTION_REVOKE,
  LAST_SUPER_MESSAGE,
  SELF_REVOKE_MESSAGE,
  SUPER_ONLY_MESSAGE,
  grantAdminAccess,
  parseSetAdminClaimData,
  revokeAdminAccess,
  setAdminClaimCore,
  type AdminCaller,
} from '../src/admin/setAdminClaim';
import { PROJECT_ID, clearEmulatorFirestore, needsEnv, runId } from './emulators';

const FIRESTORE_PROJECT = 'demo-goldengift-set-admin-claim';

describe('parseSetAdminClaimData', () => {
  test('accepts uid or email, with optional role and name', () => {
    assert.deepEqual(parseSetAdminClaimData({ uid: ' u1 ', grant: true, role: 'finance', name: '  Sara ' }), {
      uid: 'u1',
      grant: true,
      role: 'finance',
      name: 'Sara',
    });
    assert.deepEqual(parseSetAdminClaimData({ email: 'a@b.co', grant: false }), { email: 'a@b.co', grant: false });
    assert.deepEqual(parseSetAdminClaimData({ email: 'a@b.co', uid: null, grant: true, role: null, name: '' }), {
      email: 'a@b.co',
      grant: true,
    });
  });

  for (const [label, data] of [
    ['null', null],
    ['a string', 'admin@example.com'],
    ['an array', [{ uid: 'u1', grant: true }]],
    ['no grant', { uid: 'u1' }],
    ['grant as a string', { uid: 'u1', grant: 'true' }],
    ['neither uid nor email', { grant: true }],
    ['both uid and email', { uid: 'u1', email: 'a@b.co', grant: true }],
    ['an empty uid', { uid: '  ', grant: true }],
    ['a uid that is a number', { uid: 42, grant: true }],
    ['a uid of 129 characters', { uid: 'x'.repeat(129), grant: true }],
    ['an email without @', { email: 'admin.example.com', grant: true }],
    ['an email with spaces', { email: 'ad min@example.com', grant: true }],
    ['an unknown role', { uid: 'u1', grant: true, role: 'owner' }],
    ['role seller (a claim, not an admin role)', { uid: 'u1', grant: true, role: 'seller' }],
    ['a name that is a number', { uid: 'u1', grant: true, name: 7 }],
    ['a name of 101 characters', { uid: 'u1', grant: true, name: 'x'.repeat(101) }],
  ] as Array<[string, unknown]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parseSetAdminClaimData(data), { code: 'invalid-argument' });
    });
  }
});

describe(
  'setAdminClaim (Auth + Firestore emulators)',
  { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') },
  () => {
    const run = runId();
    const authApp = initializeApp({ projectId: PROJECT_ID }, `set-admin-claim-auth-${run}`);
    const dbApp = initializeApp({ projectId: FIRESTORE_PROJECT }, `set-admin-claim-db-${run}`);
    const auth = getAuth(authApp);
    const db = getFirestore(dbApp);
    const deps = { db, auth };
    const uids: string[] = [];
    let n = 0;

    /** A fresh Auth account (email `{uid}@example.com`). */
    async function account(label: string, claims?: Record<string, unknown>, displayName?: string) {
      const uid = `adm-${run}-${++n}-${label}`;
      uids.push(uid);
      const user = await auth.createUser({ uid, email: `${uid}@example.com`, ...(displayName && { displayName }) });
      if (claims) await auth.setCustomUserClaims(uid, claims);
      return user;
    }
    /** An admin as the dashboard sees one: claim + admins doc. The caller as the callable sees it. */
    async function adminAccount(label: string, role = 'super'): Promise<AdminCaller & { uid: string }> {
      const user = await account(label, { admin: true });
      await db.doc(`admins/${user.uid}`).set({
        name: `Admin ${label}`,
        email: user.email,
        role,
        permissions: [],
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { uid: user.uid, claims: { admin: true, email: user.email } };
    }
    const claimsOf = async (uid: string) => (await auth.getUser(uid)).customClaims ?? {};
    const adminDoc = async (uid: string) => (await db.doc(`admins/${uid}`).get()).data();
    const audit = async (uid: string): Promise<DocumentData[]> =>
      (await db.collection('admin_audit_log').where('target', '==', `admins/${uid}`).get()).docs
        .map((d) => d.data())
        .sort((a, b) => (a.at as Timestamp).toMillis() - (b.at as Timestamp).toMillis());
    const call = (caller: AdminCaller, data: unknown) => setAdminClaimCore(deps, data, caller);

    beforeEach(() => clearEmulatorFirestore(FIRESTORE_PROJECT));

    after(async () => {
      await clearEmulatorFirestore(FIRESTORE_PROJECT);
      await auth.deleteUsers(uids);
      await Promise.all([deleteApp(authApp), deleteApp(dbApp)]);
    });

    // ── Who may call ──────────────────────────────────────────────────────
    test('signed out → unauthenticated', async () => {
      const target = await account('t');
      await assert.rejects(call({}, { uid: target.uid, grant: true }), { code: 'unauthenticated' });
      await assert.rejects(call({ claims: { admin: true } }, { uid: target.uid, grant: true }), { code: 'unauthenticated' });
    });

    test('anyone but a super admin → permission-denied, and nothing is written', async () => {
      const target = await account('t', { seller: 'store-1' });
      const ops = await adminAccount('ops', 'ops');
      const customer = await account('customer');
      const superWithoutClaim = await adminAccount('super-stale');
      const callers: Array<[string, AdminCaller]> = [
        ['a customer', { uid: customer.uid, claims: {} }],
        ['a customer claiming admin in the data', { uid: customer.uid, claims: { admin: 'true' } }],
        ['an ops admin', ops],
        ['an admin claim without an admins doc', { uid: customer.uid, claims: { admin: true } }],
        ['a super admins doc without the claim in the token', { uid: superWithoutClaim.uid, claims: {} }],
      ];
      for (const [who, caller] of callers) {
        await assert.rejects(call(caller, { uid: target.uid, grant: true, role: 'super' }), {
          code: 'permission-denied',
          message: SUPER_ONLY_MESSAGE,
        }, who);
        // Not even existence of the target leaks.
        await assert.rejects(call(caller, { email: 'nobody@example.com', grant: true }), { code: 'permission-denied' }, who);
      }
      assert.deepEqual(await claimsOf(target.uid), { seller: 'store-1' });
      assert.equal(await adminDoc(target.uid), undefined);
      assert.deepEqual(await audit(target.uid), []);
    });

    test('unknown uid or email → not-found; malformed data → invalid-argument', async () => {
      const boss = await adminAccount('boss');
      await assert.rejects(call(boss, { uid: `adm-${run}-missing`, grant: true }), { code: 'not-found' });
      await assert.rejects(call(boss, { email: `missing-${run}@example.com`, grant: false }), { code: 'not-found' });
      await assert.rejects(call(boss, { email: 'x@y.z', uid: boss.uid, grant: true }), { code: 'invalid-argument' });
      await assert.rejects(call(boss, { uid: boss.uid, grant: true, role: 'root' }), { code: 'invalid-argument' });
    });

    // ── Grant ─────────────────────────────────────────────────────────────
    test('grant by email: claim MERGED into existing claims, admins doc created, audit entry', async () => {
      const boss = await adminAccount('boss');
      const target = await account('seller', { seller: 'store-1', tier: 2 });
      const result = await call(boss, { email: target.email, grant: true, role: 'content', name: 'Lana Content' });
      assert.deepEqual(result, { uid: target.uid, email: target.email, admin: true, role: 'content', changed: true });

      assert.deepEqual(await claimsOf(target.uid), { seller: 'store-1', tier: 2, admin: true });
      const doc = (await adminDoc(target.uid))!;
      assert.deepEqual(
        { name: doc.name, email: doc.email, role: doc.role, permissions: doc.permissions },
        { name: 'Lana Content', email: target.email, role: 'content', permissions: [] },
      );
      assert.ok(doc.createdAt instanceof Timestamp);
      assert.ok(doc.updatedAt instanceof Timestamp);
      assert.deepEqual(Object.keys(doc).sort(), ['createdAt', 'email', 'name', 'permissions', 'role', 'updatedAt']);

      const [entry, ...more] = await audit(target.uid);
      assert.equal(more.length, 0);
      assert.deepEqual(Object.keys(entry).sort(), ['action', 'adminUid', 'after', 'at', 'before', 'target']);
      assert.equal(entry.adminUid, boss.uid);
      assert.equal(entry.action, AUDIT_ACTION_GRANT);
      assert.equal(entry.target, `admins/${target.uid}`);
      assert.equal(entry.before, null);
      assert.deepEqual(entry.after, {
        admin: true,
        role: 'content',
        name: 'Lana Content',
        email: target.email,
        permissions: [],
      });
      assert.ok(entry.at instanceof Timestamp);
    });

    test('grant by uid: role defaults to ops, name to the display name', async () => {
      const boss = await adminAccount('boss');
      const target = await account('plain', undefined, 'Dara Display');
      const result = await call(boss, { uid: target.uid, grant: true });
      assert.equal(result.role, 'ops');
      assert.deepEqual(await claimsOf(target.uid), { admin: true });
      const doc = (await adminDoc(target.uid))!;
      assert.equal(doc.name, 'Dara Display');
      assert.equal(doc.role, 'ops');
    });

    test('repeating a grant changes nothing and writes no second audit entry', async () => {
      const boss = await adminAccount('boss');
      const target = await account('twice');
      await call(boss, { uid: target.uid, grant: true, role: 'finance', name: 'Fin' });
      const first = (await adminDoc(target.uid))!;
      const again = await call(boss, { uid: target.uid, grant: true, role: 'finance', name: 'Fin' });
      assert.equal(again.changed, false);
      const second = (await adminDoc(target.uid))!;
      assert.ok((second.updatedAt as Timestamp).isEqual(first.updatedAt as Timestamp));
      assert.equal((await audit(target.uid)).length, 1);
    });

    test('changing role and name keeps createdAt and permissions, audits before → after', async () => {
      const boss = await adminAccount('boss');
      const target = await account('promote');
      await call(boss, { uid: target.uid, grant: true, role: 'ops', name: 'Omar' });
      await db.doc(`admins/${target.uid}`).update({ permissions: ['orders.refund'] });
      const first = (await adminDoc(target.uid))!;

      const result = await call(boss, { email: target.email, grant: true, role: 'super', name: 'Omar S' });
      assert.equal(result.role, 'super');
      const doc = (await adminDoc(target.uid))!;
      assert.equal(doc.role, 'super');
      assert.equal(doc.name, 'Omar S');
      assert.deepEqual(doc.permissions, ['orders.refund']);
      assert.ok((doc.createdAt as Timestamp).isEqual(first.createdAt as Timestamp));

      const entries = await audit(target.uid);
      assert.equal(entries.length, 2);
      assert.deepEqual(entries[1].before, {
        admin: true,
        role: 'ops',
        name: 'Omar',
        email: target.email,
        permissions: ['orders.refund'],
      });
      assert.equal(entries[1].after.role, 'super');

      // The promoted super admin can now grant.
      const other = await account('by-new-super');
      await call({ uid: target.uid, claims: { admin: true } }, { uid: other.uid, grant: true });
      assert.equal((await claimsOf(other.uid)).admin, true);
    });

    test('a claim missing behind an existing doc is repaired (and audited)', async () => {
      const boss = await adminAccount('boss');
      const target = await account('half');
      await call(boss, { uid: target.uid, grant: true, role: 'ops' });
      await auth.setCustomUserClaims(target.uid, { seller: 'store-9' }); // claim lost, doc kept
      const result = await call(boss, { uid: target.uid, grant: true, role: 'ops' });
      assert.equal(result.changed, true);
      assert.deepEqual(await claimsOf(target.uid), { seller: 'store-9', admin: true });
      assert.equal((await audit(target.uid)).length, 2);
    });

    // ── Revoke ────────────────────────────────────────────────────────────
    test('revoke removes only the admin claim, deletes the doc, audits it', async () => {
      const boss = await adminAccount('boss');
      const target = await account('rev', { seller: 'store-1' });
      await call(boss, { uid: target.uid, grant: true, role: 'finance' });

      const result = await call(boss, { email: target.email, grant: false });
      assert.deepEqual(result, { uid: target.uid, email: target.email, admin: false, role: null, changed: true });
      assert.deepEqual(await claimsOf(target.uid), { seller: 'store-1' });
      assert.equal(await adminDoc(target.uid), undefined);

      const entries = await audit(target.uid);
      assert.equal(entries.length, 2);
      const entry = entries[1];
      assert.equal(entry.action, AUDIT_ACTION_REVOKE);
      assert.equal(entry.adminUid, boss.uid);
      assert.equal(entry.after, null);
      assert.equal(entry.before.admin, true);
      assert.equal(entry.before.role, 'finance');

      const again = await call(boss, { uid: target.uid, grant: false });
      assert.equal(again.changed, false);
      assert.equal((await audit(target.uid)).length, 2, 'no entry for a no-op revoke');
    });

    test('revoke of an admin without other claims leaves no claims at all', async () => {
      const boss = await adminAccount('boss');
      const target = await account('only-admin');
      await call(boss, { uid: target.uid, grant: true });
      await call(boss, { uid: target.uid, grant: false });
      assert.deepEqual(await claimsOf(target.uid), {});
    });

    test('a revoked super admin is refused at once, even with a stale token', async () => {
      const boss = await adminAccount('boss');
      const other = await adminAccount('other');
      await call(boss, { uid: other.uid, grant: false });
      const victim = await account('victim');
      await assert.rejects(call(other /* token still says admin */, { uid: victim.uid, grant: true }), {
        code: 'permission-denied',
      });
      assert.equal((await claimsOf(victim.uid)).admin, undefined);
    });

    // ── Lock-out guards ───────────────────────────────────────────────────
    test('revoking yourself → failed-precondition, nothing changes', async () => {
      const boss = await adminAccount('boss');
      await adminAccount('second-super'); // not the last one: refused for being yourself
      await assert.rejects(call(boss, { uid: boss.uid, grant: false }), {
        code: 'failed-precondition',
        message: SELF_REVOKE_MESSAGE,
      });
      assert.equal((await claimsOf(boss.uid)).admin, true);
      assert.equal((await adminDoc(boss.uid))!.role, 'super');
      assert.deepEqual(await audit(boss.uid), []);
    });

    test('the last super admin cannot be demoted; with a second super they can', async () => {
      const boss = await adminAccount('boss');
      await assert.rejects(call(boss, { uid: boss.uid, grant: true, role: 'ops' }), {
        code: 'failed-precondition',
        message: LAST_SUPER_MESSAGE,
      });
      assert.equal((await adminDoc(boss.uid))!.role, 'super');

      await adminAccount('second-super');
      const result = await call(boss, { uid: boss.uid, grant: true, role: 'ops' });
      assert.equal(result.role, 'ops');
    });

    test('the last super admin cannot be revoked (script / direct path, no caller)', async () => {
      const boss = await adminAccount('boss');
      const user = await auth.getUser(boss.uid);
      await assert.rejects(revokeAdminAccess(deps, user, { actorUid: 'script:test' }), {
        code: 'failed-precondition',
        message: LAST_SUPER_MESSAGE,
      });
      await assert.rejects(grantAdminAccess(deps, user, { actorUid: 'script:test', role: 'content' }), {
        code: 'failed-precondition',
      });
      assert.equal((await claimsOf(boss.uid)).admin, true);
      assert.equal((await adminDoc(boss.uid))!.role, 'super');
    });

    test('two super admins revoking each other at once: exactly one wins, one super remains', async () => {
      const a = await adminAccount('a');
      const b = await adminAccount('b');
      const results = await Promise.allSettled([
        call(a, { uid: b.uid, grant: false }),
        call(b, { uid: a.uid, grant: false }),
      ]);
      const winner = results.findIndex((r) => r.status === 'fulfilled');
      assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1, JSON.stringify(results));
      const loser = results[1 - winner] as PromiseRejectedResult;
      // The loser's transaction re-runs after the winner's commit and finds itself no
      // longer a super admin (or, failing that, the last one).
      assert.ok(['permission-denied', 'failed-precondition'].includes(loser.reason?.code), String(loser.reason));

      const [survivor, revoked] = winner === 0 ? [a, b] : [b, a];
      const supers = await db.collection('admins').where('role', '==', 'super').get();
      assert.deepEqual(supers.docs.map((d) => d.id), [survivor.uid]);
      assert.equal((await claimsOf(survivor.uid)).admin, true);
      assert.equal((await claimsOf(revoked.uid)).admin, undefined);
    });
  },
);

/**
 * scripts/create-admin.ts core (`createAdmin`) — input parsing (pure) and the
 * bootstrap against the Auth + Firestore emulators (skipped without them).
 * Firestore uses this suite's own demo- project (see setAdminClaim.test.ts for why).
 */
import assert from 'node:assert/strict';
import { after, beforeEach, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { CREATE_ADMIN_ACTOR, createAdmin, parseCreateAdminInput } from '../scripts/admin/createAdmin';
import { setAdminClaimCore } from '../src/admin/setAdminClaim';
import { PROJECT_ID, clearEmulatorFirestore, emulatorPasswordSignIn, needsEnv, runId } from './emulators';

const FIRESTORE_PROJECT = 'demo-goldengift-create-admin';

describe('parseCreateAdminInput', () => {
  test('defaults the role to super and trims', () => {
    assert.deepEqual(parseCreateAdminInput({ email: ' owner@example.com ', name: ' Owner ' }), {
      input: { email: 'owner@example.com', name: 'Owner', role: 'super' },
      problems: [],
    });
    assert.deepEqual(
      parseCreateAdminInput({ email: 'a@b.co', name: 'A', password: 'secret1', role: 'finance' }).input,
      { email: 'a@b.co', name: 'A', password: 'secret1', role: 'finance' },
    );
  });

  test('reports every problem', () => {
    const { input, problems } = parseCreateAdminInput({ email: 'nope', name: ' ', password: '12345', role: 'root' });
    assert.equal(input, null);
    assert.equal(problems.length, 4);
    assert.match(problems.join('\n'), /--email.*\n.*--name.*\n.*--password.*\n.*--role/);
  });

  test('email and name are required', () => {
    assert.equal(parseCreateAdminInput({}).problems.length, 2);
  });
});

describe(
  'createAdmin (Auth + Firestore emulators)',
  { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') },
  () => {
    const run = runId();
    const authApp = initializeApp({ projectId: PROJECT_ID }, `create-admin-auth-${run}`);
    const dbApp = initializeApp({ projectId: FIRESTORE_PROJECT }, `create-admin-db-${run}`);
    const auth = getAuth(authApp);
    const db = getFirestore(dbApp);
    const deps = { db, auth };
    const uids: string[] = [];
    let n = 0;
    const newEmail = (label: string) => `boot-${run}-${++n}-${label}@example.com`;
    const track = <T extends { uid: string }>(r: T) => {
      uids.push(r.uid);
      return r;
    };
    const auditEntries = async (uid: string) =>
      (await db.collection('admin_audit_log').where('target', '==', `admins/${uid}`).get()).docs.map((d) => d.data());

    beforeEach(() => clearEmulatorFirestore(FIRESTORE_PROJECT));

    after(async () => {
      await clearEmulatorFirestore(FIRESTORE_PROJECT);
      await auth.deleteUsers(uids);
      await Promise.all([deleteApp(authApp), deleteApp(dbApp)]);
    });

    test('creates the email/password account and makes it a super admin', async () => {
      const email = newEmail('first');
      const result = track(await createAdmin(deps, { email, name: 'First Owner', password: 'test1234', role: 'super' }));
      assert.equal(result.userCreated, true);
      assert.equal(result.passwordIgnored, false);
      assert.equal(result.role, 'super');
      assert.equal(result.changed, true);
      assert.deepEqual(result.claims, { admin: true });

      const user = await auth.getUserByEmail(email);
      assert.equal(user.uid, result.uid);
      assert.equal(user.displayName, 'First Owner');
      assert.deepEqual(user.customClaims, { admin: true });

      const doc = (await db.doc(`admins/${result.uid}`).get()).data()!;
      assert.equal(doc.name, 'First Owner');
      assert.equal(doc.email, email);
      assert.equal(doc.role, 'super');
      assert.deepEqual(doc.permissions, []);
      assert.ok(doc.createdAt instanceof Timestamp);

      const entries = await auditEntries(result.uid);
      assert.equal(entries.length, 1);
      assert.equal(entries[0].adminUid, CREATE_ADMIN_ACTOR);
      assert.equal(entries[0].action, 'admin.grant');
      assert.equal(entries[0].before, null);

      // Signs in exactly like the dashboard, and the ID token carries the claim.
      const token = await emulatorPasswordSignIn(email, 'test1234');
      assert.ok(token, 'password sign-in works');
      assert.equal(token.admin, true);
      assert.equal(token.sub, result.uid);

      // …and is a super admin setAdminClaim accepts as a caller.
      const other = track(await auth.createUser({ email: newEmail('granted') }));
      await setAdminClaimCore(deps, { uid: other.uid, grant: true, role: 'ops' }, { uid: result.uid, claims: token });
      assert.equal((await auth.getUser(other.uid)).customClaims?.admin, true);
    });

    test('an existing account is only granted: claims merged, password and profile untouched', async () => {
      const email = newEmail('existing');
      const existing = track(
        await auth.createUser({ email, password: 'original1', displayName: 'Keep Me' }),
      );
      await auth.setCustomUserClaims(existing.uid, { seller: 'store-7' });

      const result = await createAdmin(deps, { email, name: 'Ops Person', password: 'ignored99', role: 'ops' });
      assert.equal(result.uid, existing.uid);
      assert.equal(result.userCreated, false);
      assert.equal(result.passwordIgnored, true);
      assert.equal(result.role, 'ops');
      assert.deepEqual(result.claims, { seller: 'store-7', admin: true });

      const user = await auth.getUser(existing.uid);
      assert.equal(user.displayName, 'Keep Me');
      assert.ok(await emulatorPasswordSignIn(email, 'original1'), 'old password still works');
      assert.equal(await emulatorPasswordSignIn(email, 'ignored99'), null, 'password not changed');
      assert.equal((await db.doc(`admins/${existing.uid}`).get()).get('name'), 'Ops Person');
    });

    test('running it again converges: same account, no second audit entry', async () => {
      const email = newEmail('again');
      const first = track(await createAdmin(deps, { email, name: 'Again', password: 'test1234', role: 'super' }));
      const second = await createAdmin(deps, { email, name: 'Again', password: 'test1234', role: 'super' });
      assert.equal(second.uid, first.uid);
      assert.equal(second.userCreated, false);
      assert.equal(second.changed, false);
      assert.equal((await auditEntries(first.uid)).length, 1);
      assert.equal((await auth.listUsers()).users.filter((u) => u.email === email).length, 1);
    });

    test('no account and no password → refused, nothing created', async () => {
      const email = newEmail('missing');
      await assert.rejects(createAdmin(deps, { email, name: 'Nobody', role: 'super' }), /Pass --password/);
      await assert.rejects(auth.getUserByEmail(email), { code: 'auth/user-not-found' });
      assert.equal((await db.collection('admins').count().get()).data().count, 0);
    });

    test('will not demote the last super admin', async () => {
      const email = newEmail('last');
      const first = track(await createAdmin(deps, { email, name: 'Last', password: 'test1234', role: 'super' }));
      await assert.rejects(createAdmin(deps, { email, name: 'Last', role: 'ops' }), { code: 'failed-precondition' });
      assert.equal((await db.doc(`admins/${first.uid}`).get()).get('role'), 'super');
    });
  },
);

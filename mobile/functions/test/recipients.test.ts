/**
 * giftCards/recipients.ts against the Auth emulator: gift-card recipients are the
 * accounts whose phone / email Firebase Auth has VERIFIED — never what a profile
 * doc says. Random numbers and addresses per run; the accounts are deleted after.
 */
import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { authRecipientLookup, verifiedEmail } from '../src/giftCards/recipients';
import { PROJECT_ID, needsEnv, runId } from './emulators';

describe('verifiedEmail', () => {
  test('only a verified address, lower case', () => {
    assert.equal(verifiedEmail({ email: 'Sara@Example.com', emailVerified: true }), 'sara@example.com');
    assert.equal(verifiedEmail({ email: 'sara@example.com', emailVerified: false }), null);
    assert.equal(verifiedEmail({ email: undefined, emailVerified: true }), null);
  });
});

describe('authRecipientLookup (Auth emulator)', { skip: needsEnv('FIREBASE_AUTH_EMULATOR_HOST') }, () => {
  const run = runId();
  const app = initializeApp({ projectId: PROJECT_ID }, `recipients-${run}`);
  const auth = getAuth(app);
  const lookup = authRecipientLookup(auth);
  const uids: string[] = [];
  const phone = () => `+96475${String(randomInt(0, 100_000_000)).padStart(8, '0')}`;
  const create = async (props: { phoneNumber?: string; email?: string; emailVerified?: boolean }) => {
    const user = await auth.createUser(props);
    uids.push(user.uid);
    return user.uid;
  };

  after(async () => {
    await auth.deleteUsers(uids);
    await deleteApp(app);
  });

  test('a verified phone (verifyOtp / changePhone put it on the account) matches', async () => {
    const p = phone();
    const uid = await create({ phoneNumber: p });
    assert.equal(await lookup.byContact(p, null), uid);
    assert.deepEqual(await lookup.contactsOf(uid), { phone: p, email: null });
  });

  test('an email matches only when verified (Google / Apple sign-in)', async () => {
    const verified = `v-${run}@example.com`;
    const unverified = `u-${run}@example.com`;
    const g = await create({ email: verified, emailVerified: true });
    const u = await create({ email: unverified, emailVerified: false });
    assert.equal(await lookup.byContact(null, verified.toUpperCase()), g);
    assert.equal(await lookup.byContact(null, unverified), null);
    assert.deepEqual(await lookup.contactsOf(u), { phone: null, email: null });
  });

  test('the phone wins over the email; unknown contacts and accounts match nobody', async () => {
    const p = phone();
    const byPhone = await create({ phoneNumber: p });
    const email = `e-${run}@example.com`;
    await create({ email, emailVerified: true });
    assert.equal(await lookup.byContact(p, email), byPhone);
    assert.equal(await lookup.byContact(phone(), null), null);
    assert.equal(await lookup.byContact(null, `nobody-${run}@example.com`), null);
    assert.deepEqual(await lookup.contactsOf(`missing-${run}`), { phone: null, email: null });
  });
});

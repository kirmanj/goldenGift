/**
 * sendOtp / verifyOtp / changePhone cores against the Firestore + Auth emulators.
 * Skipped unless both emulator env vars are set (see ./emulators.ts).
 *
 * Delivery runs exactly as on the Functions emulator: `FUNCTIONS_EMULATOR=true`
 * is injected with a (fake) key present, which must select the `log` driver and
 * mirror the code to `otp_debug` — and `fetch` is a stub that fails the test if it
 * is ever called. Nothing here can reach OTPIQ.
 */
import assert from 'node:assert/strict';
import { randomInt } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { deleteApp, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { changePhoneCore } from '../src/auth/changePhone';
import { EXPIRY_SECONDS, INVALID_CODE_MESSAGE, MAX_ATTEMPTS, PHONE_LIMIT } from '../src/auth/otp';
import { maskPhone, phoneKey } from '../src/auth/phone';
import { resolveReviewLogin } from '../src/auth/reviewLogin';
import { sendOtpCore, type SendOtpDeps } from '../src/auth/sendOtp';
import { verifyOtpAndSignInCore } from '../src/auth/signIn';
import { OTP_DEBUG_COLLECTION_EMULATOR_ONLY } from '../src/shared/paths';
import { PROJECT_ID, needsEnv, runId } from './emulators';

describe(
  'phone OTP callables (Firestore + Auth emulators)',
  { skip: needsEnv('FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST') },
  () => {
    const app = initializeApp({ projectId: PROJECT_ID }, `phone-auth-test-${runId()}`);
    const db = getFirestore(app);
    const auth = getAuth(app);
    const deps = { db, auth };
    const noNetwork = (async () => assert.fail('fetch must never be called on the emulator')) as typeof fetch;
    const sendDeps: SendOtpDeps = {
      db,
      auth,
      apiKey: 'test-key-not-real',
      env: { FUNCTIONS_EMULATOR: 'true' },
      fetch: noNetwork,
    };

    const phones: string[] = [];
    const uids: string[] = [];
    let globalCharged = 0;

    /** A fresh, valid Iraqi mobile number (+96475xxxxxxxx) per call. */
    const newPhone = () => {
      const phone = `+96475${String(randomInt(0, 100_000_000)).padStart(8, '0')}`;
      phones.push(phone);
      return phone;
    };
    const send = async (phone: string, purpose?: 'login' | 'changePhone', uid?: string) => {
      const result = await sendOtpCore(sendDeps, { phone, purpose }, { uid });
      globalCharged++;
      return result;
    };
    /** The code as the log driver mirrored it (emulator only). */
    const codeFor = async (phone: string) => {
      const debug = (await db.collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY).doc(phoneKey(phone)).get()).data();
      assert.ok(debug, `otp_debug/${phoneKey(phone)} missing`);
      return debug.code as string;
    };
    const codeDoc = (purpose: string, phone: string) => db.collection('otp_codes').doc(`${purpose}:${phoneKey(phone)}`);
    const login = async (phone: string) => {
      await send(phone);
      const result = await verifyOtpAndSignInCore(deps, { phone, code: await codeFor(phone) });
      const { uid } = await auth.getUserByPhoneNumber(phone);
      uids.push(uid);
      return { ...result, uid };
    };
    const wrong = (code: string) => (code === '000000' ? '111111' : '000000');
    const jwtPayload = (jwt: string) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString('utf8'));

    after(async () => {
      const refs = phones.flatMap((p) => [
        db.collection('otp_codes').doc(`login:${phoneKey(p)}`),
        db.collection('otp_codes').doc(`changePhone:${phoneKey(p)}`),
        db.collection('otp_throttle').doc(`phone:${phoneKey(p)}`),
        db.collection('otp_throttle').doc(`verifyFail:${phoneKey(p)}`),
        db.collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY).doc(phoneKey(p)),
      ]);
      await Promise.all([...refs, ...uids.map((u) => db.collection('users').doc(u))].map((r) => r.delete()));
      // Give back what this run charged, so repeated runs in one emulator session
      // never approach the daily ceiling.
      const day = new Date().toISOString().slice(0, 10);
      await db.collection('otp_throttle').doc(`global:${day}`).set({ sent: FieldValue.increment(-globalCharged) }, { merge: true });
      await auth.deleteUsers([...new Set(uids)]);
      await deleteApp(app);
    });

    // ── sendOtp + verifyOtp ────────────────────────────────────────────────
    test('sendOtp: masked phone, 5-minute expiry, code only in the emulator mirror', async () => {
      const phone = newPhone();
      const result = await send(phone);
      assert.deepEqual(result, { expiresInSeconds: EXPIRY_SECONDS, phone: maskPhone(phone) });
      assert.ok(!JSON.stringify(result).includes(phoneKey(phone).slice(-7)), 'phone masked');

      const debug = (await db.collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY).doc(phoneKey(phone)).get()).data()!;
      assert.match(debug.code, /^\d{6}$/);
      assert.equal(debug.purpose, 'login');
      assert.ok(debug.at instanceof Timestamp);

      const stored = (await codeDoc('login', phone).get()).data()!;
      assert.equal(stored.phone, phone);
      assert.equal(stored.attempts, 0);
      assert.ok(!JSON.stringify(stored).includes(debug.code), 'code hashed at rest');
    });

    test('verifyOtp: first login creates the Auth user and returns a working custom token', async () => {
      const phone = newPhone();
      await assert.rejects(auth.getUserByPhoneNumber(phone), { code: 'auth/user-not-found' });

      const { token, isNewUser, uid } = await login(phone);
      assert.equal(isNewUser, true);
      const user = await auth.getUser(uid);
      assert.equal(user.phoneNumber, phone);
      assert.equal(user.displayName, undefined, 'no profile collected here');

      const custom = jwtPayload(token);
      assert.equal(custom.uid, uid);
      assert.equal(custom.claims, undefined, 'no developer claims');

      // Exchange it exactly as the app's signInWithCustomToken does.
      const res = await fetch(
        `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=fake-api-key`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ token, returnSecureToken: true }) },
      );
      assert.equal(res.status, 200, await res.clone().text());
      const idToken = jwtPayload(((await res.json()) as { idToken: string }).idToken);
      assert.equal(idToken.sub, uid);
      assert.equal(idToken.phone_number, phone);

      assert.equal((await db.collection('users').doc(uid).get()).exists, false, 'the app creates users/{uid}');
      assert.equal((await codeDoc('login', phone).get()).exists, false, 'code burned');
    });

    test('verifyOtp: a second login finds the same user; a spent code cannot be replayed', async () => {
      const phone = newPhone();
      const first = await login(phone);
      await send(phone);
      const code = await codeFor(phone);
      const second = await verifyOtpAndSignInCore(deps, { phone: `0${phoneKey(phone).slice(3)}`, code }); // local spelling
      assert.equal(second.isNewUser, false);
      assert.equal(jwtPayload(second.token).uid, first.uid);
      await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code }), {
        code: 'unauthenticated',
        message: INVALID_CODE_MESSAGE,
      });
    });

    test('verifyOtp: wrong codes count; the 6th attempt is resource-exhausted even with the right code', async () => {
      const phone = newPhone();
      await send(phone);
      const code = await codeFor(phone);
      for (let i = 1; i <= MAX_ATTEMPTS; i++) {
        await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code: wrong(code) }), {
          code: 'unauthenticated',
          message: INVALID_CODE_MESSAGE,
        });
        assert.equal((await codeDoc('login', phone).get()).get('attempts'), i);
      }
      await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code }), { code: 'resource-exhausted' });
      await assert.rejects(auth.getUserByPhoneNumber(phone), { code: 'auth/user-not-found' });
    });

    test('verifyOtp: parallel wrong guesses are all counted (transactional counter)', async () => {
      const phone = newPhone();
      await send(phone);
      const code = await codeFor(phone);
      const results = await Promise.allSettled(
        Array.from({ length: MAX_ATTEMPTS + 3 }, () => verifyOtpAndSignInCore(deps, { phone, code: wrong(code) })),
      );
      assert.ok(results.every((r) => r.status === 'rejected'));
      const codes = results.map((r) => (r as PromiseRejectedResult).reason?.code);
      const counted = codes.filter((c) => c === 'unauthenticated').length;
      // Every guess judged "wrong" incremented the counter exactly once (no lost
      // update), and never more than the ceiling allows. A guess whose transaction
      // the emulator aborted under contention was not judged at all.
      assert.ok(counted <= MAX_ATTEMPTS, `${counted} guesses judged`);
      assert.equal((await codeDoc('login', phone).get()).get('attempts'), counted);
      if (counted === MAX_ATTEMPTS) {
        await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code }), { code: 'resource-exhausted' });
      }
    });

    test('verifyOtp: wrong and missing codes are refused identically', async () => {
      const withCode = newPhone();
      await send(withCode);
      const a = await verifyOtpAndSignInCore(deps, { phone: withCode, code: wrong(await codeFor(withCode)) }).catch((e) => e);
      const b = await verifyOtpAndSignInCore(deps, { phone: newPhone(), code: '123456' }).catch((e) => e);
      assert.equal(a.code, b.code);
      assert.equal(a.message, b.message);
    });

    test('a newer code invalidates the older one', async () => {
      const phone = newPhone();
      await send(phone);
      const older = await codeFor(phone);
      await send(phone);
      const newer = await codeFor(phone);
      if (older !== newer) {
        await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code: older }), { code: 'unauthenticated' });
      }
      const { isNewUser } = await verifyOtpAndSignInCore(deps, { phone, code: newer });
      assert.equal(isNewUser, true);
      uids.push((await auth.getUserByPhoneNumber(phone)).uid);
    });

    test('sendOtp: per-phone rate limit — 4 codes per 30 minutes, then resource-exhausted', async () => {
      const phone = newPhone();
      for (let i = 0; i < PHONE_LIMIT.count; i++) await send(phone);
      const last = await codeFor(phone);
      await assert.rejects(sendOtpCore(sendDeps, { phone }, {}), { code: 'resource-exhausted', message: /Too many codes/ });
      assert.equal(await codeFor(phone), last, 'no new code was minted');
      // Other numbers are unaffected.
      await send(newPhone());
    });

    test('malformed input → invalid-argument', async () => {
      for (const data of [{}, { phone: '12' }, { phone: 'not a phone' }, { phone: 7501234567 }, null, 'x']) {
        await assert.rejects(sendOtpCore(sendDeps, data, {}), { code: 'invalid-argument' }, JSON.stringify(data));
      }
      await assert.rejects(sendOtpCore(sendDeps, { phone: newPhone(), purpose: 'verify-phone' }, {}), {
        code: 'invalid-argument',
      });
      const phone = newPhone();
      for (const code of ['', '12345', '1234567', 'abcdef', 123456, undefined]) {
        await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code }), { code: 'invalid-argument' }, String(code));
      }
      await assert.rejects(verifyOtpAndSignInCore(deps, { phone: 'x', code: '123456' }), { code: 'invalid-argument' });
    });

    test('verifyOtp: a disabled account is refused', async () => {
      const phone = newPhone();
      const { uid } = await auth.createUser({ phoneNumber: phone, disabled: true });
      uids.push(uid);
      await send(phone);
      await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code: await codeFor(phone) }), {
        code: 'permission-denied',
      });
    });

    // ── changePhone ────────────────────────────────────────────────────────
    test('changePhone requires sign-in (sendOtp and changePhone)', async () => {
      await assert.rejects(sendOtpCore(sendDeps, { phone: newPhone(), purpose: 'changePhone' }, {}), {
        code: 'unauthenticated',
      });
      await assert.rejects(changePhoneCore(deps, { phone: newPhone(), code: '123456' }, undefined), {
        code: 'unauthenticated',
      });
    });

    test('changePhone: the code is bound to the uid that asked for it', async () => {
      const alice = await login(newPhone());
      const bob = await login(newPhone());
      const target = newPhone();
      await send(target, 'changePhone', alice.uid);
      assert.equal((await codeDoc('changePhone', target).get()).get('uid'), alice.uid);
      const code = await codeFor(target);

      await assert.rejects(changePhoneCore(deps, { phone: target, code }, bob.uid), {
        code: 'unauthenticated',
        message: INVALID_CODE_MESSAGE,
      });
      assert.equal((await auth.getUser(bob.uid)).phoneNumber !== target, true);
      // A login code for the same number is a different code: it cannot change a phone.
      await assert.rejects(verifyOtpAndSignInCore(deps, { phone: target, code }), { code: 'unauthenticated' });

      // Bob's attempt neither spent the code nor its attempts.
      assert.equal((await codeDoc('changePhone', target).get()).get('attempts'), 0);
      await changePhoneCore(deps, { phone: target, code }, alice.uid);
      assert.equal((await auth.getUser(alice.uid)).phoneNumber, target);
    });

    test("changePhone: another account's number is refused before any code is sent", async () => {
      const alice = await login(newPhone());
      const bobPhone = newPhone();
      await login(bobPhone);
      await assert.rejects(sendOtpCore(sendDeps, { phone: bobPhone, purpose: 'changePhone' }, { uid: alice.uid }), {
        code: 'already-exists',
      });
      assert.equal((await codeDoc('changePhone', bobPhone).get()).exists, false, 'no code minted');
      // The login codes mirrored for bob's sign-in are the only debug entries.
      assert.equal((await db.collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY).doc(phoneKey(bobPhone)).get()).get('purpose'), 'login');
    });

    test('changePhone: re-checks ownership when the code is spent', async () => {
      const alice = await login(newPhone());
      const bob = await login(newPhone());
      const target = newPhone();
      await send(target, 'changePhone', alice.uid);
      const code = await codeFor(target);
      await auth.updateUser(bob.uid, { phoneNumber: target }); // bob took it meanwhile

      await assert.rejects(changePhoneCore(deps, { phone: target, code }, alice.uid), { code: 'already-exists' });
      assert.notEqual((await auth.getUser(alice.uid)).phoneNumber, target);
    });

    test('changePhone: updates the Auth user and users/{uid}; the old number is released', async () => {
      const oldPhone = newPhone();
      const alice = await login(oldPhone);
      const userRef = db.collection('users').doc(alice.uid);
      await userRef.set({
        name: 'Alice',
        phone: phoneKey(oldPhone).slice(3),
        countryCode: '+964',
        locale: 'ckb',
        updatedAt: Timestamp.fromDate(new Date('2026-01-01')),
      });

      const target = newPhone();
      await send(target, 'changePhone', alice.uid);
      const result = await changePhoneCore(deps, { phone: target, code: await codeFor(target) }, alice.uid);

      const national = phoneKey(target).slice(3);
      assert.deepEqual(result, { phone: national, countryCode: '+964' });
      assert.equal((await auth.getUser(alice.uid)).phoneNumber, target);
      await assert.rejects(auth.getUserByPhoneNumber(oldPhone), { code: 'auth/user-not-found' });

      const doc = (await userRef.get()).data()!;
      assert.equal(doc.phone, national);
      assert.equal(doc.countryCode, '+964');
      assert.equal(doc.name, 'Alice');
      assert.equal(doc.locale, 'ckb');
      assert.ok((doc.updatedAt as Timestamp).toMillis() > Date.parse('2026-01-02'));

      assert.equal((await codeDoc('changePhone', target).get()).exists, false, 'code burned');
      // Signing in with the new number reaches the same account.
      const again = await login(target);
      assert.equal(again.uid, alice.uid);
      assert.equal(again.isNewUser, false);
    });

    test('changePhone: never creates users/{uid} (that would fire onUserCreate)', async () => {
      const alice = await login(newPhone());
      const target = newPhone();
      await send(target, 'changePhone', alice.uid);
      await changePhoneCore(deps, { phone: target, code: await codeFor(target) }, alice.uid);
      assert.equal((await db.collection('users').doc(alice.uid).get()).exists, false);
      assert.equal((await auth.getUser(alice.uid)).phoneNumber, target);
    });

    // ── store-review demo account (App Store / Play reviewers) ────────────
    describe('store-review demo login', () => {
      const REVIEW_CODE = '246810';
      /** OTPIQ "enabled" with a recording stub: proves what is (not) sent. */
      const sent: Array<{ phoneNumber: string; verificationCode: string }> = [];
      const recordingFetch = (async (_url: string | URL | Request, init?: RequestInit) => {
        sent.push(JSON.parse(String(init?.body)) as { phoneNumber: string; verificationCode: string });
        return new Response('{}', { status: 200 });
      }) as typeof fetch;
      const realSmsDeps = (review: ReturnType<typeof resolveReviewLogin>): SendOtpDeps => ({
        ...sendDeps,
        env: { FUNCTIONS_EMULATOR: 'true', OTP_REAL_SMS: 'true' },
        fetch: recordingFetch,
        review,
      });
      const mirrored = async (phone: string) => (await db.collection(OTP_DEBUG_COLLECTION_EMULATOR_ONLY).doc(phoneKey(phone)).get()).exists;

      test('off unless both REVIEW_PHONE and REVIEW_OTP_CODE are set (and well-formed)', () => {
        assert.equal(resolveReviewLogin(undefined, undefined), null);
        assert.equal(resolveReviewLogin('', REVIEW_CODE), null);
        assert.equal(resolveReviewLogin('+9647501234567', ''), null);
        assert.equal(resolveReviewLogin('+9647501234567', '   '), null);
        assert.equal(resolveReviewLogin('not a phone', REVIEW_CODE), null);
        assert.equal(resolveReviewLogin('+9647501234567', '12345'), null);
        assert.equal(resolveReviewLogin('+9647501234567', '١٢٣٤٥٦'), null, 'ASCII digits only');
        assert.deepEqual(resolveReviewLogin(' 0750 123 4567 ', ` ${REVIEW_CODE} `), { phone: '+9647501234567', code: REVIEW_CODE });
      });

      test('disabled by default: the number goes through the normal flow', async () => {
        const phone = newPhone();
        await send(phone); // sendDeps has no `review`
        assert.ok(await mirrored(phone));
        await assert.rejects(verifyOtpAndSignInCore(deps, { phone, code: REVIEW_CODE === (await codeFor(phone)) ? '000000' : REVIEW_CODE }), {
          code: 'unauthenticated',
        });
      });

      test('the right code signs in; nothing is sent or mirrored', async () => {
        const phone = newPhone();
        const review = resolveReviewLogin(phone, REVIEW_CODE);
        sent.length = 0;
        const result = await sendOtpCore(realSmsDeps(review), { phone }, { ip: '203.0.113.7' });
        assert.deepEqual(result, { expiresInSeconds: EXPIRY_SECONDS, phone: maskPhone(phone) });
        assert.equal(sent.length, 0, 'no OTPIQ call');
        assert.equal(await mirrored(phone), false, 'no otp_debug write');
        const stored = (await codeDoc('login', phone).get()).data()!;
        assert.equal(stored.attempts, 0);
        assert.ok(!JSON.stringify(stored).includes(REVIEW_CODE), 'hashed at rest like any code');

        const { token, isNewUser } = await verifyOtpAndSignInCore({ ...deps, review }, { phone, code: REVIEW_CODE });
        assert.equal(isNewUser, true);
        const { uid } = await auth.getUserByPhoneNumber(phone);
        uids.push(uid);
        assert.equal(jwtPayload(token).uid, uid);
        assert.equal((await codeDoc('login', phone).get()).exists, false, 'burned');
      });

      test('a wrong code counts as an attempt; the limits and lockout still apply', async () => {
        const phone = newPhone();
        const review = resolveReviewLogin(phone, REVIEW_CODE);
        await sendOtpCore(realSmsDeps(review), { phone }, {});
        await assert.rejects(verifyOtpAndSignInCore({ ...deps, review }, { phone, code: '135791' }), {
          code: 'unauthenticated',
          message: INVALID_CODE_MESSAGE,
        });
        assert.equal((await codeDoc('login', phone).get()).data()?.attempts, 1);
        for (let i = 1; i < MAX_ATTEMPTS; i++) {
          await assert.rejects(verifyOtpAndSignInCore({ ...deps, review }, { phone, code: '135791' }), { code: 'unauthenticated' });
        }
        await assert.rejects(verifyOtpAndSignInCore({ ...deps, review }, { phone, code: REVIEW_CODE }), { code: 'resource-exhausted' });
      });

      test('only the configured code: a code minted by the normal flow is refused for that number', async () => {
        const phone = newPhone();
        await send(phone); // before the demo login was switched on
        const normal = await codeFor(phone);
        const review = resolveReviewLogin(phone, normal === REVIEW_CODE ? '864201' : REVIEW_CODE);
        await assert.rejects(verifyOtpAndSignInCore({ ...deps, review }, { phone, code: normal }), { code: 'unauthenticated' });
        assert.equal((await codeDoc('login', phone).get()).data()?.attempts, 1, 'counted');
      });

      test('other numbers are unaffected: a random code, sent through OTPIQ; the demo code does not work there', async () => {
        const phone = newPhone();
        const review = resolveReviewLogin(newPhone(), REVIEW_CODE);
        sent.length = 0;
        await sendOtpCore(realSmsDeps(review), { phone }, {});
        globalCharged++;
        assert.equal(sent.length, 1);
        assert.equal(sent[0].phoneNumber, phone);
        assert.match(sent[0].verificationCode, /^\d{6}$/);
        if (sent[0].verificationCode !== REVIEW_CODE) {
          await assert.rejects(verifyOtpAndSignInCore({ ...deps, review }, { phone, code: REVIEW_CODE }), { code: 'unauthenticated' });
        }
        await verifyOtpAndSignInCore({ ...deps, review }, { phone, code: sent[0].verificationCode });
        uids.push((await auth.getUserByPhoneNumber(phone)).uid);
      });
    });

    test('changePhone: wrong codes count toward the same ceiling', async () => {
      const alice = await login(newPhone());
      const target = newPhone();
      await send(target, 'changePhone', alice.uid);
      const code = await codeFor(target);
      for (let i = 0; i < MAX_ATTEMPTS; i++) {
        await assert.rejects(changePhoneCore(deps, { phone: target, code: wrong(code) }, alice.uid), {
          code: 'unauthenticated',
        });
      }
      await assert.rejects(changePhoneCore(deps, { phone: target, code }, alice.uid), { code: 'resource-exhausted' });
    });
  },
);

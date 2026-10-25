/**
 * The OTP policy — the only thing standing between a phone number and a session.
 * Each test corresponds to an attack the design anticipates. Runs without
 * emulators against an in-memory Firestore (the emulator suite in
 * phoneAuth.test.ts repeats the important ones against the real thing).
 */
import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import { Timestamp, type Firestore } from 'firebase-admin/firestore';
import {
  EXPIRY_SECONDS,
  GLOBAL_DAILY_LIMIT,
  INVALID_CODE_MESSAGE,
  MAX_ATTEMPTS,
  VERIFY_FAILURE_LIMIT,
  generateOtp,
  hashIp,
  isOtpPurpose,
  normalizeCode,
  otpCodeId,
  verifyOtp,
} from '../src/auth/otp';

type Data = Record<string, unknown>;

/**
 * An in-memory Firestore with real documents and transactional read-then-write.
 * A stub that only recorded calls would pass every test here while the attempt
 * counter silently never moved.
 */
function fakeDb() {
  const store = new Map<string, Data>();
  const write = (path: string, data: Data, merge: boolean) =>
    store.set(path, merge ? { ...(store.get(path) ?? {}), ...data } : { ...data });
  const snap = (path: string) => {
    const data = store.get(path);
    return { exists: data !== undefined, data: () => (data ? { ...data } : undefined), get: (f: string) => data?.[f] };
  };
  const ref = (path: string) => ({
    path,
    set: async (data: Data, opts?: { merge?: boolean }) => write(path, data, opts?.merge === true),
  });
  const db = {
    collection: (name: string) => ({ doc: (id: string) => ref(`${name}/${id}`) }),
    runTransaction: async <T>(fn: (tx: unknown) => Promise<T>): Promise<T> =>
      fn({
        get: async (r: { path: string }) => snap(r.path),
        getAll: async (...refs: Array<{ path: string }>) => refs.map((r) => snap(r.path)),
        set: (r: { path: string }, data: Data, opts?: { merge?: boolean }) => write(r.path, data, opts?.merge === true),
        update: (r: { path: string }, data: Data) => {
          if (!store.has(r.path)) throw new Error(`NOT_FOUND: ${r.path}`);
          write(r.path, data, true);
        },
        delete: (r: { path: string }) => store.delete(r.path),
      }),
  };
  return { db: db as unknown as Firestore, store };
}

const PHONE = '+9647501234567';
const KEY = 'otp_codes/login:9647501234567';
const CHANGE_KEY = 'otp_codes/changePhone:9647501234567';
const today = () => new Date().toISOString().slice(0, 10);

let ctx: ReturnType<typeof fakeDb>;
beforeEach(() => {
  ctx = fakeDb();
});

const invalid = { code: 'unauthenticated', message: INVALID_CODE_MESSAGE };
const exhausted = { code: 'resource-exhausted' };

describe('generateOtp', () => {
  test('mints six digits', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    assert.match(code, /^\d{6}$/);
  });

  test('stores one code doc at otp_codes/{purpose}:{phoneDigits}', async () => {
    assert.equal(otpCodeId('login', PHONE), 'login:9647501234567');
    await generateOtp(ctx.db, PHONE, 'login');
    await generateOtp(ctx.db, PHONE, 'login');
    const codeDocs = [...ctx.store.keys()].filter((k) => k.startsWith('otp_codes/'));
    assert.deepEqual(codeDocs, [KEY]);
    const doc = ctx.store.get(KEY)!;
    assert.equal(doc.phone, PHONE);
    assert.equal(doc.purpose, 'login');
    assert.equal(doc.attempts, 0);
    assert.equal('uid' in doc, false);
  });

  test('never stores the code itself — anywhere', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login', { ipHash: hashIp('10.0.0.1') });
    // The whole database is searched, not just the field we expect it in.
    assert.ok(!JSON.stringify([...ctx.store.entries()]).includes(code));
    assert.match(ctx.store.get(KEY)!.hash as string, /^[0-9a-f]{32}:[0-9a-f]{64}$/);
  });

  test('salts, so two identical codes never share a hash', async () => {
    const hashes = new Set<string>();
    for (let i = 0; i < 4; i++) {
      ctx = fakeDb();
      await generateOtp(ctx.db, PHONE, 'login');
      hashes.add(ctx.store.get(KEY)!.hash as string);
    }
    assert.equal(hashes.size, 4);
  });

  test('expires in five minutes', async () => {
    const before = Date.now();
    const { expiresInSeconds } = await generateOtp(ctx.db, PHONE, 'login');
    assert.equal(expiresInSeconds, EXPIRY_SECONDS);
    assert.equal(EXPIRY_SECONDS, 300);
    const expiresAt = (ctx.store.get(KEY)!.expiresAt as Timestamp).toMillis();
    assert.ok(expiresAt >= before + 300_000 && expiresAt <= Date.now() + 300_000);
  });

  test('replaces the outstanding code — an intercepted one must not stay usable', async () => {
    const first = await generateOtp(ctx.db, PHONE, 'login');
    const second = await generateOtp(ctx.db, PHONE, 'login');
    if (first.code !== second.code) await assert.rejects(verifyOtp(ctx.db, PHONE, first.code, 'login'), invalid);
    await verifyOtp(ctx.db, PHONE, second.code, 'login');
  });

  test('allows four codes per phone in thirty minutes, and refuses the fifth', async () => {
    for (let i = 0; i < 4; i++) await generateOtp(ctx.db, PHONE, 'login');
    await assert.rejects(generateOtp(ctx.db, PHONE, 'login'), { code: 'resource-exhausted', message: /Too many codes/ });
  });

  test('the per-phone window counts every purpose', async () => {
    for (let i = 0; i < 2; i++) await generateOtp(ctx.db, PHONE, 'login');
    for (let i = 0; i < 2; i++) await generateOtp(ctx.db, PHONE, 'changePhone', { uid: 'u1' });
    await assert.rejects(generateOtp(ctx.db, PHONE, 'changePhone', { uid: 'u1' }), exhausted);
  });

  test('the window rolls: hits older than thirty minutes no longer count', async () => {
    for (let i = 0; i < 4; i++) await generateOtp(ctx.db, PHONE, 'login');
    const throttle = ctx.store.get('otp_throttle/phone:9647501234567')!;
    throttle.hits = (throttle.hits as number[]).map(() => Date.now() - 30 * 60_000 - 1);
    await generateOtp(ctx.db, PHONE, 'login');
    assert.equal((ctx.store.get('otp_throttle/phone:9647501234567')!.hits as number[]).length, 1, 'pruned');
  });

  test('counts one phone per bucket — a second number is unaffected', async () => {
    for (let i = 0; i < 4; i++) await generateOtp(ctx.db, PHONE, 'login');
    await generateOtp(ctx.db, '+9647709998877', 'login');
  });

  test('limits one device across many numbers, which is the number-walking attack', async () => {
    const ip = hashIp('192.0.2.7');
    for (let i = 0; i < 10; i++) {
      await generateOtp(ctx.db, `+96477000000${String(i).padStart(2, '0')}`, 'login', { ipHash: ip });
    }
    await assert.rejects(generateOtp(ctx.db, '+9647709998877', 'login', { ipHash: ip }), {
      code: 'resource-exhausted',
      message: /this device/,
    });
    await generateOtp(ctx.db, '+9647709998877', 'login', { ipHash: hashIp('192.0.2.8') });
    assert.ok(![...ctx.store.keys()].some((k) => k.includes('192.0.2')), 'IPs are stored hashed');
  });

  test('a global daily ceiling stops everything, and nothing is minted', async () => {
    ctx.store.set(`otp_throttle/global:${today()}`, { sent: GLOBAL_DAILY_LIMIT, day: today() });
    await assert.rejects(generateOtp(ctx.db, PHONE, 'login'), {
      code: 'resource-exhausted',
      message: /temporarily unavailable/,
    });
    assert.equal(ctx.store.has(KEY), false);
  });

  test('the global ceiling counts each code', async () => {
    await generateOtp(ctx.db, PHONE, 'login');
    await generateOtp(ctx.db, '+9647709998877', 'login');
    assert.equal(ctx.store.get(`otp_throttle/global:${today()}`)!.sent, 2);
  });

  test('beforeIssue runs after the phone/IP limits and before the ceiling is charged', async () => {
    const ip = hashIp('192.0.2.9');
    const refusal = Object.assign(new Error('taken'), { code: 'already-exists' });
    await assert.rejects(
      generateOtp(ctx.db, PHONE, 'changePhone', { uid: 'u1', ipHash: ip, beforeIssue: async () => Promise.reject(refusal) }),
      refusal,
    );
    assert.equal(ctx.store.has(CHANGE_KEY), false, 'no code minted');
    assert.equal(ctx.store.has(`otp_throttle/global:${today()}`), false, 'no money spent');
    assert.equal((ctx.store.get('otp_throttle/phone:9647501234567')!.hits as number[]).length, 1, 'still rate-limited');
    assert.equal((ctx.store.get(`otp_throttle/ip:${ip}`)!.hits as number[]).length, 1, 'still rate-limited');

    // ...so it cannot be used as an unlimited "who owns this number" oracle.
    for (let i = 0; i < 3; i++) {
      await assert.rejects(generateOtp(ctx.db, PHONE, 'changePhone', { beforeIssue: async () => Promise.reject(refusal) }));
    }
    let ran = false;
    await assert.rejects(
      generateOtp(ctx.db, PHONE, 'changePhone', { beforeIssue: async () => void (ran = true) }),
      exhausted,
    );
    assert.equal(ran, false);
  });

  test('changePhone codes remember the uid that asked', async () => {
    await generateOtp(ctx.db, PHONE, 'changePhone', { uid: 'u1' });
    assert.equal(ctx.store.get(CHANGE_KEY)!.uid, 'u1');
  });
});

describe('verifyOtp', () => {
  test('accepts the right code and burns it, so it cannot be replayed', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    await verifyOtp(ctx.db, PHONE, code, 'login');
    assert.equal(ctx.store.has(KEY), false);
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'login'), invalid);
  });

  test('counts a wrong guess', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    await assert.rejects(verifyOtp(ctx.db, PHONE, wrong(code), 'login'), invalid);
    assert.equal(ctx.store.get(KEY)!.attempts, 1);
  });

  test('stops after five wrong guesses, and stays stopped for the right one', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    for (let i = 0; i < MAX_ATTEMPTS; i++) {
      await assert.rejects(verifyOtp(ctx.db, PHONE, wrong(code), 'login'), invalid);
    }
    // The correct code no longer helps: a million possibilities, five guesses per code.
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'login'), { code: 'resource-exhausted', message: /Too many wrong codes/ });
    assert.equal(ctx.store.get(KEY)!.attempts, MAX_ATTEMPTS);
  });

  test('a daily ceiling of wrong codes per number: after it even the right code is refused', async () => {
    assert.equal(VERIFY_FAILURE_LIMIT.count, 15);
    for (let round = 0; round < VERIFY_FAILURE_LIMIT.count / MAX_ATTEMPTS; round++) {
      const { code } = await generateOtp(ctx.db, PHONE, 'login');
      for (let i = 0; i < MAX_ATTEMPTS; i++) await assert.rejects(verifyOtp(ctx.db, PHONE, wrong(code), 'login'), invalid);
    }
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'login'), { code: 'resource-exhausted', message: /try again tomorrow/ });
    assert.equal(ctx.store.get(KEY)!.attempts, 0, 'a locked number is not probed');
    // Another number is unaffected, and the window rolls after a day.
    const other = await generateOtp(ctx.db, '+9647709998877', 'login');
    await verifyOtp(ctx.db, '+9647709998877', other.code, 'login');
    const fails = ctx.store.get('otp_throttle/verifyFail:9647501234567')!;
    fails.hits = (fails.hits as number[]).map((t) => t - VERIFY_FAILURE_LIMIT.windowMs);
    await verifyOtp(ctx.db, PHONE, code, 'login');
  });

  test('wrong codes for a missing code or a foreign changePhone code never count toward the ceiling', async () => {
    for (let i = 0; i < VERIFY_FAILURE_LIMIT.count + 2; i++) {
      await assert.rejects(verifyOtp(ctx.db, PHONE, '000000', 'login'), invalid);
    }
    assert.equal(ctx.store.has('otp_throttle/verifyFail:9647501234567'), false);
  });

  test('refuses an expired code', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    ctx.store.get(KEY)!.expiresAt = Timestamp.fromMillis(Date.now() - 1);
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'login'), invalid);
  });

  test('says the same thing for a wrong code and a number with no code at all', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    const wrongCode = await verifyOtp(ctx.db, PHONE, wrong(code), 'login').catch((e) => e);
    const absent = await verifyOtp(ctx.db, '+9647709998877', '000000', 'login').catch((e) => e);
    // Distinguishing them would enumerate which numbers have a login in flight.
    assert.equal(wrongCode.code, absent.code);
    assert.equal(wrongCode.message, absent.message);
  });

  test('keeps purposes apart — a login code cannot change a phone', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'login');
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'changePhone', 'u1'), invalid);
  });

  test('is not fooled by a code of the wrong shape', async () => {
    await generateOtp(ctx.db, PHONE, 'login');
    for (const bad of ['', '12345', '1234567', 'abcdef']) {
      await assert.rejects(verifyOtp(ctx.db, PHONE, bad, 'login'), invalid);
    }
  });

  test("changePhone: another uid is refused like a wrong code, without spending the owner's attempts", async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'changePhone', { uid: 'owner' });
    const foreign = await verifyOtp(ctx.db, PHONE, code, 'changePhone', 'intruder').catch((e) => e);
    const wrongCode = await verifyOtp(ctx.db, PHONE, wrong(code), 'changePhone', 'owner').catch((e) => e);
    assert.equal(foreign.code, wrongCode.code);
    assert.equal(foreign.message, wrongCode.message);
    assert.equal(ctx.store.get(CHANGE_KEY)!.attempts, 1, 'only the owner’s wrong guess counted');
    await verifyOtp(ctx.db, PHONE, code, 'changePhone', 'owner');
    assert.equal(ctx.store.has(CHANGE_KEY), false);
  });

  test('changePhone: a code without a stored uid is never accepted', async () => {
    const { code } = await generateOtp(ctx.db, PHONE, 'changePhone');
    await assert.rejects(verifyOtp(ctx.db, PHONE, code, 'changePhone', 'u1'), invalid);
  });
});

describe('helpers', () => {
  test('normalizeCode', () => {
    assert.equal(normalizeCode('123456'), '123456');
    assert.equal(normalizeCode(' 123 456 '), '123456');
    assert.equal(normalizeCode('١٢٣٤٥٦'), '123456');
    assert.equal(normalizeCode('۱۲۳۴۵۶'), '123456');
    for (const bad of ['12345', '1234567', 'abcdef', '', null, undefined, 123456]) {
      assert.equal(normalizeCode(bad), null, String(bad));
    }
  });

  test('hashIp: stable, 32 hex chars, null without an IP', () => {
    assert.match(hashIp('203.0.113.5')!, /^[0-9a-f]{32}$/);
    assert.equal(hashIp('203.0.113.5'), hashIp('203.0.113.5'));
    assert.notEqual(hashIp('203.0.113.5'), hashIp('203.0.113.6'));
    assert.equal(hashIp(undefined), null);
    assert.equal(hashIp(''), null);
  });

  test('isOtpPurpose', () => {
    assert.equal(isOtpPurpose('login'), true);
    assert.equal(isOtpPurpose('changePhone'), true);
    for (const bad of ['verify-phone', 'LOGIN', '', null, 1]) assert.equal(isOtpPurpose(bad), false);
  });
});

/** A six-digit code guaranteed to differ from `code`. */
function wrong(code: string): string {
  return code === '000000' ? '111111' : '000000';
}

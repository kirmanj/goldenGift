/**
 * Which driver delivers, and what the OTPIQ driver sends. `fetch` is always a
 * stub here: no test ever reaches api.otpiq.com, and the key is a fake.
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import type { Firestore } from 'firebase-admin/firestore';
import type { Auth } from 'firebase-admin/auth';
import {
  MessagingError,
  OTPIQ_ENDPOINT,
  mirrorCodeToDebug,
  selectDriver,
  sendVerificationCode,
} from '../src/auth/messaging';
import { sendOtpCore } from '../src/auth/sendOtp';

const FAKE_KEY = 'test-key-not-real';
const PHONE = '+9647501234567';

interface Call {
  url: string;
  init: RequestInit;
}

/** A `fetch` that records calls and answers with `respond` — never the network. */
function stubFetch(respond: (call: Call) => Promise<Response> | Response = () => new Response('{}', { status: 200 })) {
  const calls: Call[] = [];
  const fetchImpl = (async (url: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(url), init: init ?? {} };
    calls.push(call);
    return respond(call);
  }) as typeof fetch;
  return { calls, fetchImpl };
}

describe('selectDriver', () => {
  test('emulator: log driver even when the live key is loaded from .secret.local', () => {
    assert.deepEqual(selectDriver(FAKE_KEY, { FUNCTIONS_EMULATOR: 'true' }), { driver: 'log', mirrorToDebug: true });
  });

  test('emulator: anything but exactly OTP_REAL_SMS=true keeps the log driver', () => {
    for (const OTP_REAL_SMS of [undefined, '', 'false', '1', 'TRUE', 'yes']) {
      assert.equal(selectDriver(FAKE_KEY, { FUNCTIONS_EMULATOR: 'true', OTP_REAL_SMS }).driver, 'log', String(OTP_REAL_SMS));
    }
  });

  test('emulator + OTP_REAL_SMS=true: otpiq (deliberate manual real-delivery test), no debug mirror', () => {
    assert.deepEqual(selectDriver(FAKE_KEY, { FUNCTIONS_EMULATOR: 'true', OTP_REAL_SMS: 'true' }), {
      driver: 'otpiq',
      mirrorToDebug: false,
    });
  });

  test('emulator + OTP_REAL_SMS=true without a key: log', () => {
    assert.equal(selectDriver(undefined, { FUNCTIONS_EMULATOR: 'true', OTP_REAL_SMS: 'true' }).driver, 'log');
  });

  test('deployed with a key: otpiq', () => {
    assert.deepEqual(selectDriver(FAKE_KEY, {}), { driver: 'otpiq', mirrorToDebug: false });
    assert.equal(selectDriver(FAKE_KEY, { FUNCTIONS_EMULATOR: 'false' }).driver, 'otpiq');
  });

  test('deployed without a key: none (codes refused, never logged), and never the debug mirror', () => {
    for (const key of [undefined, '', '   ']) {
      assert.deepEqual(selectDriver(key, {}), { driver: 'none', mirrorToDebug: false });
    }
  });

  test('OTP_REAL_SMS means nothing outside the emulator', () => {
    assert.deepEqual(selectDriver(undefined, { OTP_REAL_SMS: 'true' }), { driver: 'none', mirrorToDebug: false });
  });
});

describe('sendOtp without a messaging key (deployed)', () => {
  test('answers unavailable before anything is minted, charged or logged', async () => {
    // Any Firestore / Auth access would throw: nothing may be touched.
    const untouchable = new Proxy({}, { get: () => { throw new Error('touched'); } });
    await assert.rejects(
      sendOtpCore(
        { db: untouchable as Firestore, auth: untouchable as Auth, apiKey: undefined, env: {} },
        { phone: '0750 123 4567' },
        { ip: '1.2.3.4' },
      ),
      { code: 'unavailable' },
    );
  });
});

describe('sendVerificationCode', () => {
  test('otpiq: one POST with the documented request shape', async () => {
    const { calls, fetchImpl } = stubFetch();
    await sendVerificationCode('otpiq', FAKE_KEY, PHONE, '123456', fetchImpl);

    assert.equal(calls.length, 1);
    const [{ url, init }] = calls;
    assert.equal(url, OTPIQ_ENDPOINT);
    assert.equal(url, 'https://api.otpiq.com/api/sms');
    assert.equal(init.method, 'POST');
    assert.deepEqual(init.headers, {
      Authorization: `Bearer ${FAKE_KEY}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    });
    assert.deepEqual(JSON.parse(init.body as string), {
      phoneNumber: PHONE,
      smsType: 'verification',
      verificationCode: '123456',
      provider: 'whatsapp-sms',
    });
    assert.ok(init.signal instanceof AbortSignal, 'has a timeout');
  });

  test('log driver never touches the network, even with a key', async () => {
    const { calls, fetchImpl } = stubFetch();
    await sendVerificationCode('log', FAKE_KEY, PHONE, '123456', fetchImpl);
    assert.equal(calls.length, 0);
  });

  test('otpiq without a key, or the none driver: a MessagingError, no network — never a fallback that logs the code', async () => {
    const { calls, fetchImpl } = stubFetch();
    await assert.rejects(sendVerificationCode('otpiq', undefined, PHONE, '123456', fetchImpl), MessagingError);
    await assert.rejects(sendVerificationCode('none', FAKE_KEY, PHONE, '123456', fetchImpl), (e: unknown) => {
      assert.ok(e instanceof MessagingError);
      assert.ok(!e.message.includes('123456'), 'never the code');
      return true;
    });
    assert.equal(calls.length, 0);
  });

  test('a refusal from OTPIQ is a MessagingError', async () => {
    const { fetchImpl } = stubFetch(() => new Response('{"message":"invalid number"}', { status: 400 }));
    await assert.rejects(sendVerificationCode('otpiq', FAKE_KEY, PHONE, '123456', fetchImpl), (e: unknown) => {
      assert.ok(e instanceof MessagingError);
      assert.match(e.message, /Delivery failed \(400\)/);
      assert.ok(!e.message.includes('123456'), 'never the code');
      return true;
    });
  });

  test('a network failure is a MessagingError', async () => {
    const { fetchImpl } = stubFetch(() => Promise.reject(new TypeError('fetch failed')));
    await assert.rejects(sendVerificationCode('otpiq', FAKE_KEY, PHONE, '123456', fetchImpl), (e: unknown) => {
      assert.ok(e instanceof MessagingError);
      assert.match(e.message, /fetch failed/);
      return true;
    });
  });

  test('a timeout is a MessagingError', async () => {
    const abort = Object.assign(new Error('aborted'), { name: 'AbortError' });
    const { fetchImpl } = stubFetch(() => Promise.reject(abort));
    await assert.rejects(sendVerificationCode('otpiq', FAKE_KEY, PHONE, '123456', fetchImpl), {
      message: /timed out/,
    });
  });
});

describe('mirrorCodeToDebug', () => {
  /** A db that fails the test if anything is written. */
  const untouchable = {
    collection: () => assert.fail('must not write'),
  } as unknown as Firestore;

  test('never for the otpiq driver or without the emulator choice', async () => {
    assert.equal(await mirrorCodeToDebug(untouchable, { driver: 'otpiq', mirrorToDebug: true }, PHONE, '1', 'login'), false);
    assert.equal(await mirrorCodeToDebug(untouchable, { driver: 'log', mirrorToDebug: false }, PHONE, '1', 'login'), false);
  });

  test('never unless the Admin SDK points at the Firestore emulator', async () => {
    const saved = process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.FIRESTORE_EMULATOR_HOST;
    try {
      assert.equal(await mirrorCodeToDebug(untouchable, { driver: 'log', mirrorToDebug: true }, PHONE, '1', 'login'), false);
    } finally {
      if (saved !== undefined) process.env.FIRESTORE_EMULATOR_HOST = saved;
    }
  });
});

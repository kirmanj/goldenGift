/**
 * ZainCash client, HS256 JWTs and the return page — pure (fake fetch), plus one
 * OPTIONAL live call against ZainCash's sandbox (test.zaincash.iq, public test
 * merchant, no money moves), skipped unless ZAINCASH_LIVE=1.
 */
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { describe, test } from 'node:test';
import { JwtError, signHs256, verifyHs256 } from '../src/payments/jwt';
import {
  GatewayError,
  GatewayTokenError,
  ZAINCASH_HOSTS,
  ZAINCASH_PUBLIC_TEST_MERCHANT,
  resolveZainCashConfig,
  zainCashGateway,
  zainCashOutcome,
  type FetchLike,
  type ZainCashConfig,
} from '../src/payments/zainCash';
import { appDeepLink, parseReturnQuery, returnPage } from '../src/payments/zainCashReturn';

const SECRET = 'test-secret-0123456789';
const NOW = Date.UTC(2026, 9, 21, 9, 0);
const NOW_SEC = Math.floor(NOW / 1000);

const config: ZainCashConfig = {
  env: 'test',
  host: ZAINCASH_HOSTS.test,
  merchantId: 'merchant-1',
  msisdn: '9647835077893',
  secret: SECRET,
  publicTestMerchant: false,
};

/** A fake fetch that records requests and answers `reply(url, form)`. */
function fakeFetch(reply: (url: string, form: URLSearchParams) => { status?: number; body: unknown }) {
  const calls: Array<{ url: string; form: URLSearchParams; headers: Record<string, string> }> = [];
  const fetch: FetchLike = async (url, init) => {
    const form = new URLSearchParams(init.body);
    calls.push({ url, form, headers: init.headers });
    const r = reply(url, form);
    const status = r.status ?? 200;
    return { ok: status >= 200 && status < 300, status, text: async () => (typeof r.body === 'string' ? r.body : JSON.stringify(r.body)) };
  };
  return { fetch, calls };
}

describe('HS256 JWT', () => {
  test('sign → verify round trip, standard header', () => {
    const token = signHs256({ a: 1, exp: NOW_SEC + 60 }, SECRET);
    const [h] = token.split('.');
    assert.deepEqual(JSON.parse(Buffer.from(h, 'base64url').toString()), { alg: 'HS256', typ: 'JWT' });
    assert.deepEqual(verifyHs256(token, SECRET, { nowSec: NOW_SEC }), { a: 1, exp: NOW_SEC + 60 });
  });

  test('matches an independent HMAC-SHA256 signature', () => {
    const token = signHs256({ status: 'success' }, SECRET);
    const [h, p, s] = token.split('.');
    assert.equal(s, createHmac('sha256', SECRET).update(`${h}.${p}`).digest('base64url'));
  });

  test('refuses a wrong secret, a tampered payload, alg none and garbage', () => {
    const token = signHs256({ status: 'failed', orderid: 's1', id: 't1' }, SECRET);
    const reason = (fn: () => unknown) => {
      try {
        fn();
      } catch (e) {
        assert.ok(e instanceof JwtError, String(e));
        return e.reason;
      }
      return 'accepted';
    };
    assert.equal(reason(() => verifyHs256(token, 'other-secret')), 'signature');
    const [h, , s] = token.split('.');
    const forged = Buffer.from(JSON.stringify({ status: 'success', orderid: 's1', id: 't1' })).toString('base64url');
    assert.equal(reason(() => verifyHs256(`${h}.${forged}.${s}`, SECRET)), 'signature');
    const none = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    assert.equal(reason(() => verifyHs256(`${none}.${forged}.${s}`, SECRET)), 'algorithm');
    assert.equal(reason(() => verifyHs256('a.b', SECRET)), 'malformed');
    assert.equal(reason(() => verifyHs256('!!.??.**', SECRET)), 'malformed');
  });

  test('expiry with leeway; not-before', () => {
    const token = signHs256({ exp: NOW_SEC }, SECRET);
    assert.ok(verifyHs256(token, SECRET, { nowSec: NOW_SEC + 100 }));
    assert.throws(() => verifyHs256(token, SECRET, { nowSec: NOW_SEC + 121 }), (e: unknown) => e instanceof JwtError && e.reason === 'expired');
    const later = signHs256({ nbf: NOW_SEC + 1000 }, SECRET);
    assert.throws(() => verifyHs256(later, SECRET, { nowSec: NOW_SEC }), (e: unknown) => e instanceof JwtError && e.reason === 'not_yet_valid');
  });
});

describe('resolveZainCashConfig', () => {
  test('test env without a merchant id → the public sandbox merchant (docs.zaincash.iq)', () => {
    const r = resolveZainCashConfig({ env: 'test', merchantId: '', msisdn: '', secret: '' });
    assert.ok(r.config);
    assert.equal(r.config.host, 'https://test.zaincash.iq');
    assert.equal(r.config.merchantId, ZAINCASH_PUBLIC_TEST_MERCHANT.merchantId);
    assert.equal(r.config.publicTestMerchant, true);
    // Unknown / empty env = test; the secret is ignored for the public merchant.
    assert.equal(resolveZainCashConfig({ secret: 'placeholder' }).config?.secret, ZAINCASH_PUBLIC_TEST_MERCHANT.secret);
  });

  test('prod needs merchant id, wallet number and secret', () => {
    assert.equal(resolveZainCashConfig({ env: 'prod' }).config, null);
    assert.equal(resolveZainCashConfig({ env: 'prod', merchantId: 'm' }).config, null);
    assert.equal(resolveZainCashConfig({ env: 'prod', merchantId: 'm', msisdn: '9647' }).config, null);
    const r = resolveZainCashConfig({ env: 'PROD', merchantId: ' m ', msisdn: '+964 780 000 0000', secret: 's' });
    assert.deepEqual(r.config, {
      env: 'prod',
      host: 'https://api.zaincash.iq',
      merchantId: 'm',
      msisdn: '9647800000000',
      secret: 's',
      publicTestMerchant: false,
    });
  });

  test('own merchant on the test host', () => {
    const r = resolveZainCashConfig({ env: 'test', merchantId: 'm', msisdn: '9647', secret: 's' });
    assert.equal(r.config?.host, ZAINCASH_HOSTS.test);
    assert.equal(r.config?.publicTestMerchant, false);
  });
});

describe('zainCashGateway', () => {
  test('createTransaction: signed token with the documented fields, form POST to /transaction/init', async () => {
    const { fetch, calls } = fakeFetch(() => ({ body: { id: 'txn-42', status: 'pending' } }));
    const gw = zainCashGateway(config, { fetch });
    const out = await gw.createTransaction(
      { reference: 'sess-1', amount: 25000, serviceType: 'Golden Gift order GG-2610-00001', redirectUrl: 'https://x/zainCashReturn?sid=sess-1', lang: 'ku', expiresAtMs: NOW + 30 * 60 * 1000 },
      NOW,
    );
    assert.deepEqual(out, { transactionId: 'txn-42', payUrl: 'https://test.zaincash.iq/transaction/pay?id=txn-42' });
    assert.equal(calls.length, 1);
    assert.equal(calls[0].url, 'https://test.zaincash.iq/transaction/init');
    assert.equal(calls[0].headers['Content-Type'], 'application/x-www-form-urlencoded');
    assert.equal(calls[0].form.get('merchantId'), 'merchant-1');
    assert.equal(calls[0].form.get('lang'), 'ku');
    const token = calls[0].form.get('token')!;
    assert.deepEqual(verifyHs256(token, SECRET, { nowSec: NOW_SEC }), {
      amount: 25000,
      serviceType: 'Golden Gift order GG-2610-00001',
      msisdn: 9647835077893,
      orderId: 'sess-1',
      redirectUrl: 'https://x/zainCashReturn?sid=sess-1',
      iat: NOW_SEC,
      exp: NOW_SEC + 1800,
    });
  });

  test('createTransaction: `{ err: { msg } }`, HTTP errors and non-JSON become GatewayError', async () => {
    for (const reply of [
      { body: { err: { msg: 'Invalid merchant id' } } },
      { status: 500, body: { message: 'boom' } },
      { body: '<html>oops</html>' },
      { body: { status: 'pending' } },
    ]) {
      const gw = zainCashGateway(config, { fetch: fakeFetch(() => reply).fetch });
      await assert.rejects(
        gw.createTransaction({ reference: 's', amount: 5000, serviceType: 'x', redirectUrl: 'https://x', lang: 'en', expiresAtMs: NOW + 60000 }, NOW),
        GatewayError,
      );
    }
  });

  test('verifyReturn: statuses mapped; tampered / foreign tokens refused', () => {
    const gw = zainCashGateway(config);
    const token = (claims: Record<string, unknown>, secret = SECRET) => signHs256({ iat: NOW_SEC, exp: NOW_SEC + 3600, ...claims }, secret);
    assert.deepEqual(gw.verifyReturn(token({ status: 'success', orderid: 'sess-1', id: 'txn-42' }), NOW), {
      outcome: 'paid',
      transactionId: 'txn-42',
      reference: 'sess-1',
      rawStatus: 'success',
      message: null,
    });
    assert.equal(gw.verifyReturn(token({ status: 'completed', orderid: 's', id: 't' }), NOW).outcome, 'paid');
    const failed = gw.verifyReturn(token({ status: 'failed', msg: 'Invalid credentials for requester', orderid: 's', id: 't' }), NOW);
    assert.deepEqual([failed.outcome, failed.message], ['failed', 'Invalid credentials for requester']);
    assert.equal(gw.verifyReturn(token({ status: 'pending', orderId: 's', id: 't' }), NOW).outcome, 'pending');

    const refused = (t: string) => assert.throws(() => gw.verifyReturn(t, NOW), GatewayTokenError);
    refused(token({ status: 'success', orderid: 's', id: 't' }, 'attacker-secret'));
    refused(token({ status: 'success', id: 't' })); // no orderid
    refused(token({ status: 'success', orderid: 's' })); // no id
    refused(signHs256({ status: 'success', orderid: 's', id: 't', exp: NOW_SEC - 3600 }, SECRET)); // expired
    refused('not-a-token');
  });

  test('checkTransaction: POST /transaction/get with {id, msisdn} token', async () => {
    const { fetch, calls } = fakeFetch(() => ({ body: { status: 'completed', amount: '25000', orderId: 'sess-1', id: 'txn-42' } }));
    const status = await zainCashGateway(config, { fetch }).checkTransaction('txn-42', NOW);
    assert.deepEqual(status, { outcome: 'paid', rawStatus: 'completed', amount: 25000, reference: 'sess-1' });
    assert.equal(calls[0].url, 'https://test.zaincash.iq/transaction/get');
    const claims = verifyHs256(calls[0].form.get('token')!, SECRET, { nowSec: NOW_SEC });
    assert.equal(claims.id, 'txn-42');
    assert.equal(claims.msisdn, 9647835077893);
    assert.equal(calls[0].form.get('merchantId'), 'merchant-1');
  });

  test('zainCashOutcome: unknown statuses are pending (never cancel on a guess)', () => {
    assert.equal(zainCashOutcome('success'), 'paid');
    assert.equal(zainCashOutcome('COMPLETED'), 'paid');
    assert.equal(zainCashOutcome('failed'), 'failed');
    assert.equal(zainCashOutcome('cancel'), 'failed');
    assert.equal(zainCashOutcome('pending_otp'), 'pending');
    assert.equal(zainCashOutcome('weird'), 'pending');
    assert.equal(zainCashOutcome(undefined), 'pending');
  });
});

describe('zainCashReturn query and page', () => {
  test('sid + token, also when ZainCash appended `?token=` to a URL that had `?sid=`', () => {
    assert.deepEqual(parseReturnQuery({ sid: 'abc', token: 'x.y.z' }), { sid: 'abc', token: 'x.y.z' });
    assert.deepEqual(parseReturnQuery({ sid: 'abc?token=x.y.z' }), { sid: 'abc', token: 'x.y.z' });
    assert.deepEqual(parseReturnQuery({ sid: ['abc', 'def'] }), { sid: 'abc', token: null });
    assert.deepEqual(parseReturnQuery({ sid: '../etc', token: '' }), { sid: null, token: null });
    assert.deepEqual(parseReturnQuery({}), { sid: null, token: null });
  });

  test('the page deep-links back to the app, escaped, in three languages', () => {
    assert.equal(appDeepLink('s1', 'paid'), 'goldengift://payment?sid=s1&status=paid');
    assert.equal(appDeepLink(null, 'error'), 'goldengift://payment?status=error');
    const html = returnPage('s1', 'failed');
    assert.ok(html.includes('href="goldengift://payment?sid=s1&amp;status=failed"'));
    assert.ok(html.includes('location.href="goldengift://payment?sid=s1&status=failed"'));
    assert.ok(html.includes('Payment failed'));
    assert.ok(html.includes('فشلت عملية الدفع'));
    assert.ok(html.includes('پارەدان سەرنەکەوت'));
    assert.ok(html.includes('dir="rtl" lang="ckb"'));
  });
});

/**
 * ZAINCASH_LIVE=1: creates a real SANDBOX transaction with the public test
 * merchant and reads it back (pending — paying it needs the test customer on the
 * pay page in a browser; open the printed URL to try a full payment).
 */
describe('ZainCash sandbox (live)', { skip: process.env.ZAINCASH_LIVE === '1' ? false : 'set ZAINCASH_LIVE=1' }, () => {
  test('init + get against test.zaincash.iq', async () => {
    const live = resolveZainCashConfig({ env: 'test' }).config!;
    const gw = zainCashGateway(live);
    const now = Date.now();
    const created = await gw.createTransaction(
      { reference: `gg-live-${now}`, amount: 1000, serviceType: 'Golden Gift sandbox test', redirectUrl: 'https://example.com/zainCashReturn?sid=live', lang: 'en', expiresAtMs: now + 30 * 60 * 1000 },
      now,
    );
    assert.match(created.transactionId, /^[0-9a-f]{24}$/);
    assert.ok(created.payUrl.startsWith('https://test.zaincash.iq/transaction/pay?id='));
    const status = await gw.checkTransaction(created.transactionId, now);
    assert.equal(status.outcome, 'pending');
    assert.equal(status.amount, 1000);
    console.log(`ZainCash sandbox pay page: ${created.payUrl}`);
  });
});

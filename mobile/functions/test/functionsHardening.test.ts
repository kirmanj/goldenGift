/**
 * Static guards for the Phase 10 hardening of the Cloud Functions (SRS §7, §8):
 * every callable passes the App Check switch, only the two reviewed HTTPS
 * endpoints exist, heavy SDKs stay lazy (cold starts), and the shared input
 * helpers behave. Pure — no emulator.
 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { recentHits } from '../src/shared/rateLimit';
import { isOwnUploadUrl, parseStorageUrl } from '../src/shared/storageUrls';

const SRC = path.resolve(__dirname, '../src');
const index = readFileSync(path.join(SRC, 'index.ts'), 'utf8');

function sources(dir = SRC): string[] {
  return readdirSync(dir).flatMap((e) => {
    const full = path.join(dir, e);
    return statSync(full).isDirectory() ? sources(full) : full.endsWith('.ts') ? [full] : [];
  });
}

describe('index.ts', () => {
  // The options object may follow a comment line.
  const callables = [...index.matchAll(/export const (\w+) = onCall\(\s*(?:\/\/[^\n]*\n\s*)*(\{[^}]*\})/g)];

  test('every callable passes enforceAppCheck: ENFORCE_APP_CHECK', () => {
    const all = [...index.matchAll(/export const (\w+) = onCall\(/g)].map((m) => m[1]);
    assert.ok(all.length >= 23, `found ${all.length} callables`);
    assert.deepEqual(callables.map((m) => m[1]), all, 'every onCall starts with an options object');
    for (const [, name, options] of callables) {
      assert.match(options, /enforceAppCheck: ENFORCE_APP_CHECK/, `${name} does not pass the App Check switch`);
    }
  });

  test('the only HTTPS (non-callable) endpoints are the reviewed ones', () => {
    const endpoints = [...index.matchAll(/export const (\w+) = onRequest\(/g)].map((m) => m[1]).sort();
    assert.deepEqual(endpoints, ['health', 'zainCashReturn']);
    // Both refuse every method but GET / HEAD.
    assert.match(index, /req\.method !== 'GET' && req\.method !== 'HEAD'/);
    assert.match(index, /if \(req\.method !== 'GET'\) \{\s*res\.status\(405\)/);
  });

  test('the checkout callables take their warm instances from CHECKOUT_MIN_INSTANCES', () => {
    for (const name of ['placeOrder', 'createPaymentSession']) {
      const options = callables.find((m) => m[1] === name)?.[2] ?? '';
      assert.match(options, /minInstances: CHECKOUT_MIN_INSTANCES/, name);
    }
  });
});

describe('cold starts', () => {
  test('heavy SDKs are only loaded inside the functions that use them', () => {
    for (const file of sources()) {
      const src = readFileSync(file, 'utf8');
      for (const sdk of ['@google/genai', 'algoliasearch', '@google-cloud/storage']) {
        const eager = new RegExp(`^import (?!type )[^;]*from '${sdk.replace('/', '\\/')}'`, 'm');
        assert.doesNotMatch(src, eager, `${path.relative(SRC, file)} imports ${sdk} at load time`);
      }
    }
  });

  test('no console logging (structured logger only) and no plain OTP code in a log line outside the emulator', () => {
    for (const file of sources()) {
      assert.doesNotMatch(readFileSync(file, 'utf8'), /console\.(log|info|warn|error)\(/, path.relative(SRC, file));
    }
    const messaging = readFileSync(path.join(SRC, 'auth/messaging.ts'), 'utf8');
    assert.match(messaging, /if \(onFunctionsEmulator\(\)\) logger\.info\(`otp\[log\]: code for \$\{maskPhone\(phone\)\} is \$\{code\}`\)/);
  });
});

describe('storage URLs (photos sent to callables)', () => {
  const url = (p: string, host = 'firebasestorage.googleapis.com', bucket = 'goldengift-iq.appspot.com') =>
    `https://${host}/v0/b/${bucket}/o/${encodeURIComponent(p)}?alt=media&token=x`;
  const prod = {};

  test('parses download URLs', () => {
    assert.deepEqual(parseStorageUrl(url('gift_cards/u1/r/1.jpg')), {
      host: 'firebasestorage.googleapis.com',
      bucket: 'goldengift-iq.appspot.com',
      path: 'gift_cards/u1/r/1.jpg',
    });
    assert.equal(parseStorageUrl('https://example.com/a.jpg'), null);
  });

  test("only the caller's own folder of this project's bucket", () => {
    assert.ok(isOwnUploadUrl(url('gift_cards/u1/r/1.jpg'), 'gift_cards/u1/', prod));
    assert.ok(!isOwnUploadUrl(url('gift_cards/u2/r/1.jpg'), 'gift_cards/u1/', prod));
    assert.ok(!isOwnUploadUrl(url('gift_cards/u10/r/1.jpg'), 'gift_cards/u1/', prod), 'look-alike folder');
    assert.ok(!isOwnUploadUrl(url('gift_cards/u1/../u2/1.jpg'), 'gift_cards/u1/', prod), 'traversal');
    assert.ok(!isOwnUploadUrl(url('gift_cards/u1/'), 'gift_cards/u1/', prod), 'the folder itself');
    assert.ok(!isOwnUploadUrl(url('gift_cards/u1/r/1.jpg', 'evil.example'), 'gift_cards/u1/', prod), 'foreign host');
    assert.ok(!isOwnUploadUrl(url('gift_cards/u1/r/1.jpg').replace('https:', 'http:'), 'gift_cards/u1/', prod), 'not https');
    assert.ok(!isOwnUploadUrl(42, 'gift_cards/u1/', prod));
    const config = { FIREBASE_CONFIG: JSON.stringify({ storageBucket: 'goldengift-iq.appspot.com' }) };
    assert.ok(isOwnUploadUrl(url('gift_cards/u1/r/1.jpg'), 'gift_cards/u1/', config));
    assert.ok(!isOwnUploadUrl(url('gift_cards/u1/r/1.jpg', undefined, 'other-project.appspot.com'), 'gift_cards/u1/', config), 'other bucket');
  });

  test('on the emulators any Storage-emulator host passes (the path rules still apply)', () => {
    const emu = { FUNCTIONS_EMULATOR: 'true' };
    assert.ok(isOwnUploadUrl(`http://10.0.2.2:9199/v0/b/goldengift-iq.appspot.com/o/gift_cards%2Fu1%2F1.jpg?alt=media`, 'gift_cards/u1/', emu));
    assert.ok(!isOwnUploadUrl(`http://10.0.2.2:9199/v0/b/goldengift-iq.appspot.com/o/gift_cards%2Fu2%2F1.jpg?alt=media`, 'gift_cards/u1/', emu));
  });
});

describe('rate-limit windows', () => {
  test('only hits inside the window (and not from the future) count', () => {
    const now = 1_000_000;
    assert.deepEqual(recentHits([now - 10, now - 5000, now + 10, now + 120_000, 'x', null], now, 1000), [now - 10, now + 10]);
    assert.deepEqual(recentHits(undefined, now, 1000), []);
  });
});

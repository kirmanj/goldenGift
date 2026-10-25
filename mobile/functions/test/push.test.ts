import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { isInvalidTokenError, pushLanguage, resolveText, sendToTokens } from '../src/notifications/push';
import { FakeMessaging } from './fakeMessaging';

describe('push helpers', () => {
  test('users.locale → push language', () => {
    assert.equal(pushLanguage('ar'), 'ar');
    assert.equal(pushLanguage('ckb'), 'ku');
    assert.equal(pushLanguage('en'), 'en');
    assert.equal(pushLanguage(undefined), 'en');
    assert.equal(pushLanguage('fr'), 'en');
  });

  test('resolveText falls back to English', () => {
    const t = { en: 'Hi', ar: 'مرحبا', ku: '' };
    assert.equal(resolveText(t, 'ar'), 'مرحبا');
    assert.equal(resolveText(t, 'ku'), 'Hi');
    assert.equal(resolveText({ en: 'Hi', ar: null }, 'ar'), 'Hi');
  });

  test('dead-token errors', () => {
    assert.equal(isInvalidTokenError({ code: 'messaging/registration-token-not-registered' }), true);
    assert.equal(isInvalidTokenError({ code: 'messaging/invalid-registration-token' }), true);
    assert.equal(
      isInvalidTokenError({ code: 'messaging/invalid-argument', message: 'The registration token is not a valid FCM registration token' }),
      true,
    );
    // A malformed MESSAGE is invalid-argument too — that must not wipe every token.
    assert.equal(isInvalidTokenError({ code: 'messaging/invalid-argument', message: 'Invalid image URL' }), false);
    assert.equal(isInvalidTokenError({ code: 'messaging/internal-error' }), false);
    assert.equal(isInvalidTokenError(undefined), false);
  });

  test('sendToTokens: chunks of 500, de-duplicated, string data only, dead tokens reported', async () => {
    const fcm = new FakeMessaging();
    const tokens = Array.from({ length: 1001 }, (_, i) => `t${i}`);
    fcm.dead.add('t7');
    fcm.flaky.add('t8');
    const result = await sendToTokens(fcm, [...tokens, 't0', ''], {
      title: 'T',
      body: 'B',
      imageUrl: null,
      data: { route: '/orders/o1', id: null, type: 'orderStatus' },
    });
    assert.deepEqual(fcm.calls.map((c) => c.tokens.length), [500, 500, 1]);
    assert.equal(result.sent, 999);
    assert.equal(result.failed, 2);
    assert.deepEqual(result.invalidTokens, ['t7']);
    assert.deepEqual(fcm.calls[0].data, { route: '/orders/o1', type: 'orderStatus' });
    assert.deepEqual(fcm.calls[0].notification, { title: 'T', body: 'B' });
  });

  test('sendToTokens with an image', async () => {
    const fcm = new FakeMessaging();
    await sendToTokens(fcm, ['a'], { title: 'T', body: 'B', imageUrl: 'https://img/x.jpg', data: {} });
    assert.deepEqual(fcm.calls[0].notification, { title: 'T', body: 'B', imageUrl: 'https://img/x.jpg' });
  });
});

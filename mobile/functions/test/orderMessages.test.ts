import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { ORDER_MESSAGES, ORDER_NOTIFICATION_TYPE, orderStatusNotification } from '../src/notifications/orderMessages';
import { OrderStatus } from '../src/shared/enums';

const ARABIC = /[؀-ۿ]/;

describe('order notification texts', () => {
  test('one template per OrderStatus, nothing else', () => {
    assert.deepEqual(Object.keys(ORDER_MESSAGES).sort(), [...OrderStatus].sort());
  });

  for (const status of OrderStatus) {
    test(`${status}: en / ar / ku, non-empty, with the order number`, () => {
      const n = orderStatusNotification(status, { orderId: 'o1', orderNumber: 'GG-2610-00042' });
      for (const lang of ['en', 'ar', 'ku'] as const) {
        const title = n.title[lang];
        const body = n.body[lang];
        assert.ok(typeof title === 'string' && title.trim().length > 0, `${status} title.${lang}`);
        assert.ok(typeof body === 'string' && body.trim().length > 0, `${status} body.${lang}`);
        assert.ok(title.includes('GG-2610-00042'), `${status} title.${lang} has the number`);
        assert.ok(!/\{\w+\}/.test(title + body), `${status}.${lang} has no unfilled placeholder`);
        if (lang !== 'en') assert.match(title, ARABIC, `${status} title.${lang} is in Arabic script`);
      }
      assert.equal(n.type, ORDER_NOTIFICATION_TYPE);
      assert.equal(n.route, '/orders/o1');
      assert.equal(n.id, 'o1');
    });
  }

  test('Arabic and Kurdish differ (no copy-paste)', () => {
    for (const status of OrderStatus) {
      assert.notEqual(ORDER_MESSAGES[status].title.ar, ORDER_MESSAGES[status].title.ku, status);
      assert.notEqual(ORDER_MESSAGES[status].body.ar, ORDER_MESSAGES[status].body.ku, status);
    }
  });

  test("a seller cancellation includes the store's reason in every language", () => {
    const n = orderStatusNotification('cancelledBySeller', {
      orderId: 'o1',
      orderNumber: 'GG-2610-00042',
      reason: '  Out of walnut frames ',
    });
    for (const lang of ['en', 'ar', 'ku'] as const) assert.ok(n.body[lang]!.includes('Out of walnut frames'), lang);
    const noReason = orderStatusNotification('cancelledBySeller', { orderId: 'o1', orderNumber: 'GG-2610-00042', reason: '  ' });
    assert.equal(noReason.body.en, ORDER_MESSAGES.cancelledBySeller.body.en);
  });
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { parseBroadcastData } from '../src/notifications/sendBroadcast';
import { parseCancelOrderData } from '../src/orders/cancelOrder';
import { OrderFailureReason, orderFailure, promoFailure } from '../src/orders/orderErrors';
import { formatOrderNumber, orderCounterId, orderIdFor } from '../src/orders/orderNumber';
import { parsePlaceOrderData } from '../src/orders/placeOrder';
import { stripDartComments } from './dartSource';

/** Exactly what the app sends (PlaceOrderRequest.toMap()). */
const appRequest = (over: Record<string, unknown> = {}) => ({
  clientRequestId: '0f8fad5b-d9cb-469f-a165-70867728950e',
  addressId: 'home',
  deliveryDate: '2026-10-22',
  deliverySlot: 'morning',
  isGift: false,
  giftMessage: null,
  hidePrices: false,
  paymentMethod: 'cashOnDelivery',
  promoCode: null,
  useCredits: false,
  useWallet: false,
  ...over,
});

describe('placeOrder data', () => {
  test("the app's request", () => {
    assert.deepEqual(parsePlaceOrderData(appRequest()), {
      clientRequestId: '0f8fad5b-d9cb-469f-a165-70867728950e',
      addressId: 'home',
      deliveryDate: '2026-10-22',
      deliverySlot: 'morning',
      isGift: false,
      giftMessage: null,
      hidePrices: false,
      paymentMethod: 'cashOnDelivery',
      promoCode: null,
      useCredits: false,
      useWallet: false,
    });
  });

  test('gift options only count on a gift; the message is trimmed', () => {
    const gift = parsePlaceOrderData(appRequest({ isGift: true, giftMessage: '  Happy birthday!  ', hidePrices: true }));
    assert.equal(gift.giftMessage, 'Happy birthday!');
    assert.equal(gift.hidePrices, true);
    const notGift = parsePlaceOrderData(appRequest({ isGift: false, giftMessage: 'x', hidePrices: true }));
    assert.equal(notGift.giftMessage, null);
    assert.equal(notGift.hidePrices, false);
    assert.equal(parsePlaceOrderData(appRequest({ isGift: true, giftMessage: '   ' })).giftMessage, null);
  });

  test('a 200-character gift message (emoji count as one) is accepted', () => {
    assert.ok(parsePlaceOrderData(appRequest({ isGift: true, giftMessage: '👍🏽'.repeat(200) })).giftMessage);
  });

  test('optional flags may be missing; payment defaults to cash on delivery', () => {
    const minimal = parsePlaceOrderData({
      clientRequestId: 'r1',
      addressId: 'a1',
      deliveryDate: '2026-10-22',
      deliverySlot: 'evening',
    });
    assert.equal(minimal.paymentMethod, 'cashOnDelivery');
    assert.equal(minimal.isGift, false);
    assert.equal(minimal.useCredits, false);
  });

  test('promo code is normalised like PromoCodeModel.normalize (no spaces, upper case)', () => {
    assert.equal(parsePlaceOrderData(appRequest({ promoCode: ' eid10 ' })).promoCode, 'EID10');
    assert.equal(parsePlaceOrderData(appRequest({ promoCode: 'gold 10' })).promoCode, 'GOLD10');
    assert.equal(parsePlaceOrderData(appRequest({ promoCode: '   ' })).promoCode, null);
  });

  for (const [label, over] of [
    ['no clientRequestId', { clientRequestId: undefined }],
    ['empty clientRequestId', { clientRequestId: '' }],
    ['clientRequestId with a slash', { clientRequestId: 'a/b' }],
    ['clientRequestId of 129 characters', { clientRequestId: 'x'.repeat(129) }],
    ['no addressId', { addressId: null }],
    ['addressId with a slash', { addressId: 'x/y' }],
    ['date in another format', { deliveryDate: '22/10/2026' }],
    ['impossible date', { deliveryDate: '2026-02-30' }],
    ['date as a number', { deliveryDate: 20261022 }],
    ['no slot', { deliverySlot: null }],
    ['empty slot', { deliverySlot: '' }],
    ['isGift as a string', { isGift: 'yes' }],
    ['gift message of 201 characters', { isGift: true, giftMessage: 'x'.repeat(201) }],
    ['gift message as a number', { isGift: true, giftMessage: 42 }],
    ['unknown payment method', { paymentMethod: 'bitcoin' }],
    ['payment method as a number', { paymentMethod: 0 }],
    ['promo code of 41 characters', { promoCode: 'X'.repeat(41) }],
    ['useWallet as a string', { useWallet: 'true' }],
  ] as Array<[string, Record<string, unknown>]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parsePlaceOrderData(appRequest(over)), { code: 'invalid-argument' });
    });
  }
  test('invalid-argument: not an object', () => {
    for (const data of [null, 'x', [appRequest()]]) assert.throws(() => parsePlaceOrderData(data), { code: 'invalid-argument' });
  });
});

describe('cancelOrder data', () => {
  test('reason is optional and trimmed', () => {
    assert.deepEqual(parseCancelOrderData({ orderId: 'o1' }), { orderId: 'o1', reason: null });
    assert.deepEqual(parseCancelOrderData({ orderId: 'o1', reason: '  Wrong date ' }), { orderId: 'o1', reason: 'Wrong date' });
    assert.deepEqual(parseCancelOrderData({ orderId: 'o1', reason: '   ' }), { orderId: 'o1', reason: null });
    assert.equal(parseCancelOrderData({ orderId: 'o1', reason: 'x'.repeat(300) }).reason?.length, 300);
  });
  for (const [label, data] of [
    ['no orderId', {}],
    ['orderId with a slash', { orderId: 'a/b' }],
    ['reason of 301 characters', { orderId: 'o1', reason: 'x'.repeat(301) }],
    ['reason as a number', { orderId: 'o1', reason: 1 }],
    ['null', null],
  ] as Array<[string, unknown]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parseCancelOrderData(data), { code: 'invalid-argument' });
    });
  }
});

describe('sendBroadcast data', () => {
  /** BroadcastRepository.payload in the dashboard. */
  const payload = (over: Record<string, unknown> = {}) => ({
    title: { en: 'Eid sale', ar: 'تخفيضات العيد', ku: null },
    body: { en: '20% off all frames', ar: null, ku: 'داشکاندنی ٢٠٪' },
    route: '/products?category=frames',
    imageUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/broadcasts%2Fa.jpg?alt=media',
    ...over,
  });

  test("the dashboard's payload", () => {
    assert.deepEqual(parseBroadcastData(payload()), {
      title: { en: 'Eid sale', ar: 'تخفيضات العيد', ku: null },
      body: { en: '20% off all frames', ar: null, ku: 'داشکاندنی ٢٠٪' },
      route: '/products?category=frames',
      imageUrl: 'https://firebasestorage.googleapis.com/v0/b/x/o/broadcasts%2Fa.jpg?alt=media',
    });
  });
  test('route and image are optional', () => {
    const { route: _r, imageUrl: _i, ...rest } = payload();
    const parsed = parseBroadcastData(rest);
    assert.equal(parsed.route, null);
    assert.equal(parsed.imageUrl, null);
  });
  test('60 / 180 characters are the limits', () => {
    assert.ok(parseBroadcastData(payload({ title: { en: 'x'.repeat(60) }, body: { en: 'y'.repeat(180) } })));
  });
  for (const [label, over] of [
    ['no title', { title: undefined }],
    ['title without en', { title: { ar: 'عنوان' } }],
    ['blank en title', { title: { en: '   ' } }],
    ['title of 61 characters', { title: { en: 'x'.repeat(61) } }],
    ['Arabic title of 61 characters', { title: { en: 'ok', ar: 'ع'.repeat(61) } }],
    ['body of 181 characters', { body: { en: 'x'.repeat(181) } }],
    ['body as a string', { body: 'hello' }],
    ['route without a leading slash', { route: 'products' }],
    ['route with spaces', { route: '/orders/ a' }],
    ['image that is not a URL', { imageUrl: 'broadcasts/a.jpg' }],
    ['image as a number', { imageUrl: 3 }],
  ] as Array<[string, Record<string, unknown>]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parseBroadcastData(payload(over)), { code: 'invalid-argument' });
    });
  }
});

describe('order ids and numbers', () => {
  test('the order id is a stable 20-character hash of uid + clientRequestId', () => {
    const id = orderIdFor('alice', 'req-1');
    assert.match(id, /^[0-9a-f]{20}$/);
    assert.equal(orderIdFor('alice', 'req-1'), id);
    assert.notEqual(orderIdFor('bob', 'req-1'), id);
    assert.notEqual(orderIdFor('alice', 'req-2'), id);
  });
  test('GG-YYMM-#####', () => {
    const oct = { year: 2026, month: 10, day: 21, hour: 9, minute: 0 };
    assert.equal(formatOrderNumber(oct, 1), 'GG-2610-00001');
    assert.equal(formatOrderNumber(oct, 12345), 'GG-2610-12345');
    assert.equal(formatOrderNumber(oct, 123456), 'GG-2610-123456');
    assert.equal(formatOrderNumber({ ...oct, year: 2027, month: 1 }, 7), 'GG-2701-00007');
    assert.equal(orderCounterId(oct), 'orders-2610');
  });
});

describe('failure reasons', () => {
  test('failed-precondition with { reason, productIds? }', () => {
    const e = orderFailure('out_of_stock', ['p2', 'p1', 'p2']);
    assert.equal(e.code, 'failed-precondition');
    assert.deepEqual(e.details, { reason: 'out_of_stock', productIds: ['p1', 'p2'] });
    assert.deepEqual(orderFailure('min_order').details, { reason: 'min_order' });
    const promo = promoFailure('usageLimit');
    assert.equal(promo.code, 'failed-precondition');
    assert.deepEqual(promo.details, { reason: 'promo_invalid', promoReason: 'usageLimit' });
    assert.deepEqual(orderFailure('insufficient_funds').details, { reason: 'insufficient_funds' });
  });

  test("every reason is one the app's OrderFailure.from understands", () => {
    const dart = stripDartComments(
      readFileSync(path.resolve(__dirname, '../../lib/features/orders/data/orders_repository.dart'), 'utf8'),
    );
    // Only the inner `switch (details['reason'])`, not the error-code switch around it.
    const block = /switch\s*\(\s*details\['reason'\]\s*\)\s*\{([\s\S]*?)_\s*=>/.exec(dart)?.[1] ?? '';
    const appReasons = [...block.matchAll(/'([a-z_]+)'\s*=>\s*OrderFailureReason\./g)].map((m) => m[1]);
    // Every reason the server sends must be mapped by the app (the app may know more, e.g. later phases').
    for (const reason of OrderFailureReason) assert.ok(appReasons.includes(reason), `app does not map "${reason}"`);
  });
});

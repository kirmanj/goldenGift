/**
 * Pure parts of the Phase 8 functions (no emulator): gift-card rules and codes,
 * the callables' data validation, redeem refusals and the trilingual texts.
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { HttpsError } from 'firebase-functions/v2/https';
import { parseAdminIssueData } from '../src/giftCards/adminIssueGiftCard';
import {
  giftCardReceivedNotification,
  giftCardScheduledNotification,
  giftCardSentNotification,
} from '../src/giftCards/giftCardMessages';
import {
  GIFT_CARD_CODE_ALPHABET,
  generateGiftCardCode,
  isGiftCardCode,
  normalizeGiftCardCode,
  parseRecipient,
  parseTemplate,
  templateAccepts,
} from '../src/giftCards/giftCardRules';
import { userE164 } from '../src/giftCards/issueGiftCard';
import { parsePurchaseGiftCardData } from '../src/giftCards/purchaseGiftCard';
import { redeemRefusal } from '../src/giftCards/redeemGiftCard';
import { parseUpdateOrderItemsData } from '../src/orders/updateOrderItems';
import {
  partnerApprovedNotification,
  partnerRejectedNotification,
  storeReactivatedNotification,
  storeSuspendedNotification,
} from '../src/partners/partnerMessages';
import { parseReviewPartnerData, parseSetStoreStatusData } from '../src/partners/reviewPartner';
import { parsePartnerApplication } from '../src/partners/submitPartnerApplication';
import { parseAcceptQuoteData } from '../src/specialRequests/acceptQuote';
import { specialRequestQuotedNotification, specialRequestReplyNotification } from '../src/specialRequests/specialRequestMessages';

const NOW = Date.UTC(2026, 9, 21, 9, 0);
const DAY = 86_400_000;

function invalid(fn: () => unknown, pattern?: RegExp): void {
  assert.throws(fn, (e: unknown) => {
    assert.ok(e instanceof HttpsError, String(e));
    assert.equal(e.code, 'invalid-argument', e.message);
    if (pattern) assert.match(e.message, pattern);
    return true;
  });
}

describe('gift-card codes', () => {
  test('12 characters from the unambiguous alphabet', () => {
    for (let i = 0; i < 200; i++) {
      const code = generateGiftCardCode();
      assert.equal(code.length, 12);
      assert.ok(isGiftCardCode(code), code);
    }
    for (const c of '01IO') assert.ok(!GIFT_CARD_CODE_ALPHABET.includes(c), c);
  });
  test('uniform over the alphabet (every symbol reachable)', () => {
    const bytes = Buffer.from([...Array(12).keys()].map((i) => i * 8 + 3));
    assert.equal(generateGiftCardCode(() => bytes), [...bytes].map((b) => GIFT_CARD_CODE_ALPHABET[b & 31]).join(''));
  });
  test('normalize like the app (dashes, spaces, case)', () => {
    assert.equal(normalizeGiftCardCode(' abcd-efgh jklm '), 'ABCDEFGHJKLM');
    assert.ok(!isGiftCardCode('ABCDEFGHJKL0'));
    assert.ok(!isGiftCardCode('ABCDEFGHJKL'));
  });
});

describe('templates (GiftCardTemplateModel.accepts)', () => {
  const t = parseTemplate('t1', { name: 'Eid', nameAr: 'عيد', presetAmounts: [15000, '25000', -5, 0], minAmount: 10000, maxAmount: 500000 });
  test('parse', () => {
    assert.deepEqual(t.presetAmounts, [15000, 25000]);
    assert.equal(t.isActive, true);
    assert.deepEqual(t.name, { en: 'Eid', ar: 'عيد', ku: null });
  });
  test('presets and the custom range', () => {
    assert.ok(templateAccepts(t, 15000));
    assert.ok(templateAccepts(t, 10000));
    assert.ok(templateAccepts(t, 500000));
    assert.ok(!templateAccepts(t, 9999));
    assert.ok(!templateAccepts(t, 500001));
    assert.ok(!templateAccepts(t, 0));
  });
  test('presets only when both bounds are 0', () => {
    const presets = parseTemplate('t2', { name: 'X', presetAmounts: [25000], minAmount: 0, maxAmount: 0 });
    assert.ok(templateAccepts(presets, 25000));
    assert.ok(!templateAccepts(presets, 26000));
  });
});

describe('recipients', () => {
  test('phone in any shape → E.164, email lower case', () => {
    assert.deepEqual(parseRecipient({ recipientName: ' Sara ', recipientPhone: '0750 123 4567' }, { requireContact: true }), {
      recipientName: 'Sara',
      recipientPhone: '+9647501234567',
      recipientEmail: null,
    });
    assert.equal(parseRecipient({ recipientName: 'S', recipientEmail: 'Sara@Example.COM' }, { requireContact: true }).recipientEmail, 'sara@example.com');
  });
  test('phone or email required for purchases; names 1–60', () => {
    invalid(() => parseRecipient({ recipientName: 'Sara' }, { requireContact: true }));
    assert.equal(parseRecipient({ recipientName: 'Sara' }, { requireContact: false }).recipientPhone, null);
    invalid(() => parseRecipient({ recipientName: '' }, { requireContact: false }));
    invalid(() => parseRecipient({ recipientName: 'x'.repeat(61), recipientPhone: '+9647501234567' }, { requireContact: true }));
    invalid(() => parseRecipient({ recipientName: 'S', recipientPhone: '123' }, { requireContact: true }));
    invalid(() => parseRecipient({ recipientName: 'S', recipientEmail: 'nope' }, { requireContact: true }));
  });
  test('users docs → E.164 (national phone + countryCode)', () => {
    assert.equal(userE164({ phone: '7501234567', countryCode: '+964' }), '+9647501234567');
    assert.equal(userE164({ phone: '+9647501234567' }), '+9647501234567');
    assert.equal(userE164({ phone: '7501234567' }), '+9647501234567');
    assert.equal(userE164({}), null);
  });
});

describe('purchaseGiftCard data (GiftCardPurchase.toMap)', () => {
  const data = (over: Record<string, unknown> = {}) => ({
    clientRequestId: 'req-1',
    templateId: 't1',
    amount: 25000,
    recipientName: 'Sara',
    recipientPhone: '+9647701234567',
    recipientEmail: null,
    message: 'Happy birthday!',
    photoUrl: null,
    scheduledAt: null,
    paymentMethod: 'cashOnDelivery',
    addressId: 'home',
    ...over,
  });
  test('valid', () => {
    const r = parsePurchaseGiftCardData(data(), NOW);
    assert.equal(r.paymentMethod, 'cashOnDelivery');
    assert.equal(r.addressId, 'home');
    assert.equal(r.scheduledAtMs, null);
    assert.equal(parsePurchaseGiftCardData(data({ paymentMethod: 'wallet', addressId: null }), NOW).addressId, null);
  });
  test('scheduledAt: 09:00 local of a day from tomorrow to a year ahead, as given', () => {
    const tomorrow9 = new Date(NOW + DAY).toISOString();
    assert.equal(parsePurchaseGiftCardData(data({ scheduledAt: tomorrow9 }), NOW).scheduledAtMs, Date.parse(tomorrow9));
    assert.ok(parsePurchaseGiftCardData(data({ scheduledAt: new Date(NOW + 366 * DAY).toISOString() }), NOW).scheduledAtMs);
    invalid(() => parsePurchaseGiftCardData(data({ scheduledAt: new Date(NOW - 1000).toISOString() }), NOW), /scheduledAt/);
    invalid(() => parsePurchaseGiftCardData(data({ scheduledAt: new Date(NOW + 400 * DAY).toISOString() }), NOW), /scheduledAt/);
    invalid(() => parsePurchaseGiftCardData(data({ scheduledAt: 'tomorrow' }), NOW), /scheduledAt/);
  });
  for (const [label, over] of [
    ['no clientRequestId', { clientRequestId: '' }],
    ['a template path', { templateId: 'a/b' }],
    ['a fractional amount', { amount: 1000.5 }],
    ['an amount over 10,000,000', { amount: 10_000_001 }],
    ['a string amount', { amount: '25000' }],
    ['no contact', { recipientPhone: null, recipientEmail: null }],
    ['a 201-character message', { message: 'x'.repeat(201) }],
    ['a non-URL photo', { photoUrl: 'file:///x.jpg' }],
    ['card payment', { paymentMethod: 'card' }],
    ['cash on delivery without an address', { addressId: null }],
  ] as Array<[string, Record<string, unknown>]>) {
    test(`invalid: ${label}`, () => invalid(() => parsePurchaseGiftCardData(data(over), NOW)));
  }
  test('a 200-grapheme message with emoji passes', () => {
    assert.equal(parsePurchaseGiftCardData(data({ message: '👍🏽'.repeat(200) }), NOW).message.length > 200, true);
  });
});

describe('adminIssueGiftCard data (ManualGiftCardIssue.toPayload)', () => {
  test('contact and message optional; expiry in the future', () => {
    const r = parseAdminIssueData({ templateId: 't1', amount: 50000, recipientName: 'Sara' }, NOW);
    assert.equal(r.recipientPhone, null);
    assert.equal(r.message, '');
    assert.equal(r.expiresAtMs, null);
    const exp = new Date(NOW + 30 * DAY).toISOString();
    assert.equal(parseAdminIssueData({ templateId: 't1', amount: 1, recipientName: 'Sa', expiresAt: exp }, NOW).expiresAtMs, Date.parse(exp));
    invalid(() => parseAdminIssueData({ templateId: 't1', amount: 1, recipientName: 'Sa', expiresAt: new Date(NOW - 1).toISOString() }, NOW));
    invalid(() => parseAdminIssueData({ templateId: 't1', amount: 1, recipientName: 'S' }, NOW));
  });
});

describe('redeem refusals', () => {
  const card = (over: Record<string, unknown> = {}) => ({ status: 'sent', balance: 1000, expiresAt: NOW + DAY, ...over });
  test('reasons in order', () => {
    assert.equal(redeemRefusal(card(), NOW), null);
    assert.equal(redeemRefusal(card({ status: 'disabled' }), NOW), 'disabled');
    assert.equal(redeemRefusal(card({ status: 'redeemed', balance: 0 }), NOW), 'redeemed');
    assert.equal(redeemRefusal(card({ balance: 0 }), NOW), 'redeemed');
    assert.equal(redeemRefusal(card({ expiresAt: NOW }), NOW), 'expired');
    assert.equal(redeemRefusal(card({ status: 'expired' }), NOW), 'expired');
    assert.equal(redeemRefusal(card({ status: 'pending' }), NOW), 'not_sent');
  });
});

describe('acceptQuote data (AcceptQuoteRequest.toMap)', () => {
  const data = { requestId: 'r1', clientRequestId: 'c1', addressId: 'home', deliveryDate: '2026-10-22', deliverySlot: 'morning', paymentMethod: 'wallet' };
  test('valid', () => assert.equal(parseAcceptQuoteData(data).paymentMethod, 'wallet'));
  test('invalid', () => {
    invalid(() => parseAcceptQuoteData({ ...data, deliveryDate: '2026-02-30' }));
    invalid(() => parseAcceptQuoteData({ ...data, deliverySlot: null }));
    invalid(() => parseAcceptQuoteData({ ...data, paymentMethod: 'zainCash' }));
    invalid(() => parseAcceptQuoteData({ ...data, requestId: '' }));
  });
});

describe('partner data', () => {
  const app = {
    storeName: 'Rose Corner',
    ownerName: 'Sara Ahmed',
    phone: '+9647501234567',
    city: 'erbil',
    category: 'Flowers',
    instagram: 'rose.corner',
    samplePhotos: ['https://x/1.jpg'],
  };
  test('PartnerApplication.toMap', () => {
    assert.equal(parsePartnerApplication(app).phone, '+9647501234567');
    assert.equal(parsePartnerApplication({ ...app, instagram: null, samplePhotos: [] }).instagram, null);
    invalid(() => parsePartnerApplication({ ...app, storeName: 'R' }));
    invalid(() => parsePartnerApplication({ ...app, phone: '12' }));
    invalid(() => parsePartnerApplication({ ...app, instagram: 'bad handle!' }));
    invalid(() => parsePartnerApplication({ ...app, samplePhotos: Array(6).fill('https://x/1.jpg') }));
    invalid(() => parsePartnerApplication({ ...app, category: ' ' }));
  });
  test('reviewPartner / setStoreStatus', () => {
    assert.deepEqual(parseReviewPartnerData({ storeId: 's1', decision: 'approve', commissionPercent: 12.5 }), {
      storeId: 's1',
      decision: 'approve',
      commissionPercent: 12.5,
    });
    invalid(() => parseReviewPartnerData({ storeId: 's1', decision: 'approve' }));
    invalid(() => parseReviewPartnerData({ storeId: 's1', decision: 'approve', commissionPercent: 51 }));
    invalid(() => parseReviewPartnerData({ storeId: 's1', decision: 'reject', reason: 'no' }));
    invalid(() => parseReviewPartnerData({ storeId: 's1', decision: 'maybe' }));
    assert.equal(parseSetStoreStatusData({ storeId: 's1', status: 'suspended', reason: 'Late orders' }).status, 'suspended');
    invalid(() => parseSetStoreStatusData({ storeId: 's1', status: 'pendingApproval', reason: 'xxxx' }));
  });
  test('updateOrderItems (SellerOrdersRepository.payload)', () => {
    assert.deepEqual(parseUpdateOrderItemsData({ orderId: 'o1', status: 'confirmed', note: '  ' }), {
      orderId: 'o1',
      status: 'confirmed',
      note: null,
    });
    invalid(() => parseUpdateOrderItemsData({ orderId: 'o1', status: 'refunded' }), /Golden Gift/);
    invalid(() => parseUpdateOrderItemsData({ orderId: 'o1', status: 'lost' }));
    invalid(() => parseUpdateOrderItemsData({ orderId: 'o1', status: 'confirmed', note: 'x'.repeat(501) }));
  });
});

describe('trilingual texts', () => {
  const all = [
    giftCardReceivedNotification('g', 25000, 'Alice'),
    giftCardReceivedNotification('g', 25000, null),
    giftCardSentNotification('g', 25000, 'Sara'),
    giftCardScheduledNotification('g', 25000, 'Sara', '2026-11-02'),
    specialRequestReplyNotification('r', 'We can do it'),
    specialRequestReplyNotification('r', '   '),
    specialRequestQuotedNotification('r', 30000),
    partnerApprovedNotification('s', 'Rose'),
    partnerRejectedNotification('s', 'Rose', 'No photos'),
    storeSuspendedNotification('s', 'Rose', 'Late'),
    storeReactivatedNotification('s', 'Rose'),
  ];
  test('every text in en, ar and ku, amounts as IQD', () => {
    for (const n of all) {
      for (const t of [n.title, n.body]) {
        for (const lang of ['en', 'ar', 'ku'] as const) assert.ok((t[lang] ?? '').trim().length > 0, `${n.type} ${lang}`);
      }
      assert.ok(n.route?.startsWith('/'), n.type);
    }
    assert.match(giftCardSentNotification('g', 25000, 'Sara').body.en, /25,000 IQD/);
  });
  test('long replies are shortened in the notification', () => {
    assert.ok(specialRequestReplyNotification('r', 'x'.repeat(500)).body.en.length <= 140);
  });
});

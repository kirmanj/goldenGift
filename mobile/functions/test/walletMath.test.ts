/**
 * Pure wallet maths (SRS §5.10, §5.11, §5.18): checkout totals against the
 * Dart formula (checkout_rules.dart `totals()` — the shared fixture has no
 * totals section), FIFO credit consumption, refund plans, settings parsing and
 * the request parsers of adjustWallet / setUserBlocked.
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { parseAdjustWalletData } from '../src/admin/adjustWallet';
import { parseSetUserBlockedData } from '../src/admin/setUserBlocked';
import { checkoutTotals } from '../src/orders/checkoutRules';
import { refundPlan } from '../src/orders/orderRefunds';
import { baghdadMonthStartMs } from '../src/referrals/joinBonus';
import { orderQualifies, referralAbuseFlag } from '../src/referrals/orderBonus';
import { firstName } from '../src/users/processNewUser';
import { planFifo, sortFifo } from '../src/wallet/ledger';
import { DAY_MS, creditExpiryAt, parseReferralSettings } from '../src/wallet/walletSettings';
import { formatIqd } from '../src/wallet/walletTexts';

/** checkout_rules.dart `CheckoutRules.totals`, transcribed line by line. */
function dartTotals(subtotal: number, deliveryFee: number, discount = 0, credits = 0, wallet = 0) {
  const beforePayments = Math.max(0, subtotal - discount) + deliveryFee;
  const creditsUsed = Math.min(credits, beforePayments);
  const walletUsed = Math.min(wallet, beforePayments - creditsUsed);
  return {
    subtotal,
    discount: Math.min(discount, subtotal),
    deliveryFee,
    creditsUsed,
    walletUsed,
    total: beforePayments - creditsUsed - walletUsed,
  };
}

describe('checkout totals = the Dart formula', () => {
  const cases: Array<[string, number, number, number, number, number]> = [
    // label, subtotal, fee, discount, credits, wallet
    ['nothing applied', 25000, 3000, 0, 0, 0],
    ['discount only', 25000, 3000, 2500, 0, 0],
    ['credits cover part', 25000, 3000, 2500, 10000, 0],
    ['credits cover everything incl. delivery', 25000, 3000, 0, 50000, 0],
    ['credits then wallet', 25000, 3000, 0, 5000, 100000],
    ['wallet short', 25000, 3000, 0, 5000, 10000],
    ['discount larger than the subtotal: delivery still due', 10000, 2000, 15000, 1500, 5000],
    ['exact cover', 20000, 4000, 4000, 10000, 10000],
    ['free delivery city', 7000, 0, 0, 7000, 0],
  ];
  for (const [label, subtotal, fee, discount, credits, wallet] of cases) {
    test(label, () => {
      assert.deepEqual(
        checkoutTotals({ subtotal, deliveryFee: fee, discount, credits, wallet }),
        dartTotals(subtotal, fee, discount, credits, wallet),
      );
    });
  }
  test('a wallet payment reaches 0 only when credits + balance cover the rest', () => {
    assert.equal(checkoutTotals({ subtotal: 25000, deliveryFee: 3000, credits: 5000, wallet: 23000 }).total, 0);
    assert.equal(checkoutTotals({ subtotal: 25000, deliveryFee: 3000, credits: 5000, wallet: 22999 }).total, 1);
  });
});

describe('credit lots', () => {
  const lots = [
    { id: 'a', remaining: 3000 },
    { id: 'b', remaining: 5000 },
    { id: 'c', remaining: 2000 },
  ];
  test('FIFO: the oldest lot first, partly', () => {
    assert.deepEqual(planFifo(lots, 4000), {
      takes: [
        { id: 'a', take: 3000, remainingAfter: 0 },
        { id: 'b', take: 1000, remainingAfter: 4000 },
      ],
      untracked: 0,
    });
  });
  test('more than the lots hold → the rest is untracked credits', () => {
    assert.deepEqual(planFifo(lots, 12000).untracked, 2000);
    assert.deepEqual(planFifo([], 500), { takes: [], untracked: 500 });
  });
  test('empty lots are skipped; 0 takes nothing', () => {
    assert.deepEqual(planFifo([{ id: 'x', remaining: 0 }, ...lots], 1000).takes, [{ id: 'a', take: 1000, remainingAfter: 2000 }]);
    assert.deepEqual(planFifo(lots, 0), { takes: [], untracked: 0 });
  });
  test('sortFifo: createdAt, then id', () => {
    const sorted = sortFifo([
      { id: 'z', createdAtMs: 2 },
      { id: 'b', createdAtMs: 1 },
      { id: 'a', createdAtMs: 1 },
    ]);
    assert.deepEqual(sorted.map((l) => l.id), ['a', 'b', 'z']);
  });
  test('expiry per app_settings/referral (0 = never)', () => {
    assert.equal(creditExpiryAt(1000, 90), 1000 + 90 * DAY_MS);
    assert.equal(creditExpiryAt(1000, 0), null);
  });
});

describe('refund plans', () => {
  const order = (over: Record<string, unknown> = {}) => ({
    total: 20000,
    creditsUsed: 5000,
    walletUsed: 0,
    paymentStatus: 'pending',
    ...over,
  });
  test('cancelled COD order: credits back, nothing else', () => {
    assert.deepEqual(refundPlan(order(), 'cancel'), { credits: 5000, balance: 0, markRefunded: false });
  });
  test('cancelled wallet order: credits + balance back, payment refunded', () => {
    const o = order({ total: 0, walletUsed: 15000, paymentStatus: 'paid' });
    assert.deepEqual(refundPlan(o, 'cancel'), { credits: 5000, balance: 15000, markRefunded: true });
  });
  test('refunded after delivery (COD paid): cash total + wallet to balance, credits back', () => {
    const o = order({ walletUsed: 3000, paymentStatus: 'paid' });
    assert.deepEqual(refundPlan(o, 'refund'), { credits: 5000, balance: 23000, markRefunded: true });
  });
  test('unpaid order reaching refunded: only credits / wallet', () => {
    assert.deepEqual(refundPlan(order({ walletUsed: 2000 }), 'refund'), { credits: 5000, balance: 2000, markRefunded: false });
  });
  test('what was already returned is never returned again', () => {
    const cancelled = order({ refundedCredits: 5000, refundedBalance: 0, refundedToWallet: true });
    assert.deepEqual(refundPlan(cancelled, 'refund'), { credits: 0, balance: 0, markRefunded: false });
    const paidCard = order({ creditsUsed: 0, paymentStatus: 'paid', walletUsed: 1000, refundedBalance: 1000 });
    assert.deepEqual(refundPlan(paidCard, 'cancel'), { credits: 0, balance: 0, markRefunded: false });
    assert.deepEqual(refundPlan(paidCard, 'refund'), { credits: 0, balance: 20000, markRefunded: true });
  });
  test('malformed amounts never refund negative', () => {
    assert.deepEqual(refundPlan({ creditsUsed: -5, walletUsed: 'x', total: null }, 'refund'), {
      credits: 0,
      balance: 0,
      markRefunded: false,
    });
  });
});

describe('referral helpers', () => {
  test('settings: missing / negative → 0', () => {
    assert.deepEqual(parseReferralSettings(undefined), { joinBonus: 0, orderBonus: 0, maxReferralsPerMonth: 0, creditsExpiryDays: 0 });
    assert.deepEqual(parseReferralSettings({ joinBonus: '5000', orderBonus: -1, maxReferralsPerMonth: 10, creditsExpiryDays: 90.4 }), {
      joinBonus: 5000,
      orderBonus: 0,
      maxReferralsPerMonth: 10,
      creditsExpiryDays: 90,
    });
  });
  test('the month is Iraq time: 31 Oct 22:00 UTC is already November in Baghdad', () => {
    assert.equal(baghdadMonthStartMs(Date.UTC(2026, 9, 31, 22, 0)), Date.UTC(2026, 10, 1) - 3 * 3600 * 1000);
    assert.equal(baghdadMonthStartMs(Date.UTC(2026, 9, 31, 20, 59)), Date.UTC(2026, 9, 1) - 3 * 3600 * 1000);
  });
  test('first name for the referrer list', () => {
    assert.equal(firstName('  Sara   Ahmed '), 'Sara');
    assert.equal(firstName('سارا أحمد'), 'سارا');
    assert.equal(firstName(''), null);
    assert.equal(firstName(42), null);
    assert.equal(firstName('x'.repeat(60))?.length, 40);
  });
  test('abuse flags', () => {
    const referral = { referrerUid: 'a', referredUid: 'b' };
    const ok = { deviceId: 'd1' };
    assert.equal(referralAbuseFlag(referral, ok, { deviceId: 'd2' }), null);
    assert.equal(referralAbuseFlag(referral, undefined, ok), 'deleted');
    assert.equal(referralAbuseFlag(referral, { isDeleted: true }, ok), 'deleted');
    assert.equal(referralAbuseFlag(referral, { isBlocked: true }, ok), 'blocked');
    assert.equal(referralAbuseFlag(referral, ok, { isBlocked: true }), 'blocked');
    assert.equal(referralAbuseFlag({ referrerUid: 'a', referredUid: 'a' }, ok, { deviceId: 'd2' }), 'selfReferral');
    assert.equal(referralAbuseFlag(referral, { deviceId: ' d1 ' }, { deviceId: 'd1' }), 'sameDevice');
    assert.equal(referralAbuseFlag(referral, { deviceId: '' }, { deviceId: '' }), null);
  });
  test('which orders complete a referral', () => {
    const order = { userId: 'b', status: 'delivered', paymentStatus: 'paid', total: 18000, walletUsed: 0 };
    assert.equal(orderQualifies(order, 'b'), true);
    assert.equal(orderQualifies({ ...order, total: 0, walletUsed: 4000 }, 'b'), true);
    assert.equal(orderQualifies({ ...order, total: 0 }, 'b'), false); // paid with credits only
    assert.equal(orderQualifies({ ...order, paymentStatus: 'pending' }, 'b'), false);
    assert.equal(orderQualifies({ ...order, status: 'outForDelivery' }, 'b'), false);
    assert.equal(orderQualifies({ ...order, referralCredited: true }, 'b'), false);
    assert.equal(orderQualifies(order, 'c'), false);
    assert.equal(orderQualifies(undefined, 'b'), false);
  });
  test('IQD like CurrencyFormatter.format', () => {
    assert.equal(formatIqd(5000), '5,000 IQD');
    assert.equal(formatIqd(1234567), '1,234,567 IQD');
    assert.equal(formatIqd(0), '0 IQD');
  });
});

describe('adjustWallet data', () => {
  const payload = { uid: 'u1', bucket: 'credits', amount: -2500, reason: '  Goodwill  ' };
  test("the dashboard's payload", () => {
    assert.deepEqual(parseAdjustWalletData(payload), { uid: 'u1', bucket: 'credits', amount: -2500, reason: 'Goodwill', requestId: null });
    assert.equal(parseAdjustWalletData({ ...payload, amount: 10_000_000 }).amount, 10_000_000);
    assert.equal(parseAdjustWalletData({ ...payload, requestId: 'r-1' }).requestId, 'r-1');
  });
  for (const [label, over] of [
    ['no uid', { uid: undefined }],
    ['uid with a slash', { uid: 'a/b' }],
    ['unknown bucket', { bucket: 'points' }],
    ['amount 0', { amount: 0 }],
    ['fractional amount', { amount: 10.5 }],
    ['amount as a string', { amount: '100' }],
    ['more than 10,000,000', { amount: 10_000_001 }],
    ['less than -10,000,000', { amount: -10_000_001 }],
    ['reason of 2 characters', { reason: ' ab ' }],
    ['reason of 301 characters', { reason: 'x'.repeat(301) }],
    ['no reason', { reason: undefined }],
    ['bad requestId', { requestId: 'a/b' }],
  ] as Array<[string, Record<string, unknown>]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parseAdjustWalletData({ ...payload, ...over }), { code: 'invalid-argument' });
    });
  }
});

describe('setUserBlocked data', () => {
  test("the dashboard's payload; reason optional and trimmed", () => {
    assert.deepEqual(parseSetUserBlockedData({ uid: 'u1', blocked: true, reason: ' Fraud ' }), { uid: 'u1', blocked: true, reason: 'Fraud' });
    assert.deepEqual(parseSetUserBlockedData({ uid: 'u1', blocked: false }), { uid: 'u1', blocked: false, reason: null });
  });
  for (const [label, data] of [
    ['null', null],
    ['no uid', { blocked: true }],
    ['blocked as a string', { uid: 'u1', blocked: 'true' }],
    ['reason as a number', { uid: 'u1', blocked: true, reason: 4 }],
    ['reason of 301 characters', { uid: 'u1', blocked: true, reason: 'x'.repeat(301) }],
  ] as Array<[string, unknown]>) {
    test(`invalid-argument: ${label}`, () => {
      assert.throws(() => parseSetUserBlockedData(data), { code: 'invalid-argument' });
    });
  }
});

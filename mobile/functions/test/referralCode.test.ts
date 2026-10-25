import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  REFERRAL_CODE_ALPHABET,
  REFERRAL_CODE_LENGTH,
  generateReferralCode,
  isReferralCode,
  normalizeEnteredCode,
} from '../src/users/referralCode';
import { REFERRAL_NOT_APPLIED_TEXT } from '../src/users/referralNotice';

describe('referral codes', () => {
  test('alphabet: 32 distinct upper-case letters and digits without I, O, 0, 1', () => {
    assert.equal(REFERRAL_CODE_ALPHABET.length, 32);
    assert.equal(new Set(REFERRAL_CODE_ALPHABET).size, 32);
    assert.match(REFERRAL_CODE_ALPHABET, /^[A-Z2-9]+$/);
    for (const ambiguous of 'IO01') assert.ok(!REFERRAL_CODE_ALPHABET.includes(ambiguous), ambiguous);
  });

  test('generated codes have 6 characters from the alphabet', () => {
    assert.equal(REFERRAL_CODE_LENGTH, 6);
    for (let i = 0; i < 1000; i++) {
      const code = generateReferralCode();
      assert.equal(code.length, 6, code);
      for (const ch of code) assert.ok(REFERRAL_CODE_ALPHABET.includes(ch), code);
      assert.ok(isReferralCode(code), code);
    }
  });

  test('randomness sanity: codes differ and every symbol is used about equally', () => {
    const n = 2000;
    const codes = Array.from({ length: n }, generateReferralCode);
    // 2000 draws from 32^6 codes: a single collision has p ≈ 0.002, five are practically impossible.
    assert.ok(new Set(codes).size >= n - 5, 'too many duplicate codes');

    const counts = new Map<string, number>();
    for (const ch of codes.join('')) counts.set(ch, (counts.get(ch) ?? 0) + 1);
    assert.equal(counts.size, 32, 'every symbol appears');
    // 12000 symbols → 375 expected each, σ ≈ 19; 250…500 is > 6σ either side.
    for (const [ch, count] of counts) assert.ok(count > 250 && count < 500, `${ch}: ${count}`);

    // Positions are independent: the first character is not stuck.
    assert.ok(new Set(codes.map((c) => c[0])).size > 25);
  });

  test('isReferralCode', () => {
    assert.ok(isReferralCode('K7QX2M'));
    for (const bad of ['K7QX2', 'K7QX2MM', 'k7qx2m', 'K7QX0M', 'K7QXIM', 'K7 X2M', null, 123456]) {
      assert.ok(!isReferralCode(bad), String(bad));
    }
  });

  test('normalizeEnteredCode', () => {
    assert.equal(normalizeEnteredCode(null), null);
    assert.equal(normalizeEnteredCode(undefined), null);
    assert.equal(normalizeEnteredCode('   '), null);
    assert.equal(normalizeEnteredCode(' k7qx2m '), 'K7QX2M');
    assert.equal(normalizeEnteredCode(123456), '123456');
  });
});

describe('referralNotApplied notification text', () => {
  /** Same script checks as the seeder (scripts/seed-data/index.ts). */
  const KURDISH_ONLY = /[یکەڕڵۆێڤپچژگ]/;
  const ARABIC_ONLY = /[يكةى]/;

  test('Arabic and Kurdish copy use their own letters', () => {
    const t = REFERRAL_NOT_APPLIED_TEXT;
    for (const s of [t.titleAr, t.bodyAr]) assert.ok(!KURDISH_ONLY.test(s), s);
    for (const s of [t.titleKu, t.bodyKu]) assert.ok(!ARABIC_ONLY.test(s), s);
    for (const s of Object.values(t)) assert.ok(s.trim().length > 0);
  });
});

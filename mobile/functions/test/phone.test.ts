/**
 * Phone normalisation decides whether two spellings of one number are one person.
 * Every case here is a real shape a form has produced.
 */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  looksLikePhone,
  maskPhone,
  normalizeDigits,
  normalizePhone,
  phoneKey,
  splitPhone,
} from '../src/auth/phone';

describe('normalizePhone', () => {
  for (const [input, expected, label] of [
    ['0750 123 4567', '+9647501234567', 'Iraqi local, spaced'],
    ['07501234567', '+9647501234567', 'Iraqi local, bare'],
    ['7501234567', '+9647501234567', 'national number without the trunk 0 (as users/{uid}.phone stores it)'],
    ['+964 750 123 4567', '+9647501234567', 'already international'],
    ['00964 750 1234567', '+9647501234567', '00 instead of +'],
    ['0750-123-4567', '+9647501234567', 'hyphenated'],
    ['(0750) 1234567', '+9647501234567', 'parenthesised'],
    ['  07501234567  ', '+9647501234567', 'padded'],
    ['+9647701234567', '+9647701234567', 'a different operator'],
  ]) {
    test(`reads "${input}" as ${expected} (${label})`, () => assert.equal(normalizePhone(input), expected));
  }

  test('reads Arabic-Indic digits, which is what the keyboard gives', () =>
    assert.equal(normalizePhone('٠٧٥٠١٢٣٤٥٦٧'), '+9647501234567'));

  test('reads Persian digits too', () => assert.equal(normalizePhone('۰۷۵۰۱۲۳۴۵۶۷'), '+9647501234567'));

  test('keeps a foreign number as its own country, not as Iraqi', () =>
    assert.equal(normalizePhone('+44 20 7946 0958'), '+442079460958'));

  for (const [input, label] of [
    ['', 'empty'],
    ['   ', 'blank'],
    ['abcdefg', 'letters'],
    ['0750123', 'too short'],
    ['075012345678901234', 'too long'],
    ['name@company.iq', 'an email'],
    [null, 'null'],
    [undefined, 'undefined'],
    [7501234567, 'a number, not a string'],
    [{ phone: '07501234567' }, 'an object'],
  ] as Array<[unknown, string]>) {
    test(`refuses ${label}`, () => assert.equal(normalizePhone(input), null));
  }

  test('is idempotent — normalising twice changes nothing', () => {
    const once = normalizePhone('0750 123 4567')!;
    assert.equal(normalizePhone(once), once);
  });

  test('collapses every spelling of one number onto one key', () => {
    const spellings = ['07501234567', '+964 750 123 4567', '00964-750-1234567', '٠٧٥٠١٢٣٤٥٦٧'];
    const keys = new Set(spellings.map((s) => phoneKey(normalizePhone(s)!)));
    // The whole point: one person, one rate-limit bucket, one account.
    assert.deepEqual([...keys], ['9647501234567']);
  });
});

describe('normalizeDigits', () => {
  test('leaves ASCII alone', () => assert.equal(normalizeDigits('0750'), '0750'));
  test('converts mixed scripts', () => assert.equal(normalizeDigits('٠٧5۰'), '0750'));
});

describe('looksLikePhone', () => {
  for (const v of ['07501234567', '+964 750 123 4567', '0750-123-4567']) {
    test(`yes for ${v}`, () => assert.equal(looksLikePhone(v), true));
  }
  for (const v of ['ava@example.com', 'Ava', '123']) {
    test(`no for ${v}`, () => assert.equal(looksLikePhone(v), false));
  }
});

describe('maskPhone', () => {
  test('shows enough to recognise and not enough to dial', () => {
    const masked = maskPhone('+9647501234567');
    assert.equal(masked, '+964 750 ••• 4567');
    assert.ok(!masked.includes('1234567'));
  });
  test('never echoes a short input in full', () => assert.equal(maskPhone('+12345'), '•••'));
});

describe('splitPhone', () => {
  test('→ the users/{uid} fields', () =>
    assert.deepEqual(splitPhone('+9647501234567'), { phone: '7501234567', countryCode: '+964' }));
  test('foreign numbers keep their own calling code', () =>
    assert.deepEqual(splitPhone('+442079460958'), { phone: '2079460958', countryCode: '+44' }));
});

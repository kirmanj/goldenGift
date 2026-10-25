import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { PromoRejection, PromoType, evaluatePromo, normalizePromoCode, parsePromoCode } from '../src/orders/promoRules';
import { parseDartEnums } from './dartSource';

/** Shared with mobile/test/core/promo_rules_test.dart — both must pass. */
const FIXTURE = path.resolve(__dirname, '../../test/fixtures/promo_cases.json');
const DART_RULES = path.resolve(__dirname, '../../lib/core/utils/promo_rules.dart');
const DART_MODEL = path.resolve(__dirname, '../../lib/models/promo_code_model.dart');

interface PromoCase {
  name: string;
  promo: (Record<string, unknown> & { code: string }) | null;
  lines: Array<{ productId: string; storeId: string; categoryIds: string[]; lineTotal: number }>;
  expected: { discount?: number; rejection?: string };
  now: string;
  userUsageCount: number;
  userOrderCount: number;
}

const cases = (JSON.parse(readFileSync(FIXTURE, 'utf8')) as { cases: PromoCase[] }).cases;

describe('promo rules (shared fixture)', () => {
  test('fixture has cases for every rejection', () => {
    assert.ok(cases.length >= 20);
    const seen = new Set(cases.map((c) => c.expected.rejection).filter(Boolean));
    for (const r of PromoRejection) assert.ok(seen.has(r), `no case for ${r}`);
  });

  for (const c of cases) {
    test(c.name, () => {
      // The Dart test reads the fixture through PromoCodeModel.fromMap, expiresAt as a date.
      const promo = c.promo === null ? null : parsePromoCode(c.promo.code, c.promo);
      const result = evaluatePromo(promo, {
        lines: c.lines,
        nowMs: Date.parse(c.now),
        userUsageCount: c.userUsageCount,
        userOrderCount: c.userOrderCount,
      });
      if (c.expected.rejection !== undefined) {
        assert.equal(result.rejection, c.expected.rejection);
        assert.equal(result.discount, 0);
      } else {
        assert.equal(result.rejection, null);
        assert.equal(result.discount, c.expected.discount);
      }
    });
  }
});

describe('promo rules ↔ Dart', () => {
  test('PromoRejection names and order match promo_rules.dart', () => {
    assert.deepEqual(parseDartEnums(DART_RULES).get('PromoRejection'), [...PromoRejection]);
  });
  test('PromoType matches promo_code_model.dart', () => {
    assert.deepEqual(parseDartEnums(DART_MODEL).get('PromoType'), [...PromoType]);
  });
  test('codes are normalised like PromoCodeModel.normalize', () => {
    assert.equal(normalizePromoCode(' gold 10 '), 'GOLD10');
    assert.equal(normalizePromoCode('eid\t10\n'), 'EID10');
  });
});

describe('parsePromoCode (PromoCodeModel.fromMap)', () => {
  test('defaults', () => {
    assert.deepEqual(parsePromoCode('eid10', {}), {
      code: 'EID10',
      type: 'percent',
      value: 0,
      maxDiscount: null,
      minOrder: null,
      usageLimit: null,
      usageCount: 0,
      perUserLimit: 1,
      firstOrderOnly: false,
      categoryIds: [],
      storeIds: [],
      isPublic: false,
      isActive: true,
      expiresAtMs: null,
    });
  });
  test('stored values, Firestore timestamps and numeric strings', () => {
    const expires = Timestamp.fromMillis(Date.UTC(2026, 11, 31));
    const p = parsePromoCode('X', {
      code: 'eid 10',
      type: 'fixed',
      value: '5000',
      maxDiscount: 2000.4,
      usageLimit: 3,
      usageCount: 2,
      perUserLimit: 0,
      categoryIds: ['mugs', 7],
      isActive: false,
      expiresAt: expires,
    });
    assert.equal(p.code, 'EID10');
    assert.equal(p.type, 'fixed');
    assert.equal(p.value, 5000);
    assert.equal(p.maxDiscount, 2000);
    assert.deepEqual(p.categoryIds, ['mugs']);
    assert.equal(p.perUserLimit, 0);
    assert.equal(p.isActive, false);
    assert.equal(p.expiresAtMs, expires.toMillis());
    assert.equal(parsePromoCode('X', { type: 'bogus' }).type, 'percent');
  });
  test('an unrestricted code splits nothing; maxDiscount 0 means no cap', () => {
    const promo = parsePromoCode('P', { type: 'percent', value: 50, maxDiscount: 0 });
    const r = evaluatePromo(promo, { lines: [{ productId: 'a', storeId: 's', categoryIds: [], lineTotal: 10001 }], nowMs: 0 });
    assert.deepEqual(r, { valid: true, discount: 5000, eligibleSubtotal: 10001, rejection: null });
  });
});

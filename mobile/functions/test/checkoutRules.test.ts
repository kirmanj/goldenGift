import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import {
  BAGHDAD_UTC_OFFSET_MS,
  DEFAULT_DELIVERY_SLOTS,
  addDays,
  availableSlots,
  baghdadNow,
  checkoutTotals,
  earliestDeliveryDate,
  lastDeliveryDate,
  meetsMinimum,
  parseCities,
  parseDeliverySlots,
  parseGeneralSettings,
  parseHm,
  parseIsoDate,
  parsePaymentSettings,
  type DeliverySlot,
} from '../src/orders/checkoutRules';

/** Shared with mobile/test/features/checkout/checkout_rules_fixture_test.dart — both must pass. */
const FIXTURE = path.resolve(__dirname, '../../test/fixtures/checkout_rules_cases.json');

interface Fixture {
  defaultSlots: DeliverySlot[];
  earliestDeliveryDate: Array<{ now: string; sameDayCutoff: string; maxPreparationDays: number; earliest: string }>;
  availableSlots: Array<{ date: string; now: string; slots: DeliverySlot[] | null; available: string[] }>;
  deliveryDates: Array<{ earliest: string; count: number; last: string }>;
}

const fixture = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

/** "2026-10-21T13:59" in Iraq → the instant (the server only ever sees instants). */
function instantOf(baghdadWallClock: string): number {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(baghdadWallClock);
  assert.ok(m, baghdadWallClock);
  const [y, mo, d, h, mi] = m.slice(1).map(Number);
  return Date.UTC(y, mo - 1, d, h, mi) - BAGHDAD_UTC_OFFSET_MS;
}

describe('checkout rules (shared fixture)', () => {
  test('fixture has cases', () => {
    assert.ok(fixture.earliestDeliveryDate.length > 10);
    assert.ok(fixture.availableSlots.length > 5);
  });

  test('default slots', () => {
    assert.deepEqual(DEFAULT_DELIVERY_SLOTS, fixture.defaultSlots);
    assert.deepEqual(parseDeliverySlots(undefined), fixture.defaultSlots);
    assert.deepEqual(parseDeliverySlots([]), fixture.defaultSlots);
  });

  for (const c of fixture.earliestDeliveryDate) {
    test(`earliest: ${c.now} cut-off "${c.sameDayCutoff}" +${c.maxPreparationDays} days → ${c.earliest}`, () => {
      assert.equal(earliestDeliveryDate(baghdadNow(instantOf(c.now)), c.maxPreparationDays, c.sameDayCutoff), c.earliest);
    });
  }

  for (const c of fixture.availableSlots) {
    test(`slots on ${c.date} at ${c.now} → [${c.available.join(', ')}]`, () => {
      const slots = c.slots === null ? DEFAULT_DELIVERY_SLOTS : c.slots;
      assert.deepEqual(
        availableSlots(c.date, baghdadNow(instantOf(c.now)), slots).map((s) => s.id),
        c.available,
      );
    });
  }

  for (const c of fixture.deliveryDates) {
    test(`delivery window ${c.earliest} → ${c.last}`, () => {
      assert.equal(lastDeliveryDate(c.earliest), c.last);
      assert.equal(addDays(c.earliest, c.count - 1), c.last);
    });
  }
});

describe('checkout rules (server details)', () => {
  test('Iraq time is UTC+3: 22:30 UTC is already tomorrow in Baghdad', () => {
    assert.deepEqual(baghdadNow(Date.UTC(2026, 9, 21, 22, 30)), { year: 2026, month: 10, day: 22, hour: 1, minute: 30 });
    assert.deepEqual(baghdadNow(Date.UTC(2026, 11, 31, 21, 0)), { year: 2027, month: 1, day: 1, hour: 0, minute: 0 });
    // 10:59 UTC = 13:59 Baghdad: still before a 14:00 cut-off.
    assert.equal(earliestDeliveryDate(baghdadNow(Date.UTC(2026, 9, 21, 10, 59)), 0, '14:00'), '2026-10-21');
    assert.equal(earliestDeliveryDate(baghdadNow(Date.UTC(2026, 9, 21, 11, 0)), 0, '14:00'), '2026-10-22');
  });

  test('parseHm', () => {
    assert.deepEqual(parseHm('14:00'), [14, 0]);
    assert.deepEqual(parseHm(' 9:05 '), [9, 5]);
    assert.equal(parseHm('24:00'), null);
    assert.equal(parseHm('12:60'), null);
    assert.equal(parseHm('1200'), null);
    assert.equal(parseHm(''), null);
  });

  test('parseIsoDate accepts only real calendar dates', () => {
    assert.deepEqual(parseIsoDate('2028-02-29'), { year: 2028, month: 2, day: 29 });
    for (const bad of ['2027-02-29', '2026-13-01', '2026-10-32', '2026-1-05', '26-10-21', '2026-10-21T00:00', 20261021, null]) {
      assert.equal(parseIsoDate(bad), null, String(bad));
    }
  });

  test('stored slots: missing fields read like DeliverySlot.fromMap', () => {
    assert.deepEqual(parseDeliverySlots([{ id: 'x' }, 'junk', { from: '09:00', to: '11:00' }]), [
      { id: 'x', from: '00:00', to: '23:59' },
      { id: '', from: '09:00', to: '11:00' },
    ]);
  });

  test('totals: discount, then credits, then wallet; never negative', () => {
    assert.deepEqual(checkoutTotals({ subtotal: 25000, deliveryFee: 3000 }), {
      subtotal: 25000,
      discount: 0,
      deliveryFee: 3000,
      creditsUsed: 0,
      walletUsed: 0,
      total: 28000,
    });
    assert.deepEqual(checkoutTotals({ subtotal: 10000, deliveryFee: 2000, discount: 15000, credits: 1500, wallet: 5000 }), {
      subtotal: 10000,
      discount: 10000,
      deliveryFee: 2000,
      creditsUsed: 1500,
      walletUsed: 500,
      total: 0,
    });
  });

  test('minimum order applies to the subtotal; 0 = none', () => {
    assert.equal(meetsMinimum(0, 0), true);
    assert.equal(meetsMinimum(9999, 10000), false);
    assert.equal(meetsMinimum(10000, 10000), true);
  });

  test('settings parsers use the app defaults', () => {
    assert.deepEqual(parseGeneralSettings(undefined), {
      sameDayCutoff: '14:00',
      minOrder: 0,
      deliverySlots: [...DEFAULT_DELIVERY_SLOTS],
    });
    assert.equal(parseGeneralSettings({ sameDayCutoff: 1400, minOrder: '5000' }).sameDayCutoff, '14:00');
    assert.equal(parseGeneralSettings({ minOrder: '5000' }).minOrder, 5000);
    assert.deepEqual(parseCities({ items: [{ id: 'erbil', deliveryFee: 3000 }, { id: 'duhok', deliveryFee: '4000', isActive: false }] }), [
      { id: 'erbil', deliveryFee: 3000, isActive: true },
      { id: 'duhok', deliveryFee: 4000, isActive: false },
    ]);
    assert.deepEqual(parsePaymentSettings(undefined), {
      cashOnDelivery: true,
      wallet: true,
      card: false,
      fastPay: false,
      zainCash: false,
    });
  });
});

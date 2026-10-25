import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { ALLOWED_NEXT, derivedOrderStatus, ORDER_FLOW } from '../src/orders/orderTransitions';
import { OrderStatus } from '../src/shared/enums';
import { stripDartComments } from './dartSource';

const FIXTURE = path.resolve(__dirname, '../../test/fixtures/order_status_transitions.json');
const ORDER_MODEL = path.resolve(__dirname, '../../lib/models/order_model.dart');

const fixture = JSON.parse(readFileSync(FIXTURE, 'utf8')) as { flow: string[]; allowedNext: Record<string, string[]> };

/** `OrderStatusX.allowedNext` and `flow`, read from the Dart source. */
function dartTransitions(): { flow: string[]; allowedNext: Record<string, string[]> } {
  const src = stripDartComments(readFileSync(ORDER_MODEL, 'utf8'));
  const start = src.indexOf('get allowedNext');
  assert.ok(start >= 0, 'allowedNext not found in order_model.dart');
  const body = src.slice(start, src.indexOf('};', start));
  const allowedNext: Record<string, string[]> = {};
  for (const m of body.matchAll(/((?:OrderStatus\.\w+\s*\|\|\s*)*OrderStatus\.\w+)\s*=>\s*const\s*\[([^\]]*)\]/g)) {
    const targets = [...m[2].matchAll(/OrderStatus\.(\w+)/g)].map((t) => t[1]);
    for (const from of m[1].matchAll(/OrderStatus\.(\w+)/g)) allowedNext[from[1]] = targets;
  }
  const flowMatch = /static\s+const\s+flow\s*=\s*\[([^\]]*)\]/.exec(src);
  assert.ok(flowMatch, 'flow not found in order_model.dart');
  return { flow: [...flowMatch[1].matchAll(/OrderStatus\.(\w+)/g)].map((m) => m[1]), allowedNext };
}

describe('order status transitions: TS ↔ fixture ↔ Dart', () => {
  test('flow', () => {
    assert.deepEqual([...ORDER_FLOW], fixture.flow);
    assert.deepEqual(dartTransitions().flow, fixture.flow);
  });
  test('allowedNext covers every status', () => {
    assert.deepEqual(Object.keys(fixture.allowedNext).sort(), [...OrderStatus].sort());
    assert.deepEqual(Object.keys(ALLOWED_NEXT).sort(), [...OrderStatus].sort());
  });
  test('allowedNext (TS = fixture)', () => {
    for (const s of OrderStatus) assert.deepEqual([...ALLOWED_NEXT[s]], fixture.allowedNext[s], s);
  });
  test('allowedNext (Dart source = fixture)', () => {
    assert.deepEqual(dartTransitions().allowedNext, fixture.allowedNext);
  });
});

describe('derivedOrderStatus', () => {
  const cases: Array<[OrderStatus[], OrderStatus | null]> = [
    [[], null],
    [['pending'], 'pending'],
    [['confirmed', 'pending'], 'pending'],
    [['preparing', 'outForDelivery'], 'preparing'],
    [['delivered', 'cancelledBySeller'], 'delivered'],
    [['cancelledBySeller', 'readyForDelivery', 'returned'], 'readyForDelivery'],
    [['cancelledBySeller', 'cancelledBySeller'], 'cancelledBySeller'],
    [['cancelledByBuyer', 'cancelledBySeller'], 'cancelledBySeller'],
    [['cancelledByBuyer'], 'cancelledByBuyer'],
    [['returned', 'cancelledBySeller'], 'returned'],
    [['refunded', 'refunded'], 'refunded'],
    [['refunded', 'cancelledBySeller'], 'cancelledBySeller'],
  ];
  for (const [lines, expected] of cases) {
    test(`[${lines.join(', ')}] → ${expected}`, () => assert.equal(derivedOrderStatus(lines), expected));
  }
});

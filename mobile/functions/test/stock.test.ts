import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { coversDemand, orderStockLines, stockDemand, stockUpdate } from '../src/orders/stock';

const product = (over: Record<string, unknown> = {}) => ({
  stock: 3,
  salesCount: 10,
  optionGroups: [
    { id: 'size', type: 'textVariant', values: [{ id: 's', stock: 2 }, { id: 'l', stock: null }, { id: 'm' }] },
    { id: 'name', type: 'text' },
  ],
  ...over,
});

describe('stock', () => {
  test('demand sums quantities per product and per value', () => {
    const demand = stockDemand([
      { productId: 'p1', qty: 2, values: [{ groupId: 'size', valueId: 's' }] },
      { productId: 'p1', qty: 1, values: [] },
      { productId: 'p2', qty: 4, values: [] },
    ]);
    assert.equal(demand.get('p1')?.qty, 3);
    assert.equal(demand.get('p1')?.values.get('size\u0000s'), 2);
    assert.equal(demand.get('p2')?.qty, 4);
  });

  test('covers: product stock and stocked values; null = unlimited', () => {
    const d = (qty: number, values: Array<{ groupId: string; valueId: string }> = []) =>
      stockDemand([{ productId: 'p', qty, values }]).get('p')!;
    assert.equal(coversDemand(product(), d(3)), true);
    assert.equal(coversDemand(product(), d(4)), false);
    assert.equal(coversDemand(product({ stock: null }), d(1000)), true);
    assert.equal(coversDemand(product({ stock: 0 }), d(1)), false);
    assert.equal(coversDemand(product(), d(2, [{ groupId: 'size', valueId: 's' }])), true);
    assert.equal(coversDemand(product(), d(3, [{ groupId: 'size', valueId: 's' }])), false);
    assert.equal(coversDemand(product({ stock: null }), d(50, [{ groupId: 'size', valueId: 'l' }])), true);
  });

  test('reserve: stock down, salesCount up, stocked values down, the rest untouched', () => {
    const demand = stockDemand([{ productId: 'p', qty: 2, values: [{ groupId: 'size', valueId: 's' }] }]).get('p')!;
    const update = stockUpdate(product(), demand, 1);
    assert.equal(update.stock, 1);
    assert.equal(update.salesCount, 12);
    assert.deepEqual(update.optionGroups, [
      { id: 'size', type: 'textVariant', values: [{ id: 's', stock: 0 }, { id: 'l', stock: null }, { id: 'm' }] },
      { id: 'name', type: 'text' },
    ]);
  });

  test('reserve on unlimited stock only counts the sale', () => {
    const demand = stockDemand([{ productId: 'p', qty: 2, values: [{ groupId: 'size', valueId: 'l' }] }]).get('p')!;
    assert.deepEqual(stockUpdate(product({ stock: null }), demand, 1), { salesCount: 12 });
  });

  test('release: the mirror image; salesCount never below 0', () => {
    const demand = stockDemand([{ productId: 'p', qty: 2, values: [{ groupId: 'size', valueId: 's' }] }]).get('p')!;
    const update = stockUpdate(product({ salesCount: 1 }), demand, -1);
    assert.equal(update.stock, 5);
    assert.equal(update.salesCount, 0);
    const values = (update.optionGroups as Array<{ values?: Array<{ stock?: number | null }> }>)[0].values!;
    assert.equal(values[0].stock, 4);
  });

  test('order items → stock lines', () => {
    assert.deepEqual(
      orderStockLines([
        { productId: 'p1', qty: 2, selections: [{ groupId: 'size', valueId: 's' }, { groupId: 'name', text: 'x' }] },
        { productId: 'p2', qty: '3' },
        'junk',
      ]),
      [
        { productId: 'p1', qty: 2, values: [{ groupId: 'size', valueId: 's' }] },
        { productId: 'p2', qty: 3, values: [] },
      ],
    );
  });
});

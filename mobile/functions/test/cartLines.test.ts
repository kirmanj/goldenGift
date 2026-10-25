import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { checkCartLine, orderItem, productIsOrderable } from '../src/orders/cartLines';

/** A product with every kind of option group (prices in IQD). */
function product(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    title: 'Photo Frame',
    titleAr: 'إطار صور',
    titleKu: 'چوارچێوەی وێنە',
    storeId: 'home',
    images: ['https://img/1.jpg', 'https://img/2.jpg'],
    price: 20000,
    isActive: true,
    availability: 'preparationDays',
    preparationDays: 1,
    stock: 5,
    optionGroups: [
      {
        id: 'frame',
        type: 'imageVariant',
        label: 'Frame',
        labelAr: 'الإطار',
        required: true,
        sortOrder: 0,
        values: [
          { id: 'walnut', label: 'Walnut', labelKu: 'گوێز', priceDelta: 5000, preparationDaysOverride: 3 },
          { id: 'black', label: 'Black', priceDelta: 0, stock: 2 },
        ],
      },
      { id: 'color', type: 'colorSwatch', label: 'Color', required: false, values: [{ id: 'gold', label: 'Gold', hex: '#C9A227', priceDelta: 1000 }] },
      { id: 'name', type: 'text', label: 'Name', required: false, maxLength: 12 },
      { id: 'when', type: 'date', label: 'Date', required: false },
      { id: 'photos', type: 'photoUpload', label: 'Photos', required: true, minPhotos: 2, maxPhotos: 3 },
      { id: 'qty', type: 'quantity', label: 'Quantity' },
    ],
    ...over,
  };
}

/** A cart line as the app writes it (CartItemModel.toMap). */
function cartItem(over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    productId: 'p1',
    storeId: 'home',
    titleSnapshot: 'Photo Frame',
    imageSnapshot: 'https://img/1.jpg',
    unitPrice: 25000,
    qty: 2,
    selections: [
      { groupId: 'frame', type: 'imageVariant', label: 'Frame', valueId: 'walnut', valueLabel: 'Walnut', priceDelta: 5000 },
      { groupId: 'name', type: 'text', label: 'Name', text: '  Sara  ', priceDelta: 0 },
      { groupId: 'when', type: 'date', label: 'Date', date: '2026-11-02T00:00:00.000', priceDelta: 0 },
      { groupId: 'photos', type: 'photoUpload', label: 'Photos', urls: ['https://u/1.jpg', 'https://u/2.jpg'], priceDelta: 0 },
    ],
    lineTotal: 50000,
    preparationDays: 3,
    ...over,
  };
}

const store = { status: 'active' };

describe('checkCartLine', () => {
  test('a valid line is re-priced from the product: price + Σ priceDelta, max preparation days', () => {
    const check = checkCartLine('line-1', cartItem(), product(), store);
    assert.equal(check.kind, 'ok');
    assert.ok(check.kind === 'ok');
    assert.equal(check.line.unitPrice, 25000);
    assert.equal(check.line.lineTotal, 50000);
    assert.equal(check.line.preparationDays, 3);
    assert.equal(check.line.qty, 2);
    assert.equal(check.line.storeId, 'home');
    assert.deepEqual(check.line.stockedValues, []);
  });

  test('the order snapshot takes labels from the product and text / date / urls from the cart', () => {
    const check = checkCartLine('line-1', cartItem(), product(), store);
    assert.ok(check.kind === 'ok');
    assert.deepEqual(check.line.selections, [
      { groupId: 'frame', type: 'imageVariant', label: 'Frame', labelAr: 'الإطار', valueId: 'walnut', valueLabel: 'Walnut', valueLabelKu: 'گوێز', priceDelta: 5000 },
      { groupId: 'name', type: 'text', label: 'Name', text: 'Sara', priceDelta: 0 },
      { groupId: 'when', type: 'date', label: 'Date', date: '2026-11-02T00:00:00.000', priceDelta: 0 },
      { groupId: 'photos', type: 'photoUpload', label: 'Photos', urls: ['https://u/1.jpg', 'https://u/2.jpg'], priceDelta: 0 },
    ]);
    assert.deepEqual(orderItem(check.line, 'pending'), {
      id: 'line-1',
      productId: 'p1',
      storeId: 'home',
      titleSnapshot: 'Photo Frame',
      titleSnapshotAr: 'إطار صور',
      titleSnapshotKu: 'چوارچێوەی وێنە',
      imageSnapshot: 'https://img/1.jpg',
      unitPrice: 25000,
      qty: 2,
      selections: check.line.selections,
      lineTotal: 50000,
      preparationDays: 3,
      status: 'pending',
    });
  });

  test('a value with its own stock is reported for the stock check', () => {
    const item = cartItem({
      unitPrice: 20000,
      preparationDays: 1,
      selections: [
        { groupId: 'frame', type: 'imageVariant', valueId: 'black', priceDelta: 0 },
        { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] },
      ],
    });
    const check = checkCartLine('l', item, product(), store);
    assert.ok(check.kind === 'ok');
    assert.deepEqual(check.line.stockedValues, [{ groupId: 'frame', valueId: 'black' }]);
  });

  test('price changed → stale, with the refreshed price and priceDelta for the cart', () => {
    const p = product();
    (p.optionGroups as Array<Record<string, unknown>>)[0].values = [{ id: 'walnut', label: 'Walnut', priceDelta: 7000, preparationDaysOverride: 3 }];
    const check = checkCartLine('l', cartItem(), { ...p, price: 21000 }, store);
    assert.equal(check.kind, 'stale');
    assert.ok(check.kind === 'stale');
    assert.equal(check.line.unitPrice, 28000);
    assert.equal(check.refresh.unitPrice, 28000);
    assert.equal(check.refresh.lineTotal, 56000);
    assert.equal(check.refresh.preparationDays, 3);
    const selections = check.refresh.selections as Array<Record<string, unknown>>;
    assert.equal(selections[0].priceDelta, 7000);
    assert.equal(selections[1].text, '  Sara  '); // the cart's own data is kept as written
  });

  test('preparation days changed → stale', () => {
    const check = checkCartLine('l', cartItem({ preparationDays: 1 }), product(), store);
    assert.equal(check.kind, 'stale');
  });

  const unavailable: Array<[string, Record<string, unknown>, Record<string, unknown> | undefined, Record<string, unknown> | undefined]> = [
    ['the product is gone', cartItem(), undefined, store],
    ['the product is inactive', cartItem(), product({ isActive: false }), store],
    ['the product is marked out of stock', cartItem(), product({ availability: 'outOfStock' }), store],
    ['the store is suspended', cartItem(), product(), { status: 'suspended' }],
    ['the store is pending approval', cartItem(), product(), { status: 'pendingApproval' }],
    ['the chosen value no longer exists', cartItem({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'oak' }, { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] }] }), product(), store],
    ['the option group no longer exists', cartItem({ selections: [...(cartItem().selections as unknown[]), { groupId: 'ribbon', type: 'text', text: 'x' }] }), product(), store],
    ['the option changed type', cartItem({ selections: [{ groupId: 'frame', type: 'textVariant', valueId: 'walnut' }, { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] }] }), product(), store],
    ['the same group twice', cartItem({ selections: [...(cartItem().selections as unknown[]), { groupId: 'name', type: 'text', text: 'Ali' }] }), product(), store],
    ['a required group is not filled', cartItem({ selections: [{ groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] }] }), product(), store],
    ['too few photos', cartItem({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'walnut' }, { groupId: 'photos', type: 'photoUpload', urls: ['a'] }] }), product(), store],
    ['too many photos', cartItem({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'walnut' }, { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b', 'c', 'd'] }] }), product(), store],
    ['text longer than maxLength', cartItem({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'walnut' }, { groupId: 'name', type: 'text', text: 'x'.repeat(13) }, { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] }] }), product(), store],
    ['qty 0', cartItem({ qty: 0 }), product(), store],
    ['qty 100', cartItem({ qty: 100 }), product(), store],
    ['qty 1.5', cartItem({ qty: 1.5 }), product(), store],
    ['qty as a string', cartItem({ qty: '2' }), product(), store],
    ['no productId', cartItem({ productId: '' }), product(), store],
  ];
  for (const [label, item, p, s] of unavailable) {
    test(`unavailable: ${label}`, () => {
      assert.equal(checkCartLine('l', item, p, s).kind, 'unavailable');
    });
  }

  test('maxLength counts code points, like the app (an emoji is one)', () => {
    const item = cartItem({ selections: [{ groupId: 'frame', type: 'imageVariant', valueId: 'walnut' }, { groupId: 'name', type: 'text', text: '🎁'.repeat(12) }, { groupId: 'photos', type: 'photoUpload', urls: ['a', 'b'] }] });
    assert.notEqual(checkCartLine('l', item, product(), store).kind, 'unavailable');
  });

  test('a store doc that does not exist does not close the product (resolveLine)', () => {
    assert.equal(productIsOrderable(product(), undefined), true);
    assert.equal(checkCartLine('l', cartItem(), product(), undefined).kind, 'ok');
  });

  test('numeric stock is not checked here (→ out_of_stock in placeOrder)', () => {
    assert.equal(checkCartLine('l', cartItem(), product({ stock: 0 }), store).kind, 'ok');
  });

  test('isActive missing counts as active (ProductModel default)', () => {
    const p = product();
    delete p.isActive;
    assert.equal(checkCartLine('l', cartItem(), p, store).kind, 'ok');
  });
});

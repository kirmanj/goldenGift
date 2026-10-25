import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import { buildProductRecord, colorDots, isIndexable, searchText } from '../src/search/productRecord';
import { searchRecordChanged } from '../src/products/onProductWrite';
import { buildSeed } from '../scripts/seed-data';

const CREATED = Timestamp.fromMillis(Date.UTC(2026, 0, 5, 9, 0, 0) + 789);

const swatch = (sortOrder: number, hexes: Array<string | undefined>, id = `colors-${sortOrder}`) => ({
  id,
  type: 'colorSwatch',
  label: 'Color',
  sortOrder,
  values: hexes.map((hex, i) => ({ id: `v${i}`, label: `V${i}`, priceDelta: 0, ...(hex !== undefined && { hex }) })),
});

const product = () => ({
  title: 'Engraved Pen',
  titleAr: 'قلم محفور باسمك',
  titleKu: 'پێنووسی هەڵکۆڵراو',
  description: 'Not in the record',
  descriptionAr: '',
  descriptionKu: '',
  storeId: 'golden-gift-home',
  categoryIds: ['engraving', 'graduation'],
  images: ['https://img/1.jpg', 'https://img/2.jpg', 'https://img/3.jpg'],
  price: 15000,
  compareAtPrice: 18000,
  currency: 'IQD',
  isActive: true,
  isFeatured: true,
  availability: 'preparationDays',
  preparationDays: 2,
  availableCities: ['erbil', 'duhok'],
  stock: 12,
  salesCount: 40,
  viewCount: 900,
  ratingAvg: 4.5,
  ratingCount: 8,
  tags: ['pen', 'Graduation'],
  giftFor: ['men', 'companies', 'men', 'kids'],
  optionGroups: [
    { id: 'name', type: 'text', label: 'Name', sortOrder: 0, maxLength: 20 },
    swatch(2, ['#000000']),
    swatch(1, ['#C0C0C0', '#1A1A1C', '#C9A227', '#B76E79', '#1F3A5F', '#FFFFFF']),
  ],
  createdAt: CREATED,
  updatedAt: Timestamp.now(),
});

describe('buildProductRecord', () => {
  test('exact record shape (small: what search results render)', () => {
    assert.deepEqual(buildProductRecord('pen-1', product()), {
      objectID: 'pen-1',
      title: 'Engraved Pen',
      titleAr: 'قلم محفور باسمك',
      titleKu: 'پێنووسی هەڵکۆڵراو',
      images: ['https://img/1.jpg', 'https://img/2.jpg'],
      price: 15000,
      compareAtPrice: 18000,
      hasDiscount: true,
      priceBand: 0,
      isFeatured: true,
      isActive: true,
      availability: 'preparationDays',
      preparationDays: 2,
      stock: 12,
      categoryIds: ['engraving', 'graduation'],
      cityKeys: ['erbil', 'duhok'],
      catCityKeys: ['engraving|erbil', 'engraving|duhok', 'graduation|erbil', 'graduation|duhok'],
      giftFor: ['men', 'companies'],
      salesCount: 40,
      ratingAvg: 4.5,
      ratingCount: 8,
      createdAt: Math.floor(CREATED.toMillis() / 1000),
      colorDots: ['#C0C0C0', '#1A1A1C', '#C9A227', '#B76E79', '#1F3A5F'],
      tags: ['pen', 'Graduation'],
      searchText: 'engraved pen قلم محفور باسمک پێنووسی هەڵکۆڵراو pen graduation',
    });
  });

  test('createdAt is epoch seconds from a Timestamp, Date, millis or ISO string; null when missing', () => {
    const seconds = Math.floor(CREATED.toMillis() / 1000);
    for (const createdAt of [CREATED, CREATED.toDate(), CREATED.toMillis(), CREATED.toDate().toISOString()]) {
      assert.equal(buildProductRecord('p', { ...product(), createdAt }).createdAt, seconds);
    }
    assert.ok(Number.isInteger(seconds) && seconds < 1e10, 'seconds, not millis');
    assert.equal(buildProductRecord('p', { ...product(), createdAt: undefined }).createdAt, null);
    assert.equal(buildProductRecord('p', { ...product(), createdAt: 'not a date' }).createdAt, null);
  });

  test('derived fields are recomputed, never copied from stale stored values', () => {
    const r = buildProductRecord('p', {
      ...product(),
      price: 250000,
      compareAtPrice: null,
      availableCities: [],
      hasDiscount: true,
      priceBand: 0,
      cityKeys: ['erbil'],
      catCityKeys: ['x|y'],
    });
    assert.equal(r.priceBand, 4);
    assert.equal(r.hasDiscount, false);
    assert.equal(r.compareAtPrice, null);
    assert.deepEqual(r.cityKeys, ['all']);
    assert.deepEqual(r.catCityKeys, ['engraving|all', 'graduation|all']);
  });

  test('defaults like ProductModel.fromMap for a sparse document', () => {
    assert.deepEqual(buildProductRecord('bare', { title: 'Bare', availability: 'teleport' }), {
      objectID: 'bare',
      title: 'Bare',
      titleAr: '',
      titleKu: '',
      images: [],
      price: 0,
      compareAtPrice: null,
      hasDiscount: false,
      priceBand: 0,
      isFeatured: false,
      isActive: true,
      availability: 'sameDay',
      preparationDays: 0,
      stock: null,
      categoryIds: [],
      cityKeys: ['all'],
      catCityKeys: [],
      giftFor: [],
      salesCount: 0,
      ratingAvg: 0,
      ratingCount: 0,
      createdAt: null,
      colorDots: [],
      tags: [],
      searchText: 'bare',
    });
  });

  test('no description, option groups, viewCount or other heavy fields in the record', () => {
    const keys = Object.keys(buildProductRecord('p', product()));
    for (const heavy of ['description', 'optionGroups', 'viewCount', 'searchKeywords', 'forKeys', 'updatedAt', 'storeId']) {
      assert.ok(!keys.includes(heavy), heavy);
    }
  });

  test('every seeded product builds a JSON-serializable record with its colour dots', () => {
    const seeded = buildSeed().filter((d) => d.collection === 'products');
    for (const p of seeded) {
      const r = buildProductRecord(p.id, p.data);
      assert.deepEqual(JSON.parse(JSON.stringify(r)), r, p.id);
      assert.ok(r.searchText.length > 0, p.id);
      for (const hex of r.colorDots) assert.match(hex, /^#[0-9A-F]{6}$/, p.id);
    }
    assert.ok(seeded.some((p) => buildProductRecord(p.id, p.data).colorDots.length > 0));
  });
});

describe('colorDots', () => {
  test('first colour-swatch group by sortOrder, at most 5, non-empty hex only', () => {
    assert.deepEqual(colorDots([swatch(1, ['#111111', '', undefined, '#222222'])]), ['#111111', '#222222']);
    assert.deepEqual(colorDots([swatch(5, ['#555555']), swatch(3, ['#333333'])]), ['#333333']);
    // Equal sortOrder: the earlier group wins (stable).
    assert.deepEqual(colorDots([swatch(1, ['#AAAAAA'], 'a'), swatch(1, ['#BBBBBB'], 'b')]), ['#AAAAAA']);
    assert.deepEqual(colorDots([swatch(0, Array(9).fill('#ABCDEF'))]).length, 5);
  });

  test('no swatch group, or junk → []', () => {
    assert.deepEqual(colorDots([{ id: 't', type: 'text', sortOrder: 0 }]), []);
    assert.deepEqual(colorDots(undefined), []);
    assert.deepEqual(colorDots('nope'), []);
    assert.deepEqual(colorDots([null, 3, { type: 'colorSwatch', values: [null, { hex: 7 }, { hex: '#123456' }] }]), [
      '#123456',
    ]);
  });
});

describe('searchText', () => {
  test('SearchTokenizer.normalize of each text, joined by spaces', () => {
    // ك → ک, ي → ی, diacritics + tatweel stripped, lower-cased; empty texts skipped.
    assert.equal(searchText(['Gold MUG', '', 'كُوبٌ ذهبـي', 'کوپی']), 'gold mug کوب ذهبی کوپی');
    assert.equal(searchText([]), '');
  });

  test('a Kurdish-keyboard query normalizes to the indexed text (ك/ک, ي/ی)', () => {
    const indexed = buildProductRecord('p', { title: 'Mug', titleAr: 'كوب ذهبي', titleKu: 'کوپی زێڕین' }).searchText;
    assert.ok(indexed.includes('کوب ذهبی'));
    assert.ok(!/[كي]/.test(indexed), 'only the unified letters remain');
  });
});

describe('isIndexable / searchRecordChanged', () => {
  test('isActive defaults to true; only an explicit false hides the product', () => {
    assert.equal(isIndexable({}), true);
    assert.equal(isIndexable({ isActive: true }), true);
    assert.equal(isIndexable({ isActive: false }), false);
    assert.equal(isIndexable(undefined), false);
    assert.equal(isIndexable(null), false);
  });

  test('changes the record does not show are not search changes', () => {
    const p = product();
    assert.equal(searchRecordChanged('p', p, { ...p, viewCount: 901, updatedAt: Timestamp.now() }), false);
    assert.equal(searchRecordChanged('p', p, { ...p, description: 'New copy' }), false);
    // The derived write-back (what onProductWrite writes) is not one either.
    assert.equal(searchRecordChanged('p', p, { ...p, priceBand: 0, hasDiscount: true, searchKeywords: ['x'] }), false);
    assert.equal(searchRecordChanged('p', p, { ...p, forKeys: ['men'] }), false);
  });

  test('record fields, (de)activation, creation and deletion are', () => {
    const p = product();
    assert.equal(searchRecordChanged('p', p, { ...p, price: 16000 }), true);
    assert.equal(searchRecordChanged('p', p, { ...p, salesCount: 41 }), true);
    assert.equal(searchRecordChanged('p', p, { ...p, images: ['https://img/9.jpg'] }), true);
    assert.equal(searchRecordChanged('p', p, { ...p, giftFor: ['women'] }), true);
    assert.equal(searchRecordChanged('p', p, { ...p, isActive: false }), true);
    assert.equal(searchRecordChanged('p', { ...p, isActive: false }, p), true);
    assert.equal(searchRecordChanged('p', undefined, p), true);
    assert.equal(searchRecordChanged('p', p, undefined), true);
    // Inactive before and after: nothing in the index either way.
    assert.equal(searchRecordChanged('p', { ...p, isActive: false }, { ...p, isActive: false, price: 1 }), false);
  });
});

import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import type { GiftAudience } from '../src/shared/enums';
import {
  REEL_DERIVED_FIELDS,
  derivedReelFields,
  reelFilterKey,
  reelFilterKeysOf,
  reelProductSnapshot,
  staleReelFields,
} from '../src/shared/reelDerived';

/** Shared with mobile/test/features/reels/ (Dart `ReelKeys` / `ReelDerived`) — both must pass. */
const FIXTURE = path.resolve(__dirname, '../../test/fixtures/product_query_keys.json');

interface Fixture {
  reelKeys: {
    filterKey: Array<{ category?: string; audience?: GiftAudience; filterKey: string | null }>;
    derived: Array<{
      reel: Record<string, unknown>;
      product: Record<string, unknown> | null;
      output: Record<string, unknown>;
    }>;
  };
}

const { reelKeys } = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

describe('reel derived fields (shared fixture)', () => {
  test('fixture has cases', () => {
    assert.ok(reelKeys.filterKey.length > 0);
    assert.ok(reelKeys.derived.length > 0);
  });

  for (const k of reelKeys.filterKey) {
    test(`filterKey ${k.category ?? '-'} / ${k.audience ?? '-'} = ${k.filterKey}`, () => {
      assert.equal(reelFilterKey({ categoryId: k.category, audience: k.audience }), k.filterKey);
    });
  }

  for (const { reel, product, output } of reelKeys.derived) {
    test(`derived ${JSON.stringify(reel)} + ${product === null ? 'no product' : String(product.title)}`, () => {
      const derived = derivedReelFields(reel, product);
      // Every field, nothing more (the dashboard writes exactly these keys).
      assert.deepEqual(Object.keys(output).sort(), [...REEL_DERIVED_FIELDS].sort());
      assert.deepEqual(derived, output);
      // A reel holding the fixture output is up to date.
      assert.deepEqual(staleReelFields({ ...reel, ...output }, derived), {});
    });
  }
});

describe('reel derived fields — details', () => {
  const product = {
    title: 'Gold Mug',
    titleAr: 'كوب ذهبي',
    titleKu: '',
    storeId: 'golden-gift-home',
    images: ['https://img/1.jpg', 'https://img/2.jpg'],
    price: 30000,
    compareAtPrice: 35000,
    categoryIds: ['mugs', 'love'],
    giftFor: ['men', 'women'],
    isActive: true,
  };

  test('filterKeysOf: categories, gift types, then every pair', () => {
    assert.deepEqual(reelFilterKeysOf(['a'], ['companies']), ['cat:a', 'for:companies', 'cat:a|for:companies']);
    assert.deepEqual(reelFilterKeysOf([], ['men']), ['for:men']);
    assert.deepEqual(reelFilterKeysOf([], []), []);
    assert.equal(reelFilterKey({}), null);
    assert.equal(reelFilterKey({ categoryId: null, audience: null }), null);
  });

  test('product snapshot: empty translations omitted, first image, whole IQD', () => {
    assert.deepEqual(reelProductSnapshot(product), {
      title: 'Gold Mug',
      titleAr: 'كوب ذهبي',
      image: 'https://img/1.jpg',
      price: 30000,
      compareAtPrice: 35000,
      isActive: true,
    });
    const sparse = { price: '12000', compareAtPrice: 14999.6, images: [7, 'https://img/x.jpg'] };
    assert.deepEqual(reelProductSnapshot(sparse), {
      title: '',
      image: 'https://img/x.jpg',
      price: 12000,
      compareAtPrice: 15000,
      isActive: true,
    });
    assert.equal(reelProductSnapshot({ isActive: 'no' }).isActive, true, 'isActive defaults to true');
  });

  test('tolerant input: junk categories / gift types, missing reel isActive = active', () => {
    const d = derivedReelFields({}, {
      ...product,
      categoryIds: ['mugs', '', 'mugs', 3],
      giftFor: ['women', 'kids', 'women'],
    });
    assert.deepEqual(d.categoryIds, ['mugs']);
    assert.deepEqual(d.giftFor, ['women']);
    assert.deepEqual(d.filterKeys, ['cat:mugs', 'for:women', 'cat:mugs|for:women']);
    assert.equal(d.visible, true);
    assert.equal(d.storeId, 'golden-gift-home');
    assert.equal(derivedReelFields({}, { ...product, storeId: 42 }).storeId, '');
  });

  test('visible only when the reel AND the product are active and the product exists', () => {
    assert.equal(derivedReelFields({ isActive: true }, product).visible, true);
    assert.equal(derivedReelFields({ isActive: false }, product).visible, false);
    assert.equal(derivedReelFields({ isActive: true }, { ...product, isActive: false }).visible, false);
    assert.equal(derivedReelFields({ isActive: true }, null).visible, false);
    assert.equal(derivedReelFields({ isActive: true }, undefined).visible, false);
  });

  test('staleReelFields: only the fields that differ; map key order irrelevant, arrays in order', () => {
    const derived = derivedReelFields({ isActive: true }, product);
    const fresh = { productId: 'p1', isActive: true, ...derived };
    assert.deepEqual(staleReelFields(fresh, derived), {});

    // Same product map with its keys in another order (Firestore does not keep them).
    const reordered = { ...fresh, product: Object.fromEntries(Object.entries(derived.product!).reverse()) };
    assert.deepEqual(staleReelFields(reordered, derived), {});

    const stale = {
      ...fresh,
      priceBand: 3,
      filterKeys: [...derived.filterKeys].reverse(),
      product: { ...derived.product, titleKu: 'old' },
      visible: false,
    };
    assert.deepEqual(Object.keys(staleReelFields(stale, derived)).sort(), [
      'filterKeys',
      'priceBand',
      'product',
      'visible',
    ]);
    assert.deepEqual(staleReelFields(stale, derived).product, derived.product);

    // A reel without any derived field (just written by an old client) gets all of them.
    const bare = { productId: 'p1', isActive: true };
    assert.deepEqual(Object.keys(staleReelFields(bare, derived)), [...REEL_DERIVED_FIELDS]);
    // A product that is gone: product null, nothing to filter on, hidden.
    assert.deepEqual(staleReelFields(fresh, derivedReelFields(fresh, null)), {
      storeId: '',
      product: null,
      categoryIds: [],
      giftFor: [],
      priceBand: 0,
      filterKeys: [],
      visible: false,
    });
  });
});

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { GiftAudience, OptionType } from '../src/shared/enums';
import { Timestamp } from 'firebase-admin/firestore';
import { derivedProductFields } from '../src/shared/productDerived';
import { keywords } from '../src/shared/searchTokenizer';
import { DAY_MS, PRODUCT_EPOCH_MS, buildSeed, validateSeed } from '../scripts/seed-data';

describe('seed data', () => {
  const docs = buildSeed();
  const of = (c: string) => docs.filter((d) => d.collection === c);

  test('passes validateSeed()', () => {
    assert.deepEqual(validateSeed(docs), []);
  });

  test('document counts', () => {
    assert.equal(of('categories').length, 50);
    assert.equal(of('products').length, 20);
    assert.equal(of('banners').length, 6);
    assert.equal(of('stores').length, 1);
    assert.deepEqual(of('app_settings').map((d) => d.id), ['general', 'cities', 'referral', 'payments']);
  });

  test('app_settings/general has store urls for the force-update button', () => {
    const general = of('app_settings').find((d) => d.id === 'general');
    assert.deepEqual(general?.data.storeUrls, {
      ios: '',
      android: 'https://play.google.com/store/apps/details?id=com.goldengift.golden_gift',
    });
  });

  test('every OptionType is used', () => {
    const used = new Set(
      of('products').flatMap((p) => (p.data.optionGroups as Array<{ type: string }>).map((g) => g.type)),
    );
    assert.deepEqual([...OptionType].filter((t) => !used.has(t)), []);
  });

  test('every product says who it is a gift for (known GiftAudience values), and every gift type has products', () => {
    for (const p of of('products')) {
      const giftFor = p.data.giftFor as string[];
      assert.ok(giftFor.length >= 1, p.id);
      for (const a of giftFor) assert.ok((GiftAudience as readonly string[]).includes(a), `${p.id}: ${a}`);
      assert.ok((p.data.forKeys as string[]).includes(giftFor[0]), `${p.id}: forKeys`);
    }
    for (const a of GiftAudience) {
      assert.ok(of('products').filter((p) => (p.data.giftFor as string[]).includes(a)).length >= 2, a);
    }
  });

  test('unknown or missing gift types fail validation', () => {
    const docs2 = buildSeed();
    const [first, second] = docs2.filter((d) => d.collection === 'products');
    first.data.giftFor = ['kids'];
    second.data.giftFor = [];
    const problems = validateSeed(docs2);
    assert.ok(problems.some((e) => e.includes(`product ${first.id}: unknown giftFor kids`)));
    assert.ok(problems.some((e) => e.includes(`product ${second.id}: needs 1–3 giftFor values`)));
  });

  test('category productCount matches products', () => {
    const counts = new Map<string, number>();
    for (const p of of('products')) {
      for (const c of p.data.categoryIds as string[]) counts.set(c, (counts.get(c) ?? 0) + 1);
    }
    for (const c of of('categories')) assert.equal(c.data.productCount, counts.get(c.id) ?? 0, c.id);
  });

  test('searchKeywords = keywords(title variants + tags)', () => {
    for (const p of of('products')) {
      const d = p.data;
      const expected = keywords([d.title, d.titleAr, d.titleKu, ...(d.tags as string[])] as string[]);
      assert.deepEqual(d.searchKeywords, expected, p.id);
    }
  });

  test('derived query fields are written, exactly as onProductWrite computes them', () => {
    for (const p of of('products')) {
      const d = p.data;
      const derived = derivedProductFields(d);
      for (const [field, value] of Object.entries(derived)) assert.deepEqual(d[field], value, `${p.id}.${field}`);
    }
    const breakfast = of('products').find((p) => (p.data.availableCities as string[]).length > 0)!;
    assert.deepEqual(breakfast.data.cityKeys, breakfast.data.availableCities);
    assert.ok(of('products').some((p) => p.data.hasDiscount === true));
    assert.ok(of('products').some((p) => p.data.hasDiscount === false));
    assert.ok(new Set(of('products').map((p) => p.data.priceBand)).size >= 3, 'several price bands');
  });

  test('stale derived fields fail validation', () => {
    const docs2 = buildSeed();
    const p = docs2.find((d) => d.collection === 'products')!;
    p.data.priceBand = 4;
    assert.ok(validateSeed(docs2).some((e) => e.includes('derived field priceBand is stale')));
  });

  test('product createdAt is fixed (one day apart, last = newest) across builds', () => {
    const millis = (docs_: typeof docs) =>
      docs_.filter((d) => d.collection === 'products').map((d) => (d.data.createdAt as Timestamp).toMillis());
    const first = millis(docs);
    assert.deepEqual(millis(buildSeed()), first);
    assert.deepEqual(first, first.map((_, i) => PRODUCT_EPOCH_MS + i * DAY_MS));
  });

  test('build is deterministic (idempotent re-runs)', () => {
    const strip = (x: unknown) => JSON.stringify(x, (k, v) => (k === 'updatedAt' || k === 'createdAt' ? undefined : v));
    assert.equal(strip(buildSeed()), strip(docs));
  });
});

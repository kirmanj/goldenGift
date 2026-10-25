import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import {
  ALL_CITIES,
  DERIVED_PRODUCT_FIELDS,
  PRICE_BAND_BOUNDS,
  PRICE_BAND_COUNT,
  catCityAnyOf,
  cityAnyOf,
  derivedProductFields,
  forAnyOf,
  forKey,
  giftAudiencesOf,
  priceBandOf,
  staleDerivedFields,
} from '../src/shared/productDerived';
import type { GiftAudience } from '../src/shared/enums';
import { keywords } from '../src/shared/searchTokenizer';

/** Shared with mobile/test/features/products/product_query_test.dart — both must pass. */
const FIXTURE = path.resolve(__dirname, '../../test/fixtures/product_query_keys.json');

interface Fixture {
  priceBandBounds: number[];
  priceBand: Array<{ price: number; band: number }>;
  derived: Array<{ input: Record<string, unknown>; output: Record<string, unknown> }>;
  queryKeys: Array<{ category: string; city: string; cityAnyOf: string[]; catCityAnyOf: string[] }>;
  forQueryKeys: Array<{ audience: GiftAudience; category?: string; city?: string; forAnyOf: string[] }>;
}

const fixture = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

describe('product derived fields (shared fixture)', () => {
  test('fixture has cases', () => {
    assert.ok(fixture.priceBand.length > 0);
    assert.ok(fixture.derived.length > 0);
    assert.ok(fixture.queryKeys.length > 0);
    assert.ok(fixture.forQueryKeys.length > 0);
    assert.ok(fixture.derived.some((d) => Array.isArray(d.output.forKeys) && d.output.forKeys.length > 0));
  });

  test('price band bounds', () => {
    assert.deepEqual([...PRICE_BAND_BOUNDS], fixture.priceBandBounds);
    assert.equal(PRICE_BAND_COUNT, fixture.priceBandBounds.length + 1);
  });

  for (const { price, band } of fixture.priceBand) {
    test(`priceBandOf(${price}) = ${band}`, () => assert.equal(priceBandOf(price), band));
  }

  for (const { input, output } of fixture.derived) {
    test(`derived ${JSON.stringify(input)}`, () => {
      const derived = derivedProductFields(input) as unknown as Record<string, unknown>;
      assert.ok(Object.keys(output).length > 0);
      for (const [field, expected] of Object.entries(output)) assert.deepEqual(derived[field], expected, field);
    });
  }

  for (const k of fixture.queryKeys) {
    test(`query keys ${k.category} / ${k.city}`, () => {
      assert.deepEqual(cityAnyOf(k.city), k.cityAnyOf);
      assert.deepEqual(catCityAnyOf(k.category, k.city), k.catCityAnyOf);
    });
  }

  for (const k of fixture.forQueryKeys) {
    test(`gift-type query keys ${k.audience} / ${k.category ?? '-'} / ${k.city ?? '-'}`, () => {
      assert.deepEqual(forAnyOf(k.audience, { categoryId: k.category, cityId: k.city }), k.forAnyOf);
    });
  }
});

describe('product derived fields — details', () => {
  const product = {
    title: 'Gold Mug',
    titleAr: 'كوب ذهبي',
    titleKu: 'کوپی زێڕین',
    tags: ['mug', 'gold'],
    price: 30000,
    compareAtPrice: 35000,
    categoryIds: ['mugs', 'birthdays'],
    availableCities: ['erbil'],
  };

  test('searchKeywords = keywords(title variants + tags), like the seeder and the app', () => {
    assert.deepEqual(
      derivedProductFields(product).searchKeywords,
      keywords(['Gold Mug', 'كوب ذهبي', 'کوپی زێڕین', 'mug', 'gold']),
    );
  });

  test('the query keys the app sends match a product deliverable there', () => {
    const restricted = derivedProductFields(product);
    assert.ok(cityAnyOf('erbil').some((k) => restricted.cityKeys.includes(k)));
    assert.ok(!cityAnyOf('basra').some((k) => restricted.cityKeys.includes(k)));
    assert.ok(catCityAnyOf('mugs', 'erbil').some((k) => restricted.catCityKeys.includes(k)));
    assert.ok(!catCityAnyOf('frames', 'erbil').some((k) => restricted.catCityKeys.includes(k)));

    const everywhere = derivedProductFields({ ...product, availableCities: [] });
    assert.deepEqual(everywhere.cityKeys, [ALL_CITIES]);
    assert.ok(catCityAnyOf('mugs', 'basra').some((k) => everywhere.catCityKeys.includes(k)));
  });

  test('tolerant input: missing fields, numeric strings, duplicates and junk entries', () => {
    assert.deepEqual(derivedProductFields({}), {
      hasDiscount: false,
      priceBand: 0,
      cityKeys: ['all'],
      catCityKeys: [],
      forKeys: [],
      searchKeywords: [],
    });
    const d = derivedProductFields({
      price: '60000',
      compareAtPrice: 75000.4,
      categoryIds: ['a', 'a', 7, '', 'b'],
      availableCities: ['erbil', null, 'erbil'],
      giftFor: ['women', 'Women', null, 'women', 'kids'],
    });
    assert.equal(d.priceBand, 2);
    assert.equal(d.hasDiscount, true);
    assert.deepEqual(d.cityKeys, ['erbil']);
    assert.deepEqual(d.catCityKeys, ['a|erbil', 'b|erbil']);
    assert.deepEqual(d.forKeys, [
      'women',
      'women|cat:a',
      'women|cat:b',
      'women|city:erbil',
      'women|cat:a|city:erbil',
      'women|cat:b|city:erbil',
    ]);
    assert.deepEqual(derivedProductFields({ giftFor: 'men' }).forKeys, [], 'not a list');
  });

  test('giftAudiencesOf: known values only, de-duplicated, first-seen order (Dart giftAudiencesOf)', () => {
    assert.deepEqual(giftAudiencesOf(['companies', 'men', 'companies', 'nobody', 3, 'women']), [
      'companies',
      'men',
      'women',
    ]);
    assert.deepEqual(giftAudiencesOf(undefined), []);
    assert.deepEqual(giftAudiencesOf({ men: true }), []);
  });

  test('the gift-type keys the app sends match a product for that audience there', () => {
    const forHer = derivedProductFields({ ...product, giftFor: ['women'] });
    const matches = (keys: string[]) => keys.some((k) => forHer.forKeys.includes(k));
    assert.ok(matches(forAnyOf('women')));
    assert.ok(matches(forAnyOf('women', { categoryId: 'mugs' })));
    assert.ok(matches(forAnyOf('women', { cityId: 'erbil' })));
    assert.ok(matches(forAnyOf('women', { categoryId: 'mugs', cityId: 'erbil' })));
    assert.ok(!matches(forAnyOf('men')));
    assert.ok(!matches(forAnyOf('women', { categoryId: 'frames' })));
    assert.ok(!matches(forAnyOf('women', { cityId: 'basra' })));
    // Unrestricted products answer every city through `city:all`.
    const everywhere = derivedProductFields({ ...product, availableCities: [], giftFor: ['companies'] });
    const anywhere = forAnyOf('companies', { categoryId: 'birthdays', cityId: 'basra' });
    assert.ok(anywhere.some((k) => everywhere.forKeys.includes(k)));
    assert.equal(forKey('men', { categoryId: 'mugs', cityKey: 'all' }), 'men|cat:mugs|city:all');
  });

  test('compareAtPrice below, equal to or missing → no discount', () => {
    for (const compareAtPrice of [20000, 30000, null, undefined]) {
      assert.equal(derivedProductFields({ ...product, compareAtPrice }).hasDiscount, false, String(compareAtPrice));
    }
  });

  test('negative prices fall in band 0, huge ones in the last band', () => {
    assert.equal(priceBandOf(-1), 0);
    assert.equal(priceBandOf(Number.MAX_SAFE_INTEGER), PRICE_BAND_COUNT - 1);
  });

  test('staleDerivedFields: only the fields that differ, arrays compared in order', () => {
    const fresh = { ...product, ...derivedProductFields(product) };
    assert.deepEqual(staleDerivedFields(fresh), {});

    const stale = { ...fresh, priceBand: 3, cityKeys: ['all'], catCityKeys: [...fresh.catCityKeys].reverse() };
    assert.deepEqual(Object.keys(staleDerivedFields(stale)).sort(), ['catCityKeys', 'cityKeys', 'priceBand']);
    assert.deepEqual(staleDerivedFields(stale).priceBand, 1);

    // A document without any derived field gets all of them.
    assert.deepEqual(Object.keys(staleDerivedFields(product)), [...DERIVED_PRODUCT_FIELDS]);
  });
});

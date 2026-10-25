import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { DEFAULT_ALGOLIA_INDEX, algoliaIndex, resolveAlgolia, type AlgoliaIndex } from '../src/search/algolia';
import {
  DEFAULT_RANKING,
  FILTER_ATTRIBUTES,
  PRIMARY_SETTINGS,
  REPLICAS,
  configureAlgoliaIndices,
  settingsPlan,
} from '../src/search/algoliaSettings';
import { buildProductRecord } from '../src/search/productRecord';
import { applyReindex, planFromDocs } from '../scripts/algolia/reindex';
import { FakeAlgolia } from './fakeAlgolia';

describe('resolveAlgolia', () => {
  const opened: Array<{ appId: string; adminKey: string; indexName: string }> = [];
  const open = (c: { appId: string; adminKey: string }, indexName: string): AlgoliaIndex => {
    opened.push({ ...c, indexName });
    return new FakeAlgolia().index(indexName);
  };
  const deployed = {};

  test('no App ID and / or no admin key → not configured, with the reason', () => {
    const cases: Array<[Parameters<typeof resolveAlgolia>[0], string]> = [
      [{}, 'ALGOLIA_APP_ID and ALGOLIA_ADMIN_KEY not set'],
      [{ appId: '', adminKey: '' }, 'ALGOLIA_APP_ID and ALGOLIA_ADMIN_KEY not set'],
      [{ appId: 'APP123', adminKey: '  ' }, 'ALGOLIA_ADMIN_KEY not set'],
      [{ appId: '', adminKey: 'secret' }, 'ALGOLIA_APP_ID not set'],
    ];
    for (const [config, reason] of cases) {
      assert.deepEqual(resolveAlgolia(config, deployed, open), { index: null, reason });
    }
    assert.equal(opened.length, 0, 'nothing opened');
  });

  test('configured → opens the named index (default "products")', () => {
    const named = resolveAlgolia({ appId: ' APP123 ', adminKey: 'secret', indexName: 'products_test' }, deployed, open);
    assert.equal(named.index?.name, 'products_test');
    const fallback = resolveAlgolia({ appId: 'APP123', adminKey: 'secret', indexName: '' }, deployed, open);
    assert.equal(fallback.index?.name, DEFAULT_ALGOLIA_INDEX);
    assert.deepEqual(opened.slice(-2), [
      { appId: 'APP123', adminKey: 'secret', indexName: 'products_test' },
      { appId: 'APP123', adminKey: 'secret', indexName: 'products' },
    ]);
  });

  test('Functions emulator: off even with credentials, unless ALGOLIA_EMULATOR_SYNC=true', () => {
    const config = { appId: 'APP123', adminKey: 'secret' };
    const off = resolveAlgolia(config, { FUNCTIONS_EMULATOR: 'true' }, open);
    assert.equal(off.index, null);
    assert.match(off.reason!, /emulator/);
    const on = resolveAlgolia(config, { FUNCTIONS_EMULATOR: 'true', ALGOLIA_EMULATOR_SYNC: 'true' }, open);
    assert.equal(on.index?.name, 'products');
  });

  test('the real index is created lazily (no network until a method is called)', () => {
    const index = algoliaIndex({ appId: 'APP123', adminKey: 'not-a-real-key' }, 'products');
    assert.equal(index.name, 'products');
    for (const m of ['saveObject', 'saveObjects', 'deleteObject', 'setSettings'] as const) {
      assert.equal(typeof index[m], 'function');
    }
  });
});

describe('Algolia index settings', () => {
  test('primary: searchable attributes, filter-only facets, prefixAll, ar + en, typos, popularity', () => {
    assert.deepEqual(PRIMARY_SETTINGS.searchableAttributes, ['searchText', 'title', 'titleAr', 'titleKu', 'tags']);
    assert.deepEqual(PRIMARY_SETTINGS.attributesForFaceting, [
      'filterOnly(categoryIds)',
      'filterOnly(cityKeys)',
      'filterOnly(catCityKeys)',
      'filterOnly(giftFor)',
      'filterOnly(availability)',
      'filterOnly(hasDiscount)',
      'filterOnly(isFeatured)',
      'filterOnly(isActive)',
      'filterOnly(priceBand)',
    ]);
    assert.equal(PRIMARY_SETTINGS.queryType, 'prefixAll');
    assert.deepEqual(PRIMARY_SETTINGS.queryLanguages, ['ar', 'en']);
    assert.equal(PRIMARY_SETTINGS.typoTolerance, true);
    assert.deepEqual(PRIMARY_SETTINGS.customRanking, ['desc(salesCount)']);
  });

  test('every filter attribute is a record field', () => {
    const record = buildProductRecord('p', {}) as unknown as Record<string, unknown>;
    for (const a of FILTER_ATTRIBUTES) assert.ok(a in record, a);
    for (const a of PRIMARY_SETTINGS.searchableAttributes!) assert.ok(a in record, a);
    for (const r of REPLICAS) assert.ok(r.sort.replace(/^(asc|desc)\((\w+)\)$/, '$2') in record, r.sort);
  });

  test('plan: replicas declared, primary forwarded, then each replica sorted', () => {
    const plan = settingsPlan('products');
    assert.deepEqual(
      plan.map((s) => [s.index, s.forwardToReplicas]),
      [
        ['products', false],
        ['products', true],
        ['products_newest', false],
        ['products_popular', false],
        ['products_price_asc', false],
        ['products_price_desc', false],
      ],
    );
    assert.deepEqual(plan[0].settings, {
      replicas: ['products_newest', 'products_popular', 'products_price_asc', 'products_price_desc'],
    });
    assert.equal(plan[1].settings, PRIMARY_SETTINGS);
    const ranking = Object.fromEntries(plan.slice(2).map((s) => [s.index, s.settings.ranking]));
    assert.deepEqual(ranking, {
      products_newest: ['desc(createdAt)', ...DEFAULT_RANKING],
      products_popular: ['desc(salesCount)', ...DEFAULT_RANKING],
      products_price_asc: ['asc(price)', ...DEFAULT_RANKING],
      products_price_desc: ['desc(price)', ...DEFAULT_RANKING],
    });
    // Standard replicas (sorted by `ranking`), not virtual ones.
    assert.ok(!JSON.stringify(plan).includes('virtual('));
  });

  test('configureAlgoliaIndices applies the plan in order and is repeatable', async () => {
    const fake = new FakeAlgolia();
    const configured = await configureAlgoliaIndices((name) => fake.index(name), 'products');
    assert.deepEqual(configured, [
      'products',
      'products_newest',
      'products_popular',
      'products_price_asc',
      'products_price_desc',
    ]);
    const first = structuredClone([...fake.settings]);
    await configureAlgoliaIndices((name) => fake.index(name), 'products');
    assert.deepEqual([...fake.settings], first, 'converges');
    assert.equal(fake.calls.length, 12);
    assert.deepEqual(fake.settings.get('products')?.replicas?.length, 4);
    assert.deepEqual(fake.settings.get('products_price_asc')?.ranking?.[0], 'asc(price)');
  });
});

describe('reindex (in memory)', () => {
  const docs = [
    { id: 'a', data: { title: 'A', price: 1000, isActive: true } },
    { id: 'b', data: { title: 'B', price: 2000 } },
    { id: 'c', data: { title: 'C', price: 3000, isActive: false } },
    { id: 'd', data: { title: 'D', price: 4000, isActive: true } },
  ];

  test('planFromDocs: active (or unset) → records, isActive false → delete', () => {
    const plan = planFromDocs(docs);
    assert.equal(plan.total, 4);
    assert.deepEqual(plan.records.map((r) => r.objectID), ['a', 'b', 'd']);
    assert.deepEqual(plan.inactiveIds, ['c']);
  });

  test('applyReindex pushes in batches, then deletes inactive records', async () => {
    const fake = new FakeAlgolia();
    const index = fake.index('products');
    await index.saveObject(buildProductRecord('c', docs[2].data)); // stale record of the inactive product
    const progress: number[] = [];
    const result = await applyReindex(index, planFromDocs(docs), 2, (n) => progress.push(n));
    assert.deepEqual(result, { batches: 2, deleted: 1 });
    assert.deepEqual(progress, [2, 3]);
    assert.deepEqual(
      fake.calls.slice(1).map((c) => [c.op, 'objectIDs' in c ? c.objectIDs : 'objectID' in c ? c.objectID : '']),
      [
        ['saveObjects', ['a', 'b']],
        ['saveObjects', ['d']],
        ['deleteObject', 'c'],
      ],
    );
    assert.deepEqual([...fake.records.get('products')!.keys()].sort(), ['a', 'b', 'd']);
  });
});

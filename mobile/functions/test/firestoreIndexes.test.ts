/**
 * mobile/firestore.indexes.json covers every product query shape the app builds
 * (SRS §5.8 AC; `FirestoreProductSource.buildQuery`) and the Reels feed (§5.27,
 * `visible == true` + one optional `filterKeys` filter + `priceBand in`, newest
 * first). Firestore merges per-field composite indexes for equality / array
 * filters that share the orderBy, so one (filter field, sort field) index per
 * pair serves every filter combination.
 * The emulator does not enforce indexes — this test is the guard.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { DERIVED_PRODUCT_FIELDS } from '../src/shared/productDerived';

const INDEXES = path.resolve(__dirname, '../../firestore.indexes.json');

interface IndexField {
  fieldPath: string;
  order?: 'ASCENDING' | 'DESCENDING';
  arrayConfig?: 'CONTAINS';
}
interface Index {
  collectionGroup: string;
  queryScope: string;
  fields: IndexField[];
}

const spec = JSON.parse(readFileSync(INDEXES, 'utf8')) as { indexes: Index[]; fieldOverrides: unknown[] };
const fieldKey = (f: IndexField) => `${f.fieldPath}:${f.order ?? f.arrayConfig}`;
/** `group(fields)`; collection-group indexes are marked `group[*](fields)`. */
const indexKey = (i: Index) =>
  `${i.collectionGroup}${i.queryScope === 'COLLECTION_GROUP' ? '[*]' : ''}(${i.fields.map(fieldKey).join(',')})`;

/** The collection-group queries: expireCredits (credit_lots), the review moderation queue and the store aggregate (reviews). */
const COLLECTION_GROUP_QUERIES = ['credit_lots', 'reviews'];

/** Equality / `in` filters (ASCENDING) and array filters (CONTAINS) the products list uses. */
const PRODUCT_FILTERS: IndexField[] = [
  { fieldPath: 'isActive', order: 'ASCENDING' },
  { fieldPath: 'categoryIds', arrayConfig: 'CONTAINS' },
  { fieldPath: 'cityKeys', arrayConfig: 'CONTAINS' },
  { fieldPath: 'catCityKeys', arrayConfig: 'CONTAINS' },
  // Gift type (+ category, + city): SRS §5.8a.
  { fieldPath: 'forKeys', arrayConfig: 'CONTAINS' },
  { fieldPath: 'availability', order: 'ASCENDING' },
  { fieldPath: 'hasDiscount', order: 'ASCENDING' },
  { fieldPath: 'isFeatured', order: 'ASCENDING' },
  { fieldPath: 'priceBand', order: 'ASCENDING' },
  { fieldPath: 'searchKeywords', arrayConfig: 'CONTAINS' },
];
const PRODUCT_SORTS: IndexField[] = [
  { fieldPath: 'createdAt', order: 'DESCENDING' },
  { fieldPath: 'salesCount', order: 'DESCENDING' },
  { fieldPath: 'price', order: 'ASCENDING' },
  { fieldPath: 'price', order: 'DESCENDING' },
];

describe('firestore.indexes.json', () => {
  test('Firebase CLI format', () => {
    assert.ok(Array.isArray(spec.indexes));
    assert.ok(Array.isArray(spec.fieldOverrides));
    for (const i of spec.indexes) {
      assert.equal(typeof i.collectionGroup, 'string');
      // Only credit_lots (expireCredits) and reviews (moderation, store ratings) are queried as collection groups.
      if (i.collectionGroup === 'credit_lots') assert.equal(i.queryScope, 'COLLECTION_GROUP', indexKey(i));
      else if (i.collectionGroup === 'reviews') assert.ok(['COLLECTION', 'COLLECTION_GROUP'].includes(i.queryScope), indexKey(i));
      else assert.equal(i.queryScope, 'COLLECTION', indexKey(i));
      assert.ok(i.fields.length >= 2, `${indexKey(i)}: composite indexes have 2+ fields`);
      for (const f of i.fields) {
        assert.deepEqual(Object.keys(f).sort(), f.arrayConfig ? ['arrayConfig', 'fieldPath'] : ['fieldPath', 'order']);
        if (f.order) assert.ok(['ASCENDING', 'DESCENDING'].includes(f.order), fieldKey(f));
        if (f.arrayConfig) assert.equal(f.arrayConfig, 'CONTAINS', fieldKey(f));
      }
    }
    const keys = spec.indexes.map(indexKey);
    assert.equal(new Set(keys).size, keys.length, 'no duplicates');
    for (const i of spec.indexes.filter((x) => x.queryScope === 'COLLECTION_GROUP')) {
      assert.ok(COLLECTION_GROUP_QUERIES.includes(i.collectionGroup), indexKey(i));
    }
  });

  // The dashboard's unfiltered review queue (collectionGroup('reviews').orderBy('createdAt', desc))
  // needs collection-group single-field indexes on createdAt; an override replaces the
  // defaults for that field, so the collection-scope ones are listed again.
  test('fieldOverrides: reviews.createdAt also indexed for collection-group queries', () => {
    assert.deepEqual(spec.fieldOverrides, [
      {
        collectionGroup: 'reviews',
        fieldPath: 'createdAt',
        indexes: [
          { order: 'ASCENDING', queryScope: 'COLLECTION' },
          { order: 'DESCENDING', queryScope: 'COLLECTION' },
          { arrayConfig: 'CONTAINS', queryScope: 'COLLECTION' },
          { order: 'ASCENDING', queryScope: 'COLLECTION_GROUP' },
          { order: 'DESCENDING', queryScope: 'COLLECTION_GROUP' },
        ],
      },
    ]);
  });

  // Catalogue lists: one (filter, sort) index per pair. Dashboard store scope
  // (sellers, SRS §9): storeId + newest, and storeId + one keyword + newest.
  const STORE_SCOPE = [
    'products(storeId:ASCENDING,createdAt:DESCENDING)',
    'products(storeId:ASCENDING,searchKeywords:CONTAINS,createdAt:DESCENDING)',
  ];
  // Phase 10: the two Home sections that run on every open (Featured; signed-in
  // "For you") get their exact composite index, so they never depend on index
  // merging (documented for equality filters, not for array-contains).
  const HOME_HOT_PATHS = [
    'products(isActive:ASCENDING,isFeatured:ASCENDING,createdAt:DESCENDING)',
    'products(isActive:ASCENDING,categoryIds:CONTAINS,salesCount:DESCENDING)',
  ];

  test('products: one (filter, sort) index per pair + the store scope + the Home hot paths — and nothing else', () => {
    const pairs = PRODUCT_SORTS.flatMap((s) => PRODUCT_FILTERS.map((f) => `products(${fieldKey(f)},${fieldKey(s)})`));
    const actual = spec.indexes.filter((i) => i.collectionGroup === 'products').map(indexKey);
    assert.equal(pairs.length, 40);
    assert.deepEqual([...actual].sort(), [...pairs, ...STORE_SCOPE, ...HOME_HOT_PATHS].sort());
  });

  test('every derived query field has its indexes', () => {
    const filtered = new Set(PRODUCT_FILTERS.map((f) => f.fieldPath));
    for (const f of DERIVED_PRODUCT_FIELDS) assert.ok(filtered.has(f), f);
  });

  test('categories: isActive == , orderBy sortOrder', () => {
    const categories = spec.indexes.filter((i) => i.collectionGroup === 'categories').map(indexKey);
    assert.deepEqual(categories, ['categories(isActive:ASCENDING,sortOrder:ASCENDING)']);
  });

  // Admin Orders filters (SRS §9): one equality filter + createdAt each;
  // Firestore merges them for combined filters.
  test('every other index (orders, wallets, gift cards, requests, reviews, payments, reels) — and nothing else', () => {
    const others = spec.indexes
      .filter((i) => !['products', 'categories'].includes(i.collectionGroup))
      .map(indexKey);
    assert.deepEqual(others, [
      // Home banners and the gift-card shop: active ones in their sort order.
      'banners(isActive:ASCENDING,sortOrder:ASCENDING)',
      'gift_card_templates(isActive:ASCENDING,sortOrder:ASCENDING)',
      'orders(userId:ASCENDING,createdAt:DESCENDING)',
      'orders(storeIds:CONTAINS,createdAt:DESCENDING)',
      'orders(status:ASCENDING,createdAt:DESCENDING)',
      'orders(address.city:ASCENDING,createdAt:DESCENDING)',
      'orders(paymentMethod:ASCENDING,createdAt:DESCENDING)',
      'orders(promoCode:ASCENDING,createdAt:DESCENDING)',
      'referrals(status:ASCENDING,createdAt:DESCENDING)',
      // onUserCreate monthly cap (SRS §5.19): referrerUid == + createdAt >= month start.
      'referrals(referrerUid:ASCENDING,createdAt:ASCENDING)',
      // expireCredits: open == true, expiresAt <= now, orderBy expiresAt.
      'credit_lots[*](open:ASCENDING,expiresAt:ASCENDING)',
      'orders(storeIds:CONTAINS,status:ASCENDING,createdAt:DESCENDING)',
      'gift_cards(status:ASCENDING,createdAt:DESCENDING)',
      'special_requests(status:ASCENDING,lastMessageAt:DESCENDING)',
      'special_requests(type:ASCENDING,lastMessageAt:DESCENDING)',
      'special_requests(lastMessageBy:ASCENDING,lastMessageAt:DESCENDING)',
      'notifications(userId:ASCENDING,createdAt:DESCENDING)',
      'special_requests(userId:ASCENDING,createdAt:DESCENDING)',
      // sendScheduledGiftCards: status == pending, scheduledAt <= now; status in […], expiresAt <= now.
      'gift_cards(status:ASCENDING,scheduledAt:ASCENDING)',
      'gift_cards(status:ASCENDING,expiresAt:ASCENDING)',
      // Dashboard review queue (collection group, newest first; Firestore merges them for combined filters).
      'reviews[*](isApproved:ASCENDING,createdAt:DESCENDING)',
      'reviews[*](rating:ASCENDING,createdAt:DESCENDING)',
      'reviews[*](storeId:ASCENDING,createdAt:DESCENDING)',
      // onReviewWrite: store aggregate — storeId == , isApproved == true, average(rating).
      'reviews[*](storeId:ASCENDING,isApproved:ASCENDING,rating:ASCENDING)',
      // App: a product's approved reviews, newest first; onReviewWrite: its aggregate (average(rating)).
      'reviews(isApproved:ASCENDING,createdAt:DESCENDING)',
      'reviews(isApproved:ASCENDING,rating:ASCENDING)',
      // Dashboard Secret Santa monitoring: status == , newest first.
      'secret_santa_groups(status:ASCENDING,createdAt:DESCENDING)',
      // Dashboard revenue tile: status in […], createdAt range, sum(total).
      'orders(status:ASCENDING,createdAt:ASCENDING,total:ASCENDING)',
      // expirePaymentSessions: unpaid gateway orders past paymentDueBy; pending sessions past expiresAt.
      'orders(paymentStatus:ASCENDING,paymentDueBy:ASCENDING)',
      'payment_sessions(status:ASCENDING,expiresAt:ASCENDING)',
      // Phase 10: the seller's Orders view is always scoped by storeIds; its city /
      // payment filters get exact indexes like status (no reliance on array-contains merging).
      'orders(storeIds:CONTAINS,address.city:ASCENDING,createdAt:DESCENDING)',
      'orders(storeIds:CONTAINS,paymentMethod:ASCENDING,createdAt:DESCENDING)',
      // Phase 11 Reels feed (SRS §5.27): visible == true [+ filterKeys array-contains]
      // [+ priceBand in], newest first — one (filter, createdAt) index per filter, merged.
      'reels(visible:ASCENDING,createdAt:DESCENDING)',
      'reels(filterKeys:CONTAINS,createdAt:DESCENDING)',
      'reels(priceBand:ASCENDING,createdAt:DESCENDING)',
      // The feed's filtered shapes, explicitly (not left to index merging).
      'reels(visible:ASCENDING,filterKeys:CONTAINS,createdAt:DESCENDING)',
      'reels(visible:ASCENDING,priceBand:ASCENDING,createdAt:DESCENDING)',
      'reels(visible:ASCENDING,filterKeys:CONTAINS,priceBand:ASCENDING,createdAt:DESCENDING)',
    ]);
  });
});

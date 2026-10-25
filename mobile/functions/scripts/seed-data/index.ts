import { isDeepStrictEqual } from 'node:util';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import {
  BannerActionType,
  BannerPlacement,
  CategoryType,
  GiftAudience,
  OptionType,
  ProductAvailability,
} from '../../src/shared/enums';
import { FirestorePaths } from '../../src/shared/paths';
import { DERIVED_PRODUCT_FIELDS, derivedProductFields } from '../../src/shared/productDerived';
import { BANNERS, placeholderImage } from './banners';
import { CATEGORIES } from './categories';
import { HOME_STORE_ID, loc, type FirestoreData, type SeedDoc } from './helpers';
import { PRODUCTS, type OptionGroupSeed, type OptionValueSeed, type ProductSeed } from './products';
import { CITIES, GENERAL_SETTINGS, HOME_STORE, PAYMENT_SETTINGS, REFERRAL_SETTINGS } from './settings';

/**
 * Product `createdAt` values are fixed and staggered one day apart from this
 * instant (instead of server timestamps) so "newest" ordering is deterministic:
 * the last entry of PRODUCTS is the newest. Re-seeding writes the same values.
 */
export const PRODUCT_EPOCH_MS = Date.UTC(2026, 0, 1, 9, 0, 0);
export const DAY_MS = 24 * 60 * 60 * 1000;

const timestamps = () => ({
  createdAt: FieldValue.serverTimestamp(),
  updatedAt: FieldValue.serverTimestamp(),
});

/** Every document the seeder writes, in write order. */
export function buildSeed(): SeedDoc[] {
  const productCount = new Map<string, number>();
  for (const p of PRODUCTS) {
    for (const c of p.categoryIds) productCount.set(c, (productCount.get(c) ?? 0) + 1);
  }

  const categories: SeedDoc[] = CATEGORIES.map((c, i) => ({
    collection: FirestorePaths.categories,
    id: c.id,
    data: {
      ...loc('title', c.title),
      iconUrl: null,
      type: c.type,
      sortOrder: i,
      isActive: true,
      isSeasonal: false,
      activeFrom: null,
      activeTo: null,
      parentId: null,
      productCount: productCount.get(c.id) ?? 0,
      ...timestamps(),
    },
  }));

  const store: SeedDoc = {
    collection: FirestorePaths.stores,
    id: HOME_STORE.id,
    data: {
      ...loc('name', HOME_STORE.name),
      ...loc('description', HOME_STORE.description),
      logoUrl: placeholderImage(['GG'], 512, 512),
      coverUrl: placeholderImage(['Golden Gift Home']),
      ownerUid: null,
      phone: HOME_STORE.phone,
      city: HOME_STORE.city,
      status: HOME_STORE.status,
      ratingAvg: 0,
      ratingCount: 0,
      productCount: PRODUCTS.length,
      ordersCount: 0,
      commissionPercent: 0,
      payoutInfo: {},
      ...timestamps(),
    },
  };

  const products: SeedDoc[] = PRODUCTS.map((p, i) => ({
    collection: FirestorePaths.products,
    id: p.id,
    data: productData(p, i),
  }));

  const banners: SeedDoc[] = BANNERS.map((b) => ({
    collection: FirestorePaths.banners,
    id: b.id,
    data: {
      imageUrl: placeholderImage(b.text),
      imageUrlAr: placeholderImage([...b.text, 'AR']),
      imageUrlKu: placeholderImage([...b.text, 'KU']),
      placement: b.placement,
      action: { type: b.action.type, value: b.action.value },
      sortOrder: b.sortOrder,
      isActive: true,
      startAt: null,
      endAt: null,
      ...timestamps(),
    },
  }));

  const settings = (id: string, data: FirestoreData): SeedDoc => ({
    collection: FirestorePaths.appSettings,
    id,
    data: { ...data, ...timestamps() },
  });
  const appSettings: SeedDoc[] = [
    settings('general', GENERAL_SETTINGS),
    settings('cities', {
      items: CITIES.map((c) => ({
        id: c.id,
        ...loc('name', c.name),
        deliveryFee: c.deliveryFee,
        isActive: true,
      })),
    }),
    settings('referral', REFERRAL_SETTINGS),
    settings('payments', PAYMENT_SETTINGS),
  ];

  return [...categories, store, ...products, ...banners, ...appSettings];
}

/**
 * Mirrors `ProductModel.toMap()` plus timestamps and the derived query fields
 * (`hasDiscount`, `priceBand`, `cityKeys`, `catCityKeys`, `forKeys`,
 * `searchKeywords` — SRS §6.4), computed exactly as `onProductWrite` does, so the
 * function finds nothing to rewrite and the data is queryable even without the
 * function running.
 */
function productData(p: ProductSeed, index: number): FirestoreData {
  const data: FirestoreData = {
    ...loc('title', p.title),
    ...loc('description', p.description),
    storeId: HOME_STORE_ID,
    categoryIds: p.categoryIds,
    images: [1, 2, 3].map((n) => `https://picsum.photos/seed/gg-${p.id}-${n}/800/800`),
    price: p.price,
    compareAtPrice: p.compareAtPrice ?? null,
    currency: 'IQD',
    isActive: true,
    isFeatured: p.isFeatured ?? false,
    availability: p.availability,
    preparationDays: p.preparationDays,
    availableCities: p.availableCities ?? [],
    stock: p.stock ?? null,
    salesCount: p.salesCount,
    viewCount: p.viewCount,
    ratingAvg: 0,
    ratingCount: 0,
    tags: p.tags,
    giftFor: [...p.giftFor],
    optionGroups: p.optionGroups.map((g, i) => optionGroupData(p.id, g, i)),
    createdAt: Timestamp.fromMillis(PRODUCT_EPOCH_MS + index * DAY_MS),
    updatedAt: FieldValue.serverTimestamp(),
  };
  return { ...data, ...derivedProductFields(data) };
}

/** Mirrors `OptionGroup.toMap()`: optional keys are omitted, not null. */
function optionGroupData(productId: string, g: OptionGroupSeed, sortOrder: number): FirestoreData {
  const values = (g.values ?? []).map((v) => optionValueData(productId, g, v));
  return {
    id: g.id,
    type: g.type,
    ...loc('label', g.label),
    required: g.required ?? false,
    sortOrder,
    ...(g.maxLength !== undefined && { maxLength: g.maxLength }),
    ...(g.minPhotos !== undefined && { minPhotos: g.minPhotos }),
    ...(g.maxPhotos !== undefined && { maxPhotos: g.maxPhotos }),
    ...(values.length > 0 && { values }),
  };
}

/** Mirrors `OptionValue.toMap()`. imageVariant values get a placeholder image. */
function optionValueData(productId: string, g: OptionGroupSeed, v: OptionValueSeed): FirestoreData {
  const imageUrl =
    v.imageUrl ??
    (g.type === 'imageVariant'
      ? `https://picsum.photos/seed/gg-${productId}-${g.id}-${v.id}/300/300`
      : undefined);
  return {
    id: v.id,
    ...loc('label', v.label),
    ...(imageUrl !== undefined && { imageUrl }),
    ...(v.hex !== undefined && { hex: v.hex }),
    priceDelta: v.priceDelta ?? 0,
    ...(v.stock !== undefined && { stock: v.stock }),
    ...(v.preparationDaysOverride !== undefined && {
      preparationDaysOverride: v.preparationDaysOverride,
    }),
  };
}

// ── Validation ───────────────────────────────────────────────────────────────

const VALUE_TYPES: readonly OptionType[] = ['imageVariant', 'textVariant', 'colorSwatch'];
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
/** Letters used in Kurdish Sorani but not Arabic: ی ک ە ڕ ڵ ۆ ێ ڤ پ چ ژ گ. */
const KURDISH_ONLY = /[یکەڕڵۆێڤپچژگ]/;
/** Arabic letters that Sorani writes differently: ي ك ة ى. */
const ARABIC_ONLY = /[يكةى]/;

/**
 * Integrity checks run before every write (and in `test/seedData.test.ts`).
 * Returns human-readable problems; empty = OK.
 */
export function validateSeed(docs: SeedDoc[]): string[] {
  const problems: string[] = [];
  const err = (msg: string) => problems.push(msg);

  const seen = new Set<string>();
  for (const d of docs) {
    const key = `${d.collection}/${d.id}`;
    if (seen.has(key)) err(`duplicate document ${key}`);
    seen.add(key);
    checkValues(key, d.data, err);
  }

  const of = (collection: string) => docs.filter((d) => d.collection === collection);
  const categories = of(FirestorePaths.categories);
  const products = of(FirestorePaths.products);
  const banners = of(FirestorePaths.banners);
  const categoryIds = new Set(categories.map((c) => c.id));
  const productIds = new Set(products.map((p) => p.id));
  const cityIds = new Set(CITIES.map((c) => c.id));

  if (categories.length !== 50) err(`expected 50 categories, got ${categories.length}`);
  for (const c of categories) {
    if (!SLUG.test(c.id)) err(`category id "${c.id}" is not a kebab-case slug`);
    if (!CategoryType.includes(c.data.type as CategoryType)) err(`category ${c.id}: bad type`);
  }

  if (products.length !== 20) err(`expected 20 products, got ${products.length}`);
  const typesUsed = new Set<string>();
  for (const p of products) {
    const d = p.data;
    const where = `product ${p.id}`;
    const price = d.price as number;
    if (!SLUG.test(p.id)) err(`${where}: id is not a kebab-case slug`);
    if (!Number.isInteger(price) || price <= 0 || price % 250 !== 0) err(`${where}: bad price ${price}`);
    const compareAt = d.compareAtPrice as number | null;
    if (compareAt !== null && (compareAt <= price || compareAt % 250 !== 0)) {
      err(`${where}: compareAtPrice must be > price and a multiple of 250`);
    }
    const cats = d.categoryIds as string[];
    if (cats.length < 1 || cats.length > 3) err(`${where}: needs 1–3 categoryIds`);
    for (const c of cats) if (!categoryIds.has(c)) err(`${where}: unknown category ${c}`);
    for (const c of d.availableCities as string[]) if (!cityIds.has(c)) err(`${where}: unknown city ${c}`);
    if ((d.images as string[]).length !== 3) err(`${where}: needs 3 images`);
    const availability = d.availability as ProductAvailability;
    const prep = d.preparationDays as number;
    if (!ProductAvailability.includes(availability)) err(`${where}: bad availability`);
    if (availability === 'sameDay' && prep !== 0) err(`${where}: sameDay needs preparationDays 0`);
    if (availability === 'preparationDays' && prep <= 0) err(`${where}: preparationDays must be > 0`);
    if ((d.searchKeywords as string[]).length === 0) err(`${where}: no searchKeywords`);
    const giftFor = d.giftFor as string[];
    if (giftFor.length < 1 || giftFor.length > GiftAudience.length) err(`${where}: needs 1–3 giftFor values`);
    if (new Set(giftFor).size !== giftFor.length) err(`${where}: duplicate giftFor value`);
    for (const a of giftFor) if (!GiftAudience.includes(a as GiftAudience)) err(`${where}: unknown giftFor ${a}`);
    const derived = derivedProductFields(d);
    for (const field of DERIVED_PRODUCT_FIELDS) {
      if (!isDeepStrictEqual(d[field], derived[field])) err(`${where}: derived field ${field} is stale`);
    }

    const groups = d.optionGroups as FirestoreData[];
    const groupIds = new Set<string>();
    for (const g of groups) {
      const gw = `${where} group ${String(g.id)}`;
      const type = g.type as OptionType;
      typesUsed.add(type);
      if (groupIds.has(g.id as string)) err(`${gw}: duplicate group id`);
      groupIds.add(g.id as string);
      if (!OptionType.includes(type)) err(`${gw}: bad type ${type}`);
      const values = (g.values as FirestoreData[] | undefined) ?? [];
      if (VALUE_TYPES.includes(type) && values.length === 0) err(`${gw}: needs values`);
      if (!VALUE_TYPES.includes(type) && values.length > 0) err(`${gw}: must not have values`);
      if ((type === 'text' || type === 'longText') && typeof g.maxLength !== 'number') {
        err(`${gw}: needs maxLength`);
      }
      if (type === 'photoUpload') {
        const min = g.minPhotos as number;
        const max = g.maxPhotos as number;
        if (!(min >= 1 && max >= min)) err(`${gw}: needs 1 <= minPhotos <= maxPhotos`);
      }
      const valueIds = new Set<string>();
      for (const v of values) {
        const vw = `${gw} value ${String(v.id)}`;
        if (valueIds.has(v.id as string)) err(`${vw}: duplicate value id`);
        valueIds.add(v.id as string);
        if ((v.priceDelta as number) % 250 !== 0) err(`${vw}: priceDelta not a multiple of 250`);
        if (type === 'colorSwatch' && !/^#[0-9A-F]{6}$/.test(String(v.hex))) err(`${vw}: needs hex #RRGGBB`);
        if (type === 'imageVariant' && typeof v.imageUrl !== 'string') err(`${vw}: needs imageUrl`);
      }
    }
  }
  for (const t of OptionType) if (!typesUsed.has(t)) err(`no product uses OptionType ${t}`);
  for (const a of GiftAudience) {
    const count = products.filter((p) => (p.data.giftFor as string[]).includes(a)).length;
    if (count < 2) err(`only ${count} product(s) for gift type ${a} (the "Shop for" filters need several)`);
  }

  const placements = new Set<string>();
  for (const b of banners) {
    const placement = b.data.placement as BannerPlacement;
    const action = b.data.action as { type: BannerActionType; value: string };
    placements.add(placement);
    if (!BannerPlacement.includes(placement)) err(`banner ${b.id}: bad placement`);
    if (!BannerActionType.includes(action.type)) err(`banner ${b.id}: bad action type`);
    if (action.type === 'category' && !categoryIds.has(action.value)) err(`banner ${b.id}: unknown category`);
    if (action.type === 'product' && !productIds.has(action.value)) err(`banner ${b.id}: unknown product`);
    if (action.type === 'route' && !action.value.startsWith('/')) err(`banner ${b.id}: route must start with /`);
  }
  for (const p of BannerPlacement) if (!placements.has(p)) err(`no banner for placement ${p}`);

  // The app's force-update button reads storeUrls.{ios,android}; '' = no listing yet.
  const general = of(FirestorePaths.appSettings).find((d) => d.id === 'general');
  const storeUrls = (general?.data.storeUrls ?? {}) as Record<string, unknown>;
  for (const platform of ['ios', 'android']) {
    const url = storeUrls[platform];
    if (typeof url !== 'string' || (url !== '' && !url.startsWith('https://'))) {
      err(`app_settings/general.storeUrls.${platform} must be '' or an https URL`);
    }
  }

  return problems;
}

/** No `undefined` anywhere (Firestore rejects it) and script sanity for Ar / Ku fields. */
function checkValues(path: string, value: unknown, err: (msg: string) => void): void {
  if (value === undefined) {
    err(`${path} is undefined`);
  } else if (Array.isArray(value)) {
    value.forEach((v, i) => checkValues(`${path}[${i}]`, v, err));
  } else if (value !== null && typeof value === 'object' && value.constructor === Object) {
    for (const [k, v] of Object.entries(value)) {
      const p = `${path}.${k}`;
      if (typeof v === 'string' && k.endsWith('Ar') && KURDISH_ONLY.test(v)) {
        err(`${p}: Arabic text contains Kurdish-only letters: "${v}"`);
      }
      if (typeof v === 'string' && k.endsWith('Ku') && ARABIC_ONLY.test(v)) {
        err(`${p}: Kurdish text contains Arabic-only letters (ي ك ة ى): "${v}"`);
      }
      checkValues(p, v, err);
    }
  }
}

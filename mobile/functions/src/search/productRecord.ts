/**
 * The Algolia record of a product (SRS §5.8). Kept small: the app renders search
 * results straight from these records (`AlgoliaProductSource` in
 * mobile/lib/features/products/data/datasources/product_sources.dart reads them
 * with `ProductModel.fromMap`), so field names match `products/{id}`.
 */
import { ProductAvailability, type GiftAudience, type OptionType } from '../shared/enums';
import {
  boolean,
  decimal,
  enumValue,
  epochMillis,
  integer,
  integerOrNull,
  mapList,
  string,
  stringList,
  stringOrNull,
} from '../shared/firestoreParse';
import { derivedProductFields, giftAudiencesOf } from '../shared/productDerived';
import { normalize } from '../shared/searchTokenizer';

export interface ProductRecord {
  objectID: string;
  title: string;
  titleAr: string;
  titleKu: string;
  /** The first two images (card + hover). */
  images: string[];
  price: number;
  compareAtPrice: number | null;
  hasDiscount: boolean;
  priceBand: number;
  isFeatured: boolean;
  isActive: boolean;
  availability: ProductAvailability;
  preparationDays: number;
  stock: number | null;
  categoryIds: string[];
  cityKeys: string[];
  catCityKeys: string[];
  /** Gift types (SRS §5.8a): the known `GiftAudience` values; the app filters `giftFor:"women"`. */
  giftFor: GiftAudience[];
  salesCount: number;
  ratingAvg: number;
  ratingCount: number;
  /** Epoch SECONDS (Algolia sorts numbers; the app multiplies by 1000). null when unknown. */
  createdAt: number | null;
  /** Up to 5 `#RRGGBB` from the first colour-swatch group (`ProductModel.colorDots`). */
  colorDots: string[];
  tags: string[];
  /**
   * `SearchTokenizer.normalize` of the three titles and the tags. The app
   * normalizes the query the same way, so ك/ک, ي/ی and diacritics match.
   */
  searchText: string;
}

/** Records shown in card results carry at most this many images. */
export const RECORD_IMAGES = 2;
/** `ProductModel.colorDots` shows at most 5 dots. */
export const MAX_COLOR_DOTS = 5;

/** Products in the search index: existing and not deactivated (`isActive` defaults to true). */
export function isIndexable<T extends Readonly<Record<string, unknown>>>(
  product: T | undefined | null,
): product is T {
  return product !== undefined && product !== null && product.isActive !== false;
}

/**
 * Builds the record from a product document. Derived fields are recomputed
 * (never trusted from the stored document), so the record is right even before
 * `onProductWrite` has written them back.
 */
export function buildProductRecord(id: string, product: Readonly<Record<string, unknown>>): ProductRecord {
  const derived = derivedProductFields(product);
  const title = string(product.title);
  const titleAr = string(product.titleAr);
  const titleKu = string(product.titleKu);
  const tags = stringList(product.tags);
  const createdMs = epochMillis(product.createdAt);
  return {
    objectID: id,
    title,
    titleAr,
    titleKu,
    images: stringList(product.images).slice(0, RECORD_IMAGES),
    price: integer(product.price),
    compareAtPrice: integerOrNull(product.compareAtPrice),
    hasDiscount: derived.hasDiscount,
    priceBand: derived.priceBand,
    isFeatured: boolean(product.isFeatured),
    isActive: boolean(product.isActive, true),
    availability: enumValue(ProductAvailability, product.availability, 'sameDay'),
    preparationDays: integer(product.preparationDays),
    stock: integerOrNull(product.stock),
    categoryIds: stringList(product.categoryIds),
    cityKeys: derived.cityKeys,
    catCityKeys: derived.catCityKeys,
    giftFor: giftAudiencesOf(product.giftFor),
    salesCount: integer(product.salesCount),
    ratingAvg: decimal(product.ratingAvg),
    ratingCount: integer(product.ratingCount),
    createdAt: createdMs === null ? null : Math.floor(createdMs / 1000),
    colorDots: colorDots(product.optionGroups),
    tags,
    searchText: searchText([title, titleAr, titleKu, ...tags]),
  };
}

/**
 * Same rule as `ProductModel.colorDots`: groups in `sortOrder`, the first
 * `colorSwatch` group, its non-empty `hex` values, at most 5.
 */
export function colorDots(optionGroups: unknown): string[] {
  const groups = mapList(optionGroups)
    .map((g, i) => ({ g, i, sortOrder: integer(g.sortOrder) }))
    .sort((a, b) => a.sortOrder - b.sortOrder || a.i - b.i);
  const swatch = groups.find(({ g }) => g.type === ('colorSwatch' satisfies OptionType));
  if (swatch === undefined) return [];
  return mapList(swatch.g.values)
    .map((v) => stringOrNull(v.hex))
    .filter((hex): hex is string => hex !== null)
    .slice(0, MAX_COLOR_DOTS);
}

/** Normalized texts joined by single spaces (empty ones skipped). */
export function searchText(texts: readonly string[]): string {
  return texts
    .map((t) => normalize(t).trim())
    .filter((t) => t.length > 0)
    .join(' ');
}

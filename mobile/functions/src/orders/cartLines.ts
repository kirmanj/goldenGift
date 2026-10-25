/**
 * Server-side re-pricing of cart lines (SRS §5.9, §5.11) — the rules of the app's
 * `resolveLine` (cart_lines.dart) and `ProductConfiguration` (product_configuration.dart)
 * applied to the CURRENT product. The cart is client-written, so nothing on a line
 * is trusted except which product, which option values, the customer's own text /
 * date / photo URLs and the quantity; prices, labels, titles and preparation days
 * come from the product.
 */
import type { DocumentData } from 'firebase-admin/firestore';
import { OptionType, StoreStatus } from '../shared/enums';
import { boolean, enumValue, integer, integerOrNull, mapList, string, stringList, stringOrNull } from '../shared/firestoreParse';
import { codePointLength } from '../shared/text';

/** `CartController.maxQty` / `ProductConfiguration.maxQtyCap`. */
export const MAX_LINE_QTY = 99;

const VALUE_TYPES: ReadonlySet<string> = new Set(['imageVariant', 'textVariant', 'colorSwatch']);

export interface OptionValueData {
  id: string;
  priceDelta: number;
  /** null = unlimited. */
  stock: number | null;
  preparationDaysOverride: number | null;
  raw: Record<string, unknown>;
}

export interface OptionGroupData {
  id: string;
  type: OptionType;
  required: boolean;
  maxLength: number | null;
  minPhotos: number | null;
  maxPhotos: number | null;
  values: OptionValueData[];
  raw: Record<string, unknown>;
}

export function parseOptionGroups(raw: unknown): OptionGroupData[] {
  return mapList(raw).map((g) => ({
    id: string(g.id),
    type: enumValue(OptionType, g.type, 'text'),
    required: boolean(g.required),
    maxLength: integerOrNull(g.maxLength),
    minPhotos: integerOrNull(g.minPhotos),
    maxPhotos: integerOrNull(g.maxPhotos),
    values: mapList(g.values).map((v) => ({
      id: string(v.id),
      priceDelta: integer(v.priceDelta),
      stock: integerOrNull(v.stock),
      preparationDaysOverride: integerOrNull(v.preparationDaysOverride),
      raw: v,
    })),
    raw: g,
  }));
}

/** `ProductModel.isOutOfStock`'s first half; the numeric stock is checked separately (→ out_of_stock). */
export function productIsOrderable(product: DocumentData | undefined, store: DocumentData | undefined): boolean {
  if (product === undefined) return false;
  if (!boolean(product.isActive, true)) return false;
  if (product.availability === 'outOfStock') return false;
  // resolveLine: a store that exists but is not active closes its products.
  if (store !== undefined && enumValue(StoreStatus, store.status, 'pendingApproval') !== 'active') return false;
  return true;
}

/** A cart line priced against the current product. */
export interface PricedLine {
  /** Cart item id (= order line id). */
  id: string;
  productId: string;
  storeId: string;
  qty: number;
  unitPrice: number;
  lineTotal: number;
  preparationDays: number;
  /** The order snapshot of the line's selections (§6.5 shape). */
  selections: Array<Record<string, unknown>>;
  /** Selected values that track their own stock. */
  stockedValues: Array<{ groupId: string; valueId: string }>;
  title: { en: string; ar: string | null; ku: string | null };
  image: string | null;
}

export type LineCheck =
  /** Product gone / inactive / outOfStock, store closed, option gone or invalid, malformed line → cart_changed. */
  | { kind: 'unavailable'; productId: string }
  /**
   * Still orderable, but its stored price or preparation days are out of date →
   * cart_changed, and `placeOrder` writes `refresh` to the cart line so the app's
   * cart shows the current values and the next checkout goes through.
   */
  | { kind: 'stale'; productId: string; line: PricedLine; refresh: Record<string, unknown> }
  | { kind: 'ok'; productId: string; line: PricedLine };

/** The cart's own selections with each chosen value's current `priceDelta` (nothing else changes). */
function refreshedSelections(raw: unknown, groups: readonly OptionGroupData[]): unknown {
  if (!Array.isArray(raw)) return raw;
  return raw.map((s: unknown) => {
    if (s === null || typeof s !== 'object') return s;
    const selection = s as Record<string, unknown>;
    const valueId = stringOrNull(selection.valueId);
    const value = groups.find((g) => g.id === selection.groupId)?.values.find((v) => v.id === valueId);
    return value === undefined ? selection : { ...selection, priceDelta: value.priceDelta };
  });
}

function localized(source: Record<string, unknown>, field: string, target: string): Record<string, unknown> {
  const out: Record<string, unknown> = { [target]: string(source[field]) };
  const ar = stringOrNull(source[`${field}Ar`]);
  const ku = stringOrNull(source[`${field}Ku`]);
  if (ar !== null) out[`${target}Ar`] = ar;
  if (ku !== null) out[`${target}Ku`] = ku;
  return out;
}

/** A selection's date as the app writes it (ISO string), or null. */
function selectionDate(v: unknown): string | null {
  if (typeof v === 'string' && v.length > 0 && !Number.isNaN(Date.parse(v))) return v;
  if (v !== null && typeof v === 'object' && typeof (v as { toDate?: unknown }).toDate === 'function') {
    return (v as { toDate(): Date }).toDate().toISOString();
  }
  return null;
}

/**
 * Checks one `carts/{uid}/items/{id}` document against its product and store
 * (undefined = the doc does not exist).
 */
export function checkCartLine(
  itemId: string,
  item: DocumentData,
  product: DocumentData | undefined,
  store: DocumentData | undefined,
): LineCheck {
  const productId = string(item.productId);
  const unavailable: LineCheck = { kind: 'unavailable', productId };
  if (productId.length === 0 || !productIsOrderable(product, store) || product === undefined) return unavailable;

  const qty = typeof item.qty === 'number' ? item.qty : Number.NaN;
  if (!Number.isInteger(qty) || qty < 1 || qty > MAX_LINE_QTY) return unavailable;

  const groups = parseOptionGroups(product.optionGroups).filter((g) => g.type !== 'quantity');
  const byGroup = new Map(groups.map((g) => [g.id, g]));
  const seen = new Set<string>();

  let unitPrice = integer(product.price);
  let preparationDays = integer(product.preparationDays);
  const selections: Array<Record<string, unknown>> = [];
  const stockedValues: PricedLine['stockedValues'] = [];

  for (const s of mapList(item.selections)) {
    const groupId = string(s.groupId);
    const group = byGroup.get(groupId);
    // An option the product no longer has, a changed option type, or the same group twice.
    if (group === undefined || seen.has(groupId) || s.type !== group.type) return unavailable;
    seen.add(groupId);

    const out: Record<string, unknown> = { groupId, type: group.type, ...localized(group.raw, 'label', 'label') };
    let filled = false;
    let priceDelta = 0;

    if (VALUE_TYPES.has(group.type)) {
      const valueId = stringOrNull(s.valueId);
      if (valueId !== null) {
        const value = group.values.find((v) => v.id === valueId);
        if (value === undefined) return unavailable;
        filled = true;
        priceDelta = value.priceDelta;
        unitPrice += value.priceDelta;
        if (value.preparationDaysOverride !== null) {
          preparationDays = Math.max(preparationDays, value.preparationDaysOverride);
        }
        if (value.stock !== null) stockedValues.push({ groupId, valueId });
        out.valueId = valueId;
        Object.assign(out, localized(value.raw, 'label', 'valueLabel'));
        const hex = stringOrNull(value.raw.hex);
        if (hex !== null) out.hex = hex;
      }
    } else if (group.type === 'text' || group.type === 'longText') {
      const text = typeof s.text === 'string' ? s.text.trim() : '';
      if (text.length > 0) {
        if (group.maxLength !== null && codePointLength(text) > group.maxLength) return unavailable;
        filled = true;
        out.text = text;
      }
    } else if (group.type === 'date') {
      const date = selectionDate(s.date);
      if (date !== null) {
        filled = true;
        out.date = date;
      }
    } else if (group.type === 'photoUpload') {
      const urls = stringList(s.urls);
      if (urls.length > 0) {
        const min = group.minPhotos ?? (group.required ? 1 : 0);
        if (urls.length < min || (group.maxPhotos !== null && urls.length > group.maxPhotos)) return unavailable;
        filled = true;
        out.urls = urls;
      }
    }

    out.priceDelta = priceDelta;
    if (filled) selections.push(out);
  }

  // ProductConfiguration.validate: every required input group must be filled.
  for (const g of groups) {
    if (g.required && !selections.some((s) => s.groupId === g.id)) return unavailable;
  }
  if (unitPrice < 0) return unavailable; // negative price deltas larger than the price: bad product data

  const line: PricedLine = {
    id: itemId,
    productId,
    storeId: string(product.storeId),
    qty,
    unitPrice,
    lineTotal: unitPrice * qty,
    preparationDays,
    selections,
    stockedValues,
    title: {
      en: string(product.title),
      ar: stringOrNull(product.titleAr),
      ku: stringOrNull(product.titleKu),
    },
    image: stringList(product.images)[0] ?? null,
  };
  const stale = integer(item.unitPrice, Number.NaN) !== unitPrice || integer(item.preparationDays) !== preparationDays;
  if (!stale) return { kind: 'ok', productId, line };
  return {
    kind: 'stale',
    productId,
    line,
    refresh: {
      unitPrice,
      lineTotal: line.lineTotal,
      preparationDays,
      selections: refreshedSelections(item.selections, groups),
    },
  };
}

/** `orders.items[]` entry (SRS §6.7): the line snapshot + `storeId` + per-line `status`. */
export function orderItem(line: PricedLine, status: string): Record<string, unknown> {
  return {
    id: line.id,
    productId: line.productId,
    storeId: line.storeId,
    titleSnapshot: line.title.en,
    ...(line.title.ar !== null && { titleSnapshotAr: line.title.ar }),
    ...(line.title.ku !== null && { titleSnapshotKu: line.title.ku }),
    imageSnapshot: line.image,
    unitPrice: line.unitPrice,
    qty: line.qty,
    selections: line.selections,
    lineTotal: line.lineTotal,
    preparationDays: line.preparationDays,
    status,
  };
}

/**
 * Stock bookkeeping for orders (SRS §5.11, Phase 6 exit criterion: concurrent
 * orders on the last unit never oversell). Applied inside the `placeOrder` /
 * `cancelOrder` / `onOrderStatusChange` transactions to product data read in
 * the same transaction, so concurrent orders serialize on the product document.
 *
 * Two levels, both `null = unlimited`: `products.stock` and, for option values
 * with their own stock (§6.4 `values[].stock`), the value inside `optionGroups`.
 */
import type { DocumentData } from 'firebase-admin/firestore';
import { integer, integerOrNull, mapList, string, stringOrNull } from '../shared/firestoreParse';

/** One line's claim on stock: its product, quantity and selected option values. */
export interface StockLine {
  productId: string;
  qty: number;
  values: Array<{ groupId: string; valueId: string }>;
}

export interface StockDemand {
  qty: number;
  /** `${groupId}\u0000${valueId}` → quantity. */
  values: Map<string, number>;
}

const valueKey = (groupId: string, valueId: string) => `${groupId}\u0000${valueId}`;

/** Σ quantity per product and per selected value. */
export function stockDemand(lines: readonly StockLine[]): Map<string, StockDemand> {
  const demand = new Map<string, StockDemand>();
  for (const line of lines) {
    const d = demand.get(line.productId) ?? { qty: 0, values: new Map<string, number>() };
    d.qty += line.qty;
    for (const v of line.values) {
      const key = valueKey(v.groupId, v.valueId);
      d.values.set(key, (d.values.get(key) ?? 0) + line.qty);
    }
    demand.set(line.productId, d);
  }
  return demand;
}

/** The order lines (`orders.items[]`) as stock claims. */
export function orderStockLines(items: unknown): StockLine[] {
  return mapList(items).map((item) => ({
    productId: string(item.productId),
    qty: Math.max(0, integer(item.qty)),
    values: mapList(item.selections)
      .map((s) => ({ groupId: string(s.groupId), valueId: stringOrNull(s.valueId) }))
      .filter((v): v is { groupId: string; valueId: string } => v.valueId !== null),
  }));
}

function valueStock(product: DocumentData, key: string): number | null {
  for (const g of mapList(product.optionGroups)) {
    for (const v of mapList(g.values)) {
      if (valueKey(string(g.id), string(v.id)) === key) return integerOrNull(v.stock);
    }
  }
  return null;
}

/** True when the product's stock (and every stocked value's) covers `demand`. */
export function coversDemand(product: DocumentData, demand: StockDemand): boolean {
  const stock = integerOrNull(product.stock);
  if (stock !== null && demand.qty > stock) return false;
  for (const [key, qty] of demand.values) {
    const s = valueStock(product, key);
    if (s !== null && qty > s) return false;
  }
  return true;
}

/**
 * The `products/{id}` update that reserves (`+1`: placing an order) or releases
 * (`-1`: a cancellation) `demand`: `stock` and stocked values move only when they
 * are not null (unlimited), `salesCount` never drops below 0.
 */
export function stockUpdate(product: DocumentData, demand: StockDemand, direction: 1 | -1): Record<string, unknown> {
  const update: Record<string, unknown> = {
    salesCount: Math.max(0, integer(product.salesCount) + direction * demand.qty),
  };
  const stock = integerOrNull(product.stock);
  if (stock !== null) update.stock = stock - direction * demand.qty;

  if (demand.values.size > 0 && Array.isArray(product.optionGroups)) {
    let changed = false;
    const groups = (product.optionGroups as unknown[]).map((g) => {
      if (g === null || typeof g !== 'object' || !Array.isArray((g as DocumentData).values)) return g;
      const group = g as DocumentData;
      const values = (group.values as unknown[]).map((v) => {
        if (v === null || typeof v !== 'object') return v;
        const value = v as DocumentData;
        const qty = demand.values.get(valueKey(string(group.id), string(value.id)));
        const current = integerOrNull(value.stock);
        if (qty === undefined || current === null) return v;
        changed = true;
        return { ...value, stock: current - direction * qty };
      });
      return { ...group, values };
    });
    if (changed) update.optionGroups = groups;
  }
  return update;
}

/**
 * Promo code rules (SRS §5.23, §6.9) — TypeScript twin of
 * `mobile/lib/core/utils/promo_rules.dart` and of `PromoCodeModel.fromMap` /
 * `PromoCodeModel.normalize` (mobile/lib/models/promo_code_model.dart). The app
 * previews a code with the Dart rules; `placeOrder` re-checks it with these.
 * Both are tested against `mobile/test/fixtures/promo_cases.json` — change both
 * sides together.
 *
 *  - `minOrder` is compared with the whole cart subtotal; the discount is computed
 *    on the eligible lines only (category / store restriction).
 *  - percent: floor(eligible × value / 100) with value capped at 100, then capped by
 *    `maxDiscount` (when > 0); fixed: the value. Never more than the eligible subtotal.
 *  - `usageLimit` counts every customer (null = unlimited); `perUserLimit` 0 = unlimited.
 *  - `firstOrderOnly` = the customer has no previous non-cancelled order.
 *  - Checks run in this order; the first failing one is the rejection.
 */
import { boolean, enumValue, epochMillis, integer, integerOrNull, stringList } from '../shared/firestoreParse';

/** `PromoRejection` (promo_rules.dart) — same names, same order. Sent as `details.promoReason`. */
export const PromoRejection = [
  'notFound',
  'inactive',
  'expired',
  'minOrder',
  'usageLimit',
  'perUserLimit',
  'firstOrderOnly',
  'notApplicable',
] as const;
export type PromoRejection = (typeof PromoRejection)[number];

/** `PromoType` (promo_code_model.dart). */
export const PromoType = ['percent', 'fixed'] as const;
export type PromoType = (typeof PromoType)[number];

/** `promo_codes/{CODE}` as the rules read it (`PromoCodeModel`). */
export interface PromoCode {
  code: string;
  type: PromoType;
  /** Percent (1–100) or a fixed IQD amount. */
  value: number;
  maxDiscount: number | null;
  minOrder: number | null;
  /** Total redemptions allowed (null = unlimited). */
  usageLimit: number | null;
  usageCount: number;
  /** Redemptions per customer (0 = unlimited). */
  perUserLimit: number;
  firstOrderOnly: boolean;
  categoryIds: string[];
  storeIds: string[];
  isPublic: boolean;
  isActive: boolean;
  /** Epoch ms; null = never expires. */
  expiresAtMs: number | null;
}

/** One cart line as the promo rules see it (`PromoLine`). */
export interface PromoLine {
  productId: string;
  storeId: string;
  categoryIds: readonly string[];
  lineTotal: number;
}

export type PromoEvaluation =
  | { valid: true; discount: number; eligibleSubtotal: number; rejection: null }
  | { valid: false; discount: 0; eligibleSubtotal: 0; rejection: PromoRejection };

/** `PromoCodeModel.normalize`: case-insensitive, without spaces. */
export function normalizePromoCode(code: string): string {
  return code.replace(/\s+/g, '').toUpperCase();
}

/** `PromoCodeModel.fromMap(id, map)`. */
export function parsePromoCode(id: string, map: Record<string, unknown>): PromoCode {
  const storedCode = typeof map.code === 'string' && map.code.length > 0 ? map.code : id;
  return {
    code: normalizePromoCode(storedCode),
    type: enumValue(PromoType, map.type, 'percent'),
    value: integer(map.value),
    maxDiscount: integerOrNull(map.maxDiscount),
    minOrder: integerOrNull(map.minOrder),
    usageLimit: integerOrNull(map.usageLimit),
    usageCount: integer(map.usageCount),
    perUserLimit: integer(map.perUserLimit, 1),
    firstOrderOnly: boolean(map.firstOrderOnly),
    categoryIds: stringList(map.categoryIds),
    storeIds: stringList(map.storeIds),
    isPublic: boolean(map.isPublic),
    isActive: boolean(map.isActive, true),
    expiresAtMs: epochMillis(map.expiresAt),
  };
}

const rejected = (rejection: PromoRejection): PromoEvaluation => ({
  valid: false,
  discount: 0,
  eligibleSubtotal: 0,
  rejection,
});

/** `PromoRules.evaluate`. `promo` null = the code does not exist. */
export function evaluatePromo(
  promo: PromoCode | null,
  input: { lines: readonly PromoLine[]; nowMs: number; userUsageCount?: number; userOrderCount?: number },
): PromoEvaluation {
  const userUsageCount = input.userUsageCount ?? 0;
  const userOrderCount = input.userOrderCount ?? 0;
  if (promo === null) return rejected('notFound');
  if (!promo.isActive || promo.value <= 0) return rejected('inactive');
  if (promo.expiresAtMs !== null && !(input.nowMs < promo.expiresAtMs)) return rejected('expired');
  if (promo.usageLimit !== null && promo.usageCount >= promo.usageLimit) return rejected('usageLimit');
  if (promo.perUserLimit > 0 && userUsageCount >= promo.perUserLimit) return rejected('perUserLimit');
  if (promo.firstOrderOnly && userOrderCount > 0) return rejected('firstOrderOnly');

  const subtotal = input.lines.reduce((s, l) => s + l.lineTotal, 0);
  if (promo.minOrder !== null && subtotal < promo.minOrder) return rejected('minOrder');

  const applies = (l: PromoLine) =>
    (promo.categoryIds.length === 0 || l.categoryIds.some((c) => promo.categoryIds.includes(c))) &&
    (promo.storeIds.length === 0 || promo.storeIds.includes(l.storeId));
  const eligible = input.lines.filter(applies).reduce((s, l) => s + l.lineTotal, 0);
  if (eligible <= 0) return rejected('notApplicable');

  // Dart `~/` truncates; every operand is positive here, so trunc == floor.
  let discount = promo.type === 'percent' ? Math.trunc((eligible * Math.min(promo.value, 100)) / 100) : promo.value;
  if (promo.maxDiscount !== null && promo.maxDiscount > 0) discount = Math.min(discount, promo.maxDiscount);
  return { valid: true, discount: Math.min(discount, eligible), eligibleSubtotal: eligible, rejection: null };
}

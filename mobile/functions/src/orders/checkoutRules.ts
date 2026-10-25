/**
 * Checkout rules (SRS §5.11) — TypeScript twin of
 * `mobile/lib/features/checkout/domain/checkout_rules.dart`. `placeOrder` applies
 * exactly what the Checkout screen offered, so both sides are tested against the
 * shared fixture `mobile/test/fixtures/checkout_rules_cases.json`.
 *
 * Times are Iraq local time: Asia/Baghdad is UTC+3 all year (no DST since 2008),
 * so the server converts with a fixed offset instead of a time-zone database.
 * Dates travel as `yyyy-MM-dd` strings (`AppDates.isoDate`).
 */
import { integer, mapList } from '../shared/firestoreParse';

export const BAGHDAD_UTC_OFFSET_MS = 3 * 60 * 60 * 1000;

/** `CheckoutRules.deliveryDates` offers this many consecutive dates from the earliest one. */
export const DELIVERY_DATE_COUNT = 14;

/** `GeneralSettings.sameDayCutoff` default (also used when the stored value is malformed). */
export const DEFAULT_SAME_DAY_CUTOFF = '14:00';

/** A wall-clock moment in Iraq (month 1–12). */
export interface LocalDateTime {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

/** A delivery window from `app_settings/general.deliverySlots` (local "HH:mm"). */
export interface DeliverySlot {
  id: string;
  from: string;
  to: string;
}

/** `DeliverySlot.defaults` (ids and times; labels live in the app). */
export const DEFAULT_DELIVERY_SLOTS: readonly DeliverySlot[] = [
  { id: 'morning', from: '10:00', to: '14:00' },
  { id: 'afternoon', from: '14:00', to: '18:00' },
  { id: 'evening', from: '18:00', to: '22:00' },
];

/** Iraq wall-clock time of an instant. */
export function baghdadNow(epochMs: number): LocalDateTime {
  const d = new Date(epochMs + BAGHDAD_UTC_OFFSET_MS);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
  };
}

/** `CheckoutRules.parseHm`: "14:00" → [14, 0]; null when malformed. */
export function parseHm(value: string): [number, number] | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (m === null) return null;
  const h = Number.parseInt(m[1], 10);
  const min = Number.parseInt(m[2], 10);
  if (h > 23 || min > 59) return null;
  return [h, min];
}

function atOrAfter(now: LocalDateTime, hm: [number, number]): boolean {
  return now.hour > hm[0] || (now.hour === hm[0] && now.minute >= hm[1]);
}

function two(n: number): string {
  return n.toString().padStart(2, '0');
}

/** `AppDates.isoDate` of a calendar date; day overflow rolls into the next month / year like Dart's DateTime. */
export function isoDate(year: number, month: number, day: number): string {
  const d = new Date(Date.UTC(year, month - 1, day));
  return `${d.getUTCFullYear()}-${two(d.getUTCMonth() + 1)}-${two(d.getUTCDate())}`;
}

/** "2026-11-02" → { year, month, day }; null unless it is a real calendar date. */
export function parseIsoDate(value: unknown): { year: number; month: number; day: number } | null {
  if (typeof value !== 'string') return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (m === null) return null;
  const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
  return isoDate(year, month, day) === value ? { year, month, day } : null;
}

export function addDays(iso: string, days: number): string {
  const d = parseIsoDate(iso);
  if (d === null) throw new Error(`addDays: not a date: ${iso}`);
  return isoDate(d.year, d.month, d.day + days);
}

/** `CheckoutRules.earliestDeliveryDate`: today + max(preparationDays), +1 day at or after the cut-off. */
export function earliestDeliveryDate(now: LocalDateTime, maxPreparationDays: number, sameDayCutoff: string): string {
  const cutoff = parseHm(sameDayCutoff) ?? [14, 0];
  const days = maxPreparationDays + (atOrAfter(now, cutoff) ? 1 : 0);
  return isoDate(now.year, now.month, now.day + days);
}

/** The last date the Checkout date row offers (`deliveryDates(earliest).last`). */
export function lastDeliveryDate(earliest: string): string {
  return addDays(earliest, DELIVERY_DATE_COUNT - 1);
}

/**
 * `CheckoutRules.availableSlots`: every slot on later days; today only those that
 * have not started yet (a slot whose start is malformed never opens today).
 */
export function availableSlots(date: string, now: LocalDateTime, slots: readonly DeliverySlot[]): DeliverySlot[] {
  if (date !== isoDate(now.year, now.month, now.day)) return [...slots];
  return slots.filter((s) => {
    const start = parseHm(s.from);
    return start !== null && !atOrAfter(now, start);
  });
}

/** `GeneralSettings.fromMap(...).deliverySlots`: the stored list, or the defaults when it is empty. */
export function parseDeliverySlots(raw: unknown): DeliverySlot[] {
  const slots = mapList(raw).map((m) => ({
    id: typeof m.id === 'string' ? m.id : '',
    from: typeof m.from === 'string' ? m.from : '00:00',
    to: typeof m.to === 'string' ? m.to : '23:59',
  }));
  return slots.length === 0 ? DEFAULT_DELIVERY_SLOTS.map((s) => ({ ...s })) : slots;
}

export interface CheckoutTotals {
  subtotal: number;
  discount: number;
  deliveryFee: number;
  creditsUsed: number;
  walletUsed: number;
  /** To pay on delivery (or online). */
  total: number;
}

/** `CheckoutRules.totals`: discount first, then credits, then wallet; never below zero. */
export function checkoutTotals(input: {
  subtotal: number;
  deliveryFee: number;
  discount?: number;
  credits?: number;
  wallet?: number;
}): CheckoutTotals {
  const discount = input.discount ?? 0;
  const beforePayments = Math.max(0, input.subtotal - discount) + input.deliveryFee;
  const creditsUsed = Math.min(input.credits ?? 0, beforePayments);
  const walletUsed = Math.min(input.wallet ?? 0, beforePayments - creditsUsed);
  return {
    subtotal: input.subtotal,
    discount: Math.min(discount, input.subtotal),
    deliveryFee: input.deliveryFee,
    creditsUsed,
    walletUsed,
    total: beforePayments - creditsUsed - walletUsed,
  };
}

/** `CheckoutRules.meetsMinimum`: `minOrder` applies to the subtotal; ≤ 0 means no minimum. */
export function meetsMinimum(subtotal: number, minOrder: number): boolean {
  return minOrder <= 0 || subtotal >= minOrder;
}

/** `app_settings/general` fields placeOrder needs (`GeneralSettings.fromMap`). */
export interface OrderGeneralSettings {
  sameDayCutoff: string;
  minOrder: number;
  deliverySlots: DeliverySlot[];
}

export function parseGeneralSettings(data: Record<string, unknown> | undefined): OrderGeneralSettings {
  return {
    sameDayCutoff: typeof data?.sameDayCutoff === 'string' ? data.sameDayCutoff : DEFAULT_SAME_DAY_CUTOFF,
    minOrder: integer(data?.minOrder),
    deliverySlots: parseDeliverySlots(data?.deliverySlots),
  };
}

/** One entry of `app_settings/cities.items` (`CityModel.fromMap`). */
export interface City {
  id: string;
  deliveryFee: number;
  isActive: boolean;
}

export function parseCities(data: Record<string, unknown> | undefined): City[] {
  return mapList(data?.items).map((m) => ({
    id: typeof m.id === 'string' ? m.id : '',
    deliveryFee: integer(m.deliveryFee),
    isActive: typeof m.isActive === 'boolean' ? m.isActive : true,
  }));
}

/** `app_settings/payments` (`PaymentSettings.fromMap` defaults: cash on delivery and wallet on). */
export interface PaymentSettings {
  cashOnDelivery: boolean;
  wallet: boolean;
  card: boolean;
  fastPay: boolean;
  zainCash: boolean;
}

export function parsePaymentSettings(data: Record<string, unknown> | undefined): PaymentSettings {
  const flag = (key: keyof PaymentSettings, fallback: boolean) =>
    typeof data?.[key] === 'boolean' ? (data[key] as boolean) : fallback;
  return {
    cashOnDelivery: flag('cashOnDelivery', true),
    wallet: flag('wallet', true),
    card: flag('card', false),
    fastPay: flag('fastPay', false),
    zainCash: flag('zainCash', false),
  };
}

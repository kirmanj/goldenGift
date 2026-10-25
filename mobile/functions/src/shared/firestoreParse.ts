/**
 * Tolerant readers for Firestore data — TypeScript twin of
 * `mobile/lib/core/utils/firestore_parse.dart`. Documents are written by the app,
 * the admin dashboard, functions and the seeder, so numbers may arrive as
 * int / double / numeric string and lists may hold stray non-string entries.
 * Use these wherever server code must read a field the way `ProductModel.fromMap`
 * reads it.
 */

/** Dart `FirestoreParse.integer`: number → rounded, numeric string → parsed, else `fallback`. */
export function integer(v: unknown, fallback = 0): number {
  if (typeof v === 'number') return Number.isFinite(v) ? Math.round(v) : fallback;
  if (typeof v === 'string' && /^[+-]?\d+$/.test(v.trim())) return Number.parseInt(v.trim(), 10);
  return fallback;
}

/** null / undefined → null, else `integer(v)`. */
export function integerOrNull(v: unknown): number | null {
  return v === null || v === undefined ? null : integer(v);
}

export function decimal(v: unknown, fallback = 0): number {
  if (typeof v === 'number') return Number.isFinite(v) ? v : fallback;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : fallback;
  }
  return fallback;
}

export function boolean(v: unknown, fallback = false): boolean {
  return typeof v === 'boolean' ? v : fallback;
}

/** A string, or '' for anything else. */
export function string(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

/** Dart `stringOrNull`: a non-empty string, else null. */
export function stringOrNull(v: unknown): string | null {
  return typeof v === 'string' && v.length > 0 ? v : null;
}

/** The string entries of a list; anything that is not a list → []. */
export function stringList(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
}

/** The plain-object entries of a list; anything that is not a list → []. */
export function mapList(v: unknown): Array<Record<string, unknown>> {
  return Array.isArray(v)
    ? v.filter((x): x is Record<string, unknown> => x !== null && typeof x === 'object' && !Array.isArray(x))
    : [];
}

/** `value` when it is one of `values`, else `fallback` (Dart `enumValue`). */
export function enumValue<T extends string>(values: readonly T[], value: unknown, fallback: T): T {
  return values.includes(value as T) ? (value as T) : fallback;
}

/**
 * Epoch milliseconds of a Firestore Timestamp, Date, ISO string or millis
 * number (Dart `FirestoreParse.date`); null when it is none of those.
 */
export function epochMillis(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.getTime();
  if (typeof v === 'string') {
    const ms = Date.parse(v);
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof v === 'object' && typeof (v as { toMillis?: unknown }).toMillis === 'function') {
    return (v as { toMillis(): number }).toMillis();
  }
  return null;
}

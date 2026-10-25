import { createHash } from 'node:crypto';
import type { LocalDateTime } from './checkoutRules';

/** `orders/{id}` length: 20 hex characters of sha256 (80 bits). */
export const ORDER_ID_LENGTH = 20;

/**
 * The order id for one checkout attempt: sha256(uid + ':' + clientRequestId),
 * so a retried `placeOrder` (same `clientRequestId`) addresses the same document
 * and can never create a second order (SRS §5.11, §6.7).
 */
export function orderIdFor(uid: string, clientRequestId: string): string {
  return createHash('sha256').update(`${uid}:${clientRequestId}`, 'utf8').digest('hex').slice(0, ORDER_ID_LENGTH);
}

/** "2610" for October 2026 (Iraq time). */
export function yymm(now: LocalDateTime): string {
  return `${(now.year % 100).toString().padStart(2, '0')}${now.month.toString().padStart(2, '0')}`;
}

/**
 * PROVISIONAL (SRS §12 item 8, owner to confirm): the monthly sequence lives in
 * the functions-only doc `counters/orders-{YYMM}` = `{ next }`, where `next` is
 * the number the next order of that month gets (a missing doc means 1).
 */
export function orderCounterId(now: LocalDateTime): string {
  return `orders-${yymm(now)}`;
}

/** `GG-YYMM-#####` (at least 5 digits; the 100 000th order of a month gets 6). */
export function formatOrderNumber(now: LocalDateTime, sequence: number): string {
  return `GG-${yymm(now)}-${sequence.toString().padStart(5, '0')}`;
}

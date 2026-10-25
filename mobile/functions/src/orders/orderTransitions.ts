/**
 * Order status transitions (SRS §5.12, §9 Orders / Seller view) — TypeScript twin
 * of `OrderStatusX.allowedNext` and `OrderStatusX.flow` in
 * mobile/lib/models/order_model.dart. Both are checked against the shared
 * fixture mobile/test/fixtures/order_status_transitions.json (and the TS test
 * also parses the Dart source), so the dashboard offers exactly the moves
 * `updateOrderItems` accepts.
 */
import type { OrderStatus } from '../shared/enums';

/** The main path, least to most advanced (cancellations, returns and refunds are off it). */
export const ORDER_FLOW: readonly OrderStatus[] = [
  'pending',
  'confirmed',
  'preparing',
  'readyForDelivery',
  'outForDelivery',
  'delivered',
];

/** Status changes staff may make (`OrderStatusX.allowedNext`). */
export const ALLOWED_NEXT: Readonly<Record<OrderStatus, readonly OrderStatus[]>> = {
  pending: ['confirmed', 'cancelledBySeller'],
  confirmed: ['preparing', 'cancelledBySeller'],
  preparing: ['readyForDelivery', 'cancelledBySeller'],
  readyForDelivery: ['outForDelivery', 'cancelledBySeller'],
  outForDelivery: ['delivered', 'returned'],
  delivered: ['returned', 'refunded'],
  returned: ['refunded'],
  cancelledByBuyer: ['refunded'],
  cancelledBySeller: ['refunded'],
  refunded: [],
};

export function allowedNext(status: OrderStatus): readonly OrderStatus[] {
  return ALLOWED_NEXT[status];
}

export function isOnFlow(status: OrderStatus): boolean {
  return ORDER_FLOW.includes(status);
}

/** Money moves are Golden Gift's (finance): a seller never sets these. */
export const SELLER_FORBIDDEN: readonly OrderStatus[] = ['refunded'];

/**
 * The order's status derived from its lines (multi-vendor, SRS §6.7): the least
 * advanced line still on the main flow; when no line is on it any more —
 * `refunded` if every line was refunded, `returned` if any line came back,
 * `cancelledByBuyer` if the customer cancelled every line, else
 * `cancelledBySeller`. Null without lines.
 */
export function derivedOrderStatus(lineStatuses: readonly OrderStatus[]): OrderStatus | null {
  if (lineStatuses.length === 0) return null;
  const onFlow = lineStatuses.filter(isOnFlow);
  if (onFlow.length > 0) {
    return onFlow.reduce((a, b) => (ORDER_FLOW.indexOf(a) <= ORDER_FLOW.indexOf(b) ? a : b));
  }
  if (lineStatuses.every((s) => s === 'refunded')) return 'refunded';
  if (lineStatuses.some((s) => s === 'returned')) return 'returned';
  if (lineStatuses.every((s) => s === 'cancelledByBuyer')) return 'cancelledByBuyer';
  return 'cancelledBySeller';
}

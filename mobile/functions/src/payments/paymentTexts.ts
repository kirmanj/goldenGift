/**
 * Online-payment texts (SRS §4.5, §5.11, §5.18) in English, Arabic and Kurdish
 * Sorani, using the app's terms (app_*.arb: "Top-up" = "شحن الرصيد" /
 * "پڕکردنەوەی باڵانس", "Order" = "الطلب" / "داواکاری"). The Kurdish copy needs the
 * same native-speaker review as the rest of the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';
import type { Trilingual } from '../notifications/orderMessages';
import { ORDER_NOTIFICATION_TYPE } from '../notifications/orderMessages';

/** `orders.cancelReason` when the gateway declined the payment. */
export const PAYMENT_FAILED_REASON = 'payment_failed';
/** `orders.cancelReason` when the order was not paid before `paymentDueBy`. */
export const PAYMENT_EXPIRED_REASON = 'payment_expired';

/** `topUp` wallet transaction. */
export const TOP_UP_TITLE: Trilingual = {
  en: 'Top-up · ZainCash',
  ar: 'شحن الرصيد · زين كاش',
  ku: 'پڕکردنەوەی باڵانس · زەین کاش',
};

/** `refund` of an online payment that arrived for an order that no longer waited for it. */
export function latePaymentTitle(orderNumber: string): Trilingual {
  return {
    en: `Payment returned · Order ${orderNumber}`,
    ar: `إعادة مبلغ الدفع · الطلب ${orderNumber}`,
    ku: `گەڕاندنەوەی پارەدان · داواکاری ${orderNumber}`,
  };
}

/** What the gateway shows on its pay page (`serviceType`). */
export function orderServiceType(orderNumber: string): string {
  return `Golden Gift order ${orderNumber}`.slice(0, 100);
}
export const TOP_UP_SERVICE_TYPE = 'Golden Gift wallet top-up';

/**
 * The customer notification when an online-payment order is cancelled because
 * the payment failed or ran out of time (instead of "cancelled as you
 * requested"); null for any other cancellation.
 */
export function paymentCancellationNotification(
  cancelReason: unknown,
  order: { orderId: string; orderNumber: string },
): UserNotification | null {
  const n = order.orderNumber;
  let body: Trilingual;
  if (cancelReason === PAYMENT_FAILED_REASON) {
    body = {
      en: "The payment didn't go through, so we cancelled the order. Nothing was charged — you can order again any time.",
      ar: 'لم تكتمل عملية الدفع، لذلك ألغينا الطلب. لم يتم خصم أي مبلغ — يمكنك الطلب مجددًا في أي وقت.',
      ku: 'پارەدانەکە سەرکەوتوو نەبوو، بۆیە داواکارییەکەمان هەڵوەشاندەوە. هیچ پارەیەک نەبڕدرا — هەر کاتێک بتەوێت دەتوانیت دووبارە داوا بکەیتەوە.',
    };
  } else if (cancelReason === PAYMENT_EXPIRED_REASON) {
    body = {
      en: "The order wasn't paid in time, so we cancelled it. You can order again any time.",
      ar: 'لم يُدفع الطلب في الوقت المحدد، لذلك ألغيناه. يمكنك الطلب مجددًا في أي وقت.',
      ku: 'پارەی داواکارییەکە لە کاتی خۆیدا نەدرا، بۆیە هەڵمانوەشاندەوە. هەر کاتێک بتەوێت دەتوانیت دووبارە داوا بکەیتەوە.',
    };
  } else {
    return null;
  }
  return {
    type: ORDER_NOTIFICATION_TYPE,
    title: { en: `Order ${n} cancelled`, ar: `تم إلغاء الطلب ${n}`, ku: `داواکاری ${n} هەڵوەشایەوە` },
    body,
    route: `/orders/${order.orderId}`,
    id: order.orderId,
  };
}

/** The return page (`zainCashReturn`), shown in the browser before the app opens. */
export const RETURN_PAGE_TEXT: Record<'paid' | 'failed' | 'pending' | 'expired' | 'error', Trilingual> = {
  paid: { en: 'Payment successful', ar: 'تم الدفع بنجاح', ku: 'پارەدان سەرکەوتوو بوو' },
  failed: { en: 'Payment failed', ar: 'فشلت عملية الدفع', ku: 'پارەدان سەرنەکەوت' },
  pending: { en: 'Payment not completed', ar: 'لم تكتمل عملية الدفع', ku: 'پارەدان تەواو نەبوو' },
  expired: { en: 'Payment time ran out', ar: 'انتهى وقت الدفع', ku: 'کاتی پارەدان بەسەرچوو' },
  error: { en: 'We could not confirm this payment', ar: 'تعذّر تأكيد عملية الدفع', ku: 'نەمانتوانی ئەم پارەدانە پشتڕاست بکەینەوە' },
};

export const RETURN_PAGE_BUTTON: Trilingual = {
  en: 'Return to Golden Gift',
  ar: 'العودة إلى Golden Gift',
  ku: 'گەڕانەوە بۆ Golden Gift',
};

export const RETURN_PAGE_HINT: Trilingual = {
  en: "If the app didn't open, go back to it — your order and wallet update automatically.",
  ar: 'إذا لم يُفتح التطبيق، فارجع إليه — يتم تحديث طلبك ومحفظتك تلقائيًا.',
  ku: 'ئەگەر ئەپەکە نەکرایەوە، بگەڕێوە بۆی — داواکاری و جزدانەکەت خۆکارانە نوێ دەبنەوە.',
};

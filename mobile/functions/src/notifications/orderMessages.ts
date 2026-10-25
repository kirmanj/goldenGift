/**
 * Customer notifications for every order status (SRS §4.5, §5.12), in English,
 * Arabic and Kurdish Sorani. `pending` is the "order received" message sent by
 * `placeOrder`; every other status is sent by `onOrderStatusChange`.
 *
 * Wording follows the app's terms (app_ar.arb "الطلب", app_ckb.arb "داواکاری").
 * The Kurdish copy needs the same native-speaker review as the rest of the app
 * (SRS §8). `{number}` is the order number (GG-YYMM-#####), `{reason}` the
 * store's cancellation note.
 */
import type { OrderStatus } from '../shared/enums';
import type { UserNotification } from './notifyUser';

/** `notifications.type` of every order notification. */
export const ORDER_NOTIFICATION_TYPE = 'orderStatus';

/** Every language present (`ku` = Kurdish Sorani). */
export interface Trilingual {
  en: string;
  ar: string;
  ku: string;
}

interface Template {
  title: Trilingual;
  body: Trilingual;
  /** Used instead of `body` when a reason is given (seller cancellations). */
  bodyWithReason?: Trilingual;
}

export const ORDER_MESSAGES: Record<OrderStatus, Template> = {
  pending: {
    title: {
      en: 'Order {number} received',
      ar: 'تم استلام الطلب {number}',
      ku: 'داواکاری {number} وەرگیرا',
    },
    body: {
      en: "Thank you! We've received your order and will confirm it soon.",
      ar: 'شكرًا لك! استلمنا طلبك وسنؤكده قريبًا.',
      ku: 'سوپاس! داواکارییەکەتمان وەرگرت و بەم زووانە پشتڕاستی دەکەینەوە.',
    },
  },
  confirmed: {
    title: {
      en: 'Order {number} confirmed',
      ar: 'تم تأكيد الطلب {number}',
      ku: 'داواکاری {number} پشتڕاستکرایەوە',
    },
    body: {
      en: 'Good news! Your order is confirmed and will be prepared soon.',
      ar: 'أخبار سارة! تم تأكيد طلبك وسيبدأ تحضيره قريبًا.',
      ku: 'هەواڵێکی خۆش! داواکارییەکەت پشتڕاستکرایەوە و بەم زووانە ئامادە دەکرێت.',
    },
  },
  preparing: {
    title: {
      en: 'Order {number} is being prepared',
      ar: 'جارٍ تحضير الطلب {number}',
      ku: 'داواکاری {number} ئامادە دەکرێت',
    },
    body: {
      en: "We're preparing your gift with care.",
      ar: 'نحضّر هديتك بكل عناية.',
      ku: 'بە وردی خەریکی ئامادەکردنی دیارییەکەتین.',
    },
  },
  readyForDelivery: {
    title: {
      en: 'Order {number} is ready',
      ar: 'الطلب {number} جاهز',
      ku: 'داواکاری {number} ئامادەیە',
    },
    body: {
      en: 'Your order is packed and ready for delivery.',
      ar: 'تم تغليف طلبك وهو جاهز للتوصيل.',
      ku: 'داواکارییەکەت پێچرایەوە و ئامادەیە بۆ گەیاندن.',
    },
  },
  outForDelivery: {
    title: {
      en: 'Order {number} is on its way',
      ar: 'الطلب {number} في الطريق إليك',
      ku: 'داواکاری {number} لە ڕێگادایە',
    },
    body: {
      en: 'Our courier is on the way to you.',
      ar: 'المندوب في طريقه إليك الآن.',
      ku: 'گەیەنەرەکەمان ئێستا بەرەو لای تۆ دێت.',
    },
  },
  delivered: {
    title: {
      en: 'Order {number} delivered',
      ar: 'تم توصيل الطلب {number}',
      ku: 'داواکاری {number} گەیەندرا',
    },
    body: {
      en: 'Your order has been delivered. We hope it brings a big smile!',
      ar: 'تم توصيل طلبك. نتمنى أن يرسم ابتسامة كبيرة!',
      ku: 'داواکارییەکەت گەیەندرا. هیوادارین زەردەخەنەیەکی گەورە بخاتە سەر لێوان!',
    },
  },
  cancelledByBuyer: {
    title: {
      en: 'Order {number} cancelled',
      ar: 'تم إلغاء الطلب {number}',
      ku: 'داواکاری {number} هەڵوەشایەوە',
    },
    body: {
      en: 'Your order has been cancelled as you requested.',
      ar: 'تم إلغاء طلبك بناءً على رغبتك.',
      ku: 'داواکارییەکەت بەپێی داوای خۆت هەڵوەشایەوە.',
    },
  },
  cancelledBySeller: {
    title: {
      en: 'Order {number} cancelled',
      ar: 'تم إلغاء الطلب {number}',
      ku: 'داواکاری {number} هەڵوەشێنرایەوە',
    },
    body: {
      en: 'Sorry, the store had to cancel your order. Contact us if you have any questions.',
      ar: 'نعتذر، اضطر المتجر إلى إلغاء طلبك. تواصل معنا إذا كان لديك أي استفسار.',
      ku: 'ببورە، فرۆشگاکە ناچار بوو داواکارییەکەت هەڵبوەشێنێتەوە. ئەگەر پرسیارێکت هەیە پەیوەندیمان پێوە بکە.',
    },
    bodyWithReason: {
      en: 'Sorry, the store had to cancel your order. Reason: {reason}',
      ar: 'نعتذر، اضطر المتجر إلى إلغاء طلبك. السبب: {reason}',
      ku: 'ببورە، فرۆشگاکە ناچار بوو داواکارییەکەت هەڵبوەشێنێتەوە. هۆکار: {reason}',
    },
  },
  returned: {
    title: {
      en: 'Order {number} returned',
      ar: 'تم إرجاع الطلب {number}',
      ku: 'داواکاری {number} گەڕێنرایەوە',
    },
    body: {
      en: "Your order was returned to us. We'll contact you about the next steps.",
      ar: 'أُعيد طلبك إلينا. سنتواصل معك بخصوص الخطوات التالية.',
      ku: 'داواکارییەکەت بۆمان گەڕێنرایەوە. سەبارەت بە هەنگاوەکانی داهاتوو پەیوەندیت پێوە دەکەین.',
    },
  },
  refunded: {
    title: {
      en: 'Order {number} refunded',
      ar: 'تم استرداد مبلغ الطلب {number}',
      ku: 'پارەی داواکاری {number} گەڕێنرایەوە',
    },
    body: {
      en: 'Your refund has been processed.',
      ar: 'تمت معالجة استرداد المبلغ.',
      ku: 'گەڕاندنەوەی پارەکەت ئەنجام درا.',
    },
  },
};

function fill(text: Trilingual, values: Record<string, string>): Trilingual {
  const apply = (s: string) => s.replace(/\{(\w+)\}/g, (m, key: string) => values[key] ?? m);
  return { en: apply(text.en), ar: apply(text.ar), ku: apply(text.ku) };
}

/** The notification for `orderId` reaching `status` (`reason`: the seller's note, if any). */
export function orderStatusNotification(
  status: OrderStatus,
  order: { orderId: string; orderNumber: string; reason?: string | null },
): UserNotification {
  const template = ORDER_MESSAGES[status];
  const reason = order.reason?.trim() ?? '';
  const values = { number: order.orderNumber, reason };
  const body = reason.length > 0 && template.bodyWithReason !== undefined ? template.bodyWithReason : template.body;
  return {
    type: ORDER_NOTIFICATION_TYPE,
    title: fill(template.title, values),
    body: fill(body, values),
    route: `/orders/${order.orderId}`,
    id: order.orderId,
  };
}

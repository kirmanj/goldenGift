/**
 * Partner (store) notifications to the store owner (SRS §5.25, §9 Stores /
 * Partners) in English, Arabic and Kurdish Sorani. They open Become a Partner,
 * which shows the store's status card. Wording follows the app's terms
 * (app_*.arb "Golden Gift" = "غولدن غيفت" / "گۆڵدن گیفت", "store" = "المتجر" /
 * "فرۆشگا"). The Kurdish copy needs the same native-speaker review as the rest of
 * the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';

/** `notifications.type` of every partner notification. */
export const PARTNER_STATUS = 'partnerStatus';
export const PARTNER_ROUTE = '/become-partner';

function n(storeId: string, title: UserNotification['title'], body: UserNotification['body']): UserNotification {
  return { type: PARTNER_STATUS, title, body, route: PARTNER_ROUTE, id: storeId };
}

export function partnerApprovedNotification(storeId: string, storeName: string): UserNotification {
  return n(
    storeId,
    { en: 'Welcome to Golden Gift!', ar: 'مرحبًا بك في غولدن غيفت!', ku: 'بەخێربێیت بۆ گۆڵدن گیفت!' },
    {
      en: `${storeName} is approved. Sign in to the partner dashboard to add your products.`,
      ar: `تمت الموافقة على ${storeName}. سجّل الدخول إلى لوحة الشركاء لإضافة منتجاتك.`,
      ku: `${storeName} پەسەندکرا. بچۆ ژوورەوەی داشبۆردی هاوبەشان بۆ زیادکردنی بەرهەمەکانت.`,
    },
  );
}

export function partnerRejectedNotification(storeId: string, storeName: string, reason: string): UserNotification {
  return n(
    storeId,
    { en: 'About your partner application', ar: 'بخصوص طلب الشراكة', ku: 'سەبارەت بە داواکاریی هاوبەشییەکەت' },
    {
      en: `We can't approve ${storeName} right now. Reason: ${reason}`,
      ar: `لا يمكننا الموافقة على ${storeName} حاليًا. السبب: ${reason}`,
      ku: `ئێستا ناتوانین ${storeName} پەسەند بکەین. هۆکار: ${reason}`,
    },
  );
}

export function storeSuspendedNotification(storeId: string, storeName: string, reason: string): UserNotification {
  return n(
    storeId,
    { en: 'Your store is paused', ar: 'تم إيقاف متجرك مؤقتًا', ku: 'فرۆشگاکەت ڕاگیرا' },
    {
      en: `${storeName} is hidden from customers for now. Reason: ${reason}`,
      ar: `${storeName} مخفي عن العملاء حاليًا. السبب: ${reason}`,
      ku: `${storeName} بۆ ئێستا لە کڕیاران شاردراوەتەوە. هۆکار: ${reason}`,
    },
  );
}

export function storeReactivatedNotification(storeId: string, storeName: string): UserNotification {
  return n(
    storeId,
    { en: 'Your store is live again', ar: 'متجرك متاح من جديد', ku: 'فرۆشگاکەت دیسان چالاکە' },
    {
      en: `${storeName} is visible to customers again.`,
      ar: `أصبح ${storeName} ظاهرًا للعملاء من جديد.`,
      ku: `${storeName} دیسان بۆ کڕیاران دەردەکەوێت.`,
    },
  );
}

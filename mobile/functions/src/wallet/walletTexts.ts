/**
 * Wallet transaction titles and referral notifications (SRS §5.18, §5.19, §4.5)
 * in English, Arabic and Kurdish Sorani. Wording follows the app's terms
 * (app_*.arb: "Credits" = "المكافآت" / "خاڵ", "Order" = "الطلب" / "داواکاری",
 * "Referral reward" = "مكافأة إحالة" / "پاداشتی بانگهێشت"). The Kurdish copy needs
 * the same native-speaker review as the rest of the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';
import type { Trilingual } from '../notifications/orderMessages';

/** `CurrencyFormatter.format`: "5,000 IQD" (0 decimals, the same in every language). */
export function formatIqd(amount: number): string {
  const sign = amount < 0 ? '-' : '';
  const digits = Math.abs(Math.round(amount)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${sign}${digits} IQD`;
}

/** `orderPayment` — e.g. "Order GG-2610-00001". */
export function orderPaymentTitle(orderNumber: string): Trilingual {
  return { en: `Order ${orderNumber}`, ar: `الطلب ${orderNumber}`, ku: `داواکاری ${orderNumber}` };
}

/** `refund` of an order's wallet / credits / paid amount. */
export function orderRefundTitle(orderNumber: string): Trilingual {
  return {
    en: `Refund · Order ${orderNumber}`,
    ar: `استرداد · الطلب ${orderNumber}`,
    ku: `گەڕاندنەوەی پارە · داواکاری ${orderNumber}`,
  };
}

/** `referralCredit` to the new user (joinBonus). */
export const JOIN_BONUS_TITLE: Trilingual = {
  en: 'Welcome bonus',
  ar: 'مكافأة الترحيب',
  ku: 'پاداشتی بەخێرهاتن',
};

/** `referralCredit` to the referrer (orderBonus). */
export const ORDER_BONUS_TITLE: Trilingual = {
  en: 'Referral reward',
  ar: 'مكافأة إحالة',
  ku: 'پاداشتی بانگهێشت',
};

/** `creditExpiry`. */
export const CREDIT_EXPIRY_TITLE: Trilingual = {
  en: 'Credits expired',
  ar: 'انتهت صلاحية رصيد المكافآت',
  ku: 'ماوەی خاڵەکان بەسەرچوو',
};

/** `adminAdjustment` (the admin's reason is stored separately and shown in the dashboard only). */
export function adjustmentTitle(bucket: 'balance' | 'credits'): Trilingual {
  return bucket === 'balance'
    ? { en: 'Balance adjustment', ar: 'تعديل الرصيد', ku: 'ڕێکخستنی باڵانس' }
    : { en: 'Credits adjustment', ar: 'تعديل المكافآت', ku: 'ڕێکخستنی خاڵەکان' };
}

/** `notifications.type` of referral rewards (the app shows the referral icon). */
export const REFERRAL_CREDITED = 'referralCredited';

/** To the referrer when the friend's first order was delivered and paid. Opens Invite & Earn. */
export function orderBonusNotification(referralId: string, amount: number, friendName: string | null): UserNotification {
  const value = formatIqd(amount);
  const name = friendName?.trim() ?? '';
  return {
    type: REFERRAL_CREDITED,
    title: {
      en: `You earned ${value} in credits`,
      ar: `ربحت ${value} مكافآت`,
      ku: `${value} خاڵت بەدەستهێنا`,
    },
    body:
      name.length > 0
        ? {
            en: `${name} received their first order. Thanks for inviting your friends!`,
            ar: `استلم ${name} أول طلب له. شكرًا لدعوتك أصدقاءك!`,
            ku: `${name} یەکەم داواکاریی خۆی وەرگرت. سوپاس بۆ بانگهێشتکردنی هاوڕێکانت!`,
          }
        : {
            en: 'A friend you invited received their first order. Thanks for inviting your friends!',
            ar: 'استلم صديق دعوته أول طلب له. شكرًا لدعوتك أصدقاءك!',
            ku: 'هاوڕێیەک کە بانگهێشتت کرد یەکەم داواکاریی خۆی وەرگرت. سوپاس بۆ بانگهێشتکردنی هاوڕێکانت!',
          },
    route: '/invite',
    id: referralId,
  };
}

/** To the new user when the join bonus was paid. Opens My Wallet. */
export function joinBonusNotification(referralId: string, amount: number): UserNotification {
  const value = formatIqd(amount);
  return {
    type: REFERRAL_CREDITED,
    title: {
      en: `Welcome gift: ${value} in credits`,
      ar: `هدية ترحيب: ${value} مكافآت`,
      ku: `دیاریی بەخێرهاتن: ${value} خاڵ`,
    },
    body: {
      en: "You joined with a friend's code. Spend your credits on any order.",
      ar: 'انضممت برمز أحد أصدقائك. استخدم مكافآتك في أي طلب.',
      ku: 'بە کۆدی هاوڕێیەک تۆمار بوویت. خاڵەکانت لە هەر داواکارییەکدا بەکاربهێنە.',
    },
    route: '/wallet',
    id: referralId,
  };
}

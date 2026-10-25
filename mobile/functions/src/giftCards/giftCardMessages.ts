/**
 * Gift-card notifications (SRS §4.5 "gift card received", §5.22) and wallet
 * titles in English, Arabic and Kurdish Sorani. Wording follows the app's terms
 * (app_*.arb "Gift card" = "بطاقة هدية" / "کارتی دیاری", "My Gift Cards" =
 * "بطاقات هداياي" / "کارتی دیارییەکانم"). The Kurdish copy needs the same
 * native-speaker review as the rest of the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';
import type { Trilingual } from '../notifications/orderMessages';
import { formatIqd } from '../wallet/walletTexts';
import { GIFT_CARD_RECEIVED, GIFT_CARD_SENT } from './giftCardRules';

/** Opens My Gift Cards. */
export const GIFT_CARDS_ROUTE = '/gift-cards';

/** `giftCardRedeem` wallet transaction (`txnGiftCardRedeem` in the app). */
export const GIFT_CARD_REDEEM_TITLE: Trilingual = {
  en: 'Gift card redeemed',
  ar: 'استبدال بطاقة هدية',
  ku: 'کارتی دیاری بەکارهێنرا',
};

/** Order line title of a gift-card purchase when the template has no name. */
export const GIFT_CARD_LINE_TITLE: Trilingual = { en: 'Gift card', ar: 'بطاقة هدية', ku: 'کارتی دیاری' };

/** Label of the order line's "Recipient" selection. */
export const RECIPIENT_LABEL: Trilingual = { en: 'Recipient', ar: 'المستلم', ku: 'وەرگر' };

/** To the recipient (an app user) when the card is sent. */
export function giftCardReceivedNotification(giftCardId: string, amount: number, from: string | null): UserNotification {
  const value = formatIqd(amount);
  const name = from?.trim() ?? '';
  return {
    type: GIFT_CARD_RECEIVED,
    title: { en: 'You received a gift card', ar: 'وصلتك بطاقة هدية', ku: 'کارتی دیارییەکت بۆ هات' },
    body:
      name.length > 0
        ? {
            en: `${name} sent you a ${value} gift card. Redeem it in My Gift Cards.`,
            ar: `أرسل لك ${name} بطاقة هدية بقيمة ${value}. استبدلها من بطاقات هداياي.`,
            ku: `${name} کارتی دیارییەکی ${value}ی بۆ ناردیت. لە کارتی دیارییەکانم بەکاری بهێنە.`,
          }
        : {
            en: `You received a ${value} gift card. Redeem it in My Gift Cards.`,
            ar: `وصلتك بطاقة هدية بقيمة ${value}. استبدلها من بطاقات هداياي.`,
            ku: `کارتی دیارییەکی ${value}ت بۆ هات. لە کارتی دیارییەکانم بەکاری بهێنە.`,
          },
    route: GIFT_CARDS_ROUTE,
    id: giftCardId,
  };
}

/** To the purchaser: the card went out (now or on its scheduled day). */
export function giftCardSentNotification(giftCardId: string, amount: number, recipientName: string): UserNotification {
  const value = formatIqd(amount);
  return {
    type: GIFT_CARD_SENT,
    title: { en: 'Your gift card was sent', ar: 'تم إرسال بطاقة الهدية', ku: 'کارتی دیارییەکەت نێردرا' },
    body: {
      en: `Your ${value} gift card is on its way to ${recipientName}.`,
      ar: `بطاقة الهدية بقيمة ${value} في طريقها إلى ${recipientName}.`,
      ku: `کارتی دیارییە ${value}ییەکەت بۆ ${recipientName} نێردرا.`,
    },
    route: GIFT_CARDS_ROUTE,
    id: giftCardId,
  };
}

/** To the purchaser when the card is scheduled for later (`date` = yyyy-MM-dd, Iraq time). */
export function giftCardScheduledNotification(
  giftCardId: string,
  amount: number,
  recipientName: string,
  date: string,
): UserNotification {
  const value = formatIqd(amount);
  return {
    type: GIFT_CARD_SENT,
    title: { en: 'Your gift card is ready', ar: 'بطاقة الهدية جاهزة', ku: 'کارتی دیارییەکەت ئامادەیە' },
    body: {
      en: `Your ${value} gift card for ${recipientName} will be sent on ${date}.`,
      ar: `سيتم إرسال بطاقة الهدية بقيمة ${value} إلى ${recipientName} بتاريخ ${date}.`,
      ku: `کارتی دیارییە ${value}ییەکەت لە ${date} بۆ ${recipientName} دەنێردرێت.`,
    },
    route: GIFT_CARDS_ROUTE,
    id: giftCardId,
  };
}

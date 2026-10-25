/**
 * Special-request notifications (SRS §4.5 "special-request reply", §5.17) and the
 * order line texts of an accepted quote, in English, Arabic and Kurdish Sorani.
 * Wording follows the app's terms (app_*.arb "Special Requests" = "الطلبات الخاصة"
 * / "داواکارییە تایبەتەکان", "Our quote" = "عرض السعر" / "نرخی پێشنیارکراو"). The
 * Kurdish copy needs the same native-speaker review as the rest of the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';
import type { Trilingual } from '../notifications/orderMessages';
import { formatIqd } from '../wallet/walletTexts';

/** `notifications.type` (the app shows the chat icon). */
export const SPECIAL_REQUEST_REPLY = 'specialRequestReply';

export const specialRequestRoute = (id: string) => `/special-requests/${id}`;

/** Order line title of an accepted quote. */
export const SPECIAL_REQUEST_LINE_TITLE: Trilingual = { en: 'Special request', ar: 'طلب خاص', ku: 'داواکاریی تایبەت' };

/** Label of the line's "Request" selection (the first 60 characters of the idea). */
export const REQUEST_LABEL: Trilingual = { en: 'Request', ar: 'الطلب', ku: 'داواکاری' };

/** Characters of the request text copied onto the order line. */
export const LINE_TEXT_MAX = 60;

/** Max characters of a reply quoted in the notification body. */
const PREVIEW_MAX = 140;

function preview(text: string): string {
  const chars = Array.from(text.trim().replace(/\s+/g, ' '));
  return chars.length <= PREVIEW_MAX ? chars.join('') : `${chars.slice(0, PREVIEW_MAX - 1).join('')}…`;
}

/** The thread message `acceptQuote` posts (role admin, `system: true`). */
export function quoteAcceptedMessage(orderNumber: string): string {
  return `Quote accepted — order ${orderNumber}`;
}

/** A new admin message in the thread. */
export function specialRequestReplyNotification(requestId: string, text: string): UserNotification {
  const body = preview(text);
  return {
    type: SPECIAL_REQUEST_REPLY,
    title: {
      en: 'New reply to your request',
      ar: 'رد جديد على طلبك',
      ku: 'وەڵامێکی نوێ بۆ داواکارییەکەت',
    },
    body:
      body.length > 0
        ? { en: body, ar: body, ku: body }
        : {
            en: 'Golden Gift replied to your special request.',
            ar: 'ردّت غولدن غيفت على طلبك الخاص.',
            ku: 'گۆڵدن گیفت وەڵامی داواکارییە تایبەتەکەتی دایەوە.',
          },
    route: specialRequestRoute(requestId),
    id: requestId,
  };
}

/** The request was quoted. */
export function specialRequestQuotedNotification(requestId: string, amount: number): UserNotification {
  const value = formatIqd(amount);
  return {
    type: SPECIAL_REQUEST_REPLY,
    title: {
      en: 'Your quote is ready',
      ar: 'عرض السعر جاهز',
      ku: 'نرخی داواکارییەکەت ئامادەیە',
    },
    body: {
      en: `We can make your idea for ${value}. Open the request to accept the quote.`,
      ar: `يمكننا تنفيذ فكرتك مقابل ${value}. افتح الطلب لقبول العرض.`,
      ku: `دەتوانین بیرۆکەکەت بە ${value} جێبەجێ بکەین. داواکارییەکە بکەرەوە بۆ پەسەندکردنی نرخەکە.`,
    },
    route: specialRequestRoute(requestId),
    id: requestId,
  };
}

/**
 * Secret Santa notifications (SRS §4.5, §5.16) in English, Arabic and Kurdish
 * Sorani, using the app's terms (app_*.arb: "Secret Santa" = "سانتا السري" /
 * "سانتای نهێنی", "Draw names" = "سحب الأسماء" / "ناوەکان ڕابکێشە"). The Kurdish
 * copy needs the same native-speaker review as the rest of the app (SRS §8).
 */
import type { UserNotification } from '../notifications/notifyUser';

/** `notifications.type` (the app shows the gift icon for it). */
export const SECRET_SANTA_DRAW_TYPE = 'secretSantaDraw';

/** To every member once the names are drawn. Opens the group (`/secret-santa/{id}`). */
export function secretSantaDrawNotification(groupId: string, groupName: string): UserNotification {
  const name = groupName.trim();
  return {
    type: SECRET_SANTA_DRAW_TYPE,
    title:
      name.length > 0
        ? { en: `${name}: names drawn!`, ar: `${name}: تم سحب الأسماء!`, ku: `${name}: ناوەکان ڕاکێشران!` }
        : { en: 'Secret Santa: names drawn!', ar: 'سانتا السري: تم سحب الأسماء!', ku: 'سانتای نهێنی: ناوەکان ڕاکێشران!' },
    body: {
      en: "Open Secret Santa to see who you're buying a gift for. Keep it a secret!",
      ar: 'افتح سانتا السري لترى لمن ستشتري الهدية. حافظ على السر!',
      ku: 'سانتای نهێنی بکەرەوە بۆ ئەوەی ببینیت دیاری بۆ کێ دەکڕیت. بە نهێنی بیهێڵەرەوە!',
    },
    route: `/secret-santa/${groupId}`,
    id: groupId,
  };
}

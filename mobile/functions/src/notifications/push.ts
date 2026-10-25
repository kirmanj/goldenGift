/**
 * FCM push (SRS §4.5). Messaging is injected (`PushMessaging`): firebase-admin's
 * `getMessaging()` in production, a fake in tests — the emulator suite has no FCM.
 */
import type { BatchResponse, MulticastMessage } from 'firebase-admin/messaging';

/** The part of firebase-admin's `Messaging` the functions use. */
export interface PushMessaging {
  sendEachForMulticast(message: MulticastMessage): Promise<BatchResponse>;
}

/** FCM accepts at most 500 tokens per multicast. */
export const FCM_MULTICAST_LIMIT = 500;

/** `users.fcmTokens` holds at most this many devices (the rules enforce it too). */
export const MAX_FCM_TOKENS = 10;

/** Trilingual text, LocalizedText-shaped (`ku` = Kurdish Sorani). */
export interface LocalizedText {
  en: string;
  ar?: string | null;
  ku?: string | null;
}

/** The language a push is sent in: users.locale `ar` → ar, `ckb` → ku, anything else → en. */
export type PushLanguage = 'en' | 'ar' | 'ku';

export function pushLanguage(locale: unknown): PushLanguage {
  if (locale === 'ar') return 'ar';
  if (locale === 'ckb' || locale === 'ku') return 'ku';
  return 'en';
}

/** `LocalizedText.resolve`: the translation, or English when it is missing or empty. */
export function resolveText(text: LocalizedText, language: PushLanguage): string {
  const value = language === 'en' ? text.en : text[language];
  return typeof value === 'string' && value.length > 0 ? value : text.en;
}

/**
 * Tokens FCM reported as dead. `invalid-argument` also covers malformed
 * messages, so it only counts when FCM says the token itself is the problem.
 */
export function isInvalidTokenError(error: { code?: string; message?: string } | undefined): boolean {
  if (error === undefined) return false;
  if (error.code === 'messaging/registration-token-not-registered' || error.code === 'messaging/invalid-registration-token') {
    return true;
  }
  return error.code === 'messaging/invalid-argument' && /token/i.test(error.message ?? '');
}

export interface PushPayload {
  title: string;
  body: string;
  imageUrl?: string | null;
  /** FCM data values must be strings; null / undefined entries are left out. */
  data: Record<string, string | null | undefined>;
}

export interface PushResult {
  sent: number;
  failed: number;
  /** Tokens to remove from `users.fcmTokens`. */
  invalidTokens: string[];
}

/** Sends `payload` to `tokens` in chunks of 500. Never throws for per-token failures. */
export async function sendToTokens(
  messaging: PushMessaging,
  tokens: readonly string[],
  payload: PushPayload,
): Promise<PushResult> {
  const unique = [...new Set(tokens.filter((t) => typeof t === 'string' && t.length > 0))];
  const data: Record<string, string> = {};
  for (const [key, value] of Object.entries(payload.data)) {
    if (typeof value === 'string') data[key] = value;
  }
  const notification: { title: string; body: string; imageUrl?: string } = { title: payload.title, body: payload.body };
  if (payload.imageUrl) notification.imageUrl = payload.imageUrl;

  const result: PushResult = { sent: 0, failed: 0, invalidTokens: [] };
  for (let i = 0; i < unique.length; i += FCM_MULTICAST_LIMIT) {
    const chunk = unique.slice(i, i + FCM_MULTICAST_LIMIT);
    const response = await messaging.sendEachForMulticast({ tokens: chunk, notification, data });
    result.sent += response.successCount;
    result.failed += response.failureCount;
    response.responses.forEach((r, j) => {
      if (!r.success && isInvalidTokenError(r.error)) result.invalidTokens.push(chunk[j]);
    });
  }
  return result;
}

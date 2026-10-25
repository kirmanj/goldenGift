/**
 * One notification to one customer (SRS §4.5, §6.13): the in-app
 * `notifications/{id}` document, then one push to every device of the user in
 * their language.
 */
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { stringList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { pushLanguage, resolveText, sendToTokens, type LocalizedText, type PushMessaging } from './push';

export interface NotifyDeps {
  db: Firestore;
  /** null = no push (in-app document only). */
  messaging: PushMessaging | null;
  logger?: Pick<typeof functionsLogger, 'warn'>;
}

export interface UserNotification {
  /** `notifications.type`, e.g. `orderStatus`. */
  type: string;
  title: LocalizedText;
  body: LocalizedText;
  /** In-app route opened on tap, e.g. `/orders/{id}`. */
  route: string | null;
  /** The target's id (`data.id`), e.g. the order id. */
  id: string | null;
  imageUrl?: string | null;
}

export interface NotifyResult {
  notificationId: string;
  /** false when `notificationId` already existed: nothing was written or pushed. */
  created: boolean;
  /** Devices FCM accepted the push for. */
  sent: number;
  /** Dead tokens removed from `users.fcmTokens`. */
  removedTokens: number;
}

/** `notifications/{id}` for one user (§6.13) — the same shape the app's NotificationModel reads. */
export function notificationDoc(userId: string, n: UserNotification): DocumentData {
  const now = FieldValue.serverTimestamp();
  return {
    userId,
    title: n.title.en,
    titleAr: n.title.ar ?? null,
    titleKu: n.title.ku ?? null,
    body: n.body.en,
    bodyAr: n.body.ar ?? null,
    bodyKu: n.body.ku ?? null,
    type: n.type,
    data: { route: n.route, id: n.id },
    ...(n.imageUrl ? { imageUrl: n.imageUrl } : {}),
    isRead: false,
    createdAt: now,
    updatedAt: now,
  };
}

/**
 * Writes the notification, then pushes it (best effort). With `notificationId`
 * the write is a create: a repeat call with the same id (a retried trigger)
 * writes and pushes nothing. Firestore errors propagate; push errors are logged.
 */
export async function notifyUser(
  deps: NotifyDeps,
  uid: string,
  n: UserNotification,
  options: { notificationId?: string } = {},
): Promise<NotifyResult> {
  const collection = deps.db.collection(P.notifications);
  const ref = options.notificationId === undefined ? collection.doc() : collection.doc(options.notificationId);
  try {
    await ref.create(notificationDoc(uid, n));
  } catch (e) {
    if (options.notificationId !== undefined && isAlreadyExists(e)) {
      return { notificationId: ref.id, created: false, sent: 0, removedTokens: 0 };
    }
    throw e;
  }
  const push = await pushToUser(deps, uid, ref.id, n);
  return { notificationId: ref.id, created: true, ...push };
}

/**
 * One multicast to the user's devices in their language, unless they turned
 * notifications off. Tokens FCM reports as dead are removed. Never throws.
 */
export async function pushToUser(
  deps: NotifyDeps,
  uid: string,
  notificationId: string,
  n: UserNotification,
): Promise<{ sent: number; removedTokens: number }> {
  const none = { sent: 0, removedTokens: 0 };
  if (deps.messaging === null) return none;
  const log = deps.logger ?? functionsLogger;
  try {
    const userRef = deps.db.collection(P.users).doc(uid);
    const user = (await userRef.get()).data();
    if (user === undefined || user.notificationsEnabled === false || user.isDeleted === true) return none;
    const tokens = stringList(user.fcmTokens);
    if (tokens.length === 0) return none;

    const language = pushLanguage(user.locale);
    const result = await sendToTokens(deps.messaging, tokens, {
      title: resolveText(n.title, language),
      body: resolveText(n.body, language),
      imageUrl: n.imageUrl,
      data: { route: n.route, id: n.id, type: n.type, notificationId },
    });
    if (result.invalidTokens.length > 0) {
      await userRef.update({ fcmTokens: FieldValue.arrayRemove(...result.invalidTokens) });
    }
    return { sent: result.sent, removedTokens: result.invalidTokens.length };
  } catch (e) {
    log.warn('push failed', { uid, notificationId, error: e instanceof Error ? e.message : String(e) });
    return none;
  }
}

function isAlreadyExists(e: unknown): boolean {
  const code = typeof e === 'object' && e !== null && 'code' in e ? (e as { code: unknown }).code : undefined;
  return code === 6 || code === 'already-exists' || code === 'ALREADY_EXISTS';
}

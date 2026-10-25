/**
 * `sendBroadcast` (SRS §4.5, §9 Notifications, §7): an admin pushes one
 * trilingual message to every opted-in customer.
 *
 *  1. Caller: `admin` claim AND `admins/{uid}.role` ∈ super | ops | content.
 *  2. Rate limit: one broadcast per 60 s platform-wide, checked and recorded in
 *     the same transaction that creates `notifications/{id}` (`userId: 'all'`,
 *     `sentBy`, `sentCount: 0`) — the in-app copy every user sees.
 *  3. Push: pages through `users` (by document id, 500 per page), skips deleted /
 *     blocked accounts and `notificationsEnabled == false`, groups the tokens by
 *     language and sends multicasts of ≤ 500; dead tokens are removed.
 *  4. `sentCount` is updated and an `admin_audit_log` entry written.
 *
 * The throttle lives in `function_runs/sendBroadcast:throttle` (functions-only,
 * no client access) so no new collection is needed.
 */
import { FieldPath, FieldValue, Timestamp, type DocumentData, type Firestore, type Query } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { ADMIN_CLAIM } from '../admin/setAdminClaim';
import { stringList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { graphemeLength } from '../shared/text';
import { pushLanguage, resolveText, sendToTokens, type LocalizedText, type PushLanguage, type PushMessaging } from './push';

/** `BroadcastRepository.titleMax` / `bodyMax` in the dashboard. */
export const BROADCAST_TITLE_MAX = 60;
export const BROADCAST_BODY_MAX = 180;
export const BROADCAST_ROUTE_MAX = 200;
export const BROADCAST_IMAGE_URL_MAX = 2048;
/** One broadcast per minute, platform-wide. */
export const BROADCAST_INTERVAL_MS = 60 * 1000;
/** Admin roles allowed to broadcast (`finance` is not). */
export const BROADCAST_ROLES: readonly string[] = ['super', 'ops', 'content'];
export const BROADCAST_THROTTLE_KEY = 'sendBroadcast:throttle';
export const AUDIT_ACTION_BROADCAST = 'notification.broadcast';
export const BROADCAST_NOTIFICATION_TYPE = 'broadcast';
const USERS_PAGE_SIZE = 500;

export interface BroadcastDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn'>;
  /** Users read per page (default 500); tests use a small page to exercise paging. */
  pageSize?: number;
}

export interface BroadcastCaller {
  uid?: string;
  claims?: Readonly<Record<string, unknown>>;
}

export interface BroadcastRequest {
  title: Required<LocalizedText>;
  body: Required<LocalizedText>;
  route: string | null;
  imageUrl: string | null;
}

export interface BroadcastResult {
  notificationId: string;
  /** Devices FCM accepted the push for. */
  sent: number;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

function localizedInput(v: unknown, name: string, max: number): Required<LocalizedText> {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw bad(`\`${name}\` must be { en, ar?, ku? }.`);
  const input = v as Record<string, unknown>;
  const read = (lang: 'en' | 'ar' | 'ku'): string | null => {
    const value = input[lang];
    if (value === undefined || value === null) return null;
    if (typeof value !== 'string') throw bad(`\`${name}.${lang}\` must be a string.`);
    const text = value.trim();
    if (graphemeLength(text) > max) throw bad(`\`${name}.${lang}\` is longer than ${max} characters.`);
    return text.length > 0 ? text : null;
  };
  const en = read('en');
  if (en === null) throw bad(`\`${name}.en\` is required.`);
  return { en, ar: read('ar'), ku: read('ku') };
}

export function parseBroadcastData(data: unknown): BroadcastRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { title: { en, ar?, ku? }, body: { en, ar?, ku? }, route?, imageUrl? }.');
  }
  const d = data as Record<string, unknown>;
  const title = localizedInput(d.title, 'title', BROADCAST_TITLE_MAX);
  const body = localizedInput(d.body, 'body', BROADCAST_BODY_MAX);

  let route: string | null = null;
  if (d.route !== undefined && d.route !== null) {
    if (typeof d.route !== 'string') throw bad('`route` must be a string.');
    const r = d.route.trim();
    if (r.length > 0) {
      if (!r.startsWith('/') || r.length > BROADCAST_ROUTE_MAX || /\s/.test(r)) {
        throw bad('`route` must be an app path starting with "/".');
      }
      route = r;
    }
  }

  let imageUrl: string | null = null;
  if (d.imageUrl !== undefined && d.imageUrl !== null) {
    if (typeof d.imageUrl !== 'string') throw bad('`imageUrl` must be a string.');
    const u = d.imageUrl.trim();
    if (u.length > 0) {
      if (!/^https?:\/\/\S+$/.test(u) || u.length > BROADCAST_IMAGE_URL_MAX) throw bad('`imageUrl` must be an http(s) URL.');
      imageUrl = u;
    }
  }
  return { title, body, route, imageUrl };
}

export async function sendBroadcastCore(deps: BroadcastDeps, data: unknown, caller: BroadcastCaller): Promise<BroadcastResult> {
  const { db } = deps;
  const uid = caller.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to send a broadcast.');
  if (caller.claims?.[ADMIN_CLAIM] !== true) throw new HttpsError('permission-denied', 'Admins only.');
  const role = (await db.collection(P.admins).doc(uid).get()).get('role');
  if (typeof role !== 'string' || !BROADCAST_ROLES.includes(role)) {
    throw new HttpsError('permission-denied', 'Your admin role cannot send broadcasts.');
  }
  const request = parseBroadcastData(data);
  const nowMs = (deps.now ?? Date.now)();

  // ── Throttle + the in-app document, atomically ──
  const throttleRef = db.collection(P.functionRuns).doc(BROADCAST_THROTTLE_KEY);
  const notificationRef = db.collection(P.notifications).doc();
  await db.runTransaction(async (tx) => {
    const last = (await tx.get(throttleRef)).get('lastAt');
    if (last instanceof Timestamp && nowMs - last.toMillis() < BROADCAST_INTERVAL_MS) {
      const wait = Math.ceil((BROADCAST_INTERVAL_MS - (nowMs - last.toMillis())) / 1000);
      throw new HttpsError('resource-exhausted', `One broadcast per minute. Try again in ${wait} s.`);
    }
    tx.set(throttleRef, {
      key: BROADCAST_THROTTLE_KEY,
      at: FieldValue.serverTimestamp(),
      lastAt: Timestamp.fromMillis(nowMs),
      lastBy: uid,
      lastNotificationId: notificationRef.id,
    });
    tx.create(notificationRef, {
      userId: 'all',
      title: request.title.en,
      titleAr: request.title.ar,
      titleKu: request.title.ku,
      body: request.body.en,
      bodyAr: request.body.ar,
      bodyKu: request.body.ku,
      type: BROADCAST_NOTIFICATION_TYPE,
      data: { route: request.route, id: null },
      ...(request.imageUrl !== null && { imageUrl: request.imageUrl }),
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      sentBy: uid,
      sentCount: 0,
    });
  });

  // ── Push ──
  let sent = 0;
  if (deps.messaging !== null) {
    try {
      sent = await pushToEveryone(db, deps.messaging, request, notificationRef.id, deps.pageSize ?? USERS_PAGE_SIZE);
    } catch (e) {
      (deps.logger ?? functionsLogger).warn('sendBroadcast: push stopped', {
        notificationId: notificationRef.id,
        error: e instanceof Error ? e.message : String(e),
      });
    }
  }

  // ── Result + audit ──
  const batch = db.batch();
  batch.update(notificationRef, { sentCount: sent, updatedAt: FieldValue.serverTimestamp() });
  batch.create(db.collection(P.adminAuditLog).doc(), {
    adminUid: uid,
    action: AUDIT_ACTION_BROADCAST,
    target: `${P.notifications}/${notificationRef.id}`,
    before: null,
    after: { title: request.title.en, route: request.route, sentCount: sent },
    at: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { notificationId: notificationRef.id, sent };
}

/** Whether a user doc should receive broadcasts. */
export function receivesBroadcasts(user: DocumentData): boolean {
  return user.notificationsEnabled !== false && user.isDeleted !== true && user.isBlocked !== true;
}

async function pushToEveryone(
  db: Firestore,
  messaging: PushMessaging,
  request: BroadcastRequest,
  notificationId: string,
  pageSize: number,
): Promise<number> {
  let sent = 0;
  const base: Query = db
    .collection(P.users)
    .orderBy(FieldPath.documentId())
    .select('fcmTokens', 'locale', 'notificationsEnabled', 'isDeleted', 'isBlocked')
    .limit(pageSize);
  let query = base;
  /** Tokens already sent to: a device that moved between accounts gets the broadcast once. */
  const seen = new Set<string>();

  for (;;) {
    const page = await query.get();
    if (page.empty) break;

    const byLanguage = new Map<PushLanguage, string[]>();
    const owner = new Map<string, string>();
    for (const doc of page.docs) {
      const user = doc.data();
      if (!receivesBroadcasts(user)) continue;
      const tokens = stringList(user.fcmTokens);
      if (tokens.length === 0) continue;
      const language = pushLanguage(user.locale);
      const list = byLanguage.get(language) ?? [];
      for (const t of tokens) {
        if (seen.has(t)) continue;
        seen.add(t);
        owner.set(t, doc.id);
        list.push(t);
      }
      byLanguage.set(language, list);
    }

    const dead = new Map<string, string[]>();
    for (const [language, tokens] of byLanguage) {
      if (tokens.length === 0) continue;
      const result = await sendToTokens(messaging, tokens, {
        title: resolveText(request.title, language),
        body: resolveText(request.body, language),
        imageUrl: request.imageUrl,
        data: { route: request.route, type: BROADCAST_NOTIFICATION_TYPE, notificationId },
      });
      sent += result.sent;
      for (const t of result.invalidTokens) {
        const uid = owner.get(t)!;
        dead.set(uid, [...(dead.get(uid) ?? []), t]);
      }
    }
    if (dead.size > 0) {
      const batch = db.batch();
      for (const [uid, tokens] of dead) {
        batch.update(db.collection(P.users).doc(uid), { fcmTokens: FieldValue.arrayRemove(...tokens) });
      }
      await batch.commit();
    }

    if (page.size < pageSize) break;
    query = base.startAfter(page.docs[page.docs.length - 1]);
  }
  return sent;
}

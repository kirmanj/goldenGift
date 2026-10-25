/**
 * `purchaseGiftCard` (SRS §5.22, §7): the Gift Card Designer's "Buy". Validates
 * the template and amount, the recipient, message, photo and schedule, and creates
 * ONE order (`orderType: 'giftCard'`) in one transaction — the same idempotent id,
 * order number, first timeline entry and wallet debit as `placeOrder`
 * (orders/createOrderDoc.ts). `onGiftCardOrderPaid` issues the card once the order
 * is paid.
 *
 * Payment (PROVISIONAL, SRS §12 item 6, owner to confirm):
 *  - `cashOnDelivery`: the courier collects at the BUYER's address (`addressId`
 *    required, its city must be served); no delivery fee. The card is issued when
 *    ops mark the order delivered (onOrderStatusChange then marks it paid).
 *  - `wallet`: the wallet BALANCE only — credits never buy gift cards — must cover
 *    the amount (else `insufficient_funds`); the order is paid at once.
 */
import type { Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { notifyUser } from '../notifications/notifyUser';
import { orderStatusNotification } from '../notifications/orderMessages';
import type { PushMessaging } from '../notifications/push';
import { baghdadNow, earliestDeliveryDate, parseCities, parseGeneralSettings, parsePaymentSettings } from '../orders/checkoutRules';
import {
  addressSnapshot,
  assertMayOrder,
  bad,
  existingOrder,
  HOME_STORE_ID,
  isDocId,
  MAX_CLIENT_REQUEST_ID_LENGTH,
  parseSyntheticPaymentMethod,
  prepareSyntheticOrder,
  type PlacedSyntheticOrder,
  type SyntheticPaymentMethod,
} from '../orders/createOrderDoc';
import { orderFailure } from '../orders/orderErrors';
import { orderIdFor } from '../orders/orderNumber';
import { FirestorePaths as P } from '../shared/paths';
import { isOwnUploadUrl } from '../shared/storageUrls';
import { GIFT_CARD_LINE_TITLE, RECIPIENT_LABEL } from './giftCardMessages';
import {
  MAX_SCHEDULE_AHEAD_MS,
  parseAmount,
  parseMessage,
  parseOptionalInstant,
  parseOptionalUrl,
  parseRecipient,
  parseTemplate,
  templateAccepts,
  type Recipient,
} from './giftCardRules';

export interface PurchaseGiftCardDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  /** Epoch ms; tests pin the clock. */
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info'>;
}

/** Validated `GiftCardPurchase.toMap()`. */
export interface PurchaseGiftCardRequest extends Recipient {
  clientRequestId: string;
  templateId: string;
  amount: number;
  message: string;
  photoUrl: string | null;
  /** Epoch ms; null = as soon as it is paid. */
  scheduledAtMs: number | null;
  paymentMethod: SyntheticPaymentMethod;
  addressId: string | null;
}

export function parsePurchaseGiftCardData(data: unknown, nowMs: number): PurchaseGiftCardRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { clientRequestId, templateId, amount, recipientName, … }.');
  }
  const d = data as Record<string, unknown>;
  if (!isDocId(d.clientRequestId, MAX_CLIENT_REQUEST_ID_LENGTH)) throw bad('`clientRequestId` is missing or invalid.');
  if (!isDocId(d.templateId)) throw bad('`templateId` is missing or invalid.');
  const amount = parseAmount(d.amount);
  const recipient = parseRecipient(d, { requireContact: true });
  const message = parseMessage(d.message);
  const photoUrl = parseOptionalUrl(d.photoUrl, 'photoUrl');
  // The Designer sends 09:00 local time of the chosen day (tomorrow … +1 year) as UTC ISO; used as given.
  const scheduledAtMs = parseOptionalInstant(d.scheduledAt, 'scheduledAt');
  if (scheduledAtMs !== null && (scheduledAtMs <= nowMs || scheduledAtMs > nowMs + MAX_SCHEDULE_AHEAD_MS)) {
    throw bad('`scheduledAt` must be between tomorrow and one year from now.');
  }
  const paymentMethod = parseSyntheticPaymentMethod(d.paymentMethod);
  let addressId: string | null = null;
  if (paymentMethod === 'cashOnDelivery') {
    if (!isDocId(d.addressId)) throw bad('`addressId` is required for cash on delivery.');
    addressId = d.addressId;
  }
  return {
    clientRequestId: d.clientRequestId,
    templateId: d.templateId,
    amount,
    ...recipient,
    message,
    photoUrl,
    scheduledAtMs,
    paymentMethod,
    addressId,
  };
}

export async function purchaseGiftCardCore(
  deps: PurchaseGiftCardDeps,
  data: unknown,
  uid: string | undefined,
): Promise<PlacedSyntheticOrder> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to buy a gift card.');
  const nowMs = (deps.now ?? Date.now)();
  const request = parsePurchaseGiftCardData(data, nowMs);
  // The Designer's photo: the buyer's own upload (gift_cards/{uid}/…), never any URL — the recipient's app shows it.
  if (request.photoUrl !== null && !isOwnUploadUrl(request.photoUrl, `gift_cards/${uid}/`)) {
    throw bad('`photoUrl` must be a photo you uploaded in the app.');
  }
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const now = baghdadNow(nowMs);
  const orderRef = db.collection(P.orders).doc(orderIdFor(uid, request.clientRequestId));
  const cod = request.paymentMethod === 'cashOnDelivery';

  const outcome = await db.runTransaction(
    async (tx) => {
      // ── Reads ──
      const already = existingOrder(await tx.get(orderRef), uid);
      if (already !== null) return { created: false, placed: already };

      const userRef = db.collection(P.users).doc(uid);
      const settings = db.collection(P.appSettings);
      const refs = [
        userRef,
        db.collection(P.giftCardTemplates).doc(request.templateId),
        settings.doc('payments'),
        ...(cod ? [userRef.collection(P.addresses).doc(request.addressId!), settings.doc('cities'), settings.doc('general')] : []),
      ];
      const [userSnap, templateSnap, paymentsSnap, addressSnap, citiesSnap, generalSnap] = await tx.getAll(...refs);
      assertMayOrder(userSnap.data());

      const template = templateSnap.exists ? parseTemplate(templateSnap.id, templateSnap.data()!) : null;
      if (template === null || !template.isActive) throw bad('This gift card design is no longer available.');
      if (!templateAccepts(template, request.amount)) throw bad('This gift card design does not offer that amount.');

      const payments = parsePaymentSettings(paymentsSnap.data());
      if (!(cod ? payments.cashOnDelivery : payments.wallet)) throw bad('That payment method is not available.');

      let address: Record<string, unknown> | null = null;
      let deliveryDate: string | null = null;
      if (cod) {
        const a = addressSnap.data();
        if (a === undefined) throw bad('That address does not exist.');
        const cityId = typeof a.city === 'string' ? a.city : '';
        if (!parseCities(citiesSnap.data()).some((c) => c.id === cityId && c.isActive)) throw orderFailure('city_not_allowed');
        address = addressSnapshot(a);
        // When the courier can come to collect: the earliest checkout date with nothing to prepare.
        deliveryDate = earliestDeliveryDate(now, 0, parseGeneralSettings(generalSnap.data()).sameDayCutoff);
      }

      const prepared = await prepareSyntheticOrder(db, tx, orderRef, now, {
        uid,
        clientRequestId: request.clientRequestId,
        orderType: 'giftCard',
        line: {
          id: 'gift-card',
          productId: '',
          storeId: HOME_STORE_ID,
          title: {
            en: template.name.en || GIFT_CARD_LINE_TITLE.en,
            ar: template.name.ar ?? GIFT_CARD_LINE_TITLE.ar,
            ku: template.name.ku ?? GIFT_CARD_LINE_TITLE.ku,
          },
          image: request.photoUrl ?? template.artworkUrl,
          unitPrice: request.amount,
          selections: [
            {
              groupId: 'recipient',
              type: 'text',
              label: RECIPIENT_LABEL.en,
              labelAr: RECIPIENT_LABEL.ar,
              labelKu: RECIPIENT_LABEL.ku,
              text: request.recipientName,
              priceDelta: 0,
            },
          ],
        },
        // PROVISIONAL (SRS §12 item 6): nothing is shipped; the courier only collects the cash.
        deliveryFee: 0,
        paymentMethod: request.paymentMethod,
        address,
        deliveryDate,
        deliverySlot: null,
        extra: {
          giftCard: {
            templateId: request.templateId,
            amount: request.amount,
            recipientName: request.recipientName,
            recipientPhone: request.recipientPhone,
            recipientEmail: request.recipientEmail,
            message: request.message,
            photoUrl: request.photoUrl,
            scheduledAt: request.scheduledAtMs === null ? null : new Date(request.scheduledAtMs).toISOString(),
          },
          giftCardId: null,
        },
      });

      // ── Writes ──
      return { created: true, placed: prepared.apply() };
    },
    { maxAttempts: 10 },
  );
  if (!outcome.created) return outcome.placed;

  const placed = outcome.placed;
  await notifyUser(
    { db, messaging: deps.messaging, logger: log },
    uid,
    orderStatusNotification('pending', { orderId: placed.orderId, orderNumber: placed.orderNumber }),
    { notificationId: `${placed.orderId}-placed` },
  ).catch((err: unknown) =>
    log.warn('purchaseGiftCard: notification failed', { orderId: placed.orderId, error: err instanceof Error ? err.message : String(err) }),
  );
  return placed;
}


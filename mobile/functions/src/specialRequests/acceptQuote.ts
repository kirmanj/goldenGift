/**
 * `acceptQuote` (SRS §5.17 "the customer can Accept, which creates an order for
 * the quoted amount", §7): ONE transaction creates the order (`orderType:
 * 'specialRequest'`, one line for the quoted amount, the same idempotent id /
 * order number / timeline / wallet debit as `placeOrder` — orders/createOrderDoc.ts),
 * sets the request `accepted` with its `orderId` and posts the system message
 * "Quote accepted — order GG-…" in the thread. Then the customer gets the
 * "order received" notification.
 *
 * What the Accept-quote screen shows is what is charged: total = `quoteAmount` +
 * the address city's delivery fee; delivery date / slot by the checkout rules
 * with 0 preparation days; payment cash on delivery, or the wallet BALANCE (never
 * credits) when it covers the whole total.
 *
 * Errors: unauthenticated; invalid-argument (data, address, date / slot, payment
 * method); not-found ("Special request not found."); permission-denied (not your
 * request, blocked account); failed-precondition `{ reason }` = quote_unavailable
 * (not quoted / already ordered) · city_not_allowed · insufficient_funds.
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { notifyUser } from '../notifications/notifyUser';
import { orderStatusNotification } from '../notifications/orderMessages';
import type { PushMessaging } from '../notifications/push';
import {
  availableSlots,
  baghdadNow,
  earliestDeliveryDate,
  lastDeliveryDate,
  parseCities,
  parseGeneralSettings,
  parseIsoDate,
  parsePaymentSettings,
} from '../orders/checkoutRules';
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
import { integer, string, stringList, stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { LINE_TEXT_MAX, quoteAcceptedMessage, REQUEST_LABEL, SPECIAL_REQUEST_LINE_TITLE } from './specialRequestMessages';

/** `SpecialRequestRules.minQuote` (dashboard). */
export const MIN_QUOTE = 1_000;

export const QUOTE_UNAVAILABLE = 'quote_unavailable';

export interface AcceptQuoteRequest {
  requestId: string;
  clientRequestId: string;
  addressId: string;
  deliveryDate: string;
  deliverySlot: string;
  paymentMethod: SyntheticPaymentMethod;
}

export interface AcceptQuoteDeps {
  db: Firestore;
  messaging: PushMessaging | null;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'info'>;
}

export function parseAcceptQuoteData(data: unknown): AcceptQuoteRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) {
    throw bad('Expected { requestId, clientRequestId, addressId, deliveryDate, deliverySlot, paymentMethod }.');
  }
  const d = data as Record<string, unknown>;
  if (!isDocId(d.requestId)) throw bad('`requestId` is missing or invalid.');
  if (!isDocId(d.clientRequestId, MAX_CLIENT_REQUEST_ID_LENGTH)) throw bad('`clientRequestId` is missing or invalid.');
  if (!isDocId(d.addressId)) throw bad('`addressId` is missing or invalid.');
  if (parseIsoDate(d.deliveryDate) === null) throw bad('`deliveryDate` must be a date "yyyy-MM-dd".');
  if (typeof d.deliverySlot !== 'string' || d.deliverySlot.length === 0 || d.deliverySlot.length > 64) {
    throw bad('`deliverySlot` is missing.');
  }
  return {
    requestId: d.requestId,
    clientRequestId: d.clientRequestId,
    addressId: d.addressId,
    deliveryDate: d.deliveryDate as string,
    deliverySlot: d.deliverySlot,
    paymentMethod: parseSyntheticPaymentMethod(d.paymentMethod),
  };
}

const quoteUnavailable = (message: string) => new HttpsError('failed-precondition', message, { reason: QUOTE_UNAVAILABLE });

export async function acceptQuoteCore(
  deps: AcceptQuoteDeps,
  data: unknown,
  uid: string | undefined,
): Promise<PlacedSyntheticOrder> {
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in to accept the quote.');
  const request = parseAcceptQuoteData(data);
  const { db } = deps;
  const log = deps.logger ?? functionsLogger;
  const now = baghdadNow((deps.now ?? Date.now)());
  const orderRef = db.collection(P.orders).doc(orderIdFor(uid, request.clientRequestId));
  const requestRef = db.collection(P.specialRequests).doc(request.requestId);

  const outcome = await db.runTransaction(
    async (tx) => {
      // ── Reads ──
      const already = existingOrder(await tx.get(orderRef), uid);
      if (already !== null) return { created: false, placed: already };

      const userRef = db.collection(P.users).doc(uid);
      const settings = db.collection(P.appSettings);
      const [requestSnap, userSnap, addressSnap, citiesSnap, generalSnap, paymentsSnap] = await tx.getAll(
        requestRef,
        userRef,
        userRef.collection(P.addresses).doc(request.addressId),
        settings.doc('cities'),
        settings.doc('general'),
        settings.doc('payments'),
      );

      const sr = requestSnap.data();
      if (sr === undefined) throw new HttpsError('not-found', 'Special request not found.');
      if (sr.userId !== uid) throw new HttpsError('permission-denied', 'This is not your request.');
      if (stringOrNull(sr.orderId) !== null) throw quoteUnavailable('This quote was already accepted.');
      const quote = integer(sr.quoteAmount);
      if (sr.status !== 'quoted' || quote < MIN_QUOTE) throw quoteUnavailable('There is no quote to accept.');
      assertMayOrder(userSnap.data());

      const address = addressSnap.data();
      if (address === undefined) throw bad('That address does not exist.');
      const cityId = string(address.city);
      const city = parseCities(citiesSnap.data()).find((c) => c.id === cityId && c.isActive);
      if (city === undefined) throw orderFailure('city_not_allowed');

      const general = parseGeneralSettings(generalSnap.data());
      const earliest = earliestDeliveryDate(now, 0, general.sameDayCutoff);
      if (request.deliveryDate < earliest || request.deliveryDate > lastDeliveryDate(earliest)) {
        throw bad(`Delivery date must be between ${earliest} and ${lastDeliveryDate(earliest)}.`);
      }
      if (!availableSlots(request.deliveryDate, now, general.deliverySlots).some((s) => s.id === request.deliverySlot)) {
        throw bad('That delivery time is not available.');
      }

      const payments = parsePaymentSettings(paymentsSnap.data());
      if (!(request.paymentMethod === 'cashOnDelivery' ? payments.cashOnDelivery : payments.wallet)) {
        throw bad('That payment method is not available.');
      }

      const text = Array.from(string(sr.text).trim().replace(/\s+/g, ' '));
      const excerpt = text.length <= LINE_TEXT_MAX ? text.join('') : `${text.slice(0, LINE_TEXT_MAX - 1).join('')}…`;
      const prepared = await prepareSyntheticOrder(db, tx, orderRef, now, {
        uid,
        clientRequestId: request.clientRequestId,
        orderType: 'specialRequest',
        line: {
          id: 'special-request',
          productId: '',
          storeId: HOME_STORE_ID,
          title: SPECIAL_REQUEST_LINE_TITLE,
          image: stringList(sr.images)[0] ?? null,
          unitPrice: quote,
          selections:
            excerpt.length === 0
              ? []
              : [
                  {
                    groupId: 'request',
                    type: 'longText',
                    label: REQUEST_LABEL.en,
                    labelAr: REQUEST_LABEL.ar,
                    labelKu: REQUEST_LABEL.ku,
                    text: excerpt,
                    priceDelta: 0,
                  },
                ],
        },
        deliveryFee: city.deliveryFee,
        paymentMethod: request.paymentMethod,
        address: addressSnapshot(address),
        deliveryDate: request.deliveryDate,
        deliverySlot: request.deliverySlot,
        extra: { specialRequestId: request.requestId },
      });

      // ── Writes ──
      const placed = prepared.apply();
      const ts = FieldValue.serverTimestamp();
      tx.update(requestRef, {
        status: 'accepted',
        orderId: orderRef.id,
        acceptedAt: ts,
        // The customer acted: the request rises in the dashboard's "awaiting reply" inbox.
        lastMessageAt: ts,
        lastMessageBy: 'customer',
        updatedAt: ts,
      });
      tx.create(requestRef.collection(P.messages).doc(), {
        senderUid: 'system',
        role: 'admin',
        text: quoteAcceptedMessage(prepared.orderNumber),
        images: [],
        system: true,
        at: ts,
      });
      return { created: true, placed };
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
    log.warn('acceptQuote: notification failed', { orderId: placed.orderId, error: err instanceof Error ? err.message : String(err) }),
  );
  return placed;
}

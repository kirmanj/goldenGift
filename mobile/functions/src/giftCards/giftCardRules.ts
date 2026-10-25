/**
 * Gift-card rules shared by the gift-card functions (SRS §5.22, §6.10):
 * templates (`GiftCardTemplateModel` in mobile/lib/models/gift_card_model.dart),
 * codes, recipients, scheduling and validity.
 */
import { randomBytes } from 'node:crypto';
import type { DocumentData } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { looksLikeEmail } from '../admin/setAdminClaim';
import { normalizePhone } from '../auth/phone';
import { boolean, integer, stringOrNull } from '../shared/firestoreParse';
import { graphemeLength } from '../shared/text';

/** 12 characters (shown as XXXX-XXXX-XXXX), unique across `gift_cards`. */
export const GIFT_CARD_CODE_LENGTH = 12;
/** No 0 / O, 1 / I: nothing a customer can misread. 32 symbols → 60 bits per code. */
export const GIFT_CARD_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** PROVISIONAL (SRS §12 item 6, owner to confirm): a card is valid for 365 days from issue. */
export const GIFT_CARD_VALIDITY_DAYS = 365;
export const DAY_MS = 24 * 60 * 60 * 1000;

/** `GiftCardPurchase.maxMessage` / `GiftCardRules.maxMessage`. */
export const GIFT_CARD_MESSAGE_MAX = 200;
export const RECIPIENT_NAME_MAX = 60;
export const MAX_EMAIL_LENGTH = 254;
export const MAX_URL_LENGTH = 2048;

/** `GiftCardRules.maxAmount`: sanity cap on any card. */
export const GIFT_CARD_MAX_AMOUNT = 10_000_000;
/** Off-template amounts (super admins only, `adminIssueGiftCard`) start here (`GiftCardRules.minCustomAmount`). */
export const GIFT_CARD_MIN_FREE_AMOUNT = 1_000;

/** A scheduled card goes out at most this far ahead (the Designer offers tomorrow … +1 year). */
export const MAX_SCHEDULE_AHEAD_MS = 367 * DAY_MS;

/** `notifications.type` values (the app's NotificationTile icons `giftCardReceived`). */
export const GIFT_CARD_RECEIVED = 'giftCardReceived';
export const GIFT_CARD_SENT = 'giftCardSent';

export interface GiftCardTemplate {
  id: string;
  name: { en: string; ar: string | null; ku: string | null };
  artworkUrl: string | null;
  gradientStart: string | null;
  gradientEnd: string | null;
  presetAmounts: number[];
  minAmount: number;
  maxAmount: number;
  isActive: boolean;
}

export function parseTemplate(id: string, data: DocumentData): GiftCardTemplate {
  return {
    id,
    name: { en: stringOrNull(data.name) ?? '', ar: stringOrNull(data.nameAr), ku: stringOrNull(data.nameKu) },
    artworkUrl: stringOrNull(data.artworkUrl),
    gradientStart: stringOrNull(data.gradientStart),
    gradientEnd: stringOrNull(data.gradientEnd),
    presetAmounts: Array.isArray(data.presetAmounts) ? data.presetAmounts.map((v) => integer(v)).filter((v) => v > 0) : [],
    minAmount: integer(data.minAmount),
    maxAmount: integer(data.maxAmount),
    isActive: boolean(data.isActive, true),
  };
}

/** `GiftCardTemplateModel.accepts`: a preset, or within [minAmount, maxAmount] when custom amounts are on. */
export function templateAccepts(t: GiftCardTemplate, amount: number): boolean {
  const allowsCustom = t.minAmount > 0 && t.maxAmount >= t.minAmount;
  return amount > 0 && (t.presetAmounts.includes(amount) || (allowsCustom && amount >= t.minAmount && amount <= t.maxAmount));
}

/** A fresh random code (uniform over the alphabet: 256 is a multiple of 32). */
export function generateGiftCardCode(random: (n: number) => Buffer = randomBytes): string {
  const bytes = random(GIFT_CARD_CODE_LENGTH);
  let code = '';
  for (let i = 0; i < GIFT_CARD_CODE_LENGTH; i++) code += GIFT_CARD_CODE_ALPHABET[bytes[i] & 31];
  return code;
}

/** `GiftCardsRepository.normalizeCode`: no spaces / dashes, upper case. */
export function normalizeGiftCardCode(input: string): string {
  return input.replace(/[\s-]/g, '').toUpperCase();
}

export function isGiftCardCode(code: string): boolean {
  return code.length === GIFT_CARD_CODE_LENGTH && [...code].every((c) => GIFT_CARD_CODE_ALPHABET.includes(c));
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export interface Recipient {
  recipientName: string;
  /** E.164. */
  recipientPhone: string | null;
  /** Lower case. */
  recipientEmail: string | null;
}

/**
 * Recipient name (1–60 characters; `minName` raises the minimum), phone (any
 * format → E.164) and / or email. `requireContact`: at least one of phone / email.
 */
export function parseRecipient(d: Record<string, unknown>, options: { requireContact: boolean; minName?: number }): Recipient {
  if (typeof d.recipientName !== 'string') throw bad('`recipientName` is required.');
  const name = d.recipientName.trim();
  const min = options.minName ?? 1;
  if (graphemeLength(name) < min || graphemeLength(name) > RECIPIENT_NAME_MAX) {
    throw bad(`\`recipientName\` must be ${min}–${RECIPIENT_NAME_MAX} characters.`);
  }

  let phone: string | null = null;
  if (d.recipientPhone !== undefined && d.recipientPhone !== null && d.recipientPhone !== '') {
    phone = normalizePhone(d.recipientPhone);
    if (phone === null) throw bad('`recipientPhone` is not a valid phone number.');
  }
  let email: string | null = null;
  if (d.recipientEmail !== undefined && d.recipientEmail !== null && d.recipientEmail !== '') {
    const value = typeof d.recipientEmail === 'string' ? d.recipientEmail.trim().toLowerCase() : '';
    if (value.length > MAX_EMAIL_LENGTH || !looksLikeEmail(value) || !/\.[a-z]{2,}$/.test(value)) {
      throw bad('`recipientEmail` is not an email address.');
    }
    email = value;
  }
  if (options.requireContact && phone === null && email === null) {
    throw bad('Give the recipient’s phone number or email.');
  }
  return { recipientName: name, recipientPhone: phone, recipientEmail: email };
}

/** Message (≤ 200 characters, may be empty). */
export function parseMessage(v: unknown): string {
  if (v === undefined || v === null) return '';
  if (typeof v !== 'string') throw bad('`message` must be a string.');
  const message = v.trim();
  if (graphemeLength(message) > GIFT_CARD_MESSAGE_MAX) throw bad(`\`message\` is longer than ${GIFT_CARD_MESSAGE_MAX} characters.`);
  return message;
}

/** An http(s) URL (download URL of an uploaded photo), or null. */
export function parseOptionalUrl(v: unknown, field: string): string | null {
  if (v === undefined || v === null || v === '') return null;
  if (typeof v !== 'string' || v.length > MAX_URL_LENGTH || !/^https?:\/\/\S+$/.test(v)) {
    throw bad(`\`${field}\` must be an http(s) URL.`);
  }
  return v;
}

/** An ISO-8601 instant → epoch ms, or null when absent. */
export function parseOptionalInstant(v: unknown, field: string): number | null {
  if (v === undefined || v === null || v === '') return null;
  const ms = typeof v === 'string' ? Date.parse(v) : Number.NaN;
  if (!Number.isFinite(ms)) throw bad(`\`${field}\` must be an ISO date-time.`);
  return ms;
}

/** Whole IQD amount in (0, max]. */
export function parseAmount(v: unknown): number {
  if (typeof v !== 'number' || !Number.isSafeInteger(v) || v <= 0 || v > GIFT_CARD_MAX_AMOUNT) {
    throw bad(`\`amount\` must be a whole number of IQD up to ${GIFT_CARD_MAX_AMOUNT}.`);
  }
  return v;
}

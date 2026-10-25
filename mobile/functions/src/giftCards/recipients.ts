/**
 * Who a gift card is for (SRS §6.10 `recipientUid`) — decided ONLY from
 * identities Firebase Auth has verified, never from `users/{uid}.phone` /
 * `.email`: those are written by the app (the rules bound and bind them, but an
 * email typed at sign-up is not verified), and a card linked to an account is
 * readable — code included — by that account (§6.17). Matching on a profile
 * field would let anyone who types somebody else's number or email into their
 * profile collect that person's cards.
 *
 *  - phone: the Auth user whose phone number is the card's E.164 number (phone
 *    numbers reach Auth only through `verifyOtp` / `changePhone`, i.e. after an
 *    OTP was confirmed);
 *  - email: the Auth user with that email AND `emailVerified` (Google / Apple
 *    sign-in, or a verified email/password account).
 *
 * A card that matches nobody keeps `recipientUid: null`; the purchaser shares the
 * code, and whoever redeems it becomes the recipient (`redeemGiftCard`).
 * Injected (`GiftCardDeps.recipients`) so the Firestore-emulator suites use a fake;
 * production passes `authRecipientLookup(getAuth())`.
 */
import type { Auth, UserRecord } from 'firebase-admin/auth';
import { authErrorCode } from '../auth/authUsers';

export interface RecipientContacts {
  /** Verified phone (E.164), or null. */
  phone: string | null;
  /** Verified email (lower case), or null. */
  email: string | null;
}

export interface RecipientLookup {
  /** The account that owns this verified phone (tried first) or verified email, or null. */
  byContact(phone: string | null, email: string | null): Promise<string | null>;
  /** The verified phone / email of an account (cards sent to it before it existed). */
  contactsOf(uid: string): Promise<RecipientContacts>;
}

/** No lookup configured: nobody is matched (never fall back to profile fields). */
export const NO_RECIPIENT_LOOKUP: RecipientLookup = {
  byContact: async () => null,
  contactsOf: async () => ({ phone: null, email: null }),
};

async function orNull(read: () => Promise<UserRecord>): Promise<UserRecord | null> {
  try {
    return await read();
  } catch (e) {
    const code = authErrorCode(e);
    if (code === 'auth/user-not-found' || code === 'auth/invalid-phone-number' || code === 'auth/invalid-email') return null;
    throw e;
  }
}

/** The verified email of an Auth user (lower case), or null. */
export function verifiedEmail(user: Pick<UserRecord, 'email' | 'emailVerified'>): string | null {
  return user.emailVerified === true && typeof user.email === 'string' && user.email.length > 0 ? user.email.toLowerCase() : null;
}

export function authRecipientLookup(auth: Auth): RecipientLookup {
  return {
    async byContact(phone, email) {
      if (phone !== null) {
        const user = await orNull(() => auth.getUserByPhoneNumber(phone));
        if (user !== null) return user.uid;
      }
      if (email !== null) {
        const user = await orNull(() => auth.getUserByEmail(email));
        if (user !== null && verifiedEmail(user) === email.toLowerCase()) return user.uid;
      }
      return null;
    },
    async contactsOf(uid) {
      const user = await orNull(() => auth.getUser(uid));
      if (user === null) return { phone: null, email: null };
      return { phone: user.phoneNumber ?? null, email: verifiedEmail(user) };
    },
  };
}

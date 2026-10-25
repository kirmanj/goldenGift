import type { RecipientContacts, RecipientLookup } from '../src/giftCards/recipients';

/**
 * In-memory stand-in for Firebase Auth's VERIFIED identities (giftCards/recipients.ts):
 * `verify(uid, { phone, email })` is what verifyOtp / Google sign-in would have
 * proven. Profile docs in Firestore play no part — exactly like production.
 */
export class FakeRecipients implements RecipientLookup {
  private readonly accounts = new Map<string, RecipientContacts>();

  verify(uid: string, contacts: Partial<RecipientContacts>): this {
    this.accounts.set(uid, { phone: contacts.phone ?? null, email: contacts.email?.toLowerCase() ?? null });
    return this;
  }

  reset(): this {
    this.accounts.clear();
    return this;
  }

  async byContact(phone: string | null, email: string | null): Promise<string | null> {
    for (const [uid, c] of this.accounts) if (phone !== null && c.phone === phone) return uid;
    for (const [uid, c] of this.accounts) if (email !== null && c.email === email.toLowerCase()) return uid;
    return null;
  }

  async contactsOf(uid: string): Promise<RecipientContacts> {
    return this.accounts.get(uid) ?? { phone: null, email: null };
  }
}

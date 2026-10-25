import type { BatchResponse, MulticastMessage, SendResponse } from 'firebase-admin/messaging';
import type { PushMessaging } from '../src/notifications/push';

/** In-memory FCM: records every multicast; tokens in `dead` fail as not registered. */
export class FakeMessaging implements PushMessaging {
  readonly calls: MulticastMessage[] = [];
  readonly dead = new Set<string>();
  /** Tokens that fail with a per-token error that is NOT a dead token (e.g. quota). */
  readonly flaky = new Set<string>();
  /** When set, every call rejects (FCM down). */
  failWith: Error | null = null;

  async sendEachForMulticast(message: MulticastMessage): Promise<BatchResponse> {
    if (this.failWith !== null) throw this.failWith;
    this.calls.push(message);
    const responses: SendResponse[] = message.tokens.map((t) => {
      if (this.dead.has(t)) {
        return {
          success: false,
          error: { code: 'messaging/registration-token-not-registered', message: 'Requested entity was not found.' },
        } as SendResponse;
      }
      if (this.flaky.has(t)) {
        return { success: false, error: { code: 'messaging/internal-error', message: 'Try again.' } } as SendResponse;
      }
      return { success: true, messageId: `msg-${t}` };
    });
    const successCount = responses.filter((r) => r.success).length;
    return { responses, successCount, failureCount: responses.length - successCount };
  }

  /** Every token any call was sent to. */
  tokens(): string[] {
    return this.calls.flatMap((c) => c.tokens);
  }

  reset(): void {
    this.calls.length = 0;
    this.dead.clear();
    this.flaky.clear();
    this.failWith = null;
  }
}

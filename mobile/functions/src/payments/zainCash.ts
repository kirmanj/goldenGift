/**
 * ZainCash merchant API (SRS §12 item 4 — PROVISIONAL first gateway), as
 * documented at https://docs.zaincash.iq ("API Integration", v1.0 / v1.1;
 * archived copy: https://web.archive.org/web/20250716001946/https://docs.zaincash.iq/):
 *
 *  1. Create: JWT (HS256, merchant secret) `{ amount, serviceType, msisdn,
 *     orderId, redirectUrl, iat, exp }` → POST `{host}/transaction/init`
 *     (form fields `token`, `merchantId`, `lang`) → `{ id, … }` (or `{ err: { msg } }`).
 *  2. The customer pays at `{host}/transaction/pay?id={id}`.
 *  3. ZainCash redirects to `redirectUrl` with `token=<JWT>` signed with the same
 *     secret: `{ status: success | completed | failed | pending, orderid, id,
 *     msg?, iat, exp }`. No token = the customer pressed "Cancel and go back".
 *  4. Check: JWT `{ id, msisdn, iat, exp }` → POST `{host}/transaction/get`
 *     (`token`, `merchantId`) → the transaction with `status` (pending,
 *     pending_otp, completed, failed, cancel).
 *
 * Amounts are whole IQD (min 250 per the docs). `lang`: en | ar | ku.
 */
import { JwtError, signHs256, verifyHs256 } from './jwt';

export const ZAINCASH_HOSTS = {
  test: 'https://test.zaincash.iq',
  prod: 'https://api.zaincash.iq',
} as const;
export type ZainCashEnv = keyof typeof ZAINCASH_HOSTS;

/**
 * The PUBLIC sandbox merchant ZainCash publishes for testing ("Test credentials ›
 * Merchant" at https://docs.zaincash.iq — archived:
 * https://web.archive.org/web/20250716001946/https://docs.zaincash.iq/). They only
 * work against test.zaincash.iq and move no real money; they are the defaults of
 * the `test` environment until Golden Gift's own merchant credentials arrive.
 * (The same page lists sandbox CUSTOMER wallets to pay with on the test pay page.)
 */
export const ZAINCASH_PUBLIC_TEST_MERCHANT = {
  msisdn: '9647835077893',
  merchantId: '5ffacf6612b5777c6d44266f',
  secret: '$2y$10$hBbAZo2GfSSvyqAyV2SaqOfYewgYpfR1O19gIh4SqyGWdmySZYPuS',
} as const;

export interface ZainCashConfig {
  env: ZainCashEnv;
  host: string;
  merchantId: string;
  msisdn: string;
  secret: string;
  /** True when these are the published sandbox credentials. */
  publicTestMerchant: boolean;
}

/**
 * The gateway configuration from the function params / secret, or null with the
 * reason. `test` without a merchant id → the public sandbox merchant; `prod`
 * needs all three values (merchant id, wallet msisdn, secret).
 */
export function resolveZainCashConfig(input: {
  env?: string;
  merchantId?: string;
  msisdn?: string;
  secret?: string;
}): { config: ZainCashConfig; reason?: undefined } | { config: null; reason: string } {
  const rawEnv = (input.env ?? '').trim().toLowerCase();
  const env: ZainCashEnv = rawEnv === 'prod' || rawEnv === 'production' || rawEnv === 'live' ? 'prod' : 'test';
  const merchantId = (input.merchantId ?? '').trim();
  const msisdn = (input.msisdn ?? '').replace(/\D/g, '');
  const secret = (input.secret ?? '').trim();
  if (merchantId.length === 0) {
    if (env === 'prod') return { config: null, reason: 'ZAINCASH_MERCHANT_ID is not set' };
    return { config: { env, host: ZAINCASH_HOSTS.test, ...ZAINCASH_PUBLIC_TEST_MERCHANT, publicTestMerchant: true } };
  }
  if (msisdn.length === 0) return { config: null, reason: 'ZAINCASH_MSISDN is not set' };
  if (secret.length === 0) return { config: null, reason: 'ZAINCASH_SECRET is not set' };
  return { config: { env, host: ZAINCASH_HOSTS[env], merchantId, msisdn, secret, publicTestMerchant: false } };
}

/** What a payment looks like to Golden Gift, whatever the gateway's words. */
export type GatewayOutcome = 'paid' | 'failed' | 'pending';

export interface GatewayInitInput {
  /** Our reference (the payment session id) — ZainCash `orderId`, returned as `orderid`. */
  reference: string;
  amount: number;
  /** Shown on the pay page, e.g. "Golden Gift order GG-2610-00001". */
  serviceType: string;
  redirectUrl: string;
  lang: 'en' | 'ar' | 'ku';
  /** The request token's `exp` (the session's expiry). */
  expiresAtMs: number;
}

export interface GatewayReturn {
  outcome: GatewayOutcome;
  transactionId: string;
  reference: string;
  rawStatus: string;
  message: string | null;
}

export interface GatewayStatus {
  outcome: GatewayOutcome;
  rawStatus: string;
  amount: number | null;
  reference: string | null;
}

/** An online payment provider (only ZainCash today). Fakes implement it in tests. */
export interface PaymentGateway {
  readonly id: 'zainCash';
  readonly env: ZainCashEnv;
  /**
   * The redirect token alone is not proof of payment: the merchant secret is not
   * secret (ZainCash's published sandbox merchant), so anyone could sign a
   * "success" token. `zainCashReturn` then confirms the outcome with
   * `checkTransaction` (server to server) before settling anything.
   */
  readonly confirmsReturnServerSide?: boolean;
  createTransaction(input: GatewayInitInput, nowMs: number): Promise<{ transactionId: string; payUrl: string }>;
  /** Verifies the redirect token (signature, algorithm, expiry); throws `GatewayTokenError`. */
  verifyReturn(token: string, nowMs: number): GatewayReturn;
  /** Server-to-server status check (used before a session is expired). */
  checkTransaction(transactionId: string, nowMs: number): Promise<GatewayStatus>;
}

export class GatewayError extends Error {}
export class GatewayTokenError extends Error {
  constructor(
    readonly reason: string,
    message: string,
  ) {
    super(message);
  }
}

/** The redirect token's / transaction's status in Golden Gift's terms (unknown → pending: never cancel on a guess). */
export function zainCashOutcome(status: unknown): GatewayOutcome {
  const s = typeof status === 'string' ? status.trim().toLowerCase() : '';
  if (s === 'success' || s === 'completed') return 'paid';
  if (s === 'failed' || s === 'cancel' || s === 'cancelled' || s === 'canceled' || s === 'expired') return 'failed';
  return 'pending';
}

export type FetchLike = (url: string, init: { method: string; headers: Record<string, string>; body: string; signal?: AbortSignal }) => Promise<{
  ok: boolean;
  status: number;
  text(): Promise<string>;
}>;

/** The msisdn as the docs show it (a number), when it fits one exactly. */
function msisdnValue(msisdn: string): number | string {
  const n = Number(msisdn);
  return Number.isSafeInteger(n) ? n : msisdn;
}

export function zainCashGateway(
  config: ZainCashConfig,
  options: { fetch?: FetchLike; timeoutMs?: number } = {},
): PaymentGateway {
  const doFetch: FetchLike = options.fetch ?? ((url, init) => fetch(url, init));
  const timeoutMs = options.timeoutMs ?? 15_000;

  async function post(path: string, fields: Record<string, string>): Promise<Record<string, unknown>> {
    const res = await doFetch(`${config.host}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
      body: new URLSearchParams(fields).toString(),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await res.text();
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      throw new GatewayError(`zainCash ${path}: HTTP ${res.status}, not JSON`);
    }
    if (typeof json !== 'object' || json === null || Array.isArray(json)) {
      throw new GatewayError(`zainCash ${path}: HTTP ${res.status}, unexpected body`);
    }
    const body = json as Record<string, unknown>;
    const err = body.err as { msg?: unknown } | undefined;
    if (!res.ok || (err !== undefined && err !== null)) {
      const msg = typeof err?.msg === 'string' ? err.msg : `HTTP ${res.status}`;
      throw new GatewayError(`zainCash ${path}: ${msg}`);
    }
    return body;
  }

  return {
    id: 'zainCash',
    env: config.env,
    confirmsReturnServerSide: config.publicTestMerchant,

    async createTransaction(input, nowMs) {
      const iat = Math.floor(nowMs / 1000);
      const token = signHs256(
        {
          amount: input.amount,
          serviceType: input.serviceType,
          msisdn: msisdnValue(config.msisdn),
          orderId: input.reference,
          redirectUrl: input.redirectUrl,
          iat,
          exp: Math.max(iat + 60, Math.floor(input.expiresAtMs / 1000)),
        },
        config.secret,
      );
      const body = await post('/transaction/init', { token, merchantId: config.merchantId, lang: input.lang });
      const id = body.id;
      if (typeof id !== 'string' || id.length === 0) throw new GatewayError('zainCash /transaction/init: no transaction id');
      return { transactionId: id, payUrl: `${config.host}/transaction/pay?id=${encodeURIComponent(id)}` };
    },

    verifyReturn(token, nowMs) {
      let claims: Record<string, unknown>;
      try {
        claims = verifyHs256(token, config.secret, { nowSec: Math.floor(nowMs / 1000) });
      } catch (e) {
        if (e instanceof JwtError) throw new GatewayTokenError(e.reason, e.message);
        throw e;
      }
      const transactionId = typeof claims.id === 'string' ? claims.id : '';
      // The docs spell it `orderid`; accept `orderId` too.
      const ref = claims.orderid ?? claims.orderId;
      const reference = typeof ref === 'string' ? ref : typeof ref === 'number' ? String(ref) : '';
      if (transactionId.length === 0 || reference.length === 0) {
        throw new GatewayTokenError('claims', 'zainCash token: id / orderid missing');
      }
      return {
        outcome: zainCashOutcome(claims.status),
        transactionId,
        reference,
        rawStatus: typeof claims.status === 'string' ? claims.status : '',
        message: typeof claims.msg === 'string' && claims.msg.length > 0 ? claims.msg.slice(0, 300) : null,
      };
    },

    async checkTransaction(transactionId, nowMs) {
      const iat = Math.floor(nowMs / 1000);
      const token = signHs256({ id: transactionId, msisdn: msisdnValue(config.msisdn), iat, exp: iat + 600 }, config.secret);
      const body = await post('/transaction/get', { token, merchantId: config.merchantId });
      const amount = Number(body.amount);
      const ref = body.orderId ?? body.orderid;
      return {
        outcome: zainCashOutcome(body.status),
        rawStatus: typeof body.status === 'string' ? body.status : '',
        amount: Number.isFinite(amount) ? Math.round(amount) : null,
        reference: typeof ref === 'string' ? ref : null,
      };
    },
  };
}

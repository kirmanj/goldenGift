/**
 * HS256 JSON Web Tokens (RFC 7519) with the standard library — all ZainCash
 * needs: requests are signed with the merchant secret and its redirect token is
 * verified with the same secret. Only `HS256` is accepted (never `none`), the
 * signature is compared in constant time and `exp` / `nbf` are enforced.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

export class JwtError extends Error {
  constructor(
    readonly reason: 'malformed' | 'algorithm' | 'signature' | 'expired' | 'not_yet_valid',
    message: string,
  ) {
    super(message);
  }
}

const b64url = (input: string | Buffer) => Buffer.from(input).toString('base64url');

function hmac(data: string, secret: string): Buffer {
  return createHmac('sha256', secret).update(data, 'utf8').digest();
}

export function signHs256(payload: Record<string, unknown>, secret: string): string {
  if (secret.length === 0) throw new Error('jwt: empty secret');
  const head = `${b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${b64url(JSON.stringify(payload))}`;
  return `${head}.${hmac(head, secret).toString('base64url')}`;
}

function decodeJson(part: string): unknown {
  if (!/^[A-Za-z0-9_-]*$/.test(part)) throw new JwtError('malformed', 'jwt: not base64url');
  try {
    return JSON.parse(Buffer.from(part, 'base64url').toString('utf8'));
  } catch {
    throw new JwtError('malformed', 'jwt: not JSON');
  }
}

/**
 * The payload of a valid token, or a `JwtError`. `nowSec` = current Unix time;
 * `leewaySec` tolerates clock skew on `exp` / `nbf`.
 */
export function verifyHs256(
  token: string,
  secret: string,
  options: { nowSec?: number; leewaySec?: number } = {},
): Record<string, unknown> {
  if (secret.length === 0) throw new Error('jwt: empty secret');
  const parts = token.trim().split('.');
  if (parts.length !== 3 || parts.some((p) => p.length === 0)) throw new JwtError('malformed', 'jwt: expected 3 parts');
  const header = decodeJson(parts[0]);
  if (typeof header !== 'object' || header === null || (header as Record<string, unknown>).alg !== 'HS256') {
    throw new JwtError('algorithm', 'jwt: only HS256 is accepted');
  }
  const expected = hmac(`${parts[0]}.${parts[1]}`, secret);
  if (!/^[A-Za-z0-9_-]+$/.test(parts[2])) throw new JwtError('malformed', 'jwt: bad signature encoding');
  const actual = Buffer.from(parts[2], 'base64url');
  if (actual.length !== expected.length || !timingSafeEqual(actual, expected)) {
    throw new JwtError('signature', 'jwt: bad signature');
  }
  const payload = decodeJson(parts[1]);
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    throw new JwtError('malformed', 'jwt: payload is not an object');
  }
  const claims = payload as Record<string, unknown>;
  const now = options.nowSec ?? Math.floor(Date.now() / 1000);
  const leeway = options.leewaySec ?? 120;
  if (typeof claims.exp === 'number' && now > claims.exp + leeway) throw new JwtError('expired', 'jwt: expired');
  if (typeof claims.nbf === 'number' && now + leeway < claims.nbf) throw new JwtError('not_yet_valid', 'jwt: not yet valid');
  return claims;
}

/**
 * Requests of scripts/enable-email-auth.ts: the Identity Toolkit Admin v2 project
 * config, read and patched so the Email/Password sign-in provider is on (the admin
 * dashboard signs in with email + password, SRS §9). Pure builders plus one sender
 * whose `fetch` and access token are injected, so the requests are unit-tested
 * without touching the network.
 */

export const IDENTITY_TOOLKIT_ADMIN_V2 = 'https://identitytoolkit.googleapis.com/admin/v2';
/** Only `signIn.email` is changed; every other sign-in setting is left as it is. */
export const EMAIL_SIGN_IN_UPDATE_MASK = 'signIn.email';
/** OAuth scope of the access token (Application Default Credentials). */
export const CLOUD_PLATFORM_SCOPE = 'https://www.googleapis.com/auth/cloud-platform';

export interface HttpRequestSpec {
  method: 'GET' | 'PATCH';
  url: string;
  /** Everything except `Authorization`, which `send` adds. */
  headers: Record<string, string>;
  body?: string;
}

export interface EmailSignInState {
  enabled: boolean;
  passwordRequired: boolean;
}

export const configUrl = (projectId: string): string =>
  `${IDENTITY_TOOLKIT_ADMIN_V2}/projects/${encodeURIComponent(projectId)}/config`;

/**
 * `x-goog-user-project` bills the call to the project itself: user credentials from
 * `gcloud auth application-default login` have no quota project of their own, and
 * Identity Toolkit refuses calls without one.
 */
function headers(projectId: string, json: boolean): Record<string, string> {
  return {
    Accept: 'application/json',
    ...(json && { 'Content-Type': 'application/json' }),
    'x-goog-user-project': projectId,
  };
}

/** `GET …/config` — the current settings. */
export function getConfigRequest(projectId: string): HttpRequestSpec {
  return { method: 'GET', url: configUrl(projectId), headers: headers(projectId, false) };
}

/** `PATCH …/config?updateMask=signIn.email` turning on email + password sign-in. */
export function enableEmailSignInRequest(projectId: string): HttpRequestSpec {
  return {
    method: 'PATCH',
    url: `${configUrl(projectId)}?updateMask=${encodeURIComponent(EMAIL_SIGN_IN_UPDATE_MASK)}`,
    headers: headers(projectId, true),
    body: JSON.stringify({ signIn: { email: { enabled: true, passwordRequired: true } } }),
  };
}

/** `signIn.email` of a config response (absent fields → false). */
export function emailSignInState(config: unknown): EmailSignInState {
  const email = (config as { signIn?: { email?: { enabled?: unknown; passwordRequired?: unknown } } } | null)?.signIn
    ?.email;
  return { enabled: email?.enabled === true, passwordRequired: email?.passwordRequired === true };
}

/** Already what the dashboard needs: enabled, with a password (not email-link only). */
export const isEmailPasswordEnabled = (state: EmailSignInState): boolean => state.enabled && state.passwordRequired;

/** The request as text, for `--dry-run` (the token is never printed). */
export function describeRequest(spec: HttpRequestSpec): string {
  const lines = [`${spec.method} ${spec.url}`, 'Authorization: Bearer <access token from Application Default Credentials>'];
  for (const [name, value] of Object.entries(spec.headers)) lines.push(`${name}: ${value}`);
  if (spec.body !== undefined) lines.push('', JSON.stringify(JSON.parse(spec.body), null, 2));
  return lines.join('\n');
}

export class IdentityToolkitError extends Error {
  constructor(
    readonly status: number,
    readonly reason: string,
    message: string,
  ) {
    super(message);
  }
}

/** Sends `spec` with the bearer token; the parsed JSON body, or `IdentityToolkitError`. */
export async function send(spec: HttpRequestSpec, accessToken: string, fetchImpl: typeof fetch = fetch): Promise<unknown> {
  const response = await fetchImpl(spec.url, {
    method: spec.method,
    headers: { ...spec.headers, Authorization: `Bearer ${accessToken}` },
    ...(spec.body !== undefined && { body: spec.body }),
    signal: AbortSignal.timeout(30_000),
  });
  const text = await response.text();
  let json: unknown = null;
  try {
    json = text.length > 0 ? JSON.parse(text) : null;
  } catch {
    // Not JSON: reported below with the raw text.
  }
  if (!response.ok) {
    const error = (json as { error?: { message?: string; status?: string } } | null)?.error;
    const reason = error?.message ?? error?.status ?? text.slice(0, 300);
    throw new IdentityToolkitError(response.status, reason, `${spec.method} ${spec.url} → ${response.status}: ${reason}`);
  }
  return json;
}

/** What to do about a failed call, by its reason. */
export function hintFor(error: IdentityToolkitError, projectId: string): string {
  if (/CONFIGURATION_NOT_FOUND/i.test(error.reason)) {
    return `Firebase Authentication is not initialised on ${projectId} yet: open the Firebase console → Authentication → Get started once, then run this again.`;
  }
  if (error.status === 401 || error.status === 403) {
    return (
      'Check `gcloud auth application-default login` (an Owner / Firebase Admin account of ' +
      `${projectId}) and that the Identity Toolkit API is enabled for the project.`
    );
  }
  return '';
}

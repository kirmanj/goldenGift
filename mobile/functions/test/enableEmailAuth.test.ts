/** scripts/enable-email-auth.ts requests — pure; `send` runs against a stub fetch only. */
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  IdentityToolkitError,
  describeRequest,
  emailSignInState,
  enableEmailSignInRequest,
  getConfigRequest,
  hintFor,
  isEmailPasswordEnabled,
  send,
} from '../scripts/auth/enableEmailAuth';

const PROJECT = 'goldengift-iq';

/** A fetch stub recording what it was called with. */
function stubFetch(status: number, body: unknown) {
  const calls: Array<{ url: string; init: RequestInit }> = [];
  const impl = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), init: init ?? {} });
    return new Response(typeof body === 'string' ? body : JSON.stringify(body), { status });
  }) as typeof fetch;
  return { impl, calls };
}

describe('enable-email-auth requests', () => {
  test('PATCH …/admin/v2/projects/goldengift-iq/config?updateMask=signIn.email', () => {
    const spec = enableEmailSignInRequest(PROJECT);
    assert.equal(spec.method, 'PATCH');
    assert.equal(
      spec.url,
      'https://identitytoolkit.googleapis.com/admin/v2/projects/goldengift-iq/config?updateMask=signIn.email',
    );
    assert.deepEqual(JSON.parse(spec.body!), { signIn: { email: { enabled: true, passwordRequired: true } } });
    assert.equal(spec.headers['x-goog-user-project'], PROJECT);
    assert.equal(spec.headers['Content-Type'], 'application/json');
    assert.ok(!('Authorization' in spec.headers), 'the token is added only when sending');
  });

  test('GET …/config reads the current settings, without a body', () => {
    const spec = getConfigRequest(PROJECT);
    assert.equal(spec.method, 'GET');
    assert.equal(spec.url, 'https://identitytoolkit.googleapis.com/admin/v2/projects/goldengift-iq/config');
    assert.equal(spec.body, undefined);
    assert.equal(spec.headers['x-goog-user-project'], PROJECT);
  });

  test('emailSignInState reads signIn.email tolerantly', () => {
    assert.deepEqual(emailSignInState({ signIn: { email: { enabled: true, passwordRequired: true } } }), {
      enabled: true,
      passwordRequired: true,
    });
    assert.deepEqual(emailSignInState({ signIn: { email: { enabled: true } } }), { enabled: true, passwordRequired: false });
    for (const config of [{}, null, undefined, { signIn: {} }, { signIn: { email: { enabled: 'true' } } }]) {
      assert.deepEqual(emailSignInState(config), { enabled: false, passwordRequired: false }, JSON.stringify(config));
    }
    assert.equal(isEmailPasswordEnabled({ enabled: true, passwordRequired: true }), true);
    assert.equal(isEmailPasswordEnabled({ enabled: true, passwordRequired: false }), false, 'email-link only');
  });

  test('--dry-run text shows method, URL, headers and body, never a token', () => {
    const text = describeRequest(enableEmailSignInRequest(PROJECT));
    assert.match(text, /^PATCH https:\/\/identitytoolkit\.googleapis\.com\/admin\/v2\/projects\/goldengift-iq\/config\?updateMask=signIn\.email$/m);
    assert.match(text, /^x-goog-user-project: goldengift-iq$/m);
    assert.match(text, /"passwordRequired": true/);
    assert.match(text, /Authorization: Bearer <access token from Application Default Credentials>/);
  });

  test('send adds the bearer token and returns the JSON body', async () => {
    const { impl, calls } = stubFetch(200, { signIn: { email: { enabled: true, passwordRequired: true } } });
    const json = await send(enableEmailSignInRequest(PROJECT), 'tok-123', impl);
    assert.deepEqual(emailSignInState(json), { enabled: true, passwordRequired: true });
    assert.equal(calls.length, 1);
    const { url, init } = calls[0];
    assert.equal(url, enableEmailSignInRequest(PROJECT).url);
    assert.equal(init.method, 'PATCH');
    const headers = init.headers as Record<string, string>;
    assert.equal(headers.Authorization, 'Bearer tok-123');
    assert.equal(headers['x-goog-user-project'], PROJECT);
    assert.equal(init.body, enableEmailSignInRequest(PROJECT).body);
  });

  test('an error response → IdentityToolkitError with the API reason and a hint', async () => {
    const { impl } = stubFetch(404, { error: { code: 404, message: 'CONFIGURATION_NOT_FOUND', status: 'NOT_FOUND' } });
    const error = await send(getConfigRequest(PROJECT), 'tok', impl).catch((e: unknown) => e);
    assert.ok(error instanceof IdentityToolkitError);
    assert.equal(error.status, 404);
    assert.equal(error.reason, 'CONFIGURATION_NOT_FOUND');
    assert.match(hintFor(error, PROJECT), /Authentication → Get started/);

    const { impl: forbidden } = stubFetch(403, 'Forbidden');
    const denied = await send(getConfigRequest(PROJECT), 'tok', forbidden).catch((e: unknown) => e);
    assert.ok(denied instanceof IdentityToolkitError);
    assert.equal(denied.reason, 'Forbidden');
    assert.match(hintFor(denied, PROJECT), /application-default login/);
  });
});

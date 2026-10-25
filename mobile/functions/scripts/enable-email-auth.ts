/**
 * Turns on the Email/Password sign-in provider of the REAL project goldengift-iq —
 * the admin dashboard signs in with email + password (SRS §9). Same as Firebase
 * console → Authentication → Sign-in method → Email/Password → Enable.
 *
 *   npm run auth:enable-email -- --dry-run   # print the requests, contact nothing
 *   npm run auth:enable-email                # read the config, enable if needed
 *
 * Uses the Identity Toolkit Admin v2 REST API with Application Default Credentials
 * (`gcloud auth application-default login` as a project Owner / Firebase Admin),
 * billed to the project via `x-goog-user-project`. Only `signIn.email` is changed
 * (updateMask); every other provider and setting stays as it is. Idempotent: when
 * email + password is already on, nothing is written.
 *
 * `--target=dev` is required (the npm script passes it). There is no emulator
 * equivalent: the Auth emulator always accepts email/password sign-in.
 */
import { parseArgs } from 'node:util';
import { GoogleAuth } from 'google-auth-library';
import {
  CLOUD_PLATFORM_SCOPE,
  IdentityToolkitError,
  describeRequest,
  emailSignInState,
  enableEmailSignInRequest,
  getConfigRequest,
  hintFor,
  isEmailPasswordEnabled,
  send,
} from './auth/enableEmailAuth';
import { PROJECT_ID } from './seed-data/helpers';
import { fail, parseTarget, refuseOtherProjects } from './target';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      target: { type: 'string' },
      project: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
    strict: true,
  });
  if (values.target === undefined) {
    fail(`This changes the REAL project ${PROJECT_ID}. Pass --target=dev (npm run auth:enable-email does).`);
  }
  if (parseTarget(values.target) !== 'dev') {
    fail('Nothing to enable on the emulator: the Auth emulator always accepts email/password sign-in. Use --target=dev.');
  }
  refuseOtherProjects(values.project, 'change the sign-in providers of');

  const read = getConfigRequest(PROJECT_ID);
  const enable = enableEmailSignInRequest(PROJECT_ID);
  if (values['dry-run']) {
    console.log(`Dry run — nothing sent. Requests for ${PROJECT_ID}:\n`);
    console.log(`${describeRequest(read)}\n`);
    console.log(`(only when email/password is not already on)\n${describeRequest(enable)}`);
    return;
  }

  let token: string;
  try {
    const value = await new GoogleAuth({ scopes: [CLOUD_PLATFORM_SCOPE] }).getAccessToken();
    if (!value) throw new Error('no access token returned');
    token = value;
  } catch (e) {
    fail(
      `No Application Default Credentials (${(e as Error).message}).\n` +
        'Run: gcloud auth application-default login',
    );
  }

  console.log(`⚠ Changing the sign-in providers of the REAL project ${PROJECT_ID}`);
  try {
    const before = emailSignInState(await send(read, token));
    console.log(`  email sign-in now      enabled=${before.enabled} passwordRequired=${before.passwordRequired}`);
    if (isEmailPasswordEnabled(before)) {
      console.log('✔ Email/Password sign-in is already enabled — nothing changed.');
      return;
    }
    const after = emailSignInState(await send(enable, token));
    console.log(`  email sign-in after    enabled=${after.enabled} passwordRequired=${after.passwordRequired}`);
    if (!isEmailPasswordEnabled(after)) fail('The update returned, but email/password sign-in is still not enabled.');
    console.log('✔ Email/Password sign-in enabled.');
  } catch (e) {
    const hint = e instanceof IdentityToolkitError ? hintFor(e, PROJECT_ID) : '';
    fail(`${(e as Error).message}${hint ? `\n${hint}` : ''}`);
  }
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});

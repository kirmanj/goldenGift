/**
 * Shared bits of the emulator-only suites. They skip unless the emulator env
 * vars are set, which `firebase emulators:exec` does. From the repo root:
 *
 *   firebase emulators:exec --only auth,firestore,storage --project goldengift-iq \
 *     "npm --prefix mobile/functions test"
 */
import { randomBytes } from 'node:crypto';

/** Admin SDK suites use the app's project id (the emulators run in single-project mode). */
export const PROJECT_ID = 'goldengift-iq';

/** `{ skip }` value for `describe`: false when every variable is set, else the reason. */
export function needsEnv(...vars: string[]): false | string {
  const missing = vars.filter((v) => !process.env[v]);
  return missing.length === 0 ? false : `${missing.join(', ')} not set`;
}

/** Unique per test run, so suites never collide with each other or with dev data. */
export function runId(): string {
  return `${Date.now().toString(36)}${randomBytes(3).toString('hex')}`;
}

/**
 * Deletes every document of `projectId` in the Firestore emulator. Only ever used
 * with a suite's own `demo-…` project, never goldengift-iq (dev data).
 */
export async function clearEmulatorFirestore(projectId: string): Promise<void> {
  if (!projectId.startsWith('demo-')) throw new Error(`refusing to clear ${projectId}: only demo- projects`);
  const res = await fetch(
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!res.ok) throw new Error(`clearing ${projectId} failed: ${res.status} ${await res.text()}`);
}

/** Signs in with email + password on the Auth emulator (as the dashboard does); the ID token's payload. */
export async function emulatorPasswordSignIn(email: string, password: string): Promise<Record<string, unknown> | null> {
  const res = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  if (!res.ok) return null;
  const { idToken } = (await res.json()) as { idToken: string };
  return JSON.parse(Buffer.from(idToken.split('.')[1], 'base64url').toString('utf8')) as Record<string, unknown>;
}

/**
 * The Storage emulator loads the PRODUCTION storage rules from firebase.json,
 * which deny the Admin SDK's download-URL metadata reads used by functions
 * tests. Tests that exercise functions (not rules) open the emulator up for
 * their own run; the rules suites (test/rules/, run last) load the real rules
 * themselves.
 */
export async function allowAllStorageEmulatorRules(): Promise<void> {
  const host = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
  if (!host) return;
  const res = await fetch(`http://${host}/internal/setRules`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      rules: {
        files: [
          {
            name: 'storage.rules',
            content:
              "rules_version = '2'; service firebase.storage { match /b/{bucket}/o { match /{allPaths=**} { allow read, write: if true; } } }",
          },
        ],
      },
    }),
  });
  if (!res.ok) throw new Error(`could not load test storage rules: ${await res.text()}`);
}


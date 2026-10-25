/**
 * Bootstraps the FIRST super admin (SRS §6.14, §9). `setAdminClaim` needs a super
 * admin caller, so the very first one is made here with the Admin SDK; every later
 * admin is granted from the dashboard through `setAdminClaim`.
 *
 *   npm run admin:create -- --email admin@test.local --name "Test Admin" --password test1234
 *       # emulators (default): Auth 127.0.0.1:9099 + Firestore 127.0.0.1:8080
 *   npm run admin:create -- --target=dev --email owner@example.com --name "Owner"
 *       # REAL project goldengift-iq (Application Default Credentials)
 *
 * Flags: --email (required), --name (required), --password (creates the
 * email/password account when none exists; an existing account is only granted —
 * its password is never changed), --role super|ops|content|finance (default super),
 * --target=emulator (default) | dev.
 *
 * Grants exactly what `setAdminClaim` grants: `admin: true` merged into the account's
 * existing custom claims, `admins/{uid}` upserted, an `admin_audit_log` entry
 * (`adminUid: "script:create-admin"`). Idempotent.
 *
 * Same guards as the seeder: only goldengift-iq, and --target=dev refuses
 * FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST. For the real project run
 * `gcloud auth application-default login` first; the account needs the Email/Password
 * provider enabled to sign in (npm run auth:enable-email). A --password typed on the
 * command line stays in the shell history — prefer creating the account in the
 * Firebase console and running this without --password, or change the password after
 * the first sign-in.
 */
import { parseArgs } from 'node:util';
import { deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { FirestorePaths } from '../src/shared/paths';
import { createAdmin, parseCreateAdminInput } from './admin/createAdmin';
import { adcHint, fail, openApp, parseTarget, prepareTarget, refuseOtherProjects } from './target';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string' },
      email: { type: 'string' },
      name: { type: 'string' },
      password: { type: 'string' },
      role: { type: 'string', default: 'super' },
    },
    strict: true,
  });
  const target = parseTarget(values.target);
  refuseOtherProjects(values.project, 'grant admin access on');
  const parsed = parseCreateAdminInput(values);
  if (parsed.input === null) fail(`Invalid arguments:\n  - ${parsed.problems.join('\n  - ')}`);
  const input = parsed.input;

  const where = prepareTarget(target, { auth: true });
  console.log(target === 'dev' ? `⚠ Granting admin access on the ${where}` : `Granting admin access on ${where}`);

  const app = await openApp(target, { auth: true });
  const db = getFirestore(app);
  try {
    const result = await createAdmin({ db, auth: getAuth(app) }, input);
    console.log('');
    console.log(`  account   ${result.email} (uid ${result.uid})`);
    console.log(`  auth      ${result.userCreated ? 'created (email/password)' : 'existing account — unchanged'}`);
    if (result.passwordIgnored) console.log('            --password ignored: the existing password was NOT changed');
    console.log(`  claims    ${JSON.stringify(result.claims)}`);
    console.log(`  profile   ${FirestorePaths.admins}/${result.uid} (role ${result.role})`);
    console.log(`  audit     ${result.changed ? `${FirestorePaths.adminAuditLog} entry written` : 'nothing changed — no entry'}`);
    console.log(
      `\n✔ ${result.email} is ${result.role === 'super' ? 'a super admin' : `an admin (${result.role})`}.` +
        '\n  If that account is signed in anywhere, sign out and in again so the new claim reaches its ID token.',
    );
  } catch (e) {
    fail(`Could not grant admin access: ${(e as Error).message}${adcHint(target)}`);
  } finally {
    await db.terminate();
    await deleteApp(app);
  }
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});

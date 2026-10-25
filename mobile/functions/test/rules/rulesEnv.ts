/**
 * Rules tests run under their own `demo-` project id instead of goldengift-iq.
 *
 * The Firestore emulator keeps security rules AND data per project id, so
 * loading the production rules here (and `clearFirestore()`) never changes the
 * dev-mode rules or the seeded data of goldengift-iq that the app, the seeder
 * and the Admin SDK suites use in the same emulator session.
 *
 * firebase.json runs the emulators with `"singleProjectMode": true`. The
 * firebase CLI starts Firestore with `single_project_mode_error=false`, so a
 * second project id is served normally; the emulator only writes a "Multiple
 * projectIds are not recommended" warning to firestore-debug.log. The setting
 * stays on, so a wrong project id in app or Admin SDK code is still flagged.
 *
 * Storage keeps ONE rule set for the whole emulator (not per project), so the
 * Storage suite restores the dev rules (mobile/storage.rules) when it finishes.
 */
import * as path from 'node:path';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';

export const RULES_PROJECT_ID = 'demo-goldengift-rules';

/** `mobile/<name>` (functions/ lives in mobile/functions). */
export function rulesFile(name: string): string {
  return path.resolve(__dirname, '../../..', name);
}

/** `assertSucceeds` / `assertFails` as `Promise<void>`, so they can be a test body. */
export async function allowed(op: Promise<unknown>): Promise<void> {
  await assertSucceeds(op);
}
export async function denied(op: Promise<unknown>): Promise<void> {
  await assertFails(op);
}

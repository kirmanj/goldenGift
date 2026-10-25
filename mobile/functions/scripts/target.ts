/**
 * Where a script reads / writes Firestore (and, for create-admin.ts, Firebase
 * Auth): `--target=emulator` (default, Firestore 127.0.0.1:8080, Auth
 * 127.0.0.1:9099) or `--target=dev` (the REAL project via Application Default
 * Credentials). Shared by seed.ts, algolia-reindex.ts and create-admin.ts so all
 * apply the same guards: the only project ever accepted is goldengift-iq, however
 * it is requested, and `--target=dev` refuses to run with FIRESTORE_EMULATOR_HOST
 * (or, when Auth is used, FIREBASE_AUTH_EMULATOR_HOST) set.
 */
import { applicationDefault, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { PROJECT_ID } from './seed-data/helpers';

export type Target = 'emulator' | 'dev';

export const DEFAULT_EMULATOR_HOST = '127.0.0.1:8080';
export const DEFAULT_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

export interface TargetServices {
  /** Also point Firebase Auth at the target (default: Firestore only). */
  auth?: boolean;
}

export function fail(message: string): never {
  console.error(`✖ ${message}`);
  process.exit(1);
}

/** `--target` value → Target, or exits. */
export function parseTarget(value: string | undefined): Target {
  const target = value ?? 'emulator';
  if (target !== 'emulator' && target !== 'dev') {
    fail(`Unknown --target=${target}. Use --target=emulator (default) or --target=dev.`);
  }
  return target;
}

/** Exits unless every project id requested (flag or environment) is goldengift-iq. */
export function refuseOtherProjects(cliProject: string | undefined, verb: string): void {
  const requested: Array<[string, string | undefined]> = [
    ['--project', cliProject],
    ['GCLOUD_PROJECT', process.env.GCLOUD_PROJECT],
    ['GOOGLE_CLOUD_PROJECT', process.env.GOOGLE_CLOUD_PROJECT],
  ];
  for (const [source, project] of requested) {
    if (project !== undefined && project !== PROJECT_ID) {
      fail(`Refusing to ${verb} project "${project}" (from ${source}). This script only uses ${PROJECT_ID}.`);
    }
  }
}

/**
 * Points the Admin SDK at the target (environment only — nothing is contacted yet)
 * and returns a one-line description of it.
 */
export function prepareTarget(target: Target, services: TargetServices = {}): string {
  if (target === 'dev') {
    const redirects = ['FIRESTORE_EMULATOR_HOST', ...(services.auth ? ['FIREBASE_AUTH_EMULATOR_HOST'] : [])];
    for (const name of redirects) {
      const value = process.env[name];
      if (value) {
        fail(`${name}=${value} is set, which would redirect --target=dev to an emulator. Unset it, or use --target=emulator.`);
      }
    }
    process.env.GOOGLE_CLOUD_QUOTA_PROJECT = PROJECT_ID;
    return `REAL project ${PROJECT_ID} (${services.auth ? 'Auth + Firestore' : 'Firestore'}, Application Default Credentials)`;
  }
  process.env.FIRESTORE_EMULATOR_HOST ??= DEFAULT_EMULATOR_HOST;
  if (!services.auth) return `Firestore EMULATOR at ${process.env.FIRESTORE_EMULATOR_HOST} (project ${PROJECT_ID})`;
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= DEFAULT_AUTH_EMULATOR_HOST;
  return (
    `EMULATORS: Auth at ${process.env.FIREBASE_AUTH_EMULATOR_HOST}, ` +
    `Firestore at ${process.env.FIRESTORE_EMULATOR_HOST} (project ${PROJECT_ID})`
  );
}

export async function assertEmulatorReachable(host: string, name = 'Firestore', only = 'firestore'): Promise<void> {
  try {
    await fetch(`http://${host}/`, { signal: AbortSignal.timeout(3000) });
  } catch {
    fail(
      `${name} emulator not reachable at ${host}. Start it from the repo root:\n` +
        `  firebase emulators:start --only ${only} --project ${PROJECT_ID}`,
    );
  }
}

/** The Admin SDK app for the prepared target (checks that the emulators are up first). */
export async function openApp(target: Target, services: TargetServices = {}): Promise<App> {
  if (target === 'emulator') {
    const only = services.auth ? 'auth,firestore' : 'firestore';
    await assertEmulatorReachable(process.env.FIRESTORE_EMULATOR_HOST!, 'Firestore', only);
    if (services.auth) await assertEmulatorReachable(process.env.FIREBASE_AUTH_EMULATOR_HOST!, 'Auth', only);
  }
  return initializeApp({
    projectId: PROJECT_ID,
    ...(target === 'dev' && { credential: applicationDefault() }),
  });
}

/** Firestore for the prepared target (checks that the emulator is up first). */
export async function openFirestore(target: Target): Promise<Firestore> {
  return getFirestore(await openApp(target));
}

/** Hint appended to a failed Firestore call. */
export function adcHint(target: Target): string {
  return target === 'dev' ? '\nIs ADC configured? Run: gcloud auth application-default login' : '';
}

/**
 * Dev data seeder (SRS §10 Phase 1) — firebase-admin, never the client SDK.
 *
 *   npm run seed:emulator      # Firestore emulator (default target), 127.0.0.1:8080
 *   npm run seed:dev           # REAL project goldengift-iq via Application Default Credentials
 *   tsx scripts/seed.ts --dry-run   # build + validate only, no Firestore access
 *
 * Writes categories (SRS §5.7), the in-house store, 20 demo products covering every
 * OptionType (with their derived query fields, so the data is queryable without
 * onProductWrite running), banners for every Home placement and
 * app_settings/{general, cities, referral, payments}. Idempotent: fixed document
 * ids + set() (full overwrite), so re-running converges to the same data. It never
 * deletes documents, and it keeps every category's uploaded icon (`iconUrl`, set by
 * the dashboard or `npm run icons:categories`) instead of resetting it to null.
 *
 * The only project it accepts is goldengift-iq (the Flutter app uses that id, also
 * against the emulator). For the real project, sign in first with
 * `gcloud auth application-default login`.
 */
import { parseArgs } from 'node:util';
import type { Firestore } from 'firebase-admin/firestore';
import { buildSeed, validateSeed } from './seed-data';
import type { SeedDoc } from './seed-data/helpers';
import { FirestorePaths } from '../src/shared/paths';
import { adcHint, fail, openFirestore, parseTarget, prepareTarget, refuseOtherProjects, type Target } from './target';

const BATCH_LIMIT = 400;

function parseOptions(): { target: Target; dryRun: boolean } {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
    strict: true,
  });
  const target = parseTarget(values.target);
  refuseOtherProjects(values.project, 'seed');
  return { target, dryRun: values['dry-run'] };
}

/** Seeded categories keep the icon already uploaded for them (brand assets, not demo data). */
async function keepUploadedIcons(db: Firestore, docs: SeedDoc[]): Promise<number> {
  const existing = await db.collection(FirestorePaths.categories).get();
  const icons = new Map(existing.docs.map((d) => [d.id, d.get('iconUrl') as unknown]));
  let kept = 0;
  for (const d of docs) {
    const icon = d.collection === FirestorePaths.categories ? icons.get(d.id) : undefined;
    if (typeof icon === 'string' && icon) {
      d.data = { ...d.data, iconUrl: icon };
      kept++;
    }
  }
  return kept;
}

async function writeAll(db: Firestore, docs: SeedDoc[]): Promise<number> {
  let batches = 0;
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + BATCH_LIMIT)) {
      batch.set(db.collection(d.collection).doc(d.id), d.data);
    }
    await batch.commit();
    batches++;
  }
  return batches;
}

function countByCollection(docs: SeedDoc[]): Map<string, number> {
  const counts = new Map<string, number>();
  for (const d of docs) counts.set(d.collection, (counts.get(d.collection) ?? 0) + 1);
  return counts;
}

async function main(): Promise<void> {
  const { target, dryRun } = parseOptions();
  const where = prepareTarget(target);
  console.log(target === 'dev' ? `⚠ Writing to ${where}` : `Seeding ${where}`);

  const docs = buildSeed();
  const problems = validateSeed(docs);
  if (problems.length > 0) {
    fail(`Seed data is invalid:\n  - ${problems.join('\n  - ')}`);
  }
  const written = countByCollection(docs);

  if (dryRun) {
    console.log('Dry run — nothing written. Documents that would be written:');
    for (const [collection, n] of written) console.log(`  ${collection.padEnd(14)} ${n}`);
    return;
  }

  const db = await openFirestore(target);

  const started = Date.now();
  let batches: number;
  let keptIcons: number;
  try {
    keptIcons = await keepUploadedIcons(db, docs);
    batches = await writeAll(db, docs);
  } catch (e) {
    fail(`Write failed: ${(e as Error).message}${adcHint(target)}`);
  }

  console.log(`\nWrote ${docs.length} documents in ${batches} batch(es) in ${Date.now() - started} ms.`);
  if (keptIcons > 0) console.log(`Kept the uploaded icon of ${keptIcons} categor${keptIcons === 1 ? 'y' : 'ies'}.`);
  console.log(`  ${'collection'.padEnd(14)} ${'written'.padStart(7)} ${'now in db'.padStart(10)}`);
  for (const [collection, n] of written) {
    const inDb = (await db.collection(collection).count().get()).data().count;
    console.log(`  ${collection.padEnd(14)} ${String(n).padStart(7)} ${String(inDb).padStart(10)}`);
  }
  await db.terminate();
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});

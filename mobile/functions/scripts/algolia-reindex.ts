/**
 * Pushes every product's Algolia record (SRS §5.8) — the initial fill after
 * `algolia:setup`, or a repair after the index drifted. onProductWrite keeps it
 * in step afterwards.
 *
 *   ALGOLIA_APP_ID=… ALGOLIA_ADMIN_KEY=… npm run algolia:reindex -- --target=dev   # REAL products (ADC)
 *   npm run algolia:reindex -- --dry-run                    # emulator products: counts + one sample record
 *   npm run algolia:reindex -- --dry-run --target=dev       # same, reading the real project (read-only)
 *
 * Flags: --target=emulator (default) | dev, --index=<primary> (default
 * ALGOLIA_INDEX_NAME or products), --batch-size=<records per request, default 500>.
 * Same target guards as the seeder: only goldengift-iq, and --target=dev refuses
 * FIRESTORE_EMULATOR_HOST. Firestore is only read. Active products are upserted;
 * `isActive == false` ones are deleted from the index. Records of products deleted
 * from Firestore are not found by a reindex (onProductWrite removes those).
 */
import { parseArgs } from 'node:util';
import { algoliaIndex } from '../src/search/algolia';
import { FirestorePaths } from '../src/shared/paths';
import { algoliaCredentialsFromEnv, indexNameFrom } from './algolia/env';
import { DEFAULT_PUSH_BATCH, applyReindex, planReindex, type ReindexPlan } from './algolia/reindex';
import { adcHint, fail, openFirestore, parseTarget, prepareTarget, refuseOtherProjects } from './target';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string' },
      index: { type: 'string' },
      'batch-size': { type: 'string', default: String(DEFAULT_PUSH_BATCH) },
      'dry-run': { type: 'boolean', default: false },
    },
    strict: true,
  });
  const target = parseTarget(values.target);
  refuseOtherProjects(values.project, 'read');
  const batchSize = Number(values['batch-size']);
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 1000) {
    fail(`--batch-size must be an integer from 1 to 1000, got ${values['batch-size']}.`);
  }
  const dryRun = values['dry-run'];
  const primary = indexNameFrom(values.index);
  // Before touching Firestore, so a missing key fails fast.
  const credentials = dryRun ? null : algoliaCredentialsFromEnv('algolia:reindex');

  console.log(`Reading products from ${prepareTarget(target)}`);
  const db = await openFirestore(target);
  let plan: ReindexPlan;
  try {
    plan = await planReindex(db.collection(FirestorePaths.products));
  } catch (e) {
    fail(`Read failed: ${(e as Error).message}${adcHint(target)}`);
  }
  await db.terminate();

  const batches = Math.ceil(plan.records.length / batchSize);
  console.log(`  products read      ${plan.total}`);
  console.log(`  records to upsert  ${plan.records.length} (${batches} batch(es) of ≤ ${batchSize})`);
  console.log(`  inactive → delete  ${plan.inactiveIds.length}`);

  if (credentials === null) {
    console.log(`\nDry run — nothing sent to Algolia (index "${primary}").`);
    if (plan.records.length > 0) console.log(`Sample record:\n${JSON.stringify(plan.records[0], null, 2)}`);
    return;
  }

  if (target === 'emulator') console.log(`⚠ Pushing EMULATOR products to the real Algolia index "${primary}".`);
  const index = algoliaIndex(credentials, primary);
  const started = Date.now();
  const result = await applyReindex(index, plan, batchSize, (pushed) =>
    console.log(`  pushed ${pushed}/${plan.records.length}`),
  );
  console.log(
    `✔ Upserted ${plan.records.length} records in ${result.batches} batch(es), deleted ${result.deleted}, ` +
      `in ${Date.now() - started} ms (app ${credentials.appId}, index "${primary}").`,
  );
}

main().catch((e: unknown) => {
  console.error(`✖ Algolia reindex failed: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
});

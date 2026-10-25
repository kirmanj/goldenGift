/**
 * Sets `orders.productIds` on orders placed before Phase 9 (SRS §5.26: the review
 * rules check "the customer bought it" against it). Idempotent — orders that
 * have the field are skipped — so it can be run again at any time.
 *
 *   npm run maintenance:backfill-product-ids                         # emulator (default)
 *   npm run maintenance:backfill-product-ids -- --dry-run --target=dev   # REAL project: count only
 *   npm run maintenance:backfill-product-ids -- --target=dev             # REAL project: write
 *
 * Admin only: it uses the Admin SDK with Application Default Credentials
 * (`gcloud auth application-default login` as a project owner / editor) — there is
 * no client path. Same guards as the seeder: only goldengift-iq, and --target=dev
 * refuses FIRESTORE_EMULATOR_HOST.
 */
import { parseArgs } from 'node:util';
import { backfillOrderProductIds } from './maintenance/backfillOrderProductIds';
import { adcHint, fail, openFirestore, parseTarget, prepareTarget, refuseOtherProjects } from './target';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      target: { type: 'string', default: 'emulator' },
      project: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
    strict: true,
  });
  const target = parseTarget(values.target);
  const dryRun = values['dry-run'];
  refuseOtherProjects(values.project, dryRun ? 'read' : 'write to');
  const where = prepareTarget(target);
  console.log(`${target === 'dev' && !dryRun ? '⚠ Writing to the' : 'Using'} ${where}${dryRun ? ' (dry run: nothing is written)' : ''}`);

  const db = await openFirestore(target);
  try {
    const result = await backfillOrderProductIds(db, {
      dryRun,
      onPage: (scanned, updated) => console.log(`  … ${scanned} orders read, ${updated} ${dryRun ? 'to update' : 'updated'}`),
    });
    console.log('');
    console.log(`  orders read          ${result.scanned}`);
    console.log(`  already had them     ${result.alreadySet}`);
    console.log(`  ${dryRun ? 'would get productIds' : 'productIds written '}  ${result.updated}`);
    if (result.sample.length > 0) console.log(`  e.g.                 ${result.sample.slice(0, 5).join(', ')}`);
    console.log(`\n✔ Done${dryRun ? ' (dry run)' : ''}.`);
  } catch (e) {
    fail(`Backfill failed: ${(e as Error).message}${adcHint(target)}`);
  } finally {
    await db.terminate();
  }
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});

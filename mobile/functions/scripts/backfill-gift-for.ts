/**
 * Gives products saved before Phase 11 their `giftFor` (SRS §5.8a: seed products
 * their own gift types, every other product For him + For her) and the matching
 * derived `forKeys`, so the gift-type filters find them. Idempotent — products
 * with a known gift type are skipped — so it can be run again at any time.
 *
 *   npm run maintenance:backfill-gift-for                            # emulator (default)
 *   npm run maintenance:backfill-gift-for -- --dry-run --target=dev  # REAL project: count only
 *   npm run maintenance:backfill-gift-for -- --target=dev            # REAL project: write
 *
 * Admin only: it uses the Admin SDK with Application Default Credentials
 * (`gcloud auth application-default login` as a project owner / editor) — there is
 * no client path. Same guards as the seeder: only goldengift-iq, and --target=dev
 * refuses FIRESTORE_EMULATOR_HOST.
 */
import { parseArgs } from 'node:util';
import { backfillGiftFor } from './maintenance/backfillGiftFor';
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
    const result = await backfillGiftFor(db, {
      dryRun,
      onPage: (scanned, updated) => console.log(`  … ${scanned} products read, ${updated} ${dryRun ? 'to update' : 'updated'}`),
    });
    console.log('');
    console.log(`  products read        ${result.scanned}`);
    console.log(`  already had giftFor  ${result.alreadySet}`);
    console.log(`  ${dryRun ? 'would get giftFor ' : 'giftFor written   '}   ${result.updated}`);
    console.log(`    of which seed      ${result.fromSeed} (their seed gift types; the others: men + women)`);
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

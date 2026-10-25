/**
 * Configures the Algolia products index and its sort replicas (SRS §5.8, §12 item 7).
 *
 *   ALGOLIA_APP_ID=… ALGOLIA_ADMIN_KEY=… npm run algolia:setup
 *   npm run algolia:setup -- --dry-run        # print the settings, contact nothing
 *   npm run algolia:setup -- --index=products # primary index (default ALGOLIA_INDEX_NAME or products)
 *
 * Creates / updates `{index}` (best match) and the standard replicas
 * `{index}_newest`, `{index}_popular`, `{index}_price_asc`, `{index}_price_desc`
 * (src/search/algoliaSettings.ts). Safe to re-run: the settings converge.
 * Records are pushed separately (`npm run algolia:reindex`, then onProductWrite).
 */
import { parseArgs } from 'node:util';
import { algoliaIndex } from '../src/search/algolia';
import { configureAlgoliaIndices, settingsPlan } from '../src/search/algoliaSettings';
import { algoliaCredentialsFromEnv, indexNameFrom } from './algolia/env';

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      index: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
    strict: true,
  });
  const primary = indexNameFrom(values.index);

  if (values['dry-run']) {
    console.log(`Dry run — nothing sent. Settings that would be applied, in order (primary "${primary}"):`);
    for (const step of settingsPlan(primary)) {
      const forward = step.forwardToReplicas ? ' (forwardToReplicas)' : '';
      console.log(`\n▸ ${step.index}${forward}\n${JSON.stringify(step.settings, null, 2)}`);
    }
    return;
  }

  const credentials = algoliaCredentialsFromEnv('algolia:setup');
  console.log(`Configuring Algolia app ${credentials.appId}, primary index "${primary}"…`);
  const configured = await configureAlgoliaIndices((name) => algoliaIndex(credentials, name), primary);
  console.log(`✔ Configured ${configured.length} indices: ${configured.join(', ')}`);
  console.log('Next: npm run algolia:reindex -- --target=dev   (pushes every product record)');
}

main().catch((e: unknown) => {
  console.error(`✖ Algolia setup failed: ${e instanceof Error ? e.message : String(e)}`);
  process.exit(1);
});

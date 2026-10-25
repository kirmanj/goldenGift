/** Algolia credentials for the maintenance scripts, from the environment only. */
import { DEFAULT_ALGOLIA_INDEX, type AlgoliaCredentials } from '../../src/search/algolia';
import { fail } from '../target';

/** `--index` flag > `ALGOLIA_INDEX_NAME` > `products`. */
export function indexNameFrom(flag: string | undefined): string {
  return flag?.trim() || process.env.ALGOLIA_INDEX_NAME?.trim() || DEFAULT_ALGOLIA_INDEX;
}

/** `ALGOLIA_APP_ID` + `ALGOLIA_ADMIN_KEY`, or exits explaining how to provide them. */
export function algoliaCredentialsFromEnv(script: string): AlgoliaCredentials {
  const appId = process.env.ALGOLIA_APP_ID?.trim() ?? '';
  const adminKey = process.env.ALGOLIA_ADMIN_KEY?.trim() ?? '';
  const missing = [!appId && 'ALGOLIA_APP_ID', !adminKey && 'ALGOLIA_ADMIN_KEY'].filter(Boolean);
  if (missing.length > 0) {
    fail(
      `${missing.join(' and ')} not set. Both come from the Algolia dashboard → Settings → API Keys ` +
        `(the ADMIN key — keep it out of the repo and out of shell history files):\n` +
        `  ALGOLIA_APP_ID=<app id> ALGOLIA_ADMIN_KEY=<admin key> npm run ${script}\n` +
        `Add --dry-run to see what would be sent without credentials.`,
    );
  }
  return { appId, adminKey };
}

/**
 * Algolia behind a tiny interface (SRS §5.8, §12 item 7), so the sync logic and
 * the scripts are tested against an in-memory fake and only `algoliaIndex()`
 * touches the official `algoliasearch` v5 client.
 *
 * Writes need the ADMIN key, which lives in Secret Manager (`ALGOLIA_ADMIN_KEY`)
 * and is bound to `onProductWrite` only. The app searches with the public
 * search-only key from `app_settings/search`.
 */
import type { Algoliasearch, IndexSettings } from 'algoliasearch';
import type { ProductRecord } from './productRecord';

export type { IndexSettings };

/** One Algolia index (records are product records; objectID = product id). */
export interface AlgoliaIndex {
  readonly name: string;
  /** Adds or replaces the record with `record.objectID`. */
  saveObject(record: ProductRecord): Promise<void>;
  /** Adds or replaces many records (chunked batches); waits until they are indexed. */
  saveObjects(records: readonly ProductRecord[]): Promise<void>;
  /** Removes the record; a record that does not exist is not an error. */
  deleteObject(objectID: string): Promise<void>;
  /** Partial settings update; waits until it is applied. */
  setSettings(settings: IndexSettings, options?: { forwardToReplicas?: boolean }): Promise<void>;
}

export interface AlgoliaCredentials {
  appId: string;
  adminKey: string;
}

/** Records per `saveObjects` batch request. */
export const ALGOLIA_BATCH_SIZE = 500;

const clients = new Map<string, Promise<Algoliasearch>>();

/** Loaded on first use only, so an unconfigured function never pays for the client. */
function client({ appId, adminKey }: AlgoliaCredentials): Promise<Algoliasearch> {
  const key = `${appId}:${adminKey}`;
  let c = clients.get(key);
  if (c === undefined) {
    c = import('algoliasearch').then(({ algoliasearch }) => algoliasearch(appId, adminKey));
    clients.set(key, c);
  }
  return c;
}

/** The real index (official client; clients are cached per warm instance). */
export function algoliaIndex(credentials: AlgoliaCredentials, indexName: string): AlgoliaIndex {
  return {
    name: indexName,
    async saveObject(record) {
      const c = await client(credentials);
      await c.addOrUpdateObject({ indexName, objectID: record.objectID, body: record });
    },
    async saveObjects(records) {
      if (records.length === 0) return;
      const c = await client(credentials);
      await c.saveObjects({
        indexName,
        objects: records as unknown as Array<Record<string, unknown>>,
        batchSize: ALGOLIA_BATCH_SIZE,
        waitForTasks: true,
      });
    },
    async deleteObject(objectID) {
      const c = await client(credentials);
      await c.deleteObject({ indexName, objectID });
    },
    async setSettings(settings, options = {}) {
      const c = await client(credentials);
      const { taskID } = await c.setSettings({
        indexName,
        indexSettings: settings,
        forwardToReplicas: options.forwardToReplicas ?? false,
      });
      await c.waitForTask({ indexName, taskID });
    },
  };
}

// ── Configuration ────────────────────────────────────────────────────────────

export interface AlgoliaConfig {
  /** Param `ALGOLIA_APP_ID` (empty until the owner provides it). */
  appId?: string;
  /** Secret `ALGOLIA_ADMIN_KEY`. */
  adminKey?: string;
  /** Param `ALGOLIA_INDEX_NAME`, default `products`. */
  indexName?: string;
}

/** Environment the decision depends on (injectable for tests). */
export interface AlgoliaEnv {
  /** Set to 'true' by the Functions emulator. */
  FUNCTIONS_EMULATOR?: string;
  /** Deliberate opt-in to sync emulator writes to the real Algolia index. */
  ALGOLIA_EMULATOR_SYNC?: string;
}

export const DEFAULT_ALGOLIA_INDEX = 'products';

export type AlgoliaResolution = { index: AlgoliaIndex; reason?: undefined } | { index: null; reason: string };

/**
 * The index to sync to, or null with the reason it is not configured:
 *  - no App ID or no admin key → not configured (the state until the owner
 *    provides Algolia credentials; never an error);
 *  - Functions emulator → off unless `ALGOLIA_EMULATOR_SYNC=true`, because emulator
 *    products share their ids with the real ones and would overwrite the real
 *    search index.
 */
export function resolveAlgolia(
  config: AlgoliaConfig,
  env: AlgoliaEnv = process.env,
  open: (credentials: AlgoliaCredentials, indexName: string) => AlgoliaIndex = algoliaIndex,
): AlgoliaResolution {
  const appId = config.appId?.trim() ?? '';
  const adminKey = config.adminKey?.trim() ?? '';
  const missing = [!appId && 'ALGOLIA_APP_ID', !adminKey && 'ALGOLIA_ADMIN_KEY'].filter(Boolean);
  if (missing.length > 0) return { index: null, reason: `${missing.join(' and ')} not set` };
  if (env.FUNCTIONS_EMULATOR === 'true' && env.ALGOLIA_EMULATOR_SYNC !== 'true') {
    return { index: null, reason: 'off on the Functions emulator (set ALGOLIA_EMULATOR_SYNC=true to sync)' };
  }
  const indexName = config.indexName?.trim() || DEFAULT_ALGOLIA_INDEX;
  return { index: open({ appId, adminKey }, indexName) };
}

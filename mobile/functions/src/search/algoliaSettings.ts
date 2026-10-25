/**
 * Algolia index configuration (SRS §5.8, §12 item 7), applied by
 * `scripts/algolia-setup.ts`. Re-running it converges to the same settings.
 *
 * One primary index (best match) plus a STANDARD replica per sort order of the
 * products list; the app picks the replica by name (`AlgoliaProductSource.indexFor`):
 * `{primary}_newest`, `{primary}_popular`, `{primary}_price_asc`, `{primary}_price_desc`.
 * Standard (not virtual) replicas sort exhaustively by the attribute, which is
 * what the sort menu promises.
 */
import type { AlgoliaIndex, IndexSettings } from './algolia';

/** Algolia's default ranking formula. */
export const DEFAULT_RANKING = ['typo', 'geo', 'words', 'filters', 'proximity', 'attribute', 'exact', 'custom'];

/** Every attribute the app filters on (`AlgoliaProductSource.filtersFor`). Filter-only: no facet counts. */
export const FILTER_ATTRIBUTES = [
  'categoryIds',
  'cityKeys',
  'catCityKeys',
  'giftFor',
  'availability',
  'hasDiscount',
  'isFeatured',
  'isActive',
  'priceBand',
] as const;

export const PRIMARY_SETTINGS: IndexSettings = {
  // `searchText` holds the normalized titles + tags; the raw titles still match exact spellings.
  searchableAttributes: ['searchText', 'title', 'titleAr', 'titleKu', 'tags'],
  attributesForFaceting: FILTER_ATTRIBUTES.map((a) => `filterOnly(${a})`),
  // Every query word matches as a prefix, so the Kurdish کوپ finds کوپی (ezafe ـی) — SRS §12 item 7.
  queryType: 'prefixAll',
  queryLanguages: ['ar', 'en'],
  typoTolerance: true,
  customRanking: ['desc(salesCount)'],
};

export interface ReplicaSpec {
  /** Suffix after `{primary}_`. */
  suffix: 'newest' | 'popular' | 'price_asc' | 'price_desc';
  /** First ranking criterion: the sort. */
  sort: string;
  /** Tie-breaker among equal sort values. */
  customRanking: string[];
}

export const REPLICAS: readonly ReplicaSpec[] = [
  { suffix: 'newest', sort: 'desc(createdAt)', customRanking: ['desc(salesCount)'] },
  { suffix: 'popular', sort: 'desc(salesCount)', customRanking: ['desc(createdAt)'] },
  { suffix: 'price_asc', sort: 'asc(price)', customRanking: ['desc(salesCount)'] },
  { suffix: 'price_desc', sort: 'desc(price)', customRanking: ['desc(salesCount)'] },
];

export function replicaName(primary: string, spec: ReplicaSpec): string {
  return `${primary}_${spec.suffix}`;
}

export function replicaSettings(spec: ReplicaSpec): IndexSettings {
  return { ranking: [spec.sort, ...DEFAULT_RANKING], customRanking: spec.customRanking };
}

/** Every `setSettings` call `configureAlgoliaIndices` makes, in order (also printed by `--dry-run`). */
export function settingsPlan(
  primary: string,
): Array<{ index: string; settings: IndexSettings; forwardToReplicas: boolean }> {
  return [
    // 1. Declare the replicas (creates the missing ones).
    { index: primary, settings: { replicas: REPLICAS.map((r) => replicaName(primary, r)) }, forwardToReplicas: false },
    // 2. Searchable / filter / language settings, forwarded so the replicas search the same way.
    { index: primary, settings: PRIMARY_SETTINGS, forwardToReplicas: true },
    // 3. Each replica's sort (after 2, which forwarded the primary's customRanking).
    ...REPLICAS.map((r) => ({ index: replicaName(primary, r), settings: replicaSettings(r), forwardToReplicas: false })),
  ];
}

/** Applies `settingsPlan(primary)`; each call waits for its task, so the order holds. */
export async function configureAlgoliaIndices(
  open: (indexName: string) => AlgoliaIndex,
  primary: string,
): Promise<string[]> {
  const configured: string[] = [];
  for (const step of settingsPlan(primary)) {
    await open(step.index).setSettings(step.settings, { forwardToReplicas: step.forwardToReplicas });
    if (!configured.includes(step.index)) configured.push(step.index);
  }
  return configured;
}

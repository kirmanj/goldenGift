/** Core of `algolia-reindex.ts`: read every product, push its record (tested on the emulator). */
import { FieldPath, type CollectionReference, type DocumentData } from 'firebase-admin/firestore';
import type { AlgoliaIndex } from '../../src/search/algolia';
import { buildProductRecord, isIndexable, type ProductRecord } from '../../src/search/productRecord';

export interface ReindexPlan {
  /** Products read. */
  total: number;
  /** Records of the indexable (active) products. */
  records: ProductRecord[];
  /** `isActive == false` products: removed from the index if present. */
  inactiveIds: string[];
}

export const DEFAULT_PAGE_SIZE = 300;
export const DEFAULT_PUSH_BATCH = 500;

export function planFromDocs(docs: ReadonlyArray<{ id: string; data: DocumentData }>): ReindexPlan {
  const plan: ReindexPlan = { total: docs.length, records: [], inactiveIds: [] };
  for (const { id, data } of docs) {
    if (isIndexable(data)) plan.records.push(buildProductRecord(id, data));
    else plan.inactiveIds.push(id);
  }
  return plan;
}

/** Reads the whole collection in pages ordered by document id. */
export async function planReindex(
  products: CollectionReference,
  pageSize = DEFAULT_PAGE_SIZE,
): Promise<ReindexPlan> {
  const docs: Array<{ id: string; data: DocumentData }> = [];
  let last: string | undefined;
  for (;;) {
    let query = products.orderBy(FieldPath.documentId()).limit(pageSize);
    if (last !== undefined) query = query.startAfter(last);
    const page = await query.get();
    for (const d of page.docs) docs.push({ id: d.id, data: d.data() });
    if (page.size < pageSize) break;
    last = page.docs[page.docs.length - 1].id;
  }
  return planFromDocs(docs);
}

/** Upserts the records in batches of `batchSize`, then deletes the inactive ones. */
export async function applyReindex(
  index: AlgoliaIndex,
  plan: ReindexPlan,
  batchSize = DEFAULT_PUSH_BATCH,
  onProgress: (pushed: number) => void = () => {},
): Promise<{ batches: number; deleted: number }> {
  let batches = 0;
  for (let i = 0; i < plan.records.length; i += batchSize) {
    const batch = plan.records.slice(i, i + batchSize);
    await index.saveObjects(batch);
    batches++;
    onProgress(i + batch.length);
  }
  for (const id of plan.inactiveIds) await index.deleteObject(id);
  return { batches, deleted: plan.inactiveIds.length };
}

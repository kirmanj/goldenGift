/**
 * `aiGiftSearch` (SRS §5.6, §7): callable for guests and signed-in customers.
 *
 * Data `{ query (1–300), locale: 'en' | 'ar' | 'ckb', budgetMax? }` →
 * `{ searchId, results: [{ productId, reason }] }` (≤ 12, best first; `reason` is
 * one line in the customer's language) — what `AiSearchRepository.search` reads.
 *
 *  1. Rate limit (Iraq calendar day): 20 searches per signed-in user, 10 per IP
 *     for guests → `resource-exhausted` (the app then shows keyword results).
 *  2. Gemini "interpret": the query + the active categories → category ids,
 *     keywords (tokenized with the shared search tokenizer), budget, recipient,
 *     occasion (structured output).
 *  3. Candidates from Firestore: `categoryIds array-contains-any` and
 *     `searchKeywords array-contains-any`, each ordered by price (≤ budget,
 *     dearest first) or by sales — shapes the existing catalogue indexes serve —
 *     then active / in stock / within budget, de-duplicated, scored, ≤ 30 kept.
 *  4. Gemini "rank": ≤ 12 of them with a one-line reason.
 *  5. `ai_searches/{searchId}` logs every search that reached the model.
 *
 * Any model failure, or nothing usable from it → `unavailable` (logged with a
 * `fallbackReason`), so the app falls back to its keyword search. No candidates
 * → an empty result list (the app falls back too).
 */
import { FieldValue, type Firestore, type Query } from 'firebase-admin/firestore';
import { logger as functionsLogger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { hashIp } from '../auth/otp';
import { baghdadNow, isoDate } from '../orders/checkoutRules';
import { integer, string, stringList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import type { GiftSearchModel } from './giftModel';
import {
  AI_LOCALES,
  MAX_BUDGET,
  MAX_QUERY_LENGTH,
  MAX_RANK_CANDIDATES,
  interpretPrompt,
  isUsable,
  keywordTokens,
  parseInterpretation,
  parseRanking,
  rankPrompt,
  type AiLocale,
  type CandidateInfo,
  type CategoryInfo,
  type Interpretation,
  type RankedResult,
} from './giftSearchPrompts';

/** SRS §5.6: 20 queries / user / day. */
export const USER_DAILY_LIMIT = 20;
/** Guests (no account): per IP and day. */
export const GUEST_DAILY_LIMIT = 10;
/**
 * All guests together, per Iraq day — the cost ceiling behind the per-IP limit
 * (an IP is cheap to change; App Check is the first line). Signed-in customers
 * are not affected.
 */
export const GUEST_GLOBAL_DAILY_LIMIT = 1000;
export const GUEST_GLOBAL_KEY = 'aiSearch:guests';
/** Read per candidate query (two queries → ≤ 60 documents in all, minus duplicates). */
export const CANDIDATE_QUERY_LIMIT = 30;
export const MAX_CANDIDATES = 60;

export type FallbackReason = 'model_error' | 'unusable_interpretation' | 'no_candidates' | 'unusable_ranking';

export interface AiGiftSearchRequest {
  query: string;
  locale: AiLocale;
  budgetMax: number | null;
}

export interface AiGiftSearchResult {
  searchId: string;
  results: RankedResult[];
}

export interface AiGiftSearchDeps {
  db: Firestore;
  /** null = no model configured (treated like a model failure). */
  model: GiftSearchModel | null;
  /** Active categories; default: read them (index.ts passes a per-instance cache). */
  categories?: () => Promise<CategoryInfo[]>;
  now?: () => number;
  logger?: Pick<typeof functionsLogger, 'warn' | 'error'>;
}

export interface AiCaller {
  uid?: string;
  /** `request.rawRequest.ip` (hashed before it is stored). */
  ip?: string;
}

const bad = (message: string) => new HttpsError('invalid-argument', message);

export function parseAiGiftSearchData(data: unknown): AiGiftSearchRequest {
  if (typeof data !== 'object' || data === null || Array.isArray(data)) throw bad('Expected { query, locale, budgetMax? }.');
  const d = data as Record<string, unknown>;
  if (typeof d.query !== 'string') throw bad('`query` is missing.');
  const query = d.query.trim();
  if (query.length === 0) throw bad('`query` is empty.');
  if (query.length > MAX_QUERY_LENGTH) throw bad(`\`query\` is longer than ${MAX_QUERY_LENGTH} characters.`);
  const rawLocale = d.locale === 'ku' ? 'ckb' : (d.locale ?? 'en');
  if (typeof rawLocale !== 'string' || !(AI_LOCALES as readonly string[]).includes(rawLocale)) {
    throw bad('`locale` must be en, ar or ckb.');
  }
  let budgetMax: number | null = null;
  if (d.budgetMax !== undefined && d.budgetMax !== null) {
    if (typeof d.budgetMax !== 'number' || !Number.isInteger(d.budgetMax) || d.budgetMax <= 0 || d.budgetMax > MAX_BUDGET) {
      throw bad('`budgetMax` must be a whole number of IQD.');
    }
    budgetMax = d.budgetMax;
  }
  return { query, locale: rawLocale as AiLocale, budgetMax };
}

/** `function_runs/{key}` of the caller's daily counter, and its limit. */
export function rateLimitKey(caller: AiCaller): { key: string; limit: number } {
  if (caller.uid) return { key: `aiSearch:u:${caller.uid}`, limit: USER_DAILY_LIMIT };
  return { key: `aiSearch:ip:${hashIp(caller.ip) ?? 'unknown'}`, limit: GUEST_DAILY_LIMIT };
}

/**
 * Counts one search for the caller today (Iraq calendar day) or throws
 * `resource-exhausted` when the day's limit is reached. One document per caller
 * (`{ key, day, count, at }`), reset when the day changes.
 */
export async function chargeRateLimit(db: Firestore, caller: AiCaller, nowMs: number): Promise<void> {
  const { key, limit } = rateLimitKey(caller);
  const ref = db.collection(P.functionRuns).doc(key);
  const guestsRef = caller.uid ? null : db.collection(P.functionRuns).doc(GUEST_GLOBAL_KEY);
  const now = baghdadNow(nowMs);
  const day = isoDate(now.year, now.month, now.day);
  const allowed = await db.runTransaction(async (tx) => {
    const [snap, guestsSnap] = guestsRef === null ? [await tx.get(ref), null] : await tx.getAll(ref, guestsRef);
    const count = snap.get('day') === day ? Math.max(0, integer(snap.get('count'))) : 0;
    if (count >= limit) return false;
    const guests = guestsSnap !== null && guestsSnap.get('day') === day ? Math.max(0, integer(guestsSnap.get('count'))) : 0;
    if (guestsRef !== null && guests >= GUEST_GLOBAL_DAILY_LIMIT) return false;
    tx.set(ref, { key, day, count: count + 1, at: FieldValue.serverTimestamp() });
    if (guestsRef !== null) tx.set(guestsRef, { key: GUEST_GLOBAL_KEY, day, count: guests + 1, at: FieldValue.serverTimestamp() });
    return true;
  });
  if (!allowed) {
    throw new HttpsError('resource-exhausted', `You can use AI gift search ${limit} times a day. Please try again tomorrow.`, {
      reason: 'rate_limited',
      limit,
    });
  }
}

/** The active categories with their three titles (sortOrder order). */
export async function loadActiveCategories(db: Firestore): Promise<CategoryInfo[]> {
  const snap = await db.collection(P.categories).where('isActive', '==', true).orderBy('sortOrder').limit(300).get();
  return snap.docs.map((d) => ({
    id: d.id,
    en: string(d.get('title')),
    ar: string(d.get('titleAr')),
    ku: string(d.get('titleKu')),
  }));
}

/** One candidate query: one array filter, then (budget) price ≤ budget, dearest first, or best sellers first. */
export interface CandidateQuerySpec {
  field: 'categoryIds' | 'searchKeywords';
  values: string[];
  budgetMax: number | null;
  /** `price` desc with a budget, else `salesCount` desc. */
  orderBy: 'price' | 'salesCount';
  limit: number;
}

/**
 * The candidate queries for an interpretation. Each maps to an existing
 * composite index (`{field} CONTAINS + price DESC` / `+ salesCount DESC`) —
 * `test/aiGiftSearch.test.ts` checks that against firestore.indexes.json.
 * `isActive`, stock and availability are filtered in memory (≤ 60 documents).
 */
export function candidateQueries(interpretation: Interpretation, budgetMax: number | null): CandidateQuerySpec[] {
  const orderBy = budgetMax === null ? 'salesCount' : 'price';
  const specs: CandidateQuerySpec[] = [];
  const tokens = keywordTokens(interpretation.keywords);
  if (tokens.length > 0) specs.push({ field: 'searchKeywords', values: tokens, budgetMax, orderBy, limit: CANDIDATE_QUERY_LIMIT });
  if (interpretation.categoryIds.length > 0) {
    specs.push({ field: 'categoryIds', values: interpretation.categoryIds, budgetMax, orderBy, limit: CANDIDATE_QUERY_LIMIT });
  }
  return specs;
}

export function buildCandidateQuery(db: Firestore, spec: CandidateQuerySpec): Query {
  let q: Query = db.collection(P.products).where(spec.field, 'array-contains-any', spec.values);
  if (spec.budgetMax !== null) q = q.where('price', '<=', spec.budgetMax);
  return q.orderBy(spec.orderBy, 'desc').limit(spec.limit);
}

interface ScoredCandidate extends CandidateInfo {
  score: number;
  salesCount: number;
}

/** Whether a product may be suggested: active, not sold out, within the budget. */
export function isSuggestible(p: Record<string, unknown>, budgetMax: number | null): boolean {
  if (p.isActive !== true) return false;
  if (p.availability === 'outOfStock') return false;
  if (typeof p.stock === 'number' && p.stock <= 0) return false;
  const price = integer(p.price, -1);
  if (price < 0) return false;
  return budgetMax === null || price <= budgetMax;
}

/**
 * Merges the query results: suggestible products only, each once, scored by
 * matching keyword tokens (×2) + matching categories, best sellers first on a
 * tie; at most MAX_CANDIDATES.
 */
export function mergeCandidates(
  docs: ReadonlyArray<{ id: string; data: Record<string, unknown> }>,
  interpretation: Interpretation,
  budgetMax: number | null,
): ScoredCandidate[] {
  const tokens = new Set(keywordTokens(interpretation.keywords));
  const categories = new Set(interpretation.categoryIds);
  const byId = new Map<string, ScoredCandidate>();
  for (const { id, data } of docs) {
    if (byId.has(id) || !isSuggestible(data, budgetMax)) continue;
    const keywords = stringList(data.searchKeywords);
    const categoryIds = stringList(data.categoryIds);
    const score = 2 * keywords.filter((k) => tokens.has(k)).length + categoryIds.filter((c) => categories.has(c)).length;
    byId.set(id, {
      id,
      title: { en: string(data.title), ar: string(data.titleAr), ku: string(data.titleKu) },
      tags: stringList(data.tags),
      price: integer(data.price),
      categoryIds,
      score,
      salesCount: integer(data.salesCount),
    });
  }
  return [...byId.values()]
    .sort((a, b) => b.score - a.score || b.salesCount - a.salesCount || (a.id < b.id ? -1 : 1))
    .slice(0, MAX_CANDIDATES);
}

export async function aiGiftSearchCore(deps: AiGiftSearchDeps, data: unknown, caller: AiCaller): Promise<AiGiftSearchResult> {
  const request = parseAiGiftSearchData(data);
  const { db } = deps;
  const clock = deps.now ?? Date.now;
  const log = deps.logger ?? functionsLogger;
  const started = clock();
  await chargeRateLimit(db, caller, started);

  const searchRef = db.collection(P.aiSearches).doc();
  const model = deps.model;
  const record = async (fields: {
    resultProductIds: string[];
    fallbackReason: FallbackReason | null;
    interpretation: Interpretation | null;
    candidateCount: number;
  }): Promise<void> => {
    try {
      await searchRef.set({
        userId: caller.uid ?? null,
        query: request.query,
        locale: request.locale,
        budgetMax: request.budgetMax,
        resultProductIds: fields.resultProductIds,
        latencyMs: Math.max(0, clock() - started),
        at: FieldValue.serverTimestamp(),
        model: model?.name ?? null,
        fallbackReason: fields.fallbackReason,
        interpretation: fields.interpretation,
        candidateCount: fields.candidateCount,
      });
    } catch (e) {
      log.warn('aiGiftSearch: log write failed', { searchId: searchRef.id, error: errorMessage(e) });
    }
  };
  const fail = async (reason: FallbackReason, interpretation: Interpretation | null, candidateCount: number, e?: unknown) => {
    log.warn('aiGiftSearch: falling back', { searchId: searchRef.id, reason, error: e === undefined ? undefined : errorMessage(e) });
    await record({ resultProductIds: [], fallbackReason: reason, interpretation, candidateCount });
    return new HttpsError('unavailable', 'AI gift search is not available right now.', { reason });
  };

  // ── 1. Interpret ──
  const categories = await (deps.categories ?? (() => loadActiveCategories(db)))();
  let interpretation: Interpretation | null;
  try {
    if (model === null) throw new Error('no model configured');
    const raw = await model.generateJson(interpretPrompt(request.query, request.locale, categories));
    interpretation = parseInterpretation(raw, new Set(categories.map((c) => c.id)));
  } catch (e) {
    throw await fail('model_error', null, 0, e);
  }
  if (interpretation === null || !isUsable(interpretation)) throw await fail('unusable_interpretation', interpretation, 0);
  const budgetMax = request.budgetMax ?? interpretation.budgetMax;
  const understood: Interpretation = { ...interpretation, budgetMax };

  // ── 2. Candidates ──
  const specs = candidateQueries(understood, budgetMax);
  const snaps = await Promise.all(specs.map((s) => buildCandidateQuery(db, s).get()));
  const candidates = mergeCandidates(
    snaps.flatMap((s) => s.docs.map((d) => ({ id: d.id, data: d.data() }))),
    understood,
    budgetMax,
  );
  if (candidates.length === 0) {
    await record({ resultProductIds: [], fallbackReason: 'no_candidates', interpretation: understood, candidateCount: 0 });
    return { searchId: searchRef.id, results: [] };
  }

  // ── 3. Rank ──
  const shortlist = candidates.slice(0, MAX_RANK_CANDIDATES);
  const names = new Map(categories.map((c) => [c.id, c.en]));
  let results: RankedResult[];
  try {
    const raw = await model.generateJson(rankPrompt(request.query, request.locale, understood, shortlist, names));
    results = parseRanking(raw, new Set(shortlist.map((c) => c.id)));
  } catch (e) {
    throw await fail('model_error', understood, candidates.length, e);
  }
  if (results.length === 0) throw await fail('unusable_ranking', understood, candidates.length);

  await record({
    resultProductIds: results.map((r) => r.productId),
    fallbackReason: null,
    interpretation: understood,
    candidateCount: candidates.length,
  });
  return { searchId: searchRef.id, results };
}

/** A per-instance cache of the active categories (they change rarely). */
export function cachedCategories(db: Firestore, ttlMs = 10 * 60 * 1000): () => Promise<CategoryInfo[]> {
  let cached: { at: number; value: Promise<CategoryInfo[]> } | null = null;
  return () => {
    const now = Date.now();
    if (cached === null || now - cached.at > ttlMs) {
      const value = loadActiveCategories(db);
      cached = { at: now, value };
      value.catch(() => {
        cached = null;
      });
    }
    return cached.value;
  };
}

function errorMessage(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

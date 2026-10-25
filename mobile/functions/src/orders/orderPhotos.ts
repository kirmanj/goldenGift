/**
 * Customer photos of an order (SRS §6.16): the app uploads them to
 * `uploads/{uid}/{cartItemId}/{n}.jpg` when the line is added to the cart;
 * after `placeOrder` commits they are copied to `orders/{orderId}/{lineId}/{n}.jpg`
 * (n = 1-based position among the line's photos) and the order's selection
 * `urls` are rewritten to the copies' download URLs.
 *
 * Best effort: a photo that cannot be copied keeps its original URL, which still
 * works. The originals are NOT deleted — the dashboard writes the whole `items`
 * array back on every status change, so an admin view loaded before the rewrite
 * could put the original URLs back.
 */
import { randomUUID } from 'node:crypto';
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { getDownloadURL, type Storage } from 'firebase-admin/storage';
import { mapList, string, stringList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';

export type Bucket = ReturnType<Storage['bucket']>;

export interface OrderPhotoDeps {
  db: Firestore;
  /** The default Storage bucket. May throw when the project has none configured. */
  bucket: () => Bucket;
}

export interface OrderPhotoResult {
  copied: number;
  /** Copies that failed (the original URL is kept). */
  failed: number;
  /** URLs that do not point into the customer's own `uploads/{uid}/` folder of this bucket (kept as they are). */
  skipped: number;
}

/** A Firebase Storage download URL (`…/v0/b/{bucket}/o/{encoded path}?…`) → bucket + object path. */
export function storageObjectFromUrl(url: string): { bucket: string; path: string } | null {
  const m = /^https?:\/\/[^/]+\/v0\/b\/([^/]+)\/o\/([^?#]+)/.exec(url);
  if (m === null) return null;
  try {
    return { bucket: decodeURIComponent(m[1]), path: decodeURIComponent(m[2]) };
  } catch {
    return null;
  }
}

/** `orders/{orderId}/{lineId}/{n}.jpg` */
export function orderPhotoPath(orderId: string, lineId: string, n: number): string {
  return `${P.orders}/${orderId}/${lineId}/${n}.jpg`;
}

export async function copyOrderPhotos(deps: OrderPhotoDeps, orderId: string, uid: string): Promise<OrderPhotoResult> {
  const result: OrderPhotoResult = { copied: 0, failed: 0, skipped: 0 };
  const orderRef = deps.db.collection(P.orders).doc(orderId);
  const order = (await orderRef.get()).data();
  if (order === undefined) return result;

  const lines = mapList(order.items)
    .map((item) => ({ lineId: string(item.id), urls: mapList(item.selections).flatMap((s) => stringList(s.urls)) }))
    .filter((l) => l.lineId.length > 0 && !l.lineId.includes('/') && l.urls.length > 0);
  if (lines.length === 0) return result;

  const bucket = deps.bucket();
  const ownFolder = `uploads/${uid}/`;
  /** `${lineId}\u0000${originalUrl}` → copy's URL. */
  const replaced = new Map<string, string>();

  for (const line of lines) {
    for (const [i, url] of line.urls.entries()) {
      const source = storageObjectFromUrl(url);
      if (source === null || source.bucket !== bucket.name || !source.path.startsWith(ownFolder)) {
        result.skipped++;
        continue;
      }
      try {
        const dest = bucket.file(orderPhotoPath(orderId, line.lineId, i + 1));
        await bucket.file(source.path).copy(dest);
        await dest.setMetadata({ metadata: { firebaseStorageDownloadTokens: randomUUID() } });
        replaced.set(`${line.lineId}\u0000${url}`, await getDownloadURL(dest));
        result.copied++;
      } catch {
        result.failed++;
      }
    }
  }
  if (replaced.size === 0) return result;

  // Re-read in a transaction so a status change made meanwhile is kept.
  await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    const items = snap.get('items');
    if (!Array.isArray(items)) return;
    const next = items.map((item: unknown) => {
      if (item === null || typeof item !== 'object') return item;
      const line = item as DocumentData;
      const lineId = string(line.id);
      if (!Array.isArray(line.selections)) return item;
      return {
        ...line,
        selections: line.selections.map((s: unknown) => {
          if (s === null || typeof s !== 'object' || !Array.isArray((s as DocumentData).urls)) return s;
          const selection = s as DocumentData;
          return {
            ...selection,
            urls: (selection.urls as unknown[]).map((u) =>
              typeof u === 'string' ? (replaced.get(`${lineId}\u0000${u}`) ?? u) : u,
            ),
          };
        }),
      };
    });
    tx.update(orderRef, { items: next, updatedAt: FieldValue.serverTimestamp() });
  });
  return result;
}

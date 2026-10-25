import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { mapList } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';
import { orderStockLines, stockDemand, stockUpdate } from './stock';

/**
 * Reads (in `tx`) the products of a cancelled order's lines and prepares the
 * release of the stock `placeOrder` reserved: `stock` and stocked option values
 * go back up (only where they are not unlimited), `salesCount` back down.
 * Products deleted since are skipped, and so are lines marked `stockReleased`
 * (a seller cancelled them earlier and their stock went back then —
 * lineCancellation.ts). Call `apply()` after the transaction's last read.
 */
export async function releaseOrderStock(
  db: Firestore,
  tx: Transaction,
  items: unknown,
): Promise<{ apply: () => void; productIds: string[] }> {
  const pending = mapList(items).filter((item) => item.stockReleased !== true);
  const demand = stockDemand(orderStockLines(pending).filter((l) => l.productId.length > 0 && !l.productId.includes('/')));
  const refs = [...demand.keys()].map((id) => db.collection(P.products).doc(id));
  const snaps = refs.length === 0 ? [] : await tx.getAll(...refs);
  const updates = snaps
    .filter((s) => s.exists)
    .map((s) => ({ ref: s.ref, update: stockUpdate(s.data()!, demand.get(s.id)!, -1) }));
  return {
    apply: () => {
      for (const u of updates) tx.update(u.ref, u.update);
    },
    productIds: updates.map((u) => u.ref.id),
  };
}

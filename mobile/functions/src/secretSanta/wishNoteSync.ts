/**
 * `onSecretSantaMemberUpdate` (SRS §5.16, §6.14): a member who edits their own
 * `wishlistNote` AFTER the draw — the rules let them, at any time — must not
 * leave their Secret Santa with the old one. `drawSecretSanta` copied the note
 * into `assignments/{giverUid}.assigneeWishlistNote`; this copies the new note
 * into the ONE assignment whose `assigneeUid` is that member (the giver who drew
 * them), and into nothing else — members never learn who drew whom.
 *
 * Idempotent and order-safe: the member doc and the assignment are re-read in one
 * transaction and the assignment gets the member's CURRENT note (not the event's),
 * written only when it differs — a retried, replayed or late event changes nothing.
 * Before the draw (`open`) there is no assignment; the draw copies the note itself.
 */
import { FieldValue, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { stringOrNull } from '../shared/firestoreParse';
import { FirestorePaths as P } from '../shared/paths';

export interface MemberUpdateEvent {
  groupId: string;
  memberUid: string;
  before: DocumentData | undefined;
  after: DocumentData | undefined;
}

export type WishNoteSyncResult =
  | { synced: true; giverUid: string }
  | { synced: false; reason: 'unchanged' | 'missing' | 'notDrawn' | 'noAssignment' | 'upToDate' };

/** The note as stored (empty / blank → null), like `drawSecretSanta` copies it. */
function note(data: DocumentData | undefined): string | null {
  const v = stringOrNull(data?.wishlistNote);
  return v === null || v.trim().length === 0 ? null : v;
}

export async function syncWishNoteToAssignment(db: Firestore, event: MemberUpdateEvent): Promise<WishNoteSyncResult> {
  if (event.before === undefined || event.after === undefined) return { synced: false, reason: 'missing' };
  if (note(event.before) === note(event.after)) return { synced: false, reason: 'unchanged' };

  const groupRef = db.collection(P.secretSantaGroups).doc(event.groupId);
  const memberRef = groupRef.collection(P.members).doc(event.memberUid);
  return db.runTransaction(async (tx): Promise<WishNoteSyncResult> => {
    // ── Reads ──
    const [groupSnap, memberSnap] = await tx.getAll(groupRef, memberRef);
    const group = groupSnap.data();
    if (group === undefined || !memberSnap.exists) return { synced: false, reason: 'missing' };
    if (group.status === 'open') return { synced: false, reason: 'notDrawn' };
    const assignments = await tx.get(groupRef.collection(P.assignments).where('assigneeUid', '==', event.memberUid).limit(2));
    const assignment = assignments.docs[0];
    if (assignment === undefined) return { synced: false, reason: 'noAssignment' };
    const current = note(memberSnap.data());
    if (stringOrNull(assignment.get('assigneeWishlistNote')) === current) return { synced: false, reason: 'upToDate' };

    // ── Writes ──
    tx.update(assignment.ref, { assigneeWishlistNote: current, updatedAt: FieldValue.serverTimestamp() });
    return { synced: true, giverUid: assignment.id };
  });
}

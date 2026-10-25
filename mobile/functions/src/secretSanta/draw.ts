/**
 * The Secret Santa draw (SRS §5.16) as a pure function: every member gives to
 * exactly one other member and receives from exactly one, nobody draws
 * themselves, and nobody draws someone on their `exclusions` list.
 *
 * That is a perfect matching in the bipartite graph givers → receivers (edges =
 * allowed pairs). It is found with augmenting paths (Kuhn's algorithm) over
 * randomly shuffled givers and candidate lists, so:
 *  - a valid draw is found whenever one exists (`impossible` is exact, never a
 *    timeout of a random retry loop), in O(n³) for n ≤ 50 members;
 *  - which valid draw comes out is random (not exactly uniform over all
 *    derangements, which a gift exchange does not need).
 */

/** A random number in [0, 1) — `Math.random` in production, seeded in tests. */
export type RandomSource = () => number;

/** Fisher–Yates with the given source. */
export function shuffled<T>(items: readonly T[], random: RandomSource): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.min(i, Math.floor(random() * (i + 1)));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * giver → receiver for every member, or null when the exclusions leave no valid
 * draw. `exclusions[giver]` lists members that giver must not draw (unknown ids
 * are ignored). Fewer than 2 members → null.
 */
export function drawAssignments(
  members: readonly string[],
  exclusions: Readonly<Record<string, readonly string[]>>,
  random: RandomSource = Math.random,
): Map<string, string> | null {
  const unique = [...new Set(members)];
  if (unique.length < 2) return null;
  const allowed = new Map<string, string[]>();
  for (const giver of unique) {
    const blocked = new Set(exclusions[giver] ?? []);
    blocked.add(giver);
    allowed.set(giver, shuffled(unique.filter((r) => !blocked.has(r)), random));
  }

  /** receiver → giver of the current partial matching. */
  const giverOf = new Map<string, string>();
  const tryAssign = (giver: string, seen: Set<string>): boolean => {
    for (const receiver of allowed.get(giver)!) {
      if (seen.has(receiver)) continue;
      seen.add(receiver);
      const current = giverOf.get(receiver);
      if (current === undefined || tryAssign(current, seen)) {
        giverOf.set(receiver, giver);
        return true;
      }
    }
    return false;
  };
  for (const giver of shuffled(unique, random)) {
    if (!tryAssign(giver, new Set())) return null;
  }

  const result = new Map<string, string>();
  for (const [receiver, giver] of giverOf) result.set(giver, receiver);
  return result;
}

/** Whether `assignments` is a valid draw of `members` under `exclusions` (used by tests and as a final guard). */
export function isValidDraw(
  members: readonly string[],
  exclusions: Readonly<Record<string, readonly string[]>>,
  assignments: ReadonlyMap<string, string>,
): boolean {
  const set = new Set(members);
  if (assignments.size !== set.size) return false;
  const received = new Set<string>();
  for (const giver of set) {
    const receiver = assignments.get(giver);
    if (receiver === undefined || receiver === giver || !set.has(receiver)) return false;
    if ((exclusions[giver] ?? []).includes(receiver)) return false;
    if (received.has(receiver)) return false;
    received.add(receiver);
  }
  return true;
}

/** A small deterministic generator (mulberry32) for reproducible tests. */
export function seededRandom(seed: number): RandomSource {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6d2b79f5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

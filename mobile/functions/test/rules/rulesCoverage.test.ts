/**
 * Completeness guard for the production rules (SRS §6.17, Phase 10) — static, no
 * emulator needed:
 *
 *  - every top-level collection AND every subcollection named in FirestorePaths
 *    (src/shared/paths.ts, itself checked against firestore_paths.dart) has an
 *    explicit `match` in mobile/firestore.production.rules, under its parent;
 *  - the rules name no collection FirestorePaths does not know (a typo there would
 *    silently deny the real collection);
 *  - both rule files end with the explicit catch-all deny;
 *  - every Storage folder the app or the dashboard uploads to (found from their
 *    upload call sites) is matched by mobile/storage.production.rules.
 *
 * Adding a collection, a subcollection or an upload folder without its rule fails
 * here — before it fails in production as PERMISSION_DENIED (or is left open).
 */
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { FirestorePaths } from '../../src/shared/paths';
import { rulesFile } from './rulesEnv';

const REPO = path.resolve(__dirname, '../../../..');

/** Strips `//` comments; keeps string literals (regexes in rules contain `{}`). */
function stripComments(src: string): string {
  return src
    .split('\n')
    .map((line) => {
      let quote: string | null = null;
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (quote !== null) {
          if (c === '\\') i++;
          else if (c === quote) quote = null;
        } else if (c === "'" || c === '"') quote = c;
        else if (c === '/' && line[i + 1] === '/') return line.slice(0, i);
      }
      return line;
    })
    .join('\n');
}

/** Every `match` block of a rules file as its full path pattern (segments), in file order. */
export function matchPatterns(rules: string): string[][] {
  const src = stripComments(rules);
  const stack: Array<string | null> = [];
  const out: string[][] = [];
  let quote: string | null = null;
  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (quote !== null) {
      if (c === '\\') i++;
      else if (c === quote) quote = null;
      continue;
    }
    if (c === "'" || c === '"') {
      quote = c;
      continue;
    }
    if (src.startsWith('match ', i) && (i === 0 || /\s/.test(src[i - 1]))) {
      // The path itself contains `{wildcards}`: the block opens at the `{` after the path's whitespace.
      const m = /^match\s+(\S+)\s*\{/.exec(src.slice(i));
      assert.ok(m !== null, `unparsable match near: ${src.slice(i, i + 60)}`);
      stack.push(m[1]);
      out.push(
        stack
          .filter((s): s is string => s !== null)
          .join('')
          .split('/')
          .filter((s) => s.length > 0),
      );
      i += m[0].length - 1;
      continue;
    }
    if (c === '{') stack.push(null);
    else if (c === '}') stack.pop();
  }
  assert.equal(stack.length, 0, 'unbalanced braces');
  return out;
}

const isWildcard = (seg: string) => /^\{[^}]+\}$/.test(seg);
const isRecursive = (seg: string) => /^\{[^}]+=\*\*\}$/.test(seg);

/** Whether pattern segments match a concrete path (segments). */
export function patternMatches(pattern: readonly string[], target: readonly string[]): boolean {
  if (pattern.length === 0) return target.length === 0;
  const [head, ...rest] = pattern;
  if (isRecursive(head)) {
    for (let k = 0; k <= target.length; k++) if (patternMatches(rest, target.slice(k))) return true;
    return false;
  }
  if (target.length === 0) return false;
  if (isWildcard(head) || head === target[0]) return patternMatches(rest, target.slice(1));
  return false;
}

/** paths.ts constants split by its section comments (top-level / admin-only vs subcollections). */
function pathSections(): { topLevel: string[]; sub: Record<string, string> } {
  const src = readFileSync(path.resolve(__dirname, '../../src/shared/paths.ts'), 'utf8');
  const body = src.slice(src.indexOf('export const FirestorePaths'), src.indexOf('} as const;'));
  const cut = body.indexOf('// ── Subcollections ──');
  assert.ok(cut > 0, 'paths.ts lost its "Subcollections" section comment');
  const pairs = (text: string) => [...text.matchAll(/^\s*(\w+):\s*'([^']+)'/gm)].map((m) => [m[1], m[2]] as const);
  const topLevel = pairs(body.slice(0, cut)).map(([, v]) => v);
  const sub = Object.fromEntries(pairs(body.slice(cut)));
  // The section split must account for every constant.
  assert.equal(topLevel.length + Object.keys(sub).length, Object.keys(FirestorePaths).length);
  return { topLevel, sub };
}

/**
 * Where each subcollection lives (SRS §6). A new subcollection in FirestorePaths
 * must be added here — with its rules — or this test fails.
 */
const SUBCOLLECTION_PARENTS: Record<string, readonly string[]> = {
  addresses: ['users'],
  savedCards: ['users'],
  items: ['carts', 'wishlists'],
  transactions: ['wallets'],
  creditLots: ['wallets'],
  statusHistory: ['orders'],
  members: ['secret_santa_groups'],
  assignments: ['secret_santa_groups'],
  messages: ['special_requests'],
  subcategories: ['categories'],
  usages: ['promo_codes'],
  storePrivate: ['stores'],
};
/** `reviews` is listed with the top-level names (SRS §6) but lives under products (and is read as a group). */
const NESTED_TOP_LEVEL: Record<string, readonly string[]> = { reviews: ['products'] };
/** Emulator-only, deliberately not in FirestorePaths (denied outright). */
const RULES_ONLY_COLLECTIONS = ['otp_debug'];

describe('firestore.production.rules covers every collection (FirestorePaths)', () => {
  const rules = readFileSync(rulesFile('firestore.production.rules'), 'utf8');
  const all = matchPatterns(rules);
  const DOCS = ['databases', '{database}', 'documents'];
  const patterns = all
    .filter((p) => p.length > 3 && DOCS.every((s, i) => p[i] === s))
    .map((p) => p.slice(3));
  const { topLevel, sub } = pathSections();

  test('parses the rules', () => {
    assert.ok(patterns.length >= 30, `found only ${patterns.length} match blocks`);
    assert.ok(patterns.some((p) => p.join('/') === 'users/{uid}/addresses/{addressId}'));
  });

  test('every top-level collection has its own match', () => {
    for (const name of topLevel) {
      const parents = NESTED_TOP_LEVEL[name];
      const ok =
        patterns.some((p) => p[0] === name && p.length >= 2) ||
        (parents !== undefined && parents.every((parent) => patterns.some((p) => p[0] === parent && p[2] === name)));
      assert.ok(ok, `no "match /${name}/{id}" in firestore.production.rules`);
    }
  });

  test('every subcollection has a match under each of its parents', () => {
    for (const [key, name] of Object.entries(sub)) {
      const parents = SUBCOLLECTION_PARENTS[key];
      assert.ok(parents !== undefined, `FirestorePaths.${key} ('${name}') is new: add its parents to SUBCOLLECTION_PARENTS and its rules`);
      for (const parent of parents) {
        assert.ok(
          patterns.some((p) => p[0] === parent && isWildcard(p[1] ?? '') && p[2] === name && p.length >= 4),
          `no "match /${parent}/{id}/${name}/{id}" in firestore.production.rules`,
        );
      }
    }
    for (const [name, parents] of Object.entries(NESTED_TOP_LEVEL)) {
      for (const parent of parents) {
        assert.ok(patterns.some((p) => p[0] === parent && p[2] === name), `no "match /${parent}/{id}/${name}/{id}"`);
      }
    }
  });

  test('the rules name no collection FirestorePaths does not know', () => {
    const known = new Set([...topLevel, ...Object.values(sub), ...RULES_ONLY_COLLECTIONS]);
    for (const p of patterns) {
      for (const seg of p.filter((s) => !isWildcard(s))) {
        assert.ok(known.has(seg), `rules match "/${p.join('/')}": "${seg}" is not in FirestorePaths`);
      }
    }
  });

  test('ends with the explicit catch-all deny', () => {
    const last = patterns[patterns.length - 1];
    assert.deepEqual(last, ['{document=**}']);
    assert.match(stripComments(rules), /match \/\{document=\*\*\}\s*\{\s*allow read, write: if false;\s*\}\s*\}\s*\}\s*$/);
  });

  test('no rule grants a client write on a functions-only collection', () => {
    const src = stripComments(rules);
    for (const name of ['function_runs', 'counters', 'otp_codes', 'otp_throttle', 'otp_debug', 'wallets', 'referrals', 'payment_sessions', 'ai_searches']) {
      const block = new RegExp(`match /${name}/\\{[^}]+\\}\\s*\\{([^}]*)\\}`).exec(src)?.[1] ?? '';
      assert.ok(block.length > 0, `match /${name} not found`);
      assert.match(block, /allow (read, )?write: if false;|allow read, write: if false;/, `${name} must deny every client write`);
    }
  });
});

// ── Storage ──────────────────────────────────────────────────────────────────

/** Dart files with a Storage call site (`.ref(`, `upload(`, `storagePath:`, `putData(`). */
function storageCallSites(): string[] {
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir)) {
      const full = path.join(dir, entry);
      if (statSync(full).isDirectory()) {
        if (entry !== 'l10n') walk(full);
      } else if (entry.endsWith('.dart') && /\.ref\(|\bupload\(|storagePath:|putData\(|putFile\(/.test(readFileSync(full, 'utf8'))) {
        files.push(path.relative(REPO, full));
      }
    }
  };
  walk(path.join(REPO, 'mobile/lib'));
  walk(path.join(REPO, 'adminDashboard/lib'));
  return files.sort();
}

/**
 * Every folder the clients upload to: the source line that builds the path and a
 * sample object path (SRS §6.16). `orders/…` is written by placeOrder only.
 */
const UPLOAD_PATHS: Array<{ file: string; snippet: string; sample: string }> = [
  { file: 'mobile/lib/features/profile/data/datasources/user_repository.dart', snippet: "ref('users/$uid/avatar.jpg')", sample: 'users/u1/avatar.jpg' },
  { file: 'mobile/lib/features/product_details/data/photo_service.dart', snippet: "ref('uploads/$uid/$cartItemId/", sample: 'uploads/u1/item-1/1.jpg' },
  { file: 'mobile/lib/features/special_requests/data/special_requests_repository.dart', snippet: "'${FirestorePaths.specialRequests}/$uid/${ref.id}'", sample: 'special_requests/u1/r1/1.jpg' },
  { file: 'mobile/lib/features/partners/presentation/screens/become_partner_screen.dart', snippet: "'partner_applications/$uid'", sample: 'partner_applications/u1/1.jpg' },
  { file: 'mobile/lib/features/gift_cards/presentation/screens/gift_card_designer_screen.dart', snippet: "'gift_cards/$uid/$_clientRequestId'", sample: 'gift_cards/u1/req-1/1.jpg' },
  { file: 'mobile/lib/features/reviews/presentation/providers/review_providers.dart', snippet: "'reviews/$uid/${orderId}_$productId'", sample: 'reviews/u1/o1_p1/1.jpg' },
  { file: 'mobile/lib/features/reviews/presentation/widgets/review_form_sheet.dart', snippet: "'${target.photoFolder(uid)}/${DateTime.now().millisecondsSinceEpoch}'", sample: 'reviews/u1/o1_p1/1729500000000/1.jpg' },
  { file: 'adminDashboard/lib/features/products/product_editor_screen.dart', snippet: "return 'products/$id';", sample: 'products/p1/1.jpg' },
  { file: 'adminDashboard/lib/features/products/widgets/option_group_builder.dart', snippet: "'${storageFolder()}/options/${g.id}-${v.id}.jpg'", sample: 'products/p1/options/size-big.jpg' },
  { file: 'adminDashboard/lib/features/gift_cards/template_editor_dialog.dart', snippet: "'${FirestorePaths.giftCardTemplates}/$_id.jpg'", sample: 'gift_card_templates/t1.jpg' },
  { file: 'adminDashboard/lib/features/stores/widgets/store_profile_form.dart', snippet: "'${FirestorePaths.storeDoc(id)}/logo.jpg'", sample: 'stores/s1/logo.jpg' },
  { file: 'adminDashboard/lib/features/stores/widgets/store_profile_form.dart', snippet: "'${FirestorePaths.storeDoc(id)}/cover.jpg'", sample: 'stores/s1/cover.jpg' },
  { file: 'adminDashboard/lib/features/banners/banner_editor_dialog.dart', snippet: "'banners/$_id$suffix.jpg'", sample: 'banners/b1-wide.jpg' },
  { file: 'adminDashboard/lib/features/notifications/broadcast_screen.dart', snippet: "'broadcasts/$_imageId.jpg'", sample: 'broadcasts/x1.jpg' },
  { file: 'adminDashboard/lib/features/categories/category_editor_dialog.dart', snippet: "'categories/${_currentId", sample: 'categories/c1.png' },
  // Phase 11: the reel's video and poster (SRS §6.16).
  { file: 'adminDashboard/lib/features/reels/data/reel_media.dart', snippet: "'${FirestorePaths.reels}/$reelId.mp4'", sample: 'reels/r1.mp4' },
  { file: 'adminDashboard/lib/features/reels/data/reel_media.dart', snippet: "'${FirestorePaths.reels}/$reelId.jpg'", sample: 'reels/r1.jpg' },
];
/** Call sites that only pass a folder built elsewhere (listed above). */
const GENERIC_CALL_SITES = [
  'adminDashboard/lib/core/widgets/form_widgets.dart',
  'mobile/lib/core/services/image_upload_service.dart',
  'mobile/lib/features/product_details/presentation/screens/product_details_screen.dart',
];

describe('storage.production.rules covers every upload folder', () => {
  const rules = readFileSync(rulesFile('storage.production.rules'), 'utf8');
  const patterns = matchPatterns(rules)
    .filter((p) => p[0] === 'b' && p[1] === '{bucket}' && p[2] === 'o' && p.length > 3)
    .map((p) => p.slice(3));

  test('every Dart file with a Storage call site is known (add new upload folders to UPLOAD_PATHS and the rules)', () => {
    const known = new Set([...UPLOAD_PATHS.map((u) => u.file), ...GENERIC_CALL_SITES]);
    for (const file of storageCallSites()) assert.ok(known.has(file), `${file} uploads to Storage: list its folder in UPLOAD_PATHS`);
  });

  test('every listed upload path is still built that way', () => {
    for (const u of UPLOAD_PATHS) {
      const src = readFileSync(path.join(REPO, u.file), 'utf8');
      assert.ok(src.includes(u.snippet), `${u.file} no longer contains ${u.snippet} — update UPLOAD_PATHS (and the rules)`);
    }
  });

  test('every upload folder (and the orders copies) has a specific match — not only the catch-all', () => {
    for (const sample of [...UPLOAD_PATHS.map((u) => u.sample), 'orders/o1/item-1/1.jpg']) {
      const hit = patterns.find((p) => p[0] !== '{allPaths=**}' && patternMatches(p, sample.split('/')));
      assert.ok(hit !== undefined, `no match in storage.production.rules for ${sample}`);
    }
  });

  test('ends with the explicit catch-all deny; nothing is publicly writable', () => {
    assert.deepEqual(patterns[patterns.length - 1], ['{allPaths=**}']);
    const src = stripComments(rules);
    assert.match(src, /match \/\{allPaths=\*\*\}\s*\{\s*allow read, write: if false;\s*\}\s*\}\s*\}\s*$/);
    assert.doesNotMatch(src, /allow (create|update|write|delete)[^;]*: if true;/, 'a public write');
  });
});

describe('rules parser helpers', () => {
  test('patternMatches', () => {
    assert.ok(patternMatches(['users', '{uid}', 'avatar.jpg'], ['users', 'a', 'avatar.jpg']));
    assert.ok(!patternMatches(['users', '{uid}', 'avatar.jpg'], ['users', 'a', 'b.jpg']));
    assert.ok(patternMatches(['uploads', '{uid}', '{all=**}'], ['uploads', 'a', 'x', 'y.jpg']));
    assert.ok(patternMatches(['{path=**}', 'reviews', '{id}'], ['products', 'p', 'reviews', 'r']));
    assert.ok(!patternMatches(['stores', '{id}', '{file}'], ['stores', 's', 'a', 'b.jpg']));
  });
});

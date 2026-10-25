/**
 * Uploads category icons in bulk (SRS §5.7, §6.3, §6.16) — the same result as
 * dashboard ▸ Categories ▸ Icon ▸ Upload, for many categories at once.
 *
 *   npm run icons:categories -- --target=dev --dry-run      # list what would change
 *   npm run icons:categories -- --target=dev                # REAL goldengift-iq (ADC)
 *   npm run icons:categories -- --target=dev --only=mugs,flowers
 *   npm run icons:categories -- --dir=../../branding/category-icons/webp   # default
 *
 * The folder holds one file per category, named by the category id:
 * `{id}.webp` (preferred, ~60 KB) or `{id}.png` / `.jpg`. Each file goes to Storage
 * `categories/{id}.{ext}` with a fresh download token; then ONE batch per category
 * sets `categories/{id}.iconUrl` and writes an `admin_audit_log` entry
 * (`adminUid: "script:category-icons"`, action `category.icon`). Files whose id has
 * no category document are skipped. Re-running uploads again (a new token = a new
 * URL, so caches never serve the old icon). Source images: branding/GGimages →
 * resized masters in branding/category-icons/ (README there).
 */
import { randomUUID } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { extname, join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { adcHint, fail, openApp, parseTarget, prepareTarget, refuseOtherProjects } from './target';

const BUCKET = 'goldengift-iq.firebasestorage.app';
const TYPES: Record<string, string> = { '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' };

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      target: { type: 'string' },
      project: { type: 'string' },
      dir: { type: 'string', default: resolve(__dirname, '../../../branding/category-icons/webp') },
      only: { type: 'string' },
      'dry-run': { type: 'boolean', default: false },
    },
  });
  const target = parseTarget(values.target);
  refuseOtherProjects(values.project, 'upload category icons to');
  const dir = resolve(values.dir!);
  const only = values.only ? new Set(values.only.split(',').map((s) => s.trim()).filter(Boolean)) : null;

  const files = readdirSync(dir)
    .filter((f) => TYPES[extname(f).toLowerCase()])
    .map((f) => ({ file: f, id: f.slice(0, -extname(f).length), ext: extname(f).toLowerCase() }))
    .filter((f) => !only || only.has(f.id))
    .sort((a, b) => a.id.localeCompare(b.id));
  if (files.length === 0) fail(`No .webp / .png / .jpg files in ${dir}${only ? ` matching --only` : ''}.`);

  const where = prepareTarget(target);
  if (target === 'emulator') process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= '127.0.0.1:9199';
  console.log(`${target === 'dev' ? '⚠ ' : ''}Category icons → ${where}${values['dry-run'] ? ' (dry run)' : ''}`);
  const app = await openApp(target);
  const db = getFirestore(app);
  const bucket = getStorage(app).bucket(BUCKET);

  let uploaded = 0;
  const skipped: string[] = [];
  try {
    for (const { file, id, ext } of files) {
      const ref = db.doc(`categories/${id}`);
      const snap = await ref.get();
      if (!snap.exists) {
        skipped.push(id);
        continue;
      }
      const path = `categories/${id}${ext}`;
      if (values['dry-run']) {
        console.log(`  would upload ${file} → ${path}`);
        continue;
      }
      const token = randomUUID();
      await bucket.file(path).save(readFileSync(join(dir, file)), {
        contentType: TYPES[ext],
        metadata: {
          cacheControl: 'public, max-age=31536000',
          metadata: { firebaseStorageDownloadTokens: token },
        },
      });
      const url =
        target === 'dev'
          ? `https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/${encodeURIComponent(path)}?alt=media&token=${token}`
          : `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST}/v0/b/${BUCKET}/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
      const before = (snap.get('iconUrl') as string | undefined) ?? null;
      const batch = db.batch();
      batch.update(ref, { iconUrl: url, updatedAt: FieldValue.serverTimestamp() });
      batch.set(db.collection('admin_audit_log').doc(), {
        adminUid: 'script:category-icons',
        action: 'category.icon',
        target: `categories/${id}`,
        before: { iconUrl: before },
        after: { iconUrl: url },
        at: FieldValue.serverTimestamp(),
      });
      await batch.commit();
      uploaded++;
      console.log(`  ✔ ${id}`);
    }
  } catch (e) {
    fail(`Upload failed: ${e instanceof Error ? e.message : String(e)}${adcHint(target)}`);
  }
  console.log(
    values['dry-run']
      ? `Dry run: ${files.length - skipped.length} icon(s) would be uploaded.`
      : `Done: ${uploaded} icon(s) uploaded.`,
  );
  if (skipped.length) console.log(`Skipped (no categories/{id} document): ${skipped.join(', ')}`);
}

void main();

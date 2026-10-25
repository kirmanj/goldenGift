/**
 * Photo URLs the app sends to callables (a gift card's photo, a partner's sample
 * photos) must be download URLs of files the CALLER uploaded to this project's
 * Storage (SRS §6.16 folders) — not any http(s) URL: a foreign URL shown to a
 * gift-card recipient or in the dashboard is a tracking pixel at best.
 *
 * A download URL looks like
 * `https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{url-encoded path}?alt=media&token=…`.
 * On the emulators the host is the Storage emulator's (127.0.0.1:9199, 10.0.2.2:9199
 * or a LAN address), so the host is only pinned outside them; the bucket is
 * checked when the runtime knows it (`FIREBASE_CONFIG.storageBucket`).
 */

export const STORAGE_DOWNLOAD_HOST = 'firebasestorage.googleapis.com';

export interface StorageUrlEnv {
  FUNCTIONS_EMULATOR?: string;
  FIREBASE_STORAGE_EMULATOR_HOST?: string;
  FIREBASE_CONFIG?: string;
}

/** `{ host, bucket, path }` of a Firebase Storage download URL, or null. */
export function parseStorageUrl(url: string): { host: string; bucket: string; path: string } | null {
  const m = /^https?:\/\/([^/?#]+)\/v0\/b\/([^/?#]+)\/o\/([^?#]+)(?:[?#]|$)/.exec(url);
  if (m === null) return null;
  try {
    return { host: m[1].toLowerCase(), bucket: decodeURIComponent(m[2]), path: decodeURIComponent(m[3]) };
  } catch {
    return null;
  }
}

function projectBucket(env: StorageUrlEnv): string | null {
  try {
    const bucket = (JSON.parse(env.FIREBASE_CONFIG ?? '{}') as { storageBucket?: unknown }).storageBucket;
    return typeof bucket === 'string' && bucket.length > 0 ? bucket : null;
  } catch {
    return null;
  }
}

/**
 * Whether `url` is a download URL of an object under `folder` (e.g.
 * `gift_cards/{uid}/`) in this project's bucket. Path traversal (`..`) and
 * look-alike folders (`gift_cards/{uid}x/`) never pass.
 */
export function isOwnUploadUrl(url: unknown, folder: string, env: StorageUrlEnv = process.env): boolean {
  if (typeof url !== 'string' || url.length > 2048) return false;
  const parsed = parseStorageUrl(url);
  if (parsed === null) return false;
  const emulated = env.FUNCTIONS_EMULATOR === 'true' || (env.FIREBASE_STORAGE_EMULATOR_HOST ?? '') !== '';
  if (!emulated && (parsed.host !== STORAGE_DOWNLOAD_HOST || !url.startsWith('https://'))) return false;
  const bucket = projectBucket(env);
  if (bucket !== null && parsed.bucket !== bucket) return false;
  const prefix = folder.endsWith('/') ? folder : `${folder}/`;
  return parsed.path.startsWith(prefix) && parsed.path.length > prefix.length && !parsed.path.split('/').includes('..');
}

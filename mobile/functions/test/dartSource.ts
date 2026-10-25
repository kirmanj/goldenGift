/** Minimal readers for the Dart constant files the parity tests compare against. */
import { readFileSync } from 'node:fs';
import * as path from 'node:path';

/**
 * Repo-relative Dart sources (functions/ lives in mobile/functions). The two
 * admin files only re-export the mobile ones (the dashboard depends on the
 * `golden_gift` package), so the enums and paths are parsed from mobile only.
 */
export const DART = {
  mobileConstants: path.resolve(__dirname, '../../lib/core/constants/app_constants.dart'),
  adminConstants: path.resolve(__dirname, '../../../adminDashboard/lib/core/constants/admin_constants.dart'),
  mobilePaths: path.resolve(__dirname, '../../lib/core/constants/firestore_paths.dart'),
  adminPaths: path.resolve(__dirname, '../../../adminDashboard/lib/core/constants/firestore_paths.dart'),
};

/** The `package:golden_gift/...` path the customer app's `lib/<rel>` is imported as. */
export function goldenGiftPackageUri(relativeToLib: string): string {
  return `package:golden_gift/${relativeToLib}`;
}

/** Removes `//` and `/* *\/` comments, leaving string literals intact. */
export function stripDartComments(src: string): string {
  let out = '';
  let i = 0;
  let quote: string | null = null;
  while (i < src.length) {
    const ch = src[i];
    const next = src[i + 1];
    if (quote) {
      out += ch;
      if (ch === '\\') {
        out += next ?? '';
        i += 2;
        continue;
      }
      if (ch === quote) quote = null;
      i++;
    } else if (ch === "'" || ch === '"') {
      quote = ch;
      out += ch;
      i++;
    } else if (ch === '/' && next === '/') {
      while (i < src.length && src[i] !== '\n') i++;
    } else if (ch === '/' && next === '*') {
      const end = src.indexOf('*/', i + 2);
      i = end === -1 ? src.length : end + 2;
    } else {
      out += ch;
      i++;
    }
  }
  return out;
}

/** `enum Name { a, b, c; ... }` → { Name: ['a', 'b', 'c'] }, in file order. */
export function parseDartEnums(file: string): Map<string, string[]> {
  const src = stripDartComments(readFileSync(file, 'utf8'));
  const enums = new Map<string, string[]>();
  for (const m of src.matchAll(/\benum\s+(\w+)\s*\{([^}]*)\}/g)) {
    // Values end at the first `;` (enhanced enums put members after it).
    const body = m[2].split(';')[0];
    const values = body
      .split(',')
      .map((v) => v.trim().match(/^(\w+)/)?.[1])
      .filter((v): v is string => v !== undefined);
    enums.set(m[1], values);
  }
  return enums;
}

export interface DartExport {
  uri: string;
  /** Names after `hide`, in source order (empty when there is no `hide`). */
  hide: string[];
  /** Names after `show`, in source order (empty when there is no `show`). */
  show: string[];
}

/** `export 'uri' [show a, b] [hide c];` directives, in file order. */
export function parseDartExports(file: string): DartExport[] {
  const src = stripDartComments(readFileSync(file, 'utf8'));
  return [...src.matchAll(/\bexport\s+'([^']+)'([^;]*);/g)].map((m) => {
    const combinators = m[2];
    const names = (keyword: 'show' | 'hide') =>
      (combinators.match(new RegExp(`\\b${keyword}\\s+([\\w\\s,]+?)(?=\\s+(?:show|hide)\\b|\\s*$)`))?.[1] ?? '')
        .split(',')
        .map((n) => n.trim())
        .filter((n) => n.length > 0);
    return { uri: m[1], show: names('show'), hide: names('hide') };
  });
}

/** `static const String name = 'value';` → { name: 'value' }. */
export function parseDartStringConstants(file: string): Map<string, string> {
  const src = stripDartComments(readFileSync(file, 'utf8'));
  const consts = new Map<string, string>();
  for (const m of src.matchAll(/static\s+const\s+String\s+(\w+)\s*=\s*'([^']*)'\s*;/g)) {
    consts.set(m[1], m[2]);
  }
  return consts;
}

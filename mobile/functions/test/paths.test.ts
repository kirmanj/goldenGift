import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { FirestorePaths } from '../src/shared/paths';
import { DART, goldenGiftPackageUri, parseDartExports, parseDartStringConstants } from './dartSource';

describe('paths.ts ↔ mobile firestore_paths.dart', () => {
  const dart = parseDartStringConstants(DART.mobilePaths);

  test('parses the Dart constants', () => {
    assert.ok(dart.size >= 20, `found only ${dart.size} constants in ${DART.mobilePaths}`);
    assert.equal(dart.get('functionRuns'), 'function_runs');
  });

  test('every Dart constant exists in paths.ts with the same value', () => {
    for (const [key, value] of dart) {
      assert.equal((FirestorePaths as Record<string, string>)[key], value, `FirestorePaths.${key}`);
    }
  });

  test('paths.ts has no constants missing from Dart', () => {
    assert.deepEqual(Object.keys(FirestorePaths).sort(), [...dart.keys()].sort());
  });
});

/** The dashboard uses exactly the app's FirestorePaths (it depends on the `golden_gift` package). */
describe('admin firestore_paths.dart re-exports the mobile paths', () => {
  test("is `export 'package:golden_gift/core/constants/firestore_paths.dart';` without show / hide", () => {
    assert.deepEqual(parseDartExports(DART.adminPaths), [
      { uri: goldenGiftPackageUri('core/constants/firestore_paths.dart'), show: [], hide: [] },
    ]);
  });

  test('defines no constants of its own', () => {
    assert.equal(parseDartStringConstants(DART.adminPaths).size, 0);
  });
});

import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import * as enums from '../src/shared/enums';
import { DART, goldenGiftPackageUri, parseDartEnums, parseDartExports } from './dartSource';

/** "Enums — single definition, must NOT diverge" (CLAUDE.md, SRS §6.15). */
const tsEnums = new Map<string, readonly string[]>(
  Object.entries(enums as Record<string, unknown>).filter(
    (e): e is [string, readonly string[]] => Array.isArray(e[1]),
  ),
);

describe('enums.ts ↔ mobile app_constants.dart', () => {
  const dartEnums = parseDartEnums(DART.mobileConstants);

  test('parses the Dart enums', () => {
    assert.ok(dartEnums.size >= 8, `found only ${dartEnums.size} enums in ${DART.mobileConstants}`);
    assert.deepEqual(dartEnums.get('OrderStatus')?.at(-1), 'refunded'); // trailing `;` handled
  });

  test('same enum names', () => {
    assert.deepEqual([...tsEnums.keys()].sort(), [...dartEnums.keys()].sort());
  });

  for (const [name, values] of dartEnums) {
    test(`${name} has identical values in the same order`, () => {
      assert.deepEqual(tsEnums.get(name), values);
    });
  }
});

/**
 * The dashboard depends on the `golden_gift` package and re-exports its enums,
 * so there is exactly one Dart definition (the one compared above).
 */
describe('admin admin_constants.dart re-exports the mobile enums', () => {
  const exports = parseDartExports(DART.adminConstants);
  const reexport = exports.find((e) => e.uri === goldenGiftPackageUri('core/constants/app_constants.dart'));

  test("has `export 'package:golden_gift/core/constants/app_constants.dart'`", () => {
    assert.ok(reexport, `no re-export in ${DART.adminConstants}; found ${JSON.stringify(exports)}`);
  });

  test('hides none of the shared enums and does not narrow them with `show`', () => {
    assert.ok(reexport);
    for (const name of tsEnums.keys()) assert.ok(!reexport.hide.includes(name), `hides ${name}`);
    if (reexport.show.length > 0) {
      for (const name of tsEnums.keys()) assert.ok(reexport.show.includes(name), `show omits ${name}`);
    }
  });

  test('declares none of the shared enums itself', () => {
    const own = [...parseDartEnums(DART.adminConstants).keys()].filter((n) => tsEnums.has(n));
    assert.deepEqual(own, []);
  });
});

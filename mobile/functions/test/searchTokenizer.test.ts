import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as path from 'node:path';
import { describe, test } from 'node:test';
import { keywords, normalize, tokenize } from '../src/shared/searchTokenizer';

/** Shared with mobile/test/core/search_tokenizer_test.dart — both must pass. */
const FIXTURE = path.resolve(__dirname, '../../test/fixtures/search_tokenizer_cases.json');

interface Fixture {
  tokenize: Array<{ input: string; output: string[] }>;
  keywords: Array<{ input: string[]; output: string[] }>;
}

const fixture = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

describe('SearchTokenizer (shared fixture)', () => {
  test('fixture has cases', () => {
    assert.ok(fixture.tokenize.length > 0);
    assert.ok(fixture.keywords.length > 0);
  });

  for (const { input, output } of fixture.tokenize) {
    test(`tokenize ${JSON.stringify(input)}`, () => {
      assert.deepEqual(tokenize(input), output);
    });
  }

  for (const { input, output } of fixture.keywords) {
    test(`keywords ${JSON.stringify(input)}`, () => {
      assert.deepEqual(keywords(input), output);
    });
  }
});

describe('SearchTokenizer details', () => {
  test('normalize unifies letter variants and strips diacritics + tatweel', () => {
    assert.equal(normalize('أإآٱ كيى'), 'اااا کیی');
    assert.equal(normalize('مُـحَمَّد'), 'محمد');
  });

  test('length counts code points, not UTF-16 units', () => {
    // One astral letter (U+1D400 MATHEMATICAL BOLD CAPITAL A) is 2 UTF-16 units but 1 character.
    assert.deepEqual(tokenize('\u{1D400} ab'), ['ab']);
  });
});

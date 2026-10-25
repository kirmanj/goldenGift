import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 10 design-token and RTL guard (CLAUDE.md "Design System", SRS §2.3,
/// §8): a static scan of lib/ (without lib/core/theme/, where the tokens are
/// defined, generated lib/l10n/, firebase_options.dart and the debug-only
/// lib/dev/). Each rule names the token to use instead; justified exceptions
/// are listed in [_allowed] with the reason.
///
/// Run alone: `flutter test test/qa/design_tokens_test.dart`.

class Rule {
  const Rule(this.id, this.pattern, this.fix, {this.check, this.only});
  final String id;
  final Pattern pattern;
  final String fix;

  /// Extra test on the call's argument text (from the opening parenthesis).
  final bool Function(String args)? check;

  /// Limits the rule to the files this returns true for.
  final bool Function(String path)? only;
}

/// `path` → rule ids allowed there, with the reason.
const _allowed = <String, Map<String, String>>{
  'lib/features/wallet/presentation/widgets/wallet_ui.dart': {
    'raw-text-style': 'icon glyphs painted by the decorative header pattern (CustomPainter), not text',
  },
  'lib/features/gift_cards/presentation/widgets/gift_card_face.dart': {
    'physical-alignment': 'gradient direction on the card artwork is decorative and fixed in both directions',
  },
  'lib/features/gift_cards/presentation/screens/gift_card_designer_screen.dart': {
    'spacing-literal': '3 px inset between the template swatch and its selection ring',
  },
  'lib/features/product_details/presentation/widgets/variant_options.dart': {
    'spacing-literal': '3 px inset between the colour swatch and its selection ring',
  },
  'lib/core/widgets/placeholder_screen.dart': {
    'hardcoded-string': '"Widget gallery (debug)" button, shown only in debug builds',
  },
  'lib/core/widgets/skeleton_loader.dart': {'shrink-wrap': 'fixed count of skeleton cards'},
  'lib/features/auth/presentation/widgets/phone_field.dart': {'shrink-wrap': 'country-code sheet: CountryCodes.all (≈20)'},
  'lib/features/profile/presentation/widgets/profile_pickers.dart': {'shrink-wrap': 'city sheet: the served cities'},
  'lib/features/wishlist/presentation/widgets/wishlist_list_sheets.dart': {
    'shrink-wrap': "list picker sheet: the customer's few named lists",
  },
  'lib/core/widgets/gg_network_image.dart': {
    'network-image': 'the one cached network image widget',
  },
  'lib/core/utils/currency_formatter.dart': {'number-format': 'the currency helper itself'},
  'lib/core/widgets/gg_logo.dart': {
    'hardcoded-string': 'the brand name "Golden Gift" is never translated (wordmark + logo semantics)',
    'raw-text-style': 'the wordmark is part of the logo: size and letter-spacing scale with the emblem',
  },
};

final _nonTrivialLiteral = RegExp(r'(?<![\w.$])(?:[2-9]|\d{2,})(?:\.\d+)?(?![\w.])');

final rules = <Rule>[
  const Rule('hardcoded-color', r'Color(0x', 'AppColors.* tokens / AppColors.*(context) helpers'),
  Rule('hardcoded-color', RegExp(r'Color\.from(ARGB|RGBO)\('), 'AppColors.* tokens'),
  Rule('material-colors', RegExp(r'\bColors\.(?!transparent\b)\w'), 'AppColors.* (Colors.transparent is fine)'),
  const Rule('with-opacity', '.withOpacity(', 'Color.withValues(alpha: …)'),
  Rule(
    'raw-text-style',
    RegExp(r'\bTextStyle\('),
    'AppTextStyles.* (copyWith for colour / weight)',
    check: (args) => RegExp(r'\bfontSize\s*:').hasMatch(args),
  ),
  Rule(
    'spacing-literal',
    RegExp(r'\bEdgeInsets(Directional)?\.(all|symmetric|only|fromLTRB|fromSTEB)\('),
    'AppSpacing.* (0 and 1 px optical nudges are fine)',
    check: (args) => _nonTrivialLiteral.hasMatch(args),
  ),
  Rule(
    'radius-literal',
    RegExp(r'\bRadius\.circular\('),
    'AppRadius.*',
    check: (args) => _nonTrivialLiteral.hasMatch(args),
  ),
  // RTL (SRS §8: RTL verified on every screen): directional APIs only.
  Rule(
    'physical-padding',
    RegExp(r'\bEdgeInsets\.only\('),
    'EdgeInsetsDirectional.only(start:/end:)',
    check: (args) => RegExp(r'\b(left|right)\s*:').hasMatch(args),
  ),
  Rule(
    'physical-padding',
    RegExp(r'\bEdgeInsets\.fromLTRB\('),
    'EdgeInsetsDirectional.fromSTEB (left ≠ right)',
    check: (args) {
      final parts = _topLevelArgs(args);
      return parts.length == 4 && parts[0] != parts[2];
    },
  ),
  Rule(
    'physical-position',
    RegExp(r'\bPositioned\('),
    'PositionedDirectional(start:/end:)',
    check: (args) => RegExp(r'\b(left|right)\s*:').hasMatch(args),
  ),
  Rule(
    'physical-radius',
    RegExp(r'\bBorderRadius\.only\('),
    'BorderRadiusDirectional.only(topStart: …)',
    check: (args) => RegExp(r'\b(topLeft|topRight|bottomLeft|bottomRight)\s*:').hasMatch(args),
  ),
  Rule('physical-alignment', RegExp(r'\bAlignment\.(top|center|bottom)(Left|Right)\b'), 'AlignmentDirectional.*Start/End'),
  Rule('physical-text-align', RegExp(r'\bTextAlign\.(left|right)\b'), 'TextAlign.start / end'),
  // Performance (SRS §8: images lazy + cached).
  Rule('network-image', RegExp(r'\b(Image\.network|NetworkImage|CachedNetworkImage|CachedNetworkImageProvider)\('),
      'GGNetworkImage (cached, decoded at the laid-out size)'),
  Rule(
    'memory-image-size',
    RegExp(r'\bImage\.memory\('),
    'Image.memory(…, cacheWidth: laid-out width × devicePixelRatio) — picked photos are up to 1600 px',
    check: (args) => !args.contains('cacheWidth'),
  ),
  Rule(
    'shrink-wrap',
    RegExp(r'\bshrinkWrap:\s*true'),
    'a lazily built list (ListView.builder / slivers); shrinkWrap lays out every item',
  ),
  // Formatting helpers (CLAUDE.md: dates via AppDates, money via CurrencyFormatter).
  Rule('date-format', RegExp(r'\bDateFormat\('), 'AppDates (no intl data for ckb)'),
  Rule('number-format', RegExp(r'\bNumberFormat\('), 'CurrencyFormatter.format'),
  // Hardcoded user-facing strings (SRS §8: 100 % string coverage).
  Rule(
    'hardcoded-string',
    RegExp(
        r'''(\bText\(\s*|\b(tooltip|semanticLabel|semanticsLabel|hintText|labelText|helperText|errorText|label|title|subtitle|message)\s*:\s*)(const\s+)?['"]'''),
    'AppLocalizations (assets/lang/*.arb)',
    check: _hasLatinWords,
    only: (path) =>
        path.startsWith('lib/core/widgets/') ||
        (path.startsWith('lib/features/') && (path.contains('/screens/') || path.contains('/widgets/'))),
  ),
];

/// The string literal right after the match has a Latin word outside
/// interpolations (IQD, the currency code, is fine).
bool _hasLatinWords(String rest) {
  final quote = rest.indexOf(RegExp('[\'"]'));
  if (quote < 0) return false;
  final q = rest[quote];
  final end = rest.indexOf(q, quote + 1);
  if (end < 0) return false;
  final literal = rest
      .substring(quote + 1, end)
      .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
      .replaceAll(RegExp(r'\$\w+'), '')
      .replaceAll('IQD', '');
  return RegExp('[A-Za-z]{2,}').hasMatch(literal);
}

/// The argument text of a call whose "(" is at [open] (balanced parens).
String _argsFrom(String src, int open) {
  var depth = 0;
  for (var j = open; j < src.length; j++) {
    final c = src[j];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return src.substring(open + 1, j);
    }
  }
  return src.substring(open);
}

/// Splits call arguments on top-level commas.
List<String> _topLevelArgs(String args) {
  final out = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < args.length; i++) {
    final c = args[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ',' && depth == 0) {
      out.add(args.substring(start, i).trim());
      start = i + 1;
    }
  }
  final last = args.substring(start).trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}

/// Drops `//` comments (keeps string contents and line numbers).
String _stripComments(String src) => src.split('\n').map((line) {
      final i = line.indexOf('//');
      if (i < 0) return line;
      // Not inside a string literal: an even number of quotes before it.
      final before = line.substring(0, i);
      final quotes = RegExp('[\'"]').allMatches(before).length;
      return quotes.isEven ? before : line;
    }).join('\n');

List<File> _sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) {
      final p = f.path.replaceAll('\\', '/');
      return !p.startsWith('lib/core/theme/') &&
          !p.startsWith('lib/l10n/') &&
          !p.startsWith('lib/dev/') &&
          p != 'lib/firebase_options.dart';
    })
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  test('rule self-check', () {
    expect(_nonTrivialLiteral.hasMatch('AppSpacing.md, 0, AppSpacing.md, 12'), isTrue);
    expect(_nonTrivialLiteral.hasMatch('top: 1'), isFalse);
    expect(_nonTrivialLiteral.hasMatch('AppSpacing.sm + AppSpacing.xs'), isFalse);
    expect(_hasLatinWords("'Saved Cards')"), isTrue);
    expect(_hasLatinWords(r"'${l10n.a}. ${l10n.b}')"), isFalse);
    expect(_topLevelArgs('a, f(b, c), d, e'), ['a', 'f(b, c)', 'd', 'e']);
  });

  test('lib/ uses design tokens, directional layout and the shared helpers', () {
    final violations = <String>[];
    for (final file in _sources()) {
      final path = file.path.replaceAll('\\', '/');
      final src = _stripComments(file.readAsStringSync());
      for (final rule in rules) {
        if (rule.only != null && !rule.only!(path)) continue;
        if (_allowed[path]?.containsKey(rule.id) ?? false) continue;
        for (final m in rule.pattern.allMatches(src)) {
          if (rule.check != null) {
            final open = src.indexOf('(', m.end - 1);
            final args = rule.id == 'hardcoded-string' ? src.substring(m.end - 1) : _argsFrom(src, open);
            if (!rule.check!(args)) continue;
          }
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          violations.add('$path:$line [${rule.id}] ${src.split('\n')[line - 1].trim()}  → use ${rule.fix}');
        }
      }
    }
    expect(violations, isEmpty, reason: '${violations.length} design-token violations');
  });

  test('GGNetworkImage decodes at the laid-out size (SRS §8: images lazy + cached)', () {
    final src = File('lib/core/widgets/gg_network_image.dart').readAsStringSync();
    expect(src, contains('CachedNetworkImage('));
    expect(src, contains('memCacheWidth: cacheWidth'));
  });

  test('every allow-list entry is still needed', () {
    final stale = <String>[];
    for (final MapEntry(key: path, value: ids) in _allowed.entries) {
      final file = File(path);
      if (!file.existsSync()) {
        stale.add('$path (file gone)');
        continue;
      }
      final src = _stripComments(file.readAsStringSync());
      for (final id in ids.keys) {
        final hit = rules.where((r) => r.id == id).any((rule) => rule.pattern.allMatches(src).any((m) {
              if (rule.check == null) return true;
              final args = rule.id == 'hardcoded-string' ? src.substring(m.end - 1) : _argsFrom(src, src.indexOf('(', m.end - 1));
              return rule.check!(args);
            }));
        if (!hit) stale.add('$path [$id]');
      }
    }
    expect(stale, isEmpty, reason: 'remove these from _allowed');
  });
}

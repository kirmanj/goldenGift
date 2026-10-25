import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_harness.dart';
import 'route_sweep_test.dart' show sweepRoutes;

/// Phase 10 accessibility guards (SRS §8): Flutter's accessibility
/// guidelines on the real app over the seeded world.
///
/// * Main screens × {en, ar} × {light, dark}: Android tap targets (48 dp),
///   iOS tap targets (44 pt), labelled tap targets and WCAG AA text contrast
///   (4.5:1, 3:1 for large text) — checked at the top and after each scroll
///   step of the page.
/// * Every swept route in en · light and ar · dark: tap targets and labels.
///
/// Contrast is sampled from a screenshot at logical resolution. With the real
/// fonts the 1-px antialiased strokes of small text lose the colour histogram
/// to borders / gradients (false failures), so this file keeps flutter_test's
/// square-glyph font: text pixels then carry the text colour exactly. Layout
/// with the real fonts is covered by route_sweep_test.dart.
///
/// Documented exceptions: none at the moment — add a label to
/// [_contrastExceptions] only with the measured ratio and the reason.

const a11yScreens = <(String, String)>[
  ('Home', '/main?tab=0'),
  ('Products', '/products?category=birthdays'),
  ('Coming soon category', '/products?category=$qaComingSoonCategory'),
  ('Product details', '/product/frame'),
  ('Cart', '/main?tab=1'),
  ('Checkout', '/checkout'),
  ('Orders', '/orders'),
  ('Order details', '/orders/o3'),
  ('Profile', '/main?tab=2'),
  ('Reels', '/main?tab=3'),
  ('Wallet', '/wallet'),
  ('Invite & Earn', '/invite'),
  ('Gift card designer', '/gift-cards/design/t1'),
  ('Special requests', '/special-requests'),
  ('Secret Santa group', '/secret-santa/g1'),
  ('AI search', '/ai-gift-search'),
  ('Notifications', '/notifications'),
  ('Address form', '/addresses/form?id=a1'),
];

/// Text labels skipped by the contrast check, with the reason.
const _contrastExceptions = <String, String>{};

/// [textContrastGuideline] minus the documented exceptions.
class QaTextContrastGuideline extends MinimumTextContrastGuideline {
  const QaTextContrastGuideline();

  @override
  bool shouldSkipNode(SemanticsData data) => super.shouldSkipNode(data) || _contrastExceptions.containsKey(data.label);
}

Future<Set<String>> _evaluate(WidgetTester tester, Map<String, AccessibilityGuideline> guidelines) async {
  final failures = <String>{};
  for (final MapEntry(key: name, value: guideline) in guidelines.entries) {
    final result = await guideline.evaluate(tester);
    if (!result.passed) {
      failures.addAll(result.reason!.split('\n\n').where((r) => r.trim().isNotEmpty).map((r) => '[$name] ${r.trim()}'));
    }
  }
  return failures;
}

void main() {
  group('main screens', () {
    final guidelines = <String, AccessibilityGuideline>{
      'android tap target 48dp': androidTapTargetGuideline,
      'ios tap target 44pt': iOSTapTargetGuideline,
      'labelled tap target': labeledTapTargetGuideline,
      'text contrast': const QaTextContrastGuideline(),
    };
    for (final (name, location) in a11yScreens) {
      for (final locale in ['en', 'ar']) {
        for (final theme in qaThemes) {
          testWidgets('$name · $locale · ${theme.name}', (tester) async {
            final semantics = tester.ensureSemantics();
            final app =
                await pumpQaApp(tester, location: location, locale: locale, theme: theme, viewport: QaViewport.tallPhone);
            final failures = await _evaluate(tester, guidelines);
            await scrollThrough(tester,
                axis: Axis.vertical, onStep: () async => failures.addAll(await _evaluate(tester, guidelines)));
            await unmountQaApp(tester, app);
            semantics.dispose();
            expect(failures, isEmpty);
          });
        }
      }
    }
  });

  group('every route', () {
    final guidelines = <String, AccessibilityGuideline>{
      'android tap target 48dp': androidTapTargetGuideline,
      'labelled tap target': labeledTapTargetGuideline,
    };
    for (final route in sweepRoutes) {
      for (final (locale, theme) in [('en', ThemeMode.light), ('ar', ThemeMode.dark)]) {
        testWidgets('${route.name} · $locale · ${theme.name}', (tester) async {
          final semantics = tester.ensureSemantics();
          final app = await pumpQaApp(tester,
              location: route.location,
              extra: route.extra,
              guest: route.guest,
              locale: locale,
              theme: theme,
              viewport: QaViewport.tallPhone);
          final failures = await _evaluate(tester, guidelines);
          await unmountQaApp(tester, app);
          semantics.dispose();
          expect(failures, isEmpty);
        });
      }
    }
  });
}

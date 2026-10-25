import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/widgets/widgets.dart';
import 'package:golden_gift/features/ai_search/data/ai_search_repository.dart';
import 'package:golden_gift/features/ai_search/presentation/widgets/ai_suggestion_grid.dart';

import 'phase9_harness.dart';

final _en = l10nFor('en');

Finder get _query => find.descendant(of: find.byKey(const ValueKey('ai-query')), matching: find.byType(TextField));
/// The heart's tap target (the heart itself is inside a scale transform).
Finder _heart(String id) => find.descendant(
    of: find.descendant(of: find.byKey(ValueKey('ai-result-$id')), matching: find.byType(WishlistHeart)),
    matching: find.byType(InkResponse));
String _text(WidgetTester tester) => tester.widget<TextField>(_query).controller!.text;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Taps a chip of a horizontally scrolling row, scrolling the row to it first.
Future<void> _chip(WidgetTester tester, String row, Finder chip) async {
  await tester.ensureVisible(find.byKey(ValueKey('ai-row-$row')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    chip,
    120,
    scrollable: find.descendant(of: find.byKey(ValueKey('ai-row-$row')), matching: find.byType(Scrollable)),
  );
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<FakeFirebaseFirestore> _catalogue() async {
  final db = FakeFirebaseFirestore();
  await seedProduct(db, 'p1', 'Plant pot', 30000);
  await seedProduct(db, 'p2', 'Graduation frame', 45000);
  await seedProduct(db, 'p3', 'Plant terrarium', 90000);
  return db;
}

/// aiGiftSearch → p2 then p1, each with a reason.
FakeCallables _ai() => FakeCallables()
  ..handlers['aiGiftSearch'] = (_) => {
        'searchId': 's1',
        'results': [
          {'productId': 'p2', 'reason': 'Perfect for her graduation day'},
          {'productId': 'p1', 'reason': 'She loves plants'},
        ],
      };

void main() {
  group('query validation', () {
    testWidgets('an empty or too-short description is refused before any call', (tester) async {
      final h = await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch, callables: _ai());
      expect(find.text(_en.aiGiftSearch), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
      expect(find.text(_en.aiSearchQueryRequired), findsOneWidget);

      await tester.enterText(_query, 'ab');
      await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
      expect(find.text(_en.aiSearchQueryTooShort), findsOneWidget);
      expect(h.callables.calls, isEmpty);
      expect(h.analytics.events.containsKey(AnalyticsEvents.aiSearch), isFalse);
    });

    testWidgets('the field stops at 300 characters with a live counter', (tester) async {
      await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch);
      await tester.enterText(_query, 'a' * 400);
      await tester.pumpAndSettle();
      expect(_text(tester).length, AiSearchRepository.maxQuery);
      expect(find.text('300/300'), findsOneWidget);
    });
  });

  group('chips', () {
    testWidgets('an example fills the text; occasion / recipient words toggle in and out', (tester) async {
      await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch);
      await _chip(tester, 'examples', find.byKey(const ValueKey('ai-example-1')));
      expect(_text(tester), aiSearchExamples[1].resolve('en'));

      await tester.enterText(_query, 'Something for');
      await _chip(tester, 'recipient', find.text(_en.aiRecipientMum));
      expect(_text(tester), 'Something for, ${_en.aiRecipientMum}');
      await _chip(tester, 'occasion', find.text(_en.aiOccasionBirthday));
      expect(_text(tester), 'Something for, ${_en.aiRecipientMum}, ${_en.aiOccasionBirthday}');
      final chip = tester.widget<CategoryChip>(
          find.ancestor(of: find.text(_en.aiOccasionBirthday), matching: find.byType(CategoryChip)));
      expect(chip.selected, isTrue);

      await _chip(tester, 'recipient', find.text(_en.aiRecipientMum));
      expect(_text(tester), 'Something for, ${_en.aiOccasionBirthday}');
    });

    testWidgets('Arabic chips join with the Arabic comma', (tester) async {
      final ar = l10nFor('ar');
      await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch, locale: 'ar');
      await tester.enterText(_query, 'هدية');
      await _chip(tester, 'recipient', find.text(ar.aiRecipientSister));
      expect(_text(tester), 'هدية، ${ar.aiRecipientSister}');
    });
  });

  testWidgets('results: AI ranking with a "why" caption, budget + locale sent, ai_search logged', (tester) async {
    final h = await pumpPhase9(
      tester,
      initialPath: AppRoutes.aiGiftSearch,
      firestore: await _catalogue(),
      callables: _ai(),
    );
    await tester.enterText(_query, "My sister's graduation, she loves plants");
    await _chip(tester, 'budget', find.byKey(const ValueKey('ai-budget-50000')));
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));

    expect(h.callables.callsTo('aiGiftSearch').single, {
      'query': "My sister's graduation, she loves plants",
      'locale': 'en',
      'budgetMax': 50000,
    });
    expect(find.text(_en.aiSearchResultsTitle), findsOneWidget);
    expect(find.byType(ProductCard), findsNWidgets(2));
    expect(find.text('Perfect for her graduation day'), findsOneWidget);
    expect(find.text('She loves plants'), findsOneWidget);
    // AI order kept: p2 before p1.
    final first = tester.getTopLeft(find.byKey(const ValueKey('ai-result-p2')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('ai-result-p1')));
    expect(first.dx < second.dx || first.dy < second.dy, isTrue);
    expect(find.byKey(const ValueKey('ai-fallback')), findsNothing);
    expect(find.byKey(const ValueKey('ai-rate-limited')), findsNothing);
    expect(h.analytics.events[AnalyticsEvents.aiSearch], {
      'search_term': "My sister's graduation, she loves plants",
      'results': 2,
      'fallback': 0,
    });

    await _tap(tester, find.text('Graduation frame'));
    expect(find.text('product p2'), findsOneWidget);
  });

  testWidgets('function down → keyword matches within the budget + "Showing keyword matches"', (tester) async {
    final h = await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch, firestore: await _catalogue());
    await tester.enterText(_query, 'plant');
    await _chip(tester, 'budget', find.byKey(const ValueKey('ai-budget-50000')));
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
    expect(find.byKey(const ValueKey('ai-fallback')), findsOneWidget);
    expect(find.text(_en.aiSearchFallbackNote), findsOneWidget);
    expect(find.text('Plant pot'), findsOneWidget);
    expect(find.text('Plant terrarium'), findsNothing); // over budget
    expect(find.byKey(const ValueKey('ai-reason-p1')), findsNothing);
    expect(h.analytics.events[AnalyticsEvents.aiSearch], {'search_term': 'plant', 'results': 1, 'fallback': 1});
  });

  testWidgets('daily limit → "reached today\'s AI searches" with keyword results', (tester) async {
    final calls = FakeCallables()
      ..handlers['aiGiftSearch'] =
          (_) => throw FirebaseFunctionsException(code: 'resource-exhausted', message: 'limit');
    await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch, firestore: await _catalogue(), callables: calls);
    await tester.enterText(_query, 'plant');
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
    expect(find.byKey(const ValueKey('ai-rate-limited')), findsOneWidget);
    expect(find.text(_en.aiSearchRateLimited), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-fallback')), findsNothing);
    expect(find.byType(ProductCard), findsNWidgets(2));
  });

  testWidgets('nothing found → empty state', (tester) async {
    await pumpPhase9(tester, initialPath: AppRoutes.aiGiftSearch, firestore: await _catalogue());
    await tester.enterText(_query, 'telescope');
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
    expect(find.byKey(const ValueKey('ai-empty')), findsOneWidget);
    expect(find.text(_en.aiSearchNoResultsTitle), findsOneWidget);
  });

  testWidgets('works for guests; the heart on a result asks them to sign in', (tester) async {
    final h = await pumpPhase9(
      tester,
      initialPath: AppRoutes.aiGiftSearch,
      guest: true,
      firestore: await _catalogue(),
      callables: _ai(),
    );
    await tester.enterText(_query, 'graduation gift');
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
    expect(find.byType(ProductCard), findsNWidgets(2));
    await _tap(tester, _heart('p1'));
    expect(find.text(_en.signInToContinue), findsOneWidget);
    expect((await h.firestore.collection('wishlists/u1/items').get()).docs, isEmpty);
  });

  testWidgets('a signed-in customer saves a result to the wishlist', (tester) async {
    final h = await pumpPhase9(
      tester,
      initialPath: AppRoutes.aiGiftSearch,
      firestore: await _catalogue(),
      callables: _ai(),
    );
    await tester.enterText(_query, 'graduation gift');
    await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
    await _tap(tester, _heart('p1'));
    final saved = await h.firestore.doc('wishlists/u1/items/p1').get();
    expect(saved.data()!['listId'], 'default');
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
    testWidgets('renders results in $locale (${mode.name}), right-to-left', (tester) async {
      final h = await pumpPhase9(
        tester,
        initialPath: AppRoutes.aiGiftSearch,
        firestore: await _catalogue(),
        callables: _ai(),
        locale: locale,
        themeMode: mode,
      );
      await _chip(tester, 'examples', find.byKey(const ValueKey('ai-example-0')));
      await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
      expect(h.callables.callsTo('aiGiftSearch').single['locale'], locale);
      expect(find.byType(AiSuggestionGrid), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(AiSuggestionGrid))), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      await pumpPhase9(
        tester,
        initialPath: AppRoutes.aiGiftSearch,
        firestore: await _catalogue(),
        callables: _ai(),
        locale: locale,
        size: const Size(320, 2400),
        textScale: 1.3,
      );
      await _chip(tester, 'examples', find.byKey(const ValueKey('ai-example-0')));
      await _tap(tester, find.byKey(const ValueKey('ai-find-gifts')));
      expect(find.byType(ProductCard), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}

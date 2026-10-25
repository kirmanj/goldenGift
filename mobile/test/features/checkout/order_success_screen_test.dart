import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/router/app_router.dart';

import 'phase6_test_harness.dart';

final _en = l10nFor('en');

Future<Phase6Harness> _pump(WidgetTester tester,
    {String locale = 'en',
    ThemeMode mode = ThemeMode.light,
    Size size = const Size(390, 1600),
    double scale = 1}) async {
  final db = FakeFirebaseFirestore();
  await seedOrder(db, 'o1', number: 'GG-2610-00042');
  return pumpPhase6(
    tester,
    initialPath: AppRoutes.orderSuccessFor('o1'),
    firestore: db,
    locale: locale,
    themeMode: mode,
    size: size,
    textScale: scale,
  );
}

void main() {
  testWidgets('shows the order number and the estimated delivery (date + slot)', (tester) async {
    await _pump(tester);
    expect(find.text(_en.orderPlacedTitle), findsOneWidget);
    expect(find.text(_en.orderPlacedBody('GG-2610-00042')), findsOneWidget);
    expect(find.text(_en.estimatedDelivery), findsOneWidget);
    final eta = tester.widget<Text>(
      find.descendant(of: find.byKey(const ValueKey('order-eta')), matching: find.byType(Text)).last,
    );
    expect(eta.data, contains('22/10/2026'));
    expect(eta.data, contains('Evening'));
    expect(eta.data, contains('18:00–22:00'));
  });

  testWidgets('Track order opens the order', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('track-order')));
    await tester.pumpAndSettle();
    expect(h.location, AppRoutes.order('o1'));
    expect(find.text(_en.orderDetails), findsOneWidget);
  });

  testWidgets('Continue shopping goes Home', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('continue-shopping')));
    await tester.pumpAndSettle();
    expect(find.text('main tab 0'), findsOneWidget);
  });

  testWidgets('system back never returns to checkout — it goes to Main', (tester) async {
    await _pump(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('main tab 0'), findsOneWidget);
  });

  group('renders without exceptions', () {
    for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light), ('ckb', ThemeMode.dark)]) {
      testWidgets('$locale ${mode.name}', (tester) async {
        await _pump(tester, locale: locale, mode: mode);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('320 px, 1.3× text', (tester) async {
      await _pump(tester, size: const Size(320, 640), scale: 1.3, locale: 'ckb');
      expect(tester.takeException(), isNull);
    });
  });
}

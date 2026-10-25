import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/banner_model.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/features/banners/banners_screen.dart';

import '../categories/admin_test_harness.dart';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.doc('categories/mugs').set(const CategoryModel(id: 'mugs', title: LocalizedText('Mugs')).toMap());
  await db.doc('products/p1').set({'title': 'Engraved wooden frame with a very long product title for testing'});
  final now = DateTime.now();
  final banners = [
    const BannerModel(
        id: 'b1',
        imageUrl: 'https://cdn.goldengift.test/b1.jpg',
        imageUrlAr: 'https://cdn.goldengift.test/b1_ar.jpg',
        placement: BannerPlacement.homeTop,
        actionType: BannerActionType.category,
        actionValue: 'mugs',
        sortOrder: 0),
    BannerModel(
        id: 'b2',
        imageUrl: 'https://cdn.goldengift.test/b2.jpg',
        placement: BannerPlacement.homeTop,
        actionType: BannerActionType.product,
        actionValue: 'p1',
        sortOrder: 1,
        startAt: now.add(const Duration(days: 3)),
        endAt: now.add(const Duration(days: 30))),
    BannerModel(
        id: 'b3',
        imageUrl: 'https://cdn.goldengift.test/b3.jpg',
        placement: BannerPlacement.homeMid1,
        actionType: BannerActionType.route,
        actionValue: '/special-requests',
        endAt: now.subtract(const Duration(days: 1))),
    const BannerModel(
        id: 'b4',
        imageUrl: 'https://cdn.goldengift.test/b4.jpg',
        placement: BannerPlacement.homeBottom,
        actionType: BannerActionType.url,
        actionValue: 'https://goldengift.app/a-very-long-campaign-landing-page-path-that-should-ellipsize',
        isActive: false),
  ];
  for (final b in banners) {
    await db.doc('banners/${b.id}').set(b.toMap());
  }
  return db;
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('renders in ${mode.name} at 800 px without overflow', (tester) async {
      await pumpAdminScreen(tester, const BannersScreen(), db: await seeded(), mode: mode);
      expect(find.text('Home · top carousel'), findsOneWidget);
      expect(find.text('Home · bottom carousel'), findsOneWidget);
      expect(find.text('Opens category · Mugs'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Expired'), 200);
      expect(find.text('Expired'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in ${mode.name} at 1280 px with no overflow in the page', (tester) async {
      final db = await seeded();
      final errors = await errorsOutsideCoreNav(
          () => pumpAdminScreen(tester, const BannersScreen(), db: db, mode: mode, size: const Size(1280, 900)));
      expect(errors, isEmpty);
      expect(find.textContaining('Opens product · Engraved'), findsOneWidget);
    });
  }

  testWidgets('move down rewrites the placement order', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const BannersScreen(), db: db);
    await tester.tap(find.byTooltip('Move down').first);
    await settle(tester);
    expect((await db.doc('banners/b1').get()).data()!['sortOrder'], 1);
    expect((await db.doc('banners/b2').get()).data()!['sortOrder'], 0);
    expect((await auditEntries(db)).single['action'], 'banner.reorder');
  });

  testWidgets('editor: English artwork required, links must be https', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const BannersScreen(), db: db);
    await tester.tap(find.text('New banner'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'dialog fits at 800 px');

    await tester.tap(find.text('Web link'));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('action-url')), 'http://goldengift.app');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);
    expect(find.text('The English artwork is required'), findsWidgets);
    expect(find.text('Links must be full https:// URLs'), findsWidgets);
    expect(await auditEntries(db), isEmpty);
  });
}

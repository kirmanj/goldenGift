import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/category_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/features/categories/categories_screen.dart';

import 'admin_test_harness.dart';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  final categories = [
    const CategoryModel(id: 'mugs', title: LocalizedText('Mugs', ar: 'أكواب', ku: 'کوپ'), sortOrder: 0, productCount: 12),
    CategoryModel(
      id: 'mothers-day',
      title: const LocalizedText("Mother's Day", ar: 'عيد الأم'),
      type: CategoryType.occasion,
      sortOrder: 1,
      isSeasonal: true,
      activeFrom: DateTime(2027, 3, 1),
      activeTo: DateTime(2027, 3, 21, 23, 59, 59),
    ),
    const CategoryModel(
        id: 'skin-and-body-care-with-a-very-long-name',
        title: LocalizedText('Skin and Body Care with a very long name that should wrap or ellipsize nicely'),
        sortOrder: 2,
        isActive: false,
        parentId: 'mugs'),
    const CategoryModel(id: 'frames', title: LocalizedText('Frames'), sortOrder: 3, productCount: 1),
    const CategoryModel(
      id: 'easter',
      title: LocalizedText('Easter Day', ar: 'عيد الفصح'),
      type: CategoryType.occasion,
      sortOrder: 4,
      comingSoon: true,
      comingSoonNote: LocalizedText('Arriving before Easter'),
    ),
    const CategoryModel(id: 'eggs', title: LocalizedText('Painted Eggs'), sortOrder: 5, parentId: 'easter'),
  ];
  for (final c in categories) {
    await db.doc('categories/${c.id}').set(c.toMap());
  }
  return db;
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('renders in ${mode.name} at 800 px without overflow', (tester) async {
      await pumpAdminScreen(tester, const CategoriesScreen(), db: await seeded(), mode: mode);
      expect(find.text('Mugs'), findsOneWidget);
      expect(find.text("Mother's Day"), findsOneWidget);
      expect(find.widgetWithText(CategoryStatusMenu, 'Hidden'), findsOneWidget);
      expect(find.widgetWithText(CategoryStatusMenu, 'Coming soon'), findsOneWidget);
      expect(find.widgetWithText(CategoryStatusMenu, 'Available'), findsNWidgets(4));
      expect(find.text('Coming soon via its parent'), findsOneWidget);
      expect(find.text('Note: Arriving before Easter'), findsOneWidget);
      expect(find.textContaining("customers see a 'coming soon' page instead of products"), findsOneWidget);
      expect(find.textContaining('Seasonal ·'), findsOneWidget);
      expect(find.text('New category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in ${mode.name} at 1280 px with no overflow in the page', (tester) async {
      final db = await seeded();
      final errors = await errorsOutsideCoreNav(
          () => pumpAdminScreen(tester, const CategoriesScreen(), db: db, mode: mode, size: const Size(1280, 900)));
      expect(errors, isEmpty);
      expect(find.text('Mugs'), findsOneWidget);
    });
  }

  testWidgets('filter chips and search narrow the list', (tester) async {
    await pumpAdminScreen(tester, const CategoriesScreen(), db: await seeded());
    await tester.tap(find.widgetWithText(ChoiceChip, 'Occasion'));
    await settle(tester);
    expect(find.text("Mother's Day"), findsOneWidget);
    expect(find.text('Mugs'), findsNothing);
    expect(find.textContaining('to reorder'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.enterText(find.widgetWithText(TextField, 'Search by title'), 'fram');
    await settle(tester);
    expect(find.text('Frames'), findsOneWidget);
    expect(find.text('Mugs'), findsNothing);
  });

  testWidgets('the status menu switches a row to Coming soon in one batch with a category.status entry',
      (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const CategoriesScreen(), db: db, size: const Size(1000, 1200));
    final framesRow = find.ancestor(of: find.text('Frames'), matching: find.byType(Card));
    await tester.tap(find.descendant(of: framesRow, matching: find.byType(CategoryStatusMenu)));
    await settle(tester);
    expect(find.text("Still listed, but customers see a 'coming soon' page instead of products."), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Coming soon'));
    await settle(tester);

    final doc = (await db.doc('categories/frames').get()).data()!;
    expect(doc['comingSoon'], isTrue);
    expect(doc['isActive'], isTrue);
    expect(doc['comingSoonSince'], isNotNull);
    final audit = (await auditEntries(db)).single;
    expect(audit['action'], 'category.status');
    expect((audit['after'] as Map)['status'], 'comingSoon');
    expect(find.textContaining('is now Coming soon'), findsOneWidget);
    expect(find.descendant(of: framesRow, matching: find.text('Coming soon')), findsOneWidget);
  });

  testWidgets('"Coming soon" filter chip lists only coming-soon categories', (tester) async {
    await pumpAdminScreen(tester, const CategoriesScreen(), db: await seeded());
    await tester.tap(find.widgetWithText(ChoiceChip, 'Coming soon'));
    await settle(tester);
    expect(find.text('Easter Day'), findsOneWidget);
    expect(find.text('Mugs'), findsNothing);
    expect(find.text('Painted Eggs'), findsNothing);
  });

  testWidgets('editor: Coming soon shows the optional note; saving stores it, Available clears it', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const CategoriesScreen(), db: db, size: const Size(1000, 1400));
    final framesRow = find.ancestor(of: find.text('Frames'), matching: find.byType(Card));
    await tester.tap(find.descendant(of: framesRow, matching: find.byTooltip('Edit')));
    await settle(tester);
    expect(find.byKey(const ValueKey('coming-soon-note')), findsNothing);
    expect(find.text('Shown in the app with its products.'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('category-status')), matching: find.text('Coming soon')));
    await settle(tester);
    expect(find.text("Still listed, but customers see a 'coming soon' page instead of products."), findsOneWidget);
    expect(find.byKey(const ValueKey('coming-soon-note')), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Coming-soon note (optional) · English'), 'Back in December');
    await tester.enterText(find.widgetWithText(TextFormField, 'Coming-soon note (optional) · کوردی'), 'لە مانگی دیسەمبەر دەگەڕێتەوە');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(tester.takeException(), isNull);

    var doc = (await db.doc('categories/frames').get()).data()!;
    expect(doc['comingSoon'], isTrue);
    expect(doc['comingSoonNote'], 'Back in December');
    expect(doc['comingSoonNoteKu'], 'لە مانگی دیسەمبەر دەگەڕێتەوە');
    expect(doc.containsKey('comingSoonNoteAr'), isFalse);
    expect(doc['comingSoonSince'], isNotNull);
    expect((await auditEntries(db)).single['action'], 'category.update');

    // Reopen: the note is there; switch to Available and save → note and since are gone.
    await tester.tap(find.descendant(of: framesRow, matching: find.byTooltip('Edit')));
    await settle(tester);
    expect(find.text('Back in December'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('category-status')), matching: find.text('Available')));
    await settle(tester);
    expect(find.byKey(const ValueKey('coming-soon-note')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    doc = (await db.doc('categories/frames').get()).data()!;
    expect(doc['comingSoon'], isFalse);
    expect(doc.containsKey('comingSoonNote'), isFalse);
    expect(doc.containsKey('comingSoonNoteKu'), isFalse);
    expect(doc.containsKey('comingSoonSince'), isFalse);
  });

  testWidgets('new category: id follows the English title, then saves with an audit entry', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const CategoriesScreen(), db: db);
    await tester.tap(find.text('New category'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'dialog fits at 800 px');

    await tester.enterText(find.widgetWithText(TextFormField, 'Title · English *'), "Teacher's Day");
    await settle(tester);
    final idField = tester.widget<TextFormField>(find.byKey(const ValueKey('category-id')));
    expect(idField.controller!.text, 'teachers-day');

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);
    final doc = await db.doc('categories/teachers-day').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['sortOrder'], 6);
    expect((await auditEntries(db)).single['action'], 'category.create');
  });

  testWidgets('new category with a taken id is refused', (tester) async {
    final db = await seeded();
    await pumpAdminScreen(tester, const CategoriesScreen(), db: db);
    await tester.tap(find.text('New category'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Title · English *'), 'Frames');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);
    expect(find.textContaining('already used'), findsWidgets);
    expect(await auditEntries(db), isEmpty);
  });
}

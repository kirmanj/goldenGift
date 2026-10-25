import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/promo_code_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/promo_codes/data/promo_codes_data.dart';
import 'package:golden_gift_admin/features/promo_codes/promo_codes_screen.dart';

import '../categories/admin_test_harness.dart';
import '../users/users_test_helpers.dart';

final _future = DateTime.now().add(const Duration(days: 30));
final _past = DateTime(2025, 1, 1);

PromoCodeModel promo({
  String code = 'EID10',
  String title = 'Eid offer',
  PromoType type = PromoType.percent,
  int value = 10,
  int? maxDiscount,
  int? minOrder,
  int? usageLimit,
  int usageCount = 0,
  int perUserLimit = 1,
  bool isActive = true,
  bool isPublic = true,
  List<String> categoryIds = const [],
  DateTime? expiresAt,
  bool noExpiry = false,
}) =>
    PromoCodeModel(
      code: code,
      title: LocalizedText(title),
      type: type,
      value: value,
      maxDiscount: maxDiscount,
      minOrder: minOrder,
      usageLimit: usageLimit,
      usageCount: usageCount,
      perUserLimit: perUserLimit,
      isActive: isActive,
      isPublic: isPublic,
      categoryIds: categoryIds,
      expiresAt: noExpiry ? null : (expiresAt ?? _future),
    );

Future<void> seedPromo(FakeFirebaseFirestore db, PromoCodeModel p, {Map<String, dynamic> extra = const {}}) =>
    db.doc('${FirestorePaths.promoCodes}/${p.code}').set({...p.toMap(), 'usageCount': p.usageCount, ...extra});

Future<Map<String, dynamic>?> promoDoc(FakeFirebaseFirestore db, String code) async =>
    (await db.doc('${FirestorePaths.promoCodes}/$code').get()).data();

Finder badge(String label) => find.descendant(of: find.byType(PromoStatusBadge), matching: find.text(label));

Finder field(String key) => find.byKey(ValueKey(key));

/// Row actions can sit beyond the window on a wide table.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

void main() {
  final now = DateTime.now();

  group('validatePromo', () {
    List<String> v(PromoCodeModel p, {bool isNew = true, Iterable<String> taken = const []}) =>
        validatePromo(p, isNew: isNew, now: now, takenCodes: taken);

    test('percent must be 1–100', () {
      expect(v(promo(value: 0)), contains('A percent discount must be between 1 and 100'));
      expect(v(promo(value: 101)), contains('A percent discount must be between 1 and 100'));
      expect(v(promo(value: 1)), isEmpty);
      expect(v(promo(value: 100)), isEmpty);
      expect(v(promo(maxDiscount: 0)), contains('Max discount must be more than 0 (or empty for no cap)'));
    });

    test('fixed must be at least 250 IQD and has no max discount', () {
      expect(v(promo(type: PromoType.fixed, value: 249)).single, contains('at least 250 IQD'));
      expect(v(promo(type: PromoType.fixed, value: 250)), isEmpty);
      expect(v(promo(type: PromoType.fixed, value: 5000, maxDiscount: 1000)), contains('Max discount only applies to percent codes'));
    });

    test('code format and uniqueness on create only', () {
      expect(validatePromoCode('ab'), isNotNull);
      expect(validatePromoCode('eid 10'), isNull); // normalized to EID10
      expect(validatePromoCode('EID_10'), isNotNull);
      expect(validatePromoCode('A' * 21), isNotNull);
      expect(validatePromoCode('NEW-YEAR-2027'), isNull);
      expect(v(promo(), taken: ['EID10']), ['Code: The code EID10 already exists']);
      expect(v(promo(), isNew: false, taken: ['EID10']), isEmpty);
    });

    test('expiry is required and must be in the future on create', () {
      expect(v(promo(noExpiry: true)), contains('Pick an expiry date and time'));
      expect(v(promo(expiresAt: _past)), contains('The expiry must be in the future'));
      expect(v(promo(expiresAt: _past), isNew: false), isEmpty);
    });

    test('limits', () {
      expect(v(promo(usageLimit: 0)), contains('Usage limit must be at least 1 (leave it empty for unlimited)'));
      expect(v(promo(usageLimit: 1, perUserLimit: 0)), isEmpty);
      expect(v(promo(title: ' ')), contains('English title is required'));
    });
  });

  group('promoStatus', () {
    test('live, inactive, expired, used up — in PromoRules order', () {
      expect(promoStatus(promo(), now), PromoStatus.live);
      expect(promoStatus(promo(isActive: false), now), PromoStatus.inactive);
      expect(promoStatus(promo(expiresAt: _past), now), PromoStatus.expired);
      expect(promoStatus(promo(usageLimit: 3, usageCount: 3), now), PromoStatus.usedUp);
      expect(promoStatus(promo(usageLimit: 3, usageCount: 2), now), PromoStatus.live);
      expect(promoStatus(promo(isActive: false, expiresAt: _past), now), PromoStatus.inactive);
      expect(promoStatus(promo(expiresAt: _past, usageLimit: 1, usageCount: 1), now), PromoStatus.expired);
    });

    test('sort puts live codes first, then by code', () {
      final sorted = sortPromos([
        promo(code: 'ZZZ'),
        promo(code: 'OLD', expiresAt: _past),
        promo(code: 'AAA'),
        promo(code: 'OFF', isActive: false),
      ], now);
      expect(sorted.map((p) => p.code), ['AAA', 'ZZZ', 'OFF', 'OLD']);
    });

    test('labels', () {
      expect(promoDiscountLabel(promo(maxDiscount: 5000)), '10% (max 5,000 IQD)');
      expect(promoDiscountLabel(promo(type: PromoType.fixed, value: 3000)), '3,000 IQD off');
      expect(promoUsesLabel(promo(usageCount: 2)), '2 / ∞');
      expect(promoUsesLabel(promo(usageCount: 2, usageLimit: 10)), '2 / 10');
    });
  });

  group('PromoAdminRepository', () {
    test('create writes toMap + usageCount 0 + timestamps and the audit entry in ONE batch', () async {
      final db = SpyFirestore();
      final p = promo(maxDiscount: 5000, minOrder: 20000, usageLimit: 100);
      await PromoAdminRepository(db, adminUid: 'admin-1').create(p);

      expect(db.batches, hasLength(1));
      final batch = db.batches.single;
      expect(batch.committed, isTrue);
      expect(batch.ops.map((o) => (o.$1, o.$2.split('/').first)), [('set', 'promo_codes'), ('set', 'admin_audit_log')]);
      final written = batch.ops.first.$3 as Map<String, dynamic>;
      expect(written['usageCount'], 0);
      expect(written['createdAt'], isA<FieldValue>());
      for (final e in p.toMap().entries) {
        expect(written[e.key], e.value, reason: e.key);
      }

      final saved = (await promoDoc(db, 'EID10'))!;
      expect(saved['usageCount'], 0);
      expect(saved['value'], 10);
      expect(saved['maxDiscount'], 5000);
      expect(saved['createdAt'], isA<Timestamp>());
      final audit = await auditEntries(db);
      expect(audit.single['action'], 'promo.create');
      expect(audit.single['target'], 'promo_codes/EID10');
      expect((audit.single['after'] as Map)['usageCount'], 0);
      expect(audit.single['adminUid'], 'admin-1');
    });

    test('create rejects a duplicate code and writes nothing', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo(usageCount: 3));
      await expectLater(
          PromoAdminRepository(db, adminUid: 'admin-1').create(promo(title: 'Other')), throwsA(isA<PromoCodeTakenException>()));
      expect(db.batches, isEmpty);
      expect((await promoDoc(db, 'EID10'))!['title'], 'Eid offer');
      expect(await auditEntries(db), isEmpty);
    });

    test('create refuses invalid codes', () async {
      final db = SpyFirestore();
      await expectLater(
          PromoAdminRepository(db, adminUid: 'admin-1').create(promo(value: 150)), throwsA(isA<PromoValidationException>()));
      expect(db.batches, isEmpty);
    });

    test('update never writes usageCount and deletes cleared translations', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo(usageCount: 7), extra: {'titleAr': 'عرض العيد', 'createdAt': Timestamp.fromDate(DateTime(2026))});
      // The model in hand is stale (usageCount 3) — the stored counter must survive.
      final before = promo(usageCount: 3);
      final after = promo(usageCount: 3, value: 15, perUserLimit: 0);
      await PromoAdminRepository(db, adminUid: 'admin-1').update(before, after);

      expect(db.batches, hasLength(1));
      final data = db.batches.single.ops.first.$3 as Map<String, dynamic>;
      expect(db.batches.single.ops.first.$1, 'update');
      expect(data.containsKey('usageCount'), isFalse);
      expect(data.containsKey('createdAt'), isFalse);

      final saved = (await promoDoc(db, 'EID10'))!;
      expect(saved['usageCount'], 7);
      expect(saved['value'], 15);
      expect(saved['perUserLimit'], 0);
      expect(saved.containsKey('titleAr'), isFalse);
      expect(saved['createdAt'], isA<Timestamp>());
      final audit = await auditEntries(db);
      expect(audit.single['action'], 'promo.update');
      expect((audit.single['before'] as Map)['value'], 10);
      expect((audit.single['after'] as Map)['value'], 15);
    });

    test('a code cannot be renamed', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo());
      await expectLater(PromoAdminRepository(db, adminUid: 'admin-1').update(promo(), promo(code: 'EID20')), throwsArgumentError);
    });

    test('toggle writes isActive with a promo.toggle entry', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo());
      await PromoAdminRepository(db, adminUid: 'admin-1').setActive(promo(), false);
      expect((await promoDoc(db, 'EID10'))!['isActive'], isFalse);
      final audit = await auditEntries(db);
      expect(audit.single['action'], 'promo.toggle');
      expect(audit.single['before'], {'isActive': true});
      expect(audit.single['after'], {'isActive': false});
      expect(db.batches, hasLength(1));
    });

    test('delete is refused once the stored counter shows a use', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo(usageCount: 2));
      // The list said 0 uses, but an order used it since.
      await expectLater(PromoAdminRepository(db, adminUid: 'admin-1').delete(promo()), throwsA(isA<PromoInUseException>()));
      expect(await promoDoc(db, 'EID10'), isNotNull);
      expect(await auditEntries(db), isEmpty);
    });

    test('delete removes an unused code with a promo.delete entry', () async {
      final db = SpyFirestore();
      await seedPromo(db, promo());
      await PromoAdminRepository(db, adminUid: 'admin-1').delete(promo());
      expect(await promoDoc(db, 'EID10'), isNull);
      final audit = await auditEntries(db);
      expect(audit.single['action'], 'promo.delete');
      expect((audit.single['before'] as Map)['code'], 'EID10');
    });

    test('usage report: orders with the code, newest first, and totals without cancelled orders', () async {
      final db = FakeFirebaseFirestore();
      Future<void> order(String id, String status, int discount, int total, DateTime at, {String code = 'EID10'}) =>
          db.doc(FirestorePaths.orderDoc(id)).set(orderData(
              number: 'GG-$id', status: status, promoCode: code, discount: discount, total: total, createdAt: at));
      await order('o1', 'delivered', 5000, 50000, DateTime(2026, 10, 20));
      await order('o2', 'cancelledByBuyer', 3000, 30000, DateTime(2026, 10, 21));
      await order('o3', 'pending', 2000, 20000, DateTime(2026, 10, 19));
      await order('o4', 'delivered', 9000, 90000, DateTime(2026, 10, 22), code: 'OTHER');

      final list = await PromoAdminRepository(db, adminUid: 'a').watchUsage('EID10').first;
      expect(list.map((o) => o.id), ['o2', 'o1', 'o3']);
      final totals = PromoUsageTotals.of(list);
      expect(totals.orders, 3);
      expect(totals.counted, 2);
      expect(totals.excluded, 1);
      expect(totals.discount, 7000);
      expect(totals.revenue, 70000);
    });
  });

  group('PromoCodesScreen', () {
    testWidgets('lists every code with its status badge and filters by status', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo(usageCount: 4));
      await seedPromo(db, promo(code: 'OLD5', expiresAt: _past));
      await seedPromo(db, promo(code: 'FULL', usageLimit: 2, usageCount: 2));
      await seedPromo(db, promo(code: 'OFF', isActive: false, isPublic: false));
      await pumpWith(tester, const PromoCodesScreen(), db: db);

      for (final label in ['Live', 'Expired', 'Used up', 'Inactive']) {
        expect(badge(label), findsOneWidget, reason: label);
      }
      expect(find.text('4 / ∞'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Percent · 10%'), findsNWidgets(4));
      expect(find.text('Private'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Expired'));
      await settle(tester);
      expect(find.text('OLD5'), findsOneWidget);
      expect(find.text('EID10'), findsNothing);
      expect(find.text('1 of 4'), findsOneWidget);
    });

    testWidgets('editing through the dialog keeps the usage counter', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo(usageCount: 4));
      await pumpWith(tester, const PromoCodesScreen(), db: db, size: const Size(1440, 2400));

      await tapVisible(tester, find.byTooltip('Edit'));
      expect(find.text('Edit EID10'), findsOneWidget);
      final codeField = tester.widget<TextField>(find.descendant(of: field('promo-code'), matching: find.byType(TextField)));
      expect(codeField.enabled, isFalse);
      await tester.enterText(field('promo-value-percent'), '15');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Edit EID10'), findsNothing);
      final saved = (await promoDoc(db, 'EID10'))!;
      expect(saved['value'], 15);
      expect(saved['usageCount'], 4);
      expect((await auditEntries(db)).single['action'], 'promo.update');
    });

    testWidgets('create dialog enforces percent bounds, the expiry and a unique code', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo());
      await pumpWith(tester, const PromoCodesScreen(), db: db, size: const Size(1440, 2400));

      await tester.tap(find.text('New promo code'));
      await settle(tester);
      await tester.enterText(field('promo-code'), 'eid10');
      expect(tester.widget<TextField>(find.descendant(of: field('promo-code'), matching: find.byType(TextField))).controller!.text,
          'EID10');
      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Title · English *'), 'Big sale');
      await tester.enterText(field('promo-value-percent'), '101');
      await tester.tap(find.text('Create'));
      await settle(tester);
      expect(find.text('The code EID10 already exists'), findsOneWidget);
      expect(find.text('Between 1 and 100'), findsOneWidget);
      expect(find.textContaining('Pick an expiry date and time'), findsOneWidget);
      expect((await db.collection(FirestorePaths.promoCodes).get()).docs, hasLength(1));
      expect(await auditEntries(db), isEmpty);
    });

    testWidgets('the preview runs PromoRules on the sample cart', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo(maxDiscount: 4000, minOrder: 20000, categoryIds: ['mugs']));
      await pumpWith(tester, const PromoCodesScreen(), db: db, size: const Size(1440, 2400));
      await tapVisible(tester, find.byTooltip('Edit'));

      Text result() => tester.widget<Text>(field('preview-result'));
      // 10% of 50,000 = 5,000, capped at 4,000.
      expect(result().data, 'Discount 4,000 IQD — the customer pays 46,000 IQD before delivery.');

      await tester.enterText(field('preview-subtotal'), '10000');
      await settle(tester);
      expect(result().data, 'Not applied: Below the minimum order of 20,000 IQD.');

      await tester.enterText(field('preview-subtotal'), '30000');
      final matchSwitch = find.text('Cart lines match the category / store restriction');
      await tester.ensureVisible(matchSwitch);
      await tester.tap(matchSwitch);
      await settle(tester);
      expect(result().data, 'Not applied: No cart line matches the category / store restriction.');
    });

    testWidgets('a used code cannot be deleted — deactivating is offered', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo(usageCount: 4));
      await pumpWith(tester, const PromoCodesScreen(), db: db);

      await tapVisible(tester, find.byTooltip('Delete'));
      expect(find.text('EID10 has been used'), findsOneWidget);
      await tester.tap(find.text('Deactivate'));
      await settle(tester);
      expect(await promoDoc(db, 'EID10'), isNotNull);
      expect((await promoDoc(db, 'EID10'))!['isActive'], isFalse);
      expect((await auditEntries(db)).single['action'], 'promo.toggle');
    });

    testWidgets('an unused code is deleted after confirming', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo());
      await pumpWith(tester, const PromoCodesScreen(), db: db);
      await tapVisible(tester, find.byTooltip('Delete'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      expect(await promoDoc(db, 'EID10'), isNull);
      expect((await auditEntries(db)).single['action'], 'promo.delete');
    });

    testWidgets('finance is read-only but sees the usage report', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo(usageCount: 1));
      await db.doc(FirestorePaths.orderDoc('o1')).set(orderData(promoCode: 'EID10', discount: 5000, total: 50000));
      await pumpWith(tester, const PromoCodesScreen(), db: db, session: sessionAs(AdminRole.finance));

      expect(find.textContaining('Read-only'), findsOneWidget);
      expect(find.text('New promo code'), findsNothing);
      expect(find.byTooltip('Edit'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);

      await tapVisible(tester, find.byTooltip('Usage report'));
      expect(find.text('Usage — EID10'), findsOneWidget);
      expect(find.text('GG-2610-00001'), findsOneWidget);
      expect(find.text('50,000 IQD'), findsWidgets); // revenue + order total
      expect(find.text('1 / ∞'), findsNWidgets(2)); // table + report tile
    });

    testWidgets('content editors may edit; sellers are locked out', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedPromo(db, promo());
      await pumpWith(tester, const PromoCodesScreen(), db: db, session: sessionAs(AdminRole.content));
      expect(find.text('New promo code'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);

      // Sellers are stopped by AdminScaffold's seller gate and by PromoAccess.
      await pumpWith(tester, const PromoCodesScreen(), db: db, session: sessionAs(AdminRole.seller));
      expect(find.text('EID10'), findsNothing);
      expect(find.text('New promo code'), findsNothing);
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final width in [800.0, 1440.0]) {
        testWidgets('table, editor and usage report render in ${mode.name} at $width px', (tester) async {
          final db = FakeFirebaseFirestore();
          await seedPromo(db, promo(usageCount: 1, maxDiscount: 5000, categoryIds: ['mugs']));
          await seedPromo(db, promo(code: 'OLD5', expiresAt: _past, type: PromoType.fixed, value: 5000));
          await db.doc(FirestorePaths.orderDoc('o1')).set(orderData(promoCode: 'EID10', discount: 5000));
          final errors = await errorsOutsideCoreNav(() async {
            await pumpWith(tester, const PromoCodesScreen(), db: db, mode: mode, size: Size(width, 1000));
            expect(badge('Live'), findsOneWidget);
            await tapVisible(tester, find.byTooltip('Edit').first);
            expect(find.text('Preview'), findsOneWidget);
            await tester.tap(find.byTooltip('Close'));
            await settle(tester);
            await tapVisible(tester, find.byTooltip('Usage report').first);
            expect(find.text('Discount given'), findsOneWidget);
          });
          expect(errors, isEmpty);
        });
      }
    }
  });
}

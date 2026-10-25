import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/store_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/stores/data/phone_input.dart';
import 'package:golden_gift_admin/features/stores/data/stores_admin_repository.dart';
import 'package:golden_gift_admin/features/stores/store_detail_screen.dart';
import 'package:golden_gift_admin/features/stores/stores_screen.dart';

import '../products/products_test_helpers.dart' show RecordingFirestore;
import '../seller/phase8_test_harness.dart';

Future<void> seedApplication(FirebaseFirestore db, String storeId) => db.doc(FirestorePaths.storeApplication(storeId)).set({
      'storeName': 'Wood & Words',
      'ownerName': 'Hawre Aziz',
      'phone': '+9647501112233',
      'city': 'erbil',
      'category': 'Engraved wood',
      'instagram': 'woodandwords',
      'samplePhotos': ['https://example.com/s1.jpg', 'https://example.com/s2.jpg'],
      'submittedAt': Timestamp.fromDate(DateTime(2026, 10, 18, 10)),
    });

void main() {
  // cloud_firestore's FieldValue caches its platform factory on first use;
  // make it the fake one before any test builds a FieldValue.
  setUpAll(FakeFirebaseFirestore.new);

  group('sales', () {
    test('only this store’s lines count; cancelled / returned lines do not; commission estimate', () {
      final orders = [
        OrderModel.fromMap('o1', multiStoreOrder()),
        OrderModel.fromMap('o2', multiStoreOrder(number: 'GG-2', aStatus: 'cancelledBySeller')),
        OrderModel.fromMap('o3', {
          ...multiStoreOrder(number: 'GG-3'),
          'storeIds': ['store-b'],
          'items': [orderLine('x', 'store-b', unitPrice: 99000)],
        }),
      ];
      final sales = StoreSales.of(orders, 'store-a', 12.5);
      expect(sales.orderCount, 2);
      expect(sales.itemCount, 2);
      expect(sales.total, 30000, reason: '2 × 15,000 from o1; the cancelled o2 line and store-b lines are ignored');
      expect(sales.commissionDue, 3750);
      expect(storeSalesTotal(orders.first, 'store-b'), 42000);
      expect(storeLines(orders.first, 'store-a').single.line.titleSnapshot.en, 'Engraved Mug');
    });
  });

  group('validation', () {
    test('commission 0–50, reasons, phones', () {
      expect(validateCommission(null), isNotNull);
      expect(validateCommission(-1), isNotNull);
      expect(validateCommission(50.5), isNotNull);
      expect(validateCommission(0), isNull);
      expect(validateCommission(50), isNull);
      expect(validateReason(''), 'A reason is required.');
      expect(validateReason('no'), startsWith('Give a reason'));
      expect(validateReason('Fake photos'), isNull);
      expect(normalizeStaffPhone('0750 111 2233'), '+9647501112233');
      expect(normalizeStaffPhone('+44 20 7946 0958'), '+442079460958');
      expect(normalizeStaffPhone('12'), isNull);
      expect(validateStaffPhone(''), isNull);
      expect(validateStaffPhone('', required: true), 'Required');
    });

    test('profile update rules', () {
      const ok = StoreProfileUpdate(name: LocalizedText('Wood & Words'), phone: '0750 111 2233', commissionPercent: 15);
      expect(ok.validate(), isEmpty);
      expect(const StoreProfileUpdate(name: LocalizedText(' ')).validate(), contains('English store name is required.'));
      expect(const StoreProfileUpdate(name: LocalizedText('A'), phone: '99').validate(), contains('The phone number is not valid.'));
      expect(const StoreProfileUpdate(name: LocalizedText('A'), commissionPercent: 70).validate().single, startsWith('Commission'));
      expect(ok.changes()['phone'], '+9647501112233');
      expect(const StoreProfileUpdate(name: LocalizedText('A')).changes().containsKey('commissionPercent'), isFalse);
    });
  });

  group('repository', () {
    test('profile update = store update + store.update audit in ONE batch; cleared translation deleted', () async {
      final db = RecordingFirestore();
      await seedStore(db, 'store-a', name: 'Old name');
      await db.doc('stores/store-a').update({'nameAr': 'قديم'});
      final before = StoreModel.fromMap('store-a', (await db.doc('stores/store-a').get()).data()!);
      db.commits.clear();
      await StoresAdminRepository(db, FakeCallables().call).updateProfile(
        before,
        const StoreProfileUpdate(name: LocalizedText('Wood & Words'), city: 'duhok', commissionPercent: 20),
        actorUid: 'admin-1',
      );
      expect(db.commits.single, ['update stores/store-a', startsWith('set admin_audit_log/')]);
      final saved = (await db.doc('stores/store-a').get()).data()!;
      expect(saved['name'], 'Wood & Words');
      expect(saved.containsKey('nameAr'), isFalse);
      expect(saved['city'], 'duhok');
      expect(saved['commissionPercent'], 20);
      expect(saved['status'], 'active', reason: 'status / counters are never touched');
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'store.update');
      expect((audit['before'] as Map)['name'], 'Old name');
      expect((audit['after'] as Map)['commissionPercent'], 20);
    });

    test('invalid profile → nothing written', () async {
      final db = RecordingFirestore();
      await seedStore(db, 'store-a');
      db.commits.clear();
      final before = StoreModel.fromMap('store-a', (await db.doc('stores/store-a').get()).data()!);
      await expectLater(
        StoresAdminRepository(db, FakeCallables().call)
            .updateProfile(before, const StoreProfileUpdate(name: LocalizedText('')), actorUid: 'a'),
        throwsArgumentError,
      );
      expect(db.commits, isEmpty);
    });

    test('approve / reject / suspend / reactivate payloads; required fields never reach the server', () async {
      final calls = FakeCallables()
        ..responses['reviewPartner'] = {'storeId': 's1', 'status': 'active'}
        ..responses['setStoreStatus'] = {'storeId': 's1', 'status': 'suspended'};
      final repo = StoresAdminRepository(FakeFirebaseFirestore(), calls.call);

      expect(await repo.approve('s1', 12.5), 'active');
      await repo.reject('s1', '  Photos are not original  ');
      await repo.setStatus('s1', StoreStatus.suspended, 'Late deliveries');
      await repo.setStatus('s1', StoreStatus.active, 'Resolved with the owner');
      expect(calls.calls.map((c) => c.$1), ['reviewPartner', 'reviewPartner', 'setStoreStatus', 'setStoreStatus']);
      expect(calls.calls[0].$2, {'storeId': 's1', 'decision': 'approve', 'commissionPercent': 12.5});
      expect(calls.calls[1].$2, {'storeId': 's1', 'decision': 'reject', 'reason': 'Photos are not original'});
      expect(calls.calls[2].$2, {'storeId': 's1', 'status': 'suspended', 'reason': 'Late deliveries'});
      expect(calls.calls[3].$2, {'storeId': 's1', 'status': 'active', 'reason': 'Resolved with the owner'});

      calls.calls.clear();
      expect(() => repo.approve('s1', 60), throwsArgumentError);
      expect(() => repo.reject('s1', ' '), throwsArgumentError);
      expect(() => repo.setStatus('s1', StoreStatus.suspended, ''), throwsArgumentError);
      expect(() => repo.setStatus('s1', StoreStatus.pendingApproval, 'Because'), throwsArgumentError);
      expect(calls.calls, isEmpty);
    });

    test('lists by status: pending oldest first, others by name', () async {
      final db = FakeFirebaseFirestore();
      await seedStore(db, 'p2', name: 'Bravo', status: 'pendingApproval', createdAt: DateTime(2026, 10, 2));
      await seedStore(db, 'p1', name: 'Zulu', status: 'pendingApproval', createdAt: DateTime(2026, 10, 1));
      await seedStore(db, 'a2', name: 'Zeta');
      await seedStore(db, 'a1', name: 'Alpha');
      final repo = StoresAdminRepository(db, FakeCallables().call);
      expect((await repo.watchByStatus(StoreStatus.pendingApproval).first).map((r) => r.store.id), ['p1', 'p2']);
      expect((await repo.watchByStatus(StoreStatus.active).first).map((r) => r.store.id), ['a1', 'a2']);
      expect(StoresAccess.canReview(AdminRole.finance), isFalse);
      expect(StoresAccess.canReview(AdminRole.ops), isTrue);
    });
  });

  group('screens', () {
    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      await db.doc('app_settings/cities').set({
        'items': [
          {'id': 'erbil', 'name': 'Erbil', 'deliveryFee': 3000, 'isActive': true},
          {'id': 'duhok', 'name': 'Duhok', 'deliveryFee': 4000, 'isActive': true},
        ],
      });
      await seedStore(db, 'pending-1', name: 'Wood & Words', status: 'pendingApproval', commission: 0);
      await seedApplication(db, 'pending-1');
      await seedStore(db, 'store-a', name: 'Store A', commission: 10);
      await seedStore(db, 'store-s', name: 'Sleepy Store', status: 'suspended');
      await db.doc('orders/o1').set(multiStoreOrder());
      return db;
    }

    testWidgets('list: pending tab first with the owner from the application; tabs; row opens the store', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const StoresScreen(), db: db, size: const Size(1440, 1000));
      expect(find.text('Pending applications (1)'), findsOneWidget);
      expect(find.text('Wood & Words'), findsOneWidget);
      expect(find.text('Hawre Aziz'), findsOneWidget);
      expect(find.text('Store A'), findsNothing);
      await tester.tap(find.text('Active'));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Store A'), findsOneWidget);
      await tester.tap(find.text('Store A'));
      await settle(tester);
      expect(find.text('visited: /stores/store-a'), findsOneWidget);
    });

    testWidgets('pending store: application details, approve with commission → reviewPartner', (tester) async {
      final db = await seeded();
      final calls = FakeCallables()..responses['reviewPartner'] = {'storeId': 'pending-1', 'status': 'active'};
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'pending-1'), db: db, calls: calls, size: const Size(1440, 1400));
      expect(find.text('Application'), findsOneWidget);
      expect(find.text('Engraved wood'), findsOneWidget);
      expect(find.text('Sample photos (2)'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(find.text('15'), findsOneWidget, reason: 'provisional default commission');
      await tester.enterText(find.byKey(const ValueKey('approveCommission')), '80');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await settle(tester);
      expect(find.textContaining('Commission must be between 0 and 50'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('approveCommission')), '12');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await settle(tester);
      expect(calls.payloadsFor('reviewPartner').single, {'storeId': 'pending-1', 'decision': 'approve', 'commissionPercent': 12.0});
    });

    testWidgets('pending store: reject needs a reason, then goes back to the list', (tester) async {
      final db = await seeded();
      final calls = FakeCallables()..responses['reviewPartner'] = {'storeId': 'pending-1', 'status': 'rejected'};
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'pending-1'), db: db, calls: calls, size: const Size(1440, 1400));
      await tester.tap(find.text('Reject'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await settle(tester);
      expect(find.text('A reason is required.'), findsOneWidget);
      expect(calls.calls, isEmpty);
      await tester.enterText(find.byKey(const ValueKey('reasonField')), 'Photos are not original');
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await settle(tester);
      expect(calls.payloadsFor('reviewPartner').single,
          {'storeId': 'pending-1', 'decision': 'reject', 'reason': 'Photos are not original'});
      expect(find.text('visited: /stores'), findsOneWidget);
    });

    testWidgets('active store: suspend → setStoreStatus; a missing function is explained', (tester) async {
      final db = await seeded();
      final calls = FakeCallables()
        ..errors['setStoreStatus'] = FirebaseFunctionsException(code: 'unimplemented', message: 'UNIMPLEMENTED');
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'store-a'), db: db, calls: calls, size: const Size(1440, 1400));
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.text('Suspend'));
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('reasonField')), 'Late deliveries');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await settle(tester);
      expect(calls.payloadsFor('setStoreStatus').single, {'storeId': 'store-a', 'status': 'suspended', 'reason': 'Late deliveries'});
      expect(find.text('The setStoreStatus function is not deployed yet.'), findsOneWidget);
    });

    testWidgets('profile editor saves with audit; sales card counts only this store’s lines', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'store-a'), db: db, size: const Size(1440, 1600));
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('30,000 IQD'), findsWidgets, reason: 'store-a lines of o1 (store-b’s 42,000 is ignored)');
      expect(find.text('3,000 IQD'), findsOneWidget, reason: '10 % commission estimate');

      await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Store name · English *'),
          'Store A Deluxe');
      await tester.enterText(find.byKey(const ValueKey('storeCommission')), '18');
      await tester.tap(find.text('Save profile'));
      await settle(tester);
      final saved = (await db.doc('stores/store-a').get()).data()!;
      expect(saved['name'], 'Store A Deluxe');
      expect(saved['commissionPercent'], 18);
      expect((await auditEntries(db)).single['action'], 'store.update');
    });

    testWidgets('roles without review rights see no actions and a read-only profile', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'pending-1'),
          db: db, session: staffSession(AdminRole.finance), size: const Size(1440, 1400));
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Save profile'), findsNothing);
      expect(find.text('Your role can view this store but not approve or suspend it.'), findsOneWidget);
    });

    testWidgets('a deleted (rejected) store shows a note', (tester) async {
      final db = await seeded();
      await pumpPhase8(tester, const StoreDetailScreen(storeId: 'gone'), db: db);
      expect(find.textContaining('doesn’t exist'), findsOneWidget);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('list + detail lay out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
        final db = await seeded();
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const StoresScreen(), db: db, mode: mode, size: size);
          expect(find.text('Wood & Words'), findsOneWidget);
          await pumpPhase8(tester, const StoreDetailScreen(storeId: 'pending-1'), db: db, mode: mode, size: size);
          expect(find.text('Application'), findsOneWidget);
          await pumpPhase8(tester, const StoreDetailScreen(storeId: 'store-a'), db: db, mode: mode, size: size);
          expect(find.text('Store profile'), findsOneWidget);
        });
        expect(errors, isEmpty);
      });
    }
  });
}

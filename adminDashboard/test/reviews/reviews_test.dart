import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/reviews/data/reviews_admin_repository.dart';
import 'package:golden_gift_admin/features/reviews/review_detail_panel.dart';
import 'package:golden_gift_admin/features/reviews/reviews_screen.dart';

import '../products/products_test_helpers.dart' show RecordingFirestore;
import '../seller/phase8_test_harness.dart';

Map<String, dynamic> reviewMap({
  required String productId,
  String storeId = 'store-a',
  String userName = 'Sara',
  int rating = 5,
  bool approved = false,
  String text = 'Beautiful engraving, arrived on time.\nWould order again.',
  int images = 2,
  String orderId = 'o1',
  DateTime? at,
}) =>
    {
      'productId': productId,
      'userId': 'cust-$userName',
      'userName': userName,
      'storeId': storeId,
      'rating': rating,
      'text': text,
      'images': [for (var i = 0; i < images; i++) 'https://example.com/r/$i.jpg'],
      'orderId': orderId,
      'isApproved': approved,
      'createdAt': Timestamp.fromDate(at ?? DateTime(2026, 10, 20, 12)),
    };

Future<void> seedReview(FirebaseFirestore db, String productId, String id, Map<String, dynamic> data) =>
    db.doc('${FirestorePaths.productReviews(productId)}/$id').set(data);

/// Two products in two stores, five reviews (three pending).
Future<FakeFirebaseFirestore> reviewsWorld([FakeFirebaseFirestore? db]) async {
  final d = db ?? FakeFirebaseFirestore();
  await seedStore(d, 'store-a', name: 'Atelier A');
  await seedStore(d, 'store-b', name: 'Bazaar B');
  await d.doc('products/p1').set({'title': 'Engraved Mug', 'storeId': 'store-a', 'price': 15000});
  await d.doc('products/p2').set({'title': 'Walnut Frame', 'storeId': 'store-b', 'price': 42000});
  await d.doc('orders/o1').set(multiStoreOrder());
  await seedReview(d, 'p1', 'o1_sara', reviewMap(productId: 'p1', at: DateTime(2026, 10, 20, 12)));
  await seedReview(d, 'p1', 'o2_omar',
      reviewMap(productId: 'p1', userName: 'Omar', rating: 2, text: 'Text was misspelled', at: DateTime(2026, 10, 19)));
  await seedReview(d, 'p2', 'o3_lana',
      reviewMap(productId: 'p2', storeId: 'store-b', userName: 'Lana', rating: 4, at: DateTime(2026, 10, 21)));
  await seedReview(d, 'p1', 'o4_dara',
      reviewMap(productId: 'p1', userName: 'Dara', rating: 5, approved: true, images: 0, at: DateTime(2026, 10, 18)));
  await seedReview(d, 'p2', 'o5_zhin',
      reviewMap(productId: 'p2', storeId: 'store-b', userName: 'Zhin', rating: 3, approved: true, at: DateTime(2026, 10, 17)));
  return d;
}

Future<List<String>> names(ReviewsAdminRepository repo, ReviewFilters f) async =>
    [for (final r in await repo.watch(f).first) r.review.userName];

void main() {
  group('queue', () {
    test('pending first by default, newest first; approval / rating / store filters', () async {
      final db = await reviewsWorld();
      final repo = ReviewsAdminRepository(db);
      expect(await names(repo, const ReviewFilters()), ['Lana', 'Sara', 'Omar']);
      expect(await names(repo, const ReviewFilters(approval: ReviewApproval.approved)), ['Dara', 'Zhin']);
      expect(await names(repo, const ReviewFilters(approval: ReviewApproval.all)), ['Lana', 'Sara', 'Omar', 'Dara', 'Zhin']);
      expect(await names(repo, const ReviewFilters(approval: ReviewApproval.all, rating: 5)), ['Sara', 'Dara']);
      expect(await names(repo, const ReviewFilters(storeId: 'store-b')), ['Lana']);
      expect(await names(repo, const ReviewFilters(approval: ReviewApproval.all, storeId: 'store-b', rating: 3)), ['Zhin']);
    });

    test('a product filter reads that product’s reviews and applies the rest on the client', () async {
      final db = await reviewsWorld();
      final repo = ReviewsAdminRepository(db);
      expect(await names(repo, const ReviewFilters(productId: 'p1')), ['Sara', 'Omar']);
      expect(await names(repo, const ReviewFilters(productId: 'p1', approval: ReviewApproval.all)), ['Sara', 'Omar', 'Dara']);
      expect(await names(repo, const ReviewFilters(productId: 'p1', rating: 2)), ['Omar']);
      expect(await names(repo, const ReviewFilters(productId: 'nope')), isEmpty);
      final r = (await repo.watch(const ReviewFilters(productId: 'p2')).first).single;
      expect(r.review.productId, 'p2', reason: 'from the parent path');
      expect(r.path, 'products/p2/reviews/o3_lana');
    });
  });

  group('moderation writes', () {
    test('approve / hide: isApproved + moderatedBy/At and the audit entry in one batch', () async {
      final db = await reviewsWorld(RecordingFirestore()) as RecordingFirestore;
      final repo = ReviewsAdminRepository(db);
      final sara = (await repo.watch(const ReviewFilters(productId: 'p1')).first).first;
      db.commits.clear();
      await repo.setApproved(sara, true, adminUid: 'admin-1');
      expect(db.commits, [
        ['update products/p1/reviews/o1_sara', startsWith('set admin_audit_log/')],
      ]);
      final doc = (await db.doc('products/p1/reviews/o1_sara').get()).data()!;
      expect(doc['isApproved'], isTrue);
      expect(doc['moderatedBy'], 'admin-1');
      expect(doc['moderatedAt'], isA<Timestamp>());
      expect(doc.containsKey('ratingAvg'), isFalse, reason: 'aggregates belong to onReviewWrite');

      final approved = AdminReview.fromSnapshot(await db.doc('products/p1/reviews/o1_sara').get());
      await repo.setApproved(approved, false, adminUid: 'admin-1');
      expect((await db.doc('products/p1/reviews/o1_sara').get()).data()!['isApproved'], isFalse);
      final audit = await auditEntries(db);
      expect(audit.map((e) => e['action']), ['review.approve', 'review.hide']);
      expect(audit.first['target'], 'products/p1/reviews/o1_sara');
      expect(audit.first['before'], {'isApproved': false});
      expect(audit.first['after'], containsPair('isApproved', true));
      expect(audit.last['before'], {'isApproved': true});
    });

    test('bulk approve skips approved reviews; one audit entry per review', () async {
      final db = await reviewsWorld();
      final repo = ReviewsAdminRepository(db);
      final all = await repo.watch(const ReviewFilters(approval: ReviewApproval.all)).first;
      final result = await repo.bulkApprove(all, adminUid: 'admin-1');
      expect((result.approved, result.skipped, result.batches), (3, 2, 1));
      expect(await names(repo, const ReviewFilters()), isEmpty);
      final audit = await auditEntries(db);
      expect(audit, hasLength(3));
      expect(audit.every((e) => e['action'] == 'review.approve'), isTrue);
      expect({for (final e in audit) e['target']}, {
        'products/p1/reviews/o1_sara',
        'products/p1/reviews/o2_omar',
        'products/p2/reviews/o3_lana',
      });
    });

    test('bulk approve stays at ≤ 450 writes per batch', () async {
      final db = RecordingFirestore();
      for (var i = 0; i < 230; i++) {
        await seedReview(db, 'p1', 'r$i', reviewMap(productId: 'p1', at: DateTime(2026, 10, 1).add(Duration(minutes: i))));
      }
      final repo = ReviewsAdminRepository(db);
      final pending = await repo.watch(const ReviewFilters(productId: 'p1'), limit: 500).first;
      expect(pending, hasLength(200), reason: 'the per-product queue scans the newest 200');
      final all = [
        for (final d in (await db.collection('products/p1/reviews').get()).docs) AdminReview.fromSnapshot(d),
      ];
      db.commits.clear();
      final result = await repo.bulkApprove(all, adminUid: 'admin-1');
      expect(result.batches, 2);
      expect(db.commits.map((c) => c.length), [450, 10]);
      expect(await auditEntries(db), hasLength(230));
    });
  });

  group('screen', () {
    testWidgets('pending queue rows: stars, name, product, store, excerpt, photos, order link', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(1440, 1000));
      expect(find.text('Lana'), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('Dara'), findsNothing, reason: 'approved — not in the pending queue');
      expect(find.text('Engraved Mug'), findsNWidgets(2));
      expect(find.text('Walnut Frame'), findsOneWidget);
      expect(find.text('Bazaar B'), findsOneWidget);
      expect(find.text('Beautiful engraving, arrived on time.'), findsNWidgets(2));
      expect(find.text(' 2 photos'), findsNWidgets(3));
      expect(find.text('Order'), findsNWidgets(3));

      await tester.tap(find.text('Approved'));
      await settle(tester);
      expect(find.text('Dara'), findsOneWidget);
      expect(find.text('Lana'), findsNothing);

      await tester.tap(find.text('All').first);
      await settle(tester);
      expect(find.text('Zhin'), findsOneWidget);
      expect(find.text('Omar'), findsOneWidget);
    });

    testWidgets('approve from the row writes the review and the audit', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(1440, 1000));
      await tester.tap(find.byTooltip('Approve').first); // Lana (newest)
      await settle(tester);
      expect((await db.doc('products/p2/reviews/o3_lana').get()).data()!['isApproved'], isTrue);
      expect(find.text('Lana'), findsNothing, reason: 'left the pending queue');
      expect((await auditEntries(db)).single['action'], 'review.approve');
    });

    testWidgets('select rows and bulk approve them', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(1440, 1000));
      final rowBoxes = find.descendant(of: find.byType(ReviewRow), matching: find.byType(Checkbox));
      await tester.tap(rowBoxes.at(0));
      await tester.tap(rowBoxes.at(2));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.text('Approve 2'));
      await settle(tester);
      expect(find.text('Approve 2 reviews?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await settle(tester);
      expect((await db.doc('products/p2/reviews/o3_lana').get()).data()!['isApproved'], isTrue);
      expect((await db.doc('products/p1/reviews/o2_omar').get()).data()!['isApproved'], isTrue);
      expect((await db.doc('products/p1/reviews/o1_sara').get()).data()!['isApproved'], isFalse);
      expect(await auditEntries(db), hasLength(2));
      expect(find.text('Sara'), findsOneWidget);

      // Select-all ticks every pending row.
      await tester.tap(find.byKey(const ValueKey('selectAllReviews')));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('detail panel: full text, photos, customer, order; product link opens the editor', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(1440, 1000));
      await tester.tap(find.text('Sara'));
      await settle(tester);
      expect(find.text('Beautiful engraving, arrived on time.\nWould order again.'), findsOneWidget);
      expect(find.text('GG-2610-00001'), findsOneWidget, reason: 'order summary');
      expect(find.text('cust-Sara'), findsOneWidget);
      expect(find.byTooltip('Open full size'), findsNWidgets(2));

      await tester.tap(find.descendant(of: find.byType(ReviewDetailPanel), matching: find.text('Approve')));
      await settle(tester);
      expect((await db.doc('products/p1/reviews/o1_sara').get()).data()!['isApproved'], isTrue);
      expect(find.descendant(of: find.byType(ReviewDetailPanel), matching: find.text('Hide')), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(ReviewDetailPanel), matching: find.text('Engraved Mug')));
      await settle(tester);
      expect(find.text('visited: /products/p1'), findsOneWidget);
    });

    testWidgets('narrow window: the detail opens in a dialog; the order opens from it', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(800, 1200));
      await tester.tap(find.text('Lana'));
      await settle(tester);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('Open order'));
      await settle(tester);
      expect(find.text('Customer & delivery'), findsOneWidget, reason: 'the Orders detail panel');
    });

    testWidgets('product filter by id shows the product title', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, size: const Size(1440, 1000));
      await tester.enterText(find.byKey(const ValueKey('reviewProductFilter')), 'p2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text('Lana'), findsOneWidget);
      expect(find.text('Sara'), findsNothing);
      expect(find.text('Walnut Frame'), findsNWidgets(2), reason: 'helper text + row');

      await tester.tap(find.byTooltip('Clear product'));
      await settle(tester);
      expect(find.text('Sara'), findsOneWidget);
    });

    testWidgets('finance sees the queue read-only', (tester) async {
      final db = await reviewsWorld();
      await pumpPhase8(tester, const ReviewsScreen(), db: db, session: staffSession(AdminRole.finance), size: const Size(1440, 1000));
      expect(find.text('Lana'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byTooltip('Approve'), findsNothing);
      await tester.tap(find.text('Lana'));
      await settle(tester);
      expect(find.text('Your role can view reviews but not moderate them.'), findsOneWidget);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('lays out in ${mode.name} at ${size.width.toInt()} px', (tester) async {
        final db = await reviewsWorld();
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const ReviewsScreen(), db: db, mode: mode, size: size);
          await tester.tap(find.text('Sara'));
          await settle(tester);
          expect(find.text('Customer & product'), findsOneWidget);
        });
        expect(errors, isEmpty);
      });
    }
  });
}

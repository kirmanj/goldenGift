import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/notifications/data/notifications_repository.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

import 'firestore_read_counter.dart';
import 'qa_harness.dart';

/// Phase 10 performance guard — SRS §8 "Firestore reads per Home open ≤ 60
/// docs".
///
/// How it is measured: the real app is opened on Home (`/main`, so the Cart
/// and Profile tabs of the IndexedStack are built too) over a catalogue far
/// bigger than any section shows — 150 more products, 40 more categories,
/// banners, gift-card templates and broadcast notifications, 40 wishlist
/// items — with Firestore wrapped in a [CountingFirestore] that counts
/// documents the way Firestore bills them (see firestore_read_counter.dart).
///
/// * Home's content (banners, categories, Popular / Featured / For you, gift
///   cards, Discover's first page) is the budget: ≤ 60 documents.
/// * Session listeners that Home happens to start first are bounded too:
///   one doc per `app_settings/*`, profile and wallet; the bell's newest
///   [NotificationsRepository.bellLimit] notifications. The customer's own
///   cart and wishlist lines scale with their own data and are not counted.

const _homeBudget = 60;

Future<FakeFirebaseFirestore> _bigWorld() async {
  final db = await seedQaWorld();
  final batch = db.batch();
  for (var i = 0; i < 150; i++) {
    final p = ProductModel(
      id: 'bulk$i',
      title: LocalizedText('Bulk gift $i', ar: 'هدية $i', ku: 'دیاری $i'),
      storeId: 's1',
      categoryIds: [i.isEven ? 'mugs' : 'flowers'],
      price: 5000 + i * 1000,
      compareAtPrice: i % 3 == 0 ? 9000 + i * 1000 : null,
      isFeatured: i.isEven,
      salesCount: i,
    );
    batch.set(db.doc('products/${p.id}'), {
      ...p.toMap(),
      ...ProductDerived.of(p),
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1).add(Duration(hours: i))),
    });
  }
  for (var i = 0; i < 40; i++) {
    final at = Timestamp.fromDate(DateTime(2026, 9, 1).add(Duration(days: i)));
    batch
      ..set(db.doc('categories/bulk$i'),
          {'title': 'Category $i', 'titleAr': 'فئة $i', 'titleKu': 'پۆل $i', 'sortOrder': 20 + i, 'isActive': true})
      ..set(db.doc('banners/bulk$i'), {
        'imageUrl': '',
        'placement': ['homeTop', 'homeMid1', 'homeMid2', 'homeBottom'][i % 4],
        'action': {'type': 'route', 'value': '/special-requests'},
        'sortOrder': i,
        'isActive': true,
      })
      ..set(db.doc('gift_card_templates/bulk$i'),
          {'name': 'Template $i', 'presetAmounts': [25000], 'sortOrder': 10 + i, 'isActive': true})
      ..set(db.doc('notifications/bulk$i'),
          {'userId': 'all', 'title': 'Broadcast $i', 'body': 'Body', 'type': 'broadcast', 'isRead': false, 'createdAt': at})
      ..set(db.doc('wishlists/$qaUid/items/bulk$i'),
          {'productId': 'bulk$i', 'title': 'Bulk gift $i', 'price': 5000, 'listId': 'default', 'addedAt': at});
  }
  await batch.commit();
  return db;
}

/// Home's content queries (catalogue collections, minus the cart's id lookups).
bool _isHomeContent(String what) =>
    RegExp(r'^(listen|get) (products|categories|banners|gift_card_templates) ').hasMatch(what) &&
    !what.contains('where id');

/// The customer's own documents (scale with their own data).
bool _isOwnData(String what) =>
    what.contains('carts/$qaUid') || what.contains('wishlists/$qaUid') || what.contains('where id');

void main() {
  for (final guest in [true, false]) {
    testWidgets('Home open stays within the read budget (${guest ? 'guest' : 'signed in'})', (tester) async {
      final counter = ReadCounter();
      final app = await pumpQaApp(tester,
          location: '/main?tab=0',
          guest: guest,
          firestore: await _bigWorld(),
          wrapFirestore: (db) => CountingFirestore(db, counter));
      await unmountQaApp(tester, app);

      final content = {for (final e in counter.reads.entries) if (_isHomeContent(e.key)) e.key: e.value};
      final contentTotal = content.values.fold(0, (a, b) => a + b);
      expect(contentTotal, lessThanOrEqualTo(_homeBudget),
          reason: 'Home content read $contentTotal docs (budget $_homeBudget):\n${counter.report()}');
      // Every section really loaded (so the budget isn't met by accident).
      for (final collection in ['products', 'categories', 'banners', 'gift_card_templates']) {
        expect(content.keys.where((k) => k.contains(' $collection ')), isNotEmpty, reason: collection);
      }

      final others = {
        for (final e in counter.reads.entries)
          if (!_isHomeContent(e.key) && !_isOwnData(e.key)) e.key: e.value,
      };
      for (final MapEntry(key: what, value: docs) in others.entries) {
        final cap = what.contains('notifications') ? NotificationsRepository.bellLimit : 1;
        expect(docs, lessThanOrEqualTo(cap), reason: '$what read $docs docs:\n${counter.report()}');
      }
    });
  }
}

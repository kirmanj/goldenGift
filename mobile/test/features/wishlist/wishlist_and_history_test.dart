import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/product_details/data/product_repository.dart';
import 'package:golden_gift/features/wishlist/data/wishlist_repository.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductModel _p(String id, List<String> categories) => ProductModel(
      id: id,
      title: LocalizedText(id, ar: '$id-ar'),
      storeId: 's1',
      price: 12000,
      images: const ['https://x/1.jpg'],
      categoryIds: categories,
    );

void main() {
  test('wishlist: wishlists/{uid}/items/{productId} with a denormalized card (SRS §6.6)', () async {
    final db = FakeFirebaseFirestore();
    final repo = WishlistRepository(db);
    await repo.add('u1', _p('mug', ['mugs']));
    final doc = await db.doc('wishlists/u1/items/mug').get();
    expect(doc.data()!['listId'], 'default');
    expect(doc.data()!['titleAr'], 'mug-ar');
    expect(doc.data()!['image'], 'https://x/1.jpg');

    final items = await repo.watch('u1').first;
    expect(items.single.productId, 'mug');
    expect(items.single.price, 12000);

    await repo.remove('u1', 'mug');
    expect(await repo.watch('u1').first, isEmpty);
  });

  test('view history ranks categories and survives restarts (For you, SRS §5.4)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final history = ViewHistory(prefs);
    expect(history.topCategory, isNull);
    history.recordView(_p('a', ['mugs']));
    history.recordView(_p('b', ['frames', 'love']));
    history.recordView(_p('c', ['frames']));
    expect(history.topCategory, 'frames');
    expect(ViewHistory(prefs).state, {'frames': 2, 'mugs': 1, 'love': 1});
    history.recordView(_p('uncategorized', []));
    expect(history.state['frames'], 2);
  });
}

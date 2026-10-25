import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/reviews/data/reviews_repository.dart';

void main() {
  test('submit writes one pending review per order + customer with the first name only', () async {
    final db = FakeFirebaseFirestore();
    final repo = ReviewsRepository(db);
    await repo.submit(
      productId: 'p1',
      orderId: 'o1',
      uid: 'u1',
      userName: 'Sara Ahmed',
      storeId: 's1',
      rating: 9,
      text: '  Beautiful!  ',
      images: List.filled(5, 'https://img'),
    );
    final mine = await repo.mine(productId: 'p1', orderId: 'o1', uid: 'u1');
    expect(mine!.id, 'o1_u1');
    expect(mine.userName, 'Sara');
    expect(mine.rating, 5);
    expect(mine.text, 'Beautiful!');
    expect(mine.images, hasLength(3));
    expect(mine.isApproved, isFalse);
    // Not listed until approved.
    expect(await repo.watchApproved('p1').first, isEmpty);
  });

  test('approved reviews newest first', () async {
    final db = FakeFirebaseFirestore();
    Future<void> add(String id, bool approved, DateTime at) => db.doc('${FirestorePaths.productReviews('p1')}/$id').set({
          'userId': id,
          'userName': 'U$id',
          'storeId': 's1',
          'rating': 4,
          'orderId': 'o$id',
          'isApproved': approved,
          'createdAt': Timestamp.fromDate(at),
        });
    await add('a', true, DateTime(2026, 9, 1));
    await add('b', false, DateTime(2026, 10, 1));
    await add('c', true, DateTime(2026, 10, 2));
    final list = await ReviewsRepository(db).watchApproved('p1').first;
    expect(list.map((r) => r.id), ['c', 'a']);
    expect(list.first.productId, 'p1');
  });
}

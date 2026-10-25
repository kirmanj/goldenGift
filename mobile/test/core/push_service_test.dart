import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/services/push_service.dart';

void main() {
  test('push is never fatal: without a Firebase app register and unregister just return', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(FirestorePaths.userDoc('u1')).set({'fcmTokens': ['t1']});
    final opened = <String>[];
    final push = PushService(() => throw StateError('no Firebase app'), db, opened.add);

    await push.register('u1');
    await push.unregister('u1');

    expect((await db.doc(FirestorePaths.userDoc('u1')).get()).data()!['fcmTokens'], ['t1']);
    expect(opened, isEmpty);
  });
}

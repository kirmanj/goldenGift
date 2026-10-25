import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/notifications/data/notifications_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('broadcast read / hide state (device-local) re-emits the list', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = FakeFirebaseFirestore();
    await db.doc('${FirestorePaths.notifications}/b1').set({
      'userId': 'all',
      'title': 'Sale',
      'body': 'Now',
      'type': 'broadcast',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
    });
    await db.doc('${FirestorePaths.notifications}/n1').set({
      'userId': 'u1',
      'title': 'Order',
      'body': 'Confirmed',
      'type': 'orderStatus',
      'isRead': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
    });
    final repo = NotificationsRepository(db, prefs);
    final emissions = <List<String>>[];
    final sub = repo.watch('u1').listen((l) => emissions.add([for (final n in l) '${n.id}:${n.isRead}']));
    await pumpEventQueue();
    expect(emissions.last, ['n1:false', 'b1:false']);

    final first = (await repo.watch('u1').first).last;
    await repo.markRead(first);
    await pumpEventQueue();
    expect(emissions.last, ['n1:false', 'b1:true']);

    await repo.remove(first);
    await pumpEventQueue();
    expect(emissions.last, ['n1:false']);

    await sub.cancel();
    repo.dispose();
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/referrals/data/referrals_repository.dart';

void main() {
  test('only my referrals, newest first, with successful / pending counts', () async {
    final db = FakeFirebaseFirestore();
    Future<void> add(String id, String referrer, String status, DateTime at) =>
        db.doc('${FirestorePaths.referrals}/$id').set({
          'referrerUid': referrer,
          'referredUid': id,
          'code': 'ABC123',
          'status': status,
          'createdAt': Timestamp.fromDate(at),
        });
    await add('f1', 'me', 'completed', DateTime(2026, 9, 1));
    await add('f2', 'me', 'pending', DateTime(2026, 10, 1));
    await add('f3', 'me', 'cancelled', DateTime(2026, 10, 2));
    await add('f4', 'someone', 'completed', DateTime(2026, 10, 3));

    final list = await ReferralsRepository(db).watchMine('me').first;
    expect(list.map((r) => r.id), ['f3', 'f2', 'f1']);
    final stats = ReferralStats.of(list);
    expect(stats.successful, 1);
    expect(stats.pending, 1);
    expect(list.last.status, ReferralStatus.completed);
  });

  test('share link format (SRS §4.6)', () {
    expect(ReferralsRepository.link('AB12CD'), 'https://goldengift.app/r/AB12CD');
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/partners/data/partner_repository.dart';

void main() {
  test('submit trims, strips @ from Instagram, caps photos and returns the store id', () async {
    final sent = <Map<String, dynamic>>[];
    final repo = PartnerRepository(FakeFirebaseFirestore(), (name, data) async {
      expect(name, 'submitPartnerApplication');
      sent.add(data);
      return {'storeId': 's9'};
    });
    final id = await repo.submit(PartnerApplication(
      storeName: ' Wood & Co ',
      ownerName: 'Karwan',
      phone: '+9647501234567',
      city: 'erbil',
      category: 'Engraved wood',
      instagram: '@woodandco',
      samplePhotos: List.generate(8, (i) => 'https://img/$i.jpg'),
    ));
    expect(id, 's9');
    expect(sent.single['storeName'], 'Wood & Co');
    expect(sent.single['instagram'], 'woodandco');
    expect(sent.single['samplePhotos'], hasLength(5));
  });

  test('failures: already applied / not deployed', () async {
    Future<PartnerFailureReason> reasonFor(String code) async {
      try {
        await PartnerRepository(FakeFirebaseFirestore(), (_, __) async => throw FirebaseFunctionsException(code: code, message: ''))
            .submit(const PartnerApplication(storeName: 'a', ownerName: 'b', phone: '+964', city: 'erbil', category: 'c'));
      } on PartnerFailure catch (f) {
        return f.reason;
      }
      fail('expected PartnerFailure');
    }

    expect(await reasonFor('already-exists'), PartnerFailureReason.alreadyApplied);
    expect(await reasonFor('not-found'), PartnerFailureReason.unavailable);
  });

  test('my application status follows the store doc', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(FirestorePaths.storeDoc('s9')).set({'name': 'Wood & Co', 'ownerUid': 'u1', 'status': 'pendingApproval'});
    final mine = await PartnerRepository(db, (_, __) async => null).watchMine('u1').first;
    expect(mine?.status, StoreStatus.pendingApproval);
    expect(await PartnerRepository(db, (_, __) async => null).watchMine('u2').first, isNull);
  });
}

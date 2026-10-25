import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/features/wallet/data/wallet_repository.dart';
import 'package:golden_gift/models/wallet_model.dart';

void main() {
  test('a missing wallet reads as 0 / 0 until onUserCreate creates it', () async {
    final repo = WalletRepository(FakeFirebaseFirestore());
    final w = await repo.watch('u1').first;
    expect(w.balance, 0);
    expect(w.credits, 0);
    expect(w.spendable, 0);
  });

  test('balance, credits and transactions newest first', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(FirestorePaths.walletDoc('u1')).set({'balance': 12000, 'credits': 5000, 'currency': 'IQD'});
    Future<void> txn(String id, int amount, String bucket, String type, DateTime at) =>
        db.collection(FirestorePaths.walletTxns('u1')).doc(id).set({
          'type': type,
          'amount': amount,
          'bucket': bucket,
          'title': 'T $id',
          'titleAr': 'ع $id',
          'balanceAfter': 12000,
          'creditsAfter': 5000,
          'createdAt': Timestamp.fromDate(at),
        });
    await txn('a', 5000, 'credits', 'referralCredit', DateTime(2026, 10, 1));
    await txn('b', 12000, 'balance', 'refund', DateTime(2026, 10, 5));

    final repo = WalletRepository(db);
    final w = await repo.watch('u1').first;
    expect(w.spendable, 17000);
    final list = await repo.watchTransactions('u1').first;
    expect(list.map((t) => t.id), ['b', 'a']);
    expect(list.first.type, WalletTxnType.refund);
    expect(list.first.bucket, WalletBucket.balance);
    expect(list.last.title.ar, 'ع a');
    expect(list.last.isCredit, isTrue);
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/wallet_model.dart';

/// Read-only wallet access (SRS §5.18, §6.11: only functions / admins write).
class WalletRepository {
  WalletRepository(this._db);
  final FirebaseFirestore _db;

  Stream<WalletModel> watch(String uid) => _db
      .doc(FirestorePaths.walletDoc(uid))
      .snapshots()
      .map((s) => s.exists ? WalletModel.fromMap(s.data()!) : WalletModel.empty);

  Stream<List<WalletTxn>> watchTransactions(String uid, {int limit = 100}) => _db
      .collection(FirestorePaths.walletTxns(uid))
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) WalletTxn.fromMap(d.id, d.data())]);
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) => WalletRepository(ref.watch(firestoreProvider)));

/// The signed-in customer's wallet; 0 / 0 for guests and until `onUserCreate`
/// has created it (AUTH-3).
final walletProvider = StreamProvider<WalletModel>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(WalletModel.empty);
  return ref.watch(walletRepositoryProvider).watch(uid);
});

final walletTransactionsProvider = StreamProvider.autoDispose<List<WalletTxn>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(walletRepositoryProvider).watchTransactions(uid);
});

/// Cart / checkout "Use my credits" toggle (SRS §5.10); on by default.
final useCreditsProvider = StateProvider<bool>((ref) => true);

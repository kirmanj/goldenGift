import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../models/referral_model.dart';

/// Invite & Earn data (SRS §5.19). `referrals` are readable only through a
/// query filtered to the signed-in referrer (§6.17).
class ReferralsRepository {
  ReferralsRepository(this._db);
  final FirebaseFirestore _db;

  /// Newest first (sorted here, so the query needs no composite index).
  Stream<List<ReferralModel>> watchMine(String uid) =>
      _db.collection(FirestorePaths.referrals).where('referrerUid', isEqualTo: uid).limit(200).snapshots().map((s) => [
            for (final d in s.docs) ReferralModel.fromMap(d.id, d.data())
          ]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0))));

  /// The public link that pre-fills the code on Sign Up (SRS §4.6).
  static String link(String code) => 'https://goldengift.app/r/$code';
}

class ReferralStats {
  const ReferralStats({this.successful = 0, this.pending = 0});
  final int successful;
  final int pending;

  factory ReferralStats.of(List<ReferralModel> referrals) => ReferralStats(
        successful: referrals.where((r) => r.status == ReferralStatus.completed).length,
        pending: referrals.where((r) => r.status == ReferralStatus.pending).length,
      );
}

final referralsRepositoryProvider =
    Provider<ReferralsRepository>((ref) => ReferralsRepository(ref.watch(firestoreProvider)));

final myReferralsProvider = StreamProvider.autoDispose<List<ReferralModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(referralsRepositoryProvider).watchMine(uid);
});

final referralStatsProvider = Provider.autoDispose<ReferralStats>(
    (ref) => ReferralStats.of(ref.watch(myReferralsProvider).valueOrNull ?? const []));

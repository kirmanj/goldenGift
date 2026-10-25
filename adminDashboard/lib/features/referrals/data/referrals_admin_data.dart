import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/referral_model.dart';

import '../../../core/session/admin_session.dart';

/// Referrals module (SRS §9): ops, finance and super admins.
class ReferralAccess {
  ReferralAccess._();
  static bool canView(AdminRole r) => r == AdminRole.superAdmin || r == AdminRole.ops || r == AdminRole.finance;
}

/// Counts for the summary tiles (aggregate queries — one read per 1,000 docs).
class ReferralSummary {
  const ReferralSummary({
    this.total = 0,
    this.pending = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.joinBonusesPaid = 0,
    this.orderBonusesPaid = 0,
  });

  final int total;
  final int pending;
  final int completed;
  final int cancelled;
  final int joinBonusesPaid;
  final int orderBonusesPaid;

  /// Estimate at today's amounts: bonuses paid × the current settings (the
  /// amounts may have changed since some were paid).
  int creditsPaidEstimate(ReferralSettings s) => joinBonusesPaid * s.joinBonus + orderBonusesPaid * s.orderBonus;
}

/// Read-only: referrals are written by `onUserCreate` / `onOrderStatusChange`.
class ReferralsAdminRepository {
  ReferralsAdminRepository(this._db);
  final FirebaseFirestore _db;

  static const pageSize = 50;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(FirestorePaths.referrals);

  /// Newest first. With a status: index referrals (status ASC, createdAt DESC).
  Query<Map<String, dynamic>> query(ReferralStatus? status) {
    Query<Map<String, dynamic>> q = _col;
    if (status != null) q = q.where('status', isEqualTo: status.name);
    return q.orderBy('createdAt', descending: true);
  }

  Stream<List<ReferralModel>> watch(ReferralStatus? status, {int limit = pageSize}) => query(status)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final d in s.docs) ReferralModel.fromMap(d.id, d.data())]);

  Future<ReferralSummary> summary() async {
    Future<int> count(Query<Map<String, dynamic>> q) async => (await q.count().get()).count ?? 0;
    final results = await Future.wait([
      count(_col),
      count(_col.where('status', isEqualTo: ReferralStatus.pending.name)),
      count(_col.where('status', isEqualTo: ReferralStatus.completed.name)),
      count(_col.where('status', isEqualTo: ReferralStatus.cancelled.name)),
      count(_col.where('joinBonusPaid', isEqualTo: true)),
      count(_col.where('orderBonusPaid', isEqualTo: true)),
    ]);
    return ReferralSummary(
      total: results[0],
      pending: results[1],
      completed: results[2],
      cancelled: results[3],
      joinBonusesPaid: results[4],
      orderBonusesPaid: results[5],
    );
  }
}

final referralsAdminRepositoryProvider =
    Provider<ReferralsAdminRepository>((ref) => ReferralsAdminRepository(ref.watch(firestoreProvider)));

final adminReferralsProvider = StreamProvider.autoDispose.family<List<ReferralModel>, (ReferralStatus?, int)>(
    (ref, args) => ref.watch(referralsAdminRepositoryProvider).watch(args.$1, limit: args.$2));

final referralSummaryProvider =
    FutureProvider.autoDispose<ReferralSummary>((ref) => ref.watch(referralsAdminRepositoryProvider).summary());

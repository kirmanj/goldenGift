import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';

/// `referrals/{id}` (SRS §5.19, §6.12). Created by `onUserCreate`, completed
/// by `onOrderStatusChange`; readable only by the referrer (and admins).
class ReferralModel {
  const ReferralModel({
    required this.id,
    required this.referrerUid,
    required this.referredUid,
    required this.code,
    this.referredName,
    this.status = ReferralStatus.pending,
    this.joinBonusPaid = false,
    this.orderBonusPaid = false,
    this.firstOrderId,
    this.flags = const [],
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String referrerUid;
  final String referredUid;
  final String code;

  /// First name of the friend, for the referrer's list.
  final String? referredName;
  final ReferralStatus status;
  final bool joinBonusPaid;
  final bool orderBonusPaid;
  final String? firstOrderId;

  /// Abuse signals raised by the functions (e.g. `sameDevice`, `monthlyCap`).
  final List<String> flags;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory ReferralModel.fromMap(String id, Map<String, dynamic> map) => ReferralModel(
        id: id,
        referrerUid: map['referrerUid'] as String? ?? '',
        referredUid: map['referredUid'] as String? ?? '',
        code: map['code'] as String? ?? '',
        referredName: FirestoreParse.stringOrNull(map['referredName']),
        status: FirestoreParse.enumValue(ReferralStatus.values, map['status'], ReferralStatus.pending),
        joinBonusPaid: FirestoreParse.boolean(map['joinBonusPaid']),
        orderBonusPaid: FirestoreParse.boolean(map['orderBonusPaid']),
        firstOrderId: FirestoreParse.stringOrNull(map['firstOrderId']),
        flags: FirestoreParse.stringList(map['flags']),
        createdAt: FirestoreParse.date(map['createdAt']),
        completedAt: FirestoreParse.date(map['completedAt']),
      );
}

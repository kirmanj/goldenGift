import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// Which part of the wallet a transaction moved (SRS §6.11).
enum WalletBucket { balance, credits }

/// `wallets/{uid}` (SRS §5.18, §6.11): `balance` is real money (refunds,
/// top-ups), `credits` promotional (referrals, gift cards). Written only by
/// Cloud Functions; the app streams it and shows 0 until it exists (AUTH-3).
class WalletModel {
  const WalletModel({this.balance = 0, this.credits = 0, this.currency = 'IQD'});

  final int balance;
  final int credits;
  final String currency;

  static const empty = WalletModel();

  /// What checkout can spend (credits are consumed first).
  int get spendable => balance + credits;

  factory WalletModel.fromMap(Map<String, dynamic> map) => WalletModel(
        balance: FirestoreParse.integer(map['balance']),
        credits: FirestoreParse.integer(map['credits']),
        currency: map['currency'] as String? ?? 'IQD',
      );
}

/// `wallets/{uid}/transactions/{id}`.
class WalletTxn {
  const WalletTxn({
    required this.id,
    required this.type,
    required this.amount,
    required this.bucket,
    required this.title,
    this.orderId,
    this.referralId,
    this.giftCardId,
    this.byUid,
    this.reason,
    required this.balanceAfter,
    required this.creditsAfter,
    this.createdAt,
  });

  final String id;
  final WalletTxnType type;

  /// Signed: + credit, − debit.
  final int amount;
  final WalletBucket bucket;
  final LocalizedText title;
  final String? orderId;
  final String? referralId;
  final String? giftCardId;

  /// Admin who made an `adminAdjustment`.
  final String? byUid;

  /// Admin's reason for an adjustment (shown in the dashboard only).
  final String? reason;
  final int balanceAfter;
  final int creditsAfter;
  final DateTime? createdAt;

  bool get isCredit => amount > 0;

  factory WalletTxn.fromMap(String id, Map<String, dynamic> map) => WalletTxn(
        id: id,
        type: FirestoreParse.enumValue(WalletTxnType.values, map['type'], WalletTxnType.adminAdjustment),
        amount: FirestoreParse.integer(map['amount']),
        bucket: FirestoreParse.enumValue(WalletBucket.values, map['bucket'], WalletBucket.balance),
        title: LocalizedText.fromMap(map, 'title'),
        orderId: FirestoreParse.stringOrNull(map['orderId']),
        referralId: FirestoreParse.stringOrNull(map['referralId']),
        giftCardId: FirestoreParse.stringOrNull(map['giftCardId']),
        byUid: FirestoreParse.stringOrNull(map['byUid']),
        reason: FirestoreParse.stringOrNull(map['reason']),
        balanceAfter: FirestoreParse.integer(map['balanceAfter']),
        creditsAfter: FirestoreParse.integer(map['creditsAfter']),
        createdAt: FirestoreParse.date(map['createdAt']),
      );
}

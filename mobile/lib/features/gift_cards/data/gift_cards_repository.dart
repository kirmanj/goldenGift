import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/firestore_paths.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../core/services/callable.dart';
import '../../../models/gift_card_model.dart';
import '../../orders/data/orders_repository.dart';

/// What the Designer sends to `purchaseGiftCard` (SRS §5.22). The server
/// validates the template + amount and creates an order with
/// `orderType = giftCard`; `issueGiftCard` creates the card once it is paid.
class GiftCardPurchase {
  const GiftCardPurchase({
    required this.clientRequestId,
    required this.templateId,
    required this.amount,
    required this.recipientName,
    this.recipientPhone,
    this.recipientEmail,
    this.message = '',
    this.photoUrl,
    this.scheduledAt,
    this.paymentMethod = PaymentMethod.cashOnDelivery,
    this.addressId,
  });

  final String clientRequestId;
  final String templateId;
  final int amount;
  final String recipientName;
  final String? recipientPhone;
  final String? recipientEmail;
  final String message;
  final String? photoUrl;

  /// Send later; null = as soon as it is paid.
  final DateTime? scheduledAt;
  final PaymentMethod paymentMethod;

  /// Where the courier collects cash on delivery (the buyer's address).
  final String? addressId;

  static const maxMessage = 200;

  Map<String, dynamic> toMap() => {
        'clientRequestId': clientRequestId,
        'templateId': templateId,
        'amount': amount,
        'recipientName': recipientName.trim(),
        'recipientPhone': (recipientPhone?.trim().isEmpty ?? true) ? null : recipientPhone!.trim(),
        'recipientEmail': (recipientEmail?.trim().isEmpty ?? true) ? null : recipientEmail!.trim().toLowerCase(),
        'message': message.trim(),
        'photoUrl': photoUrl,
        'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        'paymentMethod': paymentMethod.name,
        'addressId': addressId,
      };
}

enum RedeemFailureReason { notFound, expired, alreadyRedeemed, disabled, notYetSent, tooManyAttempts, unavailable, network, unknown }

class RedeemFailure implements Exception {
  const RedeemFailure(this.reason);
  final RedeemFailureReason reason;

  /// Server contract: `not-found`; `failed-precondition` {reason: expired |
  /// redeemed | disabled | not_sent}; `resource-exhausted` (wrong-code limit).
  factory RedeemFailure.from(Object error) {
    if (error is RedeemFailure) return error;
    if (error is FirebaseFunctionsException) {
      final details = error.details is Map ? Map<String, dynamic>.from(error.details as Map) : const <String, dynamic>{};
      return RedeemFailure(switch (error.code) {
        'not-found' when details['reason'] == null => RedeemFailureReason.notFound,
        'failed-precondition' => switch (details['reason']) {
            'expired' => RedeemFailureReason.expired,
            'redeemed' => RedeemFailureReason.alreadyRedeemed,
            'disabled' => RedeemFailureReason.disabled,
            'not_sent' => RedeemFailureReason.notYetSent,
            _ => RedeemFailureReason.unknown,
          },
        'resource-exhausted' => RedeemFailureReason.tooManyAttempts,
        'unimplemented' || 'internal' || 'unavailable' => RedeemFailureReason.unavailable,
        'deadline-exceeded' => RedeemFailureReason.network,
        _ => RedeemFailureReason.unknown,
      });
    }
    return const RedeemFailure(RedeemFailureReason.unknown);
  }
}

class RedeemResult {
  const RedeemResult({required this.giftCardId, required this.amount, required this.credits});
  final String giftCardId;

  /// Added to wallet credits.
  final int amount;

  /// Credits after redeeming.
  final int credits;
}

class GiftCardsRepository {
  GiftCardsRepository(this._db, this._call);
  final FirebaseFirestore _db;
  final CallableInvoker _call;

  /// Active templates by sortOrder; [limit] = the first ones only (Home).
  Stream<List<GiftCardTemplateModel>> watchTemplates({int? limit}) {
    Query<Map<String, dynamic>> query =
        _db.collection(FirestorePaths.giftCardTemplates).where('isActive', isEqualTo: true);
    if (limit != null) query = query.orderBy('sortOrder').limit(limit);
    return query.snapshots().map((s) => [for (final d in s.docs) GiftCardTemplateModel.fromMap(d.id, d.data())]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }

  /// Cards sent to me (matched by `recipientUid` once redeemed or linked by phone).
  Stream<List<GiftCardModel>> watchReceived(String uid) => _db
      .collection(FirestorePaths.giftCards)
      .where('recipientUid', isEqualTo: uid)
      .snapshots()
      .map(_sorted);

  Stream<List<GiftCardModel>> watchPurchased(String uid) => _db
      .collection(FirestorePaths.giftCards)
      .where('purchaserUid', isEqualTo: uid)
      .snapshots()
      .map(_sorted);

  static List<GiftCardModel> _sorted(QuerySnapshot<Map<String, dynamic>> s) =>
      [for (final d in s.docs) GiftCardModel.fromMap(d.id, d.data())]
        ..sort((a, b) => (b.sentAt ?? b.scheduledAt ?? DateTime(0)).compareTo(a.sentAt ?? a.scheduledAt ?? DateTime(0)));

  Future<PlacedOrder> purchase(GiftCardPurchase purchase) async {
    try {
      final data = callableMap(await _call('purchaseGiftCard', purchase.toMap()));
      return PlacedOrder(
        orderId: data['orderId'] as String? ?? '',
        orderNumber: data['orderNumber'] as String? ?? '',
        total: (data['total'] as num?)?.toInt() ?? purchase.amount,
      );
    } catch (e) {
      throw OrderFailure.from(e);
    }
  }

  /// Codes are typed with or without dashes / spaces, any case.
  static String normalizeCode(String code) => code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  Future<RedeemResult> redeem(String code) async {
    try {
      final data = callableMap(await _call('redeemGiftCard', {'code': normalizeCode(code)}));
      return RedeemResult(
        giftCardId: data['giftCardId'] as String? ?? '',
        amount: (data['amount'] as num?)?.toInt() ?? 0,
        credits: (data['credits'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw RedeemFailure.from(e);
    }
  }
}

final giftCardsRepositoryProvider = Provider<GiftCardsRepository>(
    (ref) => GiftCardsRepository(ref.watch(firestoreProvider), ref.watch(callableInvokerProvider)));

/// The shop and the Designer (SRS §5.22): every active template.
final giftCardTemplatesProvider =
    StreamProvider<List<GiftCardTemplateModel>>((ref) => ref.watch(giftCardsRepositoryProvider).watchTemplates());

/// Templates shown on Home (section 6, SRS §5.4) — "View All" opens the shop.
const homeGiftCardLimit = 4;

/// Home section 6: the first [homeGiftCardLimit] templates (SRS §8 read budget).
final homeGiftCardTemplatesProvider = StreamProvider<List<GiftCardTemplateModel>>(
    (ref) => ref.watch(giftCardsRepositoryProvider).watchTemplates(limit: homeGiftCardLimit));

final receivedGiftCardsProvider = StreamProvider.autoDispose<List<GiftCardModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(giftCardsRepositoryProvider).watchReceived(uid);
});

final purchasedGiftCardsProvider = StreamProvider.autoDispose<List<GiftCardModel>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(giftCardsRepositoryProvider).watchPurchased(uid);
});

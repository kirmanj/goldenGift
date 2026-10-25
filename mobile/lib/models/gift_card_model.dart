import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// `gift_card_templates/{id}` (SRS §5.4 item 6, §5.22, §6.10).
class GiftCardTemplateModel {
  const GiftCardTemplateModel({
    required this.id,
    required this.name,
    this.artworkUrl,
    this.gradientStart,
    this.gradientEnd,
    this.presetAmounts = const [],
    this.minAmount = 0,
    this.maxAmount = 0,
    this.sortOrder = 0,
    this.isActive = true,
  });

  final String id;
  final LocalizedText name;
  final String? artworkUrl;

  /// `#RRGGBB`; the gold shimmer gradient when missing.
  final String? gradientStart;
  final String? gradientEnd;
  final List<int> presetAmounts;

  /// Custom-amount bounds (0 = custom amounts not allowed).
  final int minAmount;
  final int maxAmount;
  final int sortOrder;
  final bool isActive;

  bool get allowsCustomAmount => minAmount > 0 && maxAmount >= minAmount;

  /// Whether [amount] can be bought with this template.
  bool accepts(int amount) =>
      amount > 0 && (presetAmounts.contains(amount) || (allowsCustomAmount && amount >= minAmount && amount <= maxAmount));

  factory GiftCardTemplateModel.fromMap(String id, Map<String, dynamic> map) => GiftCardTemplateModel(
        id: id,
        name: LocalizedText.fromMap(map, 'name'),
        artworkUrl: FirestoreParse.stringOrNull(map['artworkUrl']),
        gradientStart: FirestoreParse.stringOrNull(map['gradientStart']),
        gradientEnd: FirestoreParse.stringOrNull(map['gradientEnd']),
        presetAmounts: (map['presetAmounts'] is List)
            ? [for (final v in map['presetAmounts'] as List) FirestoreParse.integer(v)].where((v) => v > 0).toList()
            : const [],
        minAmount: FirestoreParse.integer(map['minAmount']),
        maxAmount: FirestoreParse.integer(map['maxAmount']),
        sortOrder: FirestoreParse.integer(map['sortOrder']),
        isActive: FirestoreParse.boolean(map['isActive'], true),
      );

  Map<String, dynamic> toMap() => {
        ...name.toMap('name'),
        'artworkUrl': artworkUrl,
        'gradientStart': gradientStart,
        'gradientEnd': gradientEnd,
        'presetAmounts': presetAmounts,
        'minAmount': minAmount,
        'maxAmount': maxAmount,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };
}

enum GiftCardStatus { pending, sent, redeemed, expired, disabled }

/// `gift_cards/{id}` (SRS §5.22, §6.10). Created by `issueGiftCard` when the
/// gift-card order is paid; redeemed into wallet credits by `redeemGiftCard`.
/// Readable by the purchaser and the recipient (and admins).
class GiftCardModel {
  const GiftCardModel({
    required this.id,
    required this.code,
    required this.templateId,
    required this.amount,
    required this.balance,
    required this.purchaserUid,
    required this.recipientName,
    this.recipientPhone,
    this.recipientEmail,
    this.recipientUid,
    this.message = '',
    this.photoUrl,
    this.scheduledAt,
    this.sentAt,
    this.redeemedAt,
    this.expiresAt,
    this.status = GiftCardStatus.pending,
    this.orderId,
    this.templateName = LocalizedText.empty,
    this.gradientStart,
    this.gradientEnd,
    this.createdAt,
    this.disabledReason,
    this.disabledAt,
  });

  final String id;

  /// 12 characters, unique; shown as XXXX-XXXX-XXXX.
  final String code;
  final String templateId;
  final int amount;
  final int balance;
  final String purchaserUid;
  final String recipientName;
  final String? recipientPhone;
  final String? recipientEmail;
  final String? recipientUid;
  final String message;
  final String? photoUrl;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime? redeemedAt;
  final DateTime? expiresAt;
  final GiftCardStatus status;
  final String? orderId;

  /// Template snapshot so the card renders without another read.
  final LocalizedText templateName;
  final String? gradientStart;
  final String? gradientEnd;
  final DateTime? createdAt;

  /// Set by an admin when the card is disabled (dashboard).
  final String? disabledReason;
  final DateTime? disabledAt;

  /// `ABCD-EFGH-JKLM`
  String get formattedCode =>
      code.length == 12 ? '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}' : code;

  bool isRedeemable(DateTime now) =>
      status == GiftCardStatus.sent && balance > 0 && (expiresAt == null || now.isBefore(expiresAt!));

  factory GiftCardModel.fromMap(String id, Map<String, dynamic> map) => GiftCardModel(
        id: id,
        code: map['code'] as String? ?? '',
        templateId: map['templateId'] as String? ?? '',
        amount: FirestoreParse.integer(map['amount']),
        balance: FirestoreParse.integer(map['balance']),
        purchaserUid: map['purchaserUid'] as String? ?? '',
        recipientName: map['recipientName'] as String? ?? '',
        recipientPhone: FirestoreParse.stringOrNull(map['recipientPhone']),
        recipientEmail: FirestoreParse.stringOrNull(map['recipientEmail']),
        recipientUid: FirestoreParse.stringOrNull(map['recipientUid']),
        message: map['message'] as String? ?? '',
        photoUrl: FirestoreParse.stringOrNull(map['photoUrl']),
        scheduledAt: FirestoreParse.date(map['scheduledAt']),
        sentAt: FirestoreParse.date(map['sentAt']),
        redeemedAt: FirestoreParse.date(map['redeemedAt']),
        expiresAt: FirestoreParse.date(map['expiresAt']),
        status: FirestoreParse.enumValue(GiftCardStatus.values, map['status'], GiftCardStatus.pending),
        orderId: FirestoreParse.stringOrNull(map['orderId']),
        templateName: LocalizedText.fromMap(map, 'templateName'),
        gradientStart: FirestoreParse.stringOrNull(map['gradientStart']),
        gradientEnd: FirestoreParse.stringOrNull(map['gradientEnd']),
        createdAt: FirestoreParse.date(map['createdAt']),
        disabledReason: FirestoreParse.stringOrNull(map['disabledReason']),
        disabledAt: FirestoreParse.date(map['disabledAt']),
      );
}

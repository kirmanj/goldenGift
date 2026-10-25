import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

enum PromoType { percent, fixed }

/// `promo_codes/{CODE}` (SRS §5.23, §6.9). Usage per customer lives in
/// `promo_codes/{CODE}/usages/{uid}.count`. Written by admins; usage counters
/// only by `placeOrder`.
class PromoCodeModel {
  const PromoCodeModel({
    required this.code,
    required this.title,
    this.description = LocalizedText.empty,
    required this.type,
    required this.value,
    this.maxDiscount,
    this.minOrder,
    this.usageLimit,
    this.usageCount = 0,
    this.perUserLimit = 1,
    this.firstOrderOnly = false,
    this.categoryIds = const [],
    this.storeIds = const [],
    this.isPublic = false,
    this.isActive = true,
    this.expiresAt,
  });

  /// Upper-case; also the document id.
  final String code;
  final LocalizedText title;
  final LocalizedText description;
  final PromoType type;

  /// Percent (1–100) or a fixed IQD amount.
  final int value;
  final int? maxDiscount;
  final int? minOrder;

  /// Total redemptions allowed (null = unlimited).
  final int? usageLimit;
  final int usageCount;

  /// Redemptions per customer (0 = unlimited).
  final int perUserLimit;
  final bool firstOrderOnly;

  /// When non-empty, only matching lines count towards the discount.
  final List<String> categoryIds;
  final List<String> storeIds;
  final bool isPublic;
  final bool isActive;
  final DateTime? expiresAt;

  bool get isRestricted => categoryIds.isNotEmpty || storeIds.isNotEmpty;

  /// Codes are matched case-insensitively and without spaces.
  static String normalize(String code) => code.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  factory PromoCodeModel.fromMap(String id, Map<String, dynamic> map) => PromoCodeModel(
        code: (map['code'] as String?)?.isNotEmpty == true ? normalize(map['code'] as String) : normalize(id),
        title: LocalizedText.fromMap(map, 'title'),
        description: LocalizedText.fromMap(map, 'description'),
        type: FirestoreParse.enumValue(PromoType.values, map['type'], PromoType.percent),
        value: FirestoreParse.integer(map['value']),
        maxDiscount: FirestoreParse.integerOrNull(map['maxDiscount']),
        minOrder: FirestoreParse.integerOrNull(map['minOrder']),
        usageLimit: FirestoreParse.integerOrNull(map['usageLimit']),
        usageCount: FirestoreParse.integer(map['usageCount']),
        perUserLimit: FirestoreParse.integer(map['perUserLimit'], 1),
        firstOrderOnly: FirestoreParse.boolean(map['firstOrderOnly']),
        categoryIds: FirestoreParse.stringList(map['categoryIds']),
        storeIds: FirestoreParse.stringList(map['storeIds']),
        isPublic: FirestoreParse.boolean(map['isPublic']),
        isActive: FirestoreParse.boolean(map['isActive'], true),
        expiresAt: FirestoreParse.date(map['expiresAt']),
      );

  /// Admin editor payload (never `usageCount` — the function owns it).
  Map<String, dynamic> toMap() => {
        'code': code,
        ...title.toMap('title'),
        ...description.toMap('description'),
        'type': type.name,
        'value': value,
        'maxDiscount': maxDiscount,
        'minOrder': minOrder,
        'usageLimit': usageLimit,
        'perUserLimit': perUserLimit,
        'firstOrderOnly': firstOrderOnly,
        'categoryIds': categoryIds,
        'storeIds': storeIds,
        'isPublic': isPublic,
        'isActive': isActive,
        'expiresAt': expiresAt,
      };
}

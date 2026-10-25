import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// `stores/{storeId}` (SRS §6.2) — the public part of a partner store.
class StoreModel {
  const StoreModel({
    required this.id,
    required this.name,
    this.description = LocalizedText.empty,
    this.logoUrl,
    this.coverUrl,
    this.ownerUid,
    this.phone,
    this.city,
    this.status = StoreStatus.pendingApproval,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.productCount = 0,
    this.ordersCount = 0,
    this.commissionPercent = 0,
    this.createdAt,
  });

  final String id;
  final LocalizedText name;
  final LocalizedText description;
  final String? logoUrl;
  final String? coverUrl;
  final String? ownerUid;
  final String? phone;
  final String? city;
  final StoreStatus status;
  final double ratingAvg;
  final int ratingCount;
  final int productCount;
  final int ordersCount;
  final double commissionPercent;
  final DateTime? createdAt;

  bool get isActive => status == StoreStatus.active;

  factory StoreModel.fromMap(String id, Map<String, dynamic> map) => StoreModel(
        id: id,
        name: LocalizedText.fromMap(map, 'name'),
        description: LocalizedText.fromMap(map, 'description'),
        logoUrl: FirestoreParse.stringOrNull(map['logoUrl']),
        coverUrl: FirestoreParse.stringOrNull(map['coverUrl']),
        ownerUid: FirestoreParse.stringOrNull(map['ownerUid']),
        phone: FirestoreParse.stringOrNull(map['phone']),
        city: FirestoreParse.stringOrNull(map['city']),
        status: FirestoreParse.enumValue(StoreStatus.values, map['status'], StoreStatus.pendingApproval),
        ratingAvg: FirestoreParse.decimal(map['ratingAvg']),
        ratingCount: FirestoreParse.integer(map['ratingCount']),
        productCount: FirestoreParse.integer(map['productCount']),
        ordersCount: FirestoreParse.integer(map['ordersCount']),
        commissionPercent: FirestoreParse.decimal(map['commissionPercent']),
        createdAt: FirestoreParse.date(map['createdAt']),
      );

  Map<String, dynamic> toMap() => {
        ...name.toMap('name'),
        ...description.toMap('description'),
        'logoUrl': logoUrl,
        'coverUrl': coverUrl,
        'ownerUid': ownerUid,
        'phone': phone,
        'city': city,
        'status': status.name,
        'ratingAvg': ratingAvg,
        'ratingCount': ratingCount,
        'productCount': productCount,
        'ordersCount': ordersCount,
        'commissionPercent': commissionPercent,
      };
}

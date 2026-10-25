import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';

/// `banners/{id}` (SRS §6.8).
class BannerModel {
  const BannerModel({
    required this.id,
    required this.imageUrl,
    this.imageUrlAr,
    this.imageUrlKu,
    required this.placement,
    required this.actionType,
    required this.actionValue,
    this.sortOrder = 0,
    this.isActive = true,
    this.startAt,
    this.endAt,
  });

  final String id;

  /// Banner artwork usually contains text, so it is trilingual like other catalogue content.
  final String imageUrl;
  final String? imageUrlAr;
  final String? imageUrlKu;
  final BannerPlacement placement;
  final BannerActionType actionType;

  /// Category id, product id, URL or app route depending on [actionType].
  final String actionValue;
  final int sortOrder;
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;

  String imageFor(String languageCode) => switch (languageCode) {
        'ar' => imageUrlAr ?? imageUrl,
        'ckb' => imageUrlKu ?? imageUrl,
        _ => imageUrl,
      };

  bool isLiveAt(DateTime now) =>
      isActive &&
      (startAt == null || !now.isBefore(startAt!)) &&
      (endAt == null || !now.isAfter(endAt!));

  factory BannerModel.fromMap(String id, Map<String, dynamic> map) {
    final action = FirestoreParse.map(map['action']);
    return BannerModel(
      id: id,
      imageUrl: map['imageUrl'] as String? ?? '',
      imageUrlAr: FirestoreParse.stringOrNull(map['imageUrlAr']),
      imageUrlKu: FirestoreParse.stringOrNull(map['imageUrlKu']),
      placement: FirestoreParse.enumValue(
          BannerPlacement.values, map['placement'], BannerPlacement.homeTop),
      actionType: FirestoreParse.enumValue(
          BannerActionType.values, action['type'], BannerActionType.route),
      actionValue: action['value'] as String? ?? '',
      sortOrder: FirestoreParse.integer(map['sortOrder']),
      isActive: FirestoreParse.boolean(map['isActive'], true),
      startAt: FirestoreParse.date(map['startAt']),
      endAt: FirestoreParse.date(map['endAt']),
    );
  }

  Map<String, dynamic> toMap() => {
        'imageUrl': imageUrl,
        if (imageUrlAr != null) 'imageUrlAr': imageUrlAr,
        if (imageUrlKu != null) 'imageUrlKu': imageUrlKu,
        'placement': placement.name,
        'action': {'type': actionType.name, 'value': actionValue},
        'sortOrder': sortOrder,
        'isActive': isActive,
        'startAt': startAt,
        'endAt': endAt,
      };
}

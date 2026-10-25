import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// What the customer sees for a category (SRS §5.7a). Derived from
/// `isActive` + `comingSoon`, never stored itself.
enum CategoryStatus {
  /// Listed; opens its products.
  available,

  /// Listed with a "Soon" pill; opens the coming-soon page instead of products.
  comingSoon,

  /// Not shown anywhere in the app (`isActive == false`).
  hidden,
}

/// `categories/{id}` (SRS §6.3).
class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.title,
    this.iconUrl,
    this.type = CategoryType.productType,
    this.sortOrder = 0,
    this.isActive = true,
    this.isSeasonal = false,
    this.activeFrom,
    this.activeTo,
    this.parentId,
    this.productCount = 0,
    this.comingSoon = false,
    this.comingSoonNote = LocalizedText.empty,
    this.comingSoonSince,
  });

  /// Longest coming-soon note the dashboard accepts (SRS §6.3).
  static const comingSoonNoteMaxLength = 140;

  final String id;
  final LocalizedText title;
  final String? iconUrl;
  final CategoryType type;
  final int sortOrder;
  final bool isActive;
  final bool isSeasonal;
  final DateTime? activeFrom;
  final DateTime? activeTo;
  final String? parentId;
  final int productCount;

  /// Switched to "Coming soon" by Admin (SRS §5.7a): still listed, but opening
  /// it shows the coming-soon page. Only meaningful while [isActive].
  final bool comingSoon;

  /// Optional trilingual line for the coming-soon page, e.g. "Arriving before Ramadan".
  final LocalizedText comingSoonNote;

  /// When it was switched to coming soon (server time).
  final DateTime? comingSoonSince;

  CategoryStatus get status => !isActive
      ? CategoryStatus.hidden
      : comingSoon
          ? CategoryStatus.comingSoon
          : CategoryStatus.available;

  /// Active, and inside its seasonal window when it has one.
  bool isVisibleAt(DateTime now) {
    if (!isActive) return false;
    if (!isSeasonal) return true;
    if (activeFrom != null && now.isBefore(activeFrom!)) return false;
    if (activeTo != null && now.isAfter(activeTo!)) return false;
    return true;
  }

  /// The category that makes this one "coming soon": itself, or the nearest
  /// coming-soon ancestor through `parentId` (SRS §5.7a). Null = available.
  /// [byId] is the list the caller knows; a parent missing from it counts as
  /// available. Cycles in `parentId` are ignored.
  CategoryModel? comingSoonSource(Map<String, CategoryModel> byId) {
    final seen = <String>{};
    CategoryModel? current = this;
    while (current != null && seen.add(current.id)) {
      if (current.comingSoon) return current;
      final parent = current.parentId;
      current = parent == null ? null : byId[parent];
    }
    return null;
  }

  /// Coming soon itself or through a parent (see [comingSoonSource]).
  bool isComingSoonWithin(Map<String, CategoryModel> byId) => comingSoonSource(byId) != null;

  CategoryModel copyWith({
    LocalizedText? title,
    String? iconUrl,
    bool? isActive,
    bool? comingSoon,
    LocalizedText? comingSoonNote,
    DateTime? comingSoonSince,
    bool clearComingSoonSince = false,
    String? parentId,
    bool clearParent = false,
  }) =>
      CategoryModel(
        id: id,
        title: title ?? this.title,
        iconUrl: iconUrl ?? this.iconUrl,
        type: type,
        sortOrder: sortOrder,
        isActive: isActive ?? this.isActive,
        isSeasonal: isSeasonal,
        activeFrom: activeFrom,
        activeTo: activeTo,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        productCount: productCount,
        comingSoon: comingSoon ?? this.comingSoon,
        comingSoonNote: comingSoonNote ?? this.comingSoonNote,
        comingSoonSince: clearComingSoonSince ? null : (comingSoonSince ?? this.comingSoonSince),
      );

  factory CategoryModel.fromMap(String id, Map<String, dynamic> map) => CategoryModel(
        id: id,
        title: LocalizedText.fromMap(map, 'title'),
        iconUrl: FirestoreParse.stringOrNull(map['iconUrl']),
        type: FirestoreParse.enumValue(CategoryType.values, map['type'], CategoryType.productType),
        sortOrder: FirestoreParse.integer(map['sortOrder']),
        isActive: FirestoreParse.boolean(map['isActive'], true),
        isSeasonal: FirestoreParse.boolean(map['isSeasonal']),
        activeFrom: FirestoreParse.date(map['activeFrom']),
        activeTo: FirestoreParse.date(map['activeTo']),
        parentId: FirestoreParse.stringOrNull(map['parentId']),
        productCount: FirestoreParse.integer(map['productCount']),
        comingSoon: FirestoreParse.boolean(map['comingSoon']),
        comingSoonNote: LocalizedText.fromMap(map, 'comingSoonNote'),
        comingSoonSince: FirestoreParse.date(map['comingSoonSince']),
      );

  /// The note keys are written only when there is a note.
  Map<String, dynamic> toMap() => {
        ...title.toMap('title'),
        'iconUrl': iconUrl,
        'type': type.name,
        'sortOrder': sortOrder,
        'isActive': isActive,
        'isSeasonal': isSeasonal,
        'activeFrom': activeFrom,
        'activeTo': activeTo,
        'parentId': parentId,
        'productCount': productCount,
        'comingSoon': comingSoon,
        if (!comingSoonNote.isEmpty) ...comingSoonNote.toMap('comingSoonNote'),
        'comingSoonSince': comingSoonSince,
      };
}

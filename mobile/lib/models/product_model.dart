import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// Known [GiftAudience] values of a Firestore list, de-duplicated, in order.
List<GiftAudience> giftAudiencesOf(Object? value) {
  final out = <GiftAudience>[];
  for (final name in FirestoreParse.stringList(value)) {
    final a = FirestoreParse.enumOrNull(GiftAudience.values, name);
    if (a != null && !out.contains(a)) out.add(a);
  }
  return out;
}

/// `products/{id}` (SRS §6.4). Prices are whole IQD.
class ProductModel {
  const ProductModel({
    required this.id,
    required this.title,
    this.description = LocalizedText.empty,
    required this.storeId,
    this.categoryIds = const [],
    this.images = const [],
    required this.price,
    this.compareAtPrice,
    this.currency = AppConstants.currencyCode,
    this.isActive = true,
    this.isFeatured = false,
    this.availability = ProductAvailability.sameDay,
    this.preparationDays = 0,
    this.availableCities = const [],
    this.stock,
    this.salesCount = 0,
    this.viewCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.searchKeywords = const [],
    this.tags = const [],
    this.giftFor = const [],
    this.optionGroups = const [],
    this.colorDotsCache = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final LocalizedText title;
  final LocalizedText description;
  final String storeId;
  final List<String> categoryIds;
  final List<String> images;
  final int price;
  final int? compareAtPrice;
  final String currency;
  final bool isActive;
  final bool isFeatured;
  final ProductAvailability availability;
  final int preparationDays;

  /// City ids; empty = deliverable to every served city (SRS §4.3).
  final List<String> availableCities;

  /// null = unlimited.
  final int? stock;
  final int salesCount;
  final int viewCount;
  final double ratingAvg;
  final int ratingCount;
  final List<String> searchKeywords;
  final List<String> tags;

  /// Who it is a gift for (SRS §5.8a); unknown values are dropped.
  final List<GiftAudience> giftFor;
  final List<OptionGroup> optionGroups;

  /// Pre-computed `colorDots` from a search record (Algolia hits carry no option groups).
  final List<String> colorDotsCache;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory ProductModel.fromMap(String id, Map<String, dynamic> map) {
    final groups = FirestoreParse.mapList(map['optionGroups'])
        .map(OptionGroup.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ProductModel(
      id: id,
      title: LocalizedText.fromMap(map, 'title'),
      description: LocalizedText.fromMap(map, 'description'),
      storeId: map['storeId'] as String? ?? '',
      categoryIds: FirestoreParse.stringList(map['categoryIds']),
      images: FirestoreParse.stringList(map['images']),
      price: FirestoreParse.integer(map['price']),
      compareAtPrice: FirestoreParse.integerOrNull(map['compareAtPrice']),
      currency: map['currency'] as String? ?? AppConstants.currencyCode,
      isActive: FirestoreParse.boolean(map['isActive'], true),
      isFeatured: FirestoreParse.boolean(map['isFeatured']),
      availability: FirestoreParse.enumValue(
          ProductAvailability.values, map['availability'], ProductAvailability.sameDay),
      preparationDays: FirestoreParse.integer(map['preparationDays']),
      availableCities: FirestoreParse.stringList(map['availableCities']),
      stock: FirestoreParse.integerOrNull(map['stock']),
      salesCount: FirestoreParse.integer(map['salesCount']),
      viewCount: FirestoreParse.integer(map['viewCount']),
      ratingAvg: FirestoreParse.decimal(map['ratingAvg']),
      ratingCount: FirestoreParse.integer(map['ratingCount']),
      searchKeywords: FirestoreParse.stringList(map['searchKeywords']),
      tags: FirestoreParse.stringList(map['tags']),
      giftFor: giftAudiencesOf(map['giftFor']),
      optionGroups: groups,
      colorDotsCache: FirestoreParse.stringList(map['colorDots']),
      createdAt: FirestoreParse.date(map['createdAt']),
      updatedAt: FirestoreParse.date(map['updatedAt']),
    );
  }

  /// Without `createdAt` / `updatedAt` — the writer sets server timestamps.
  Map<String, dynamic> toMap() => {
        ...title.toMap('title'),
        ...description.toMap('description'),
        'storeId': storeId,
        'categoryIds': categoryIds,
        'images': images,
        'price': price,
        'compareAtPrice': compareAtPrice,
        'currency': currency,
        'isActive': isActive,
        'isFeatured': isFeatured,
        'availability': availability.name,
        'preparationDays': preparationDays,
        'availableCities': availableCities,
        'stock': stock,
        'salesCount': salesCount,
        'viewCount': viewCount,
        'ratingAvg': ratingAvg,
        'ratingCount': ratingCount,
        'searchKeywords': searchKeywords,
        'tags': tags,
        'giftFor': giftFor.map((a) => a.name).toList(),
        'optionGroups': optionGroups.map((g) => g.toMap()).toList(),
      };

  String? get mainImage => images.isEmpty ? null : images.first;

  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  /// Rounded discount percentage for the red badge (SRS §4.4), 0 when none.
  int get discountPercent =>
      hasDiscount ? ((compareAtPrice! - price) * 100 / compareAtPrice!).round() : 0;

  bool get isOutOfStock =>
      availability == ProductAvailability.outOfStock || (stock != null && stock! <= 0);

  bool get isSameDay => availability == ProductAvailability.sameDay && preparationDays == 0;

  /// Up to 5 hex colours from the first colour-swatch group (product-card dots, SRS §4.4).
  List<String> get colorDots {
    if (colorDotsCache.isNotEmpty) return colorDotsCache.take(5).toList();
    for (final g in optionGroups) {
      if (g.type == OptionType.colorSwatch) {
        return g.values.map((v) => v.hex).whereType<String>().take(5).toList();
      }
    }
    return const [];
  }

  bool isAvailableIn(String cityId) =>
      availableCities.isEmpty || availableCities.contains(cityId);
}

/// One customization input on a product (SRS §5.9, §6.4).
class OptionGroup {
  const OptionGroup({
    required this.id,
    required this.type,
    required this.label,
    this.required = false,
    this.sortOrder = 0,
    this.maxLength,
    this.minPhotos,
    this.maxPhotos,
    this.values = const [],
  });

  final String id;
  final OptionType type;
  final LocalizedText label;
  final bool required;
  final int sortOrder;

  /// `text` / `longText`.
  final int? maxLength;

  /// `photoUpload`.
  final int? minPhotos;
  final int? maxPhotos;

  /// `imageVariant` / `textVariant` / `colorSwatch`.
  final List<OptionValue> values;

  factory OptionGroup.fromMap(Map<String, dynamic> map) => OptionGroup(
        id: map['id'] as String? ?? '',
        type: FirestoreParse.enumValue(OptionType.values, map['type'], OptionType.text),
        label: LocalizedText.fromMap(map, 'label'),
        required: FirestoreParse.boolean(map['required']),
        sortOrder: FirestoreParse.integer(map['sortOrder']),
        maxLength: FirestoreParse.integerOrNull(map['maxLength']),
        minPhotos: FirestoreParse.integerOrNull(map['minPhotos']),
        maxPhotos: FirestoreParse.integerOrNull(map['maxPhotos']),
        values: FirestoreParse.mapList(map['values']).map(OptionValue.fromMap).toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        ...label.toMap('label'),
        'required': required,
        'sortOrder': sortOrder,
        if (maxLength != null) 'maxLength': maxLength,
        if (minPhotos != null) 'minPhotos': minPhotos,
        if (maxPhotos != null) 'maxPhotos': maxPhotos,
        if (values.isNotEmpty) 'values': values.map((v) => v.toMap()).toList(),
      };

  bool get hasValues =>
      type == OptionType.imageVariant ||
      type == OptionType.textVariant ||
      type == OptionType.colorSwatch;

  OptionValue? valueById(String? valueId) {
    for (final v in values) {
      if (v.id == valueId) return v;
    }
    return null;
  }
}

class OptionValue {
  const OptionValue({
    required this.id,
    required this.label,
    this.imageUrl,
    this.hex,
    this.priceDelta = 0,
    this.stock,
    this.preparationDaysOverride,
  });

  final String id;
  final LocalizedText label;
  final String? imageUrl;

  /// `#RRGGBB` for colour swatches.
  final String? hex;

  /// Added to the unit price when selected (whole IQD, may be negative).
  final int priceDelta;
  final int? stock;
  final int? preparationDaysOverride;

  factory OptionValue.fromMap(Map<String, dynamic> map) => OptionValue(
        id: map['id'] as String? ?? '',
        label: LocalizedText.fromMap(map, 'label'),
        imageUrl: FirestoreParse.stringOrNull(map['imageUrl']),
        hex: FirestoreParse.stringOrNull(map['hex']),
        priceDelta: FirestoreParse.integer(map['priceDelta']),
        stock: FirestoreParse.integerOrNull(map['stock']),
        preparationDaysOverride: FirestoreParse.integerOrNull(map['preparationDaysOverride']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        ...label.toMap('label'),
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (hex != null) 'hex': hex,
        'priceDelta': priceDelta,
        if (stock != null) 'stock': stock,
        if (preparationDaysOverride != null) 'preparationDaysOverride': preparationDaysOverride,
      };
}

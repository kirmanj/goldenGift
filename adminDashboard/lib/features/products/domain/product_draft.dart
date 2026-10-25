import 'dart:convert';

import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

/// Kebab-case id from an English text: "Mother's Day Mug!" → `mothers-day-mug`
/// (same rules as the seeded ids). Empty when the text has no latin letters or
/// digits — callers pick a fallback.
String slugify(String text, {int maxLength = 60}) {
  final slug = text
      .toLowerCase()
      .replaceAll(RegExp(r"['’`]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.length <= maxLength) return slug;
  return slug.substring(0, maxLength).replaceAll(RegExp(r'-+$'), '');
}

/// [base], else `base-2`, `base-3` … — the first one not in [taken].
String uniqueId(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  for (var n = 2;; n++) {
    final candidate = '$base-$n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// `#RRGGBB` (SRS §6.4 `hex`).
final hexColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Swatch / text / image groups carry `values` (SRS §5.9).
bool optionTypeHasValues(OptionType type) =>
    type == OptionType.imageVariant || type == OptionType.textVariant || type == OptionType.colorSwatch;

String optionTypeLabel(OptionType type) => switch (type) {
      OptionType.imageVariant => 'Image variant',
      OptionType.textVariant => 'Text variant',
      OptionType.colorSwatch => 'Colour swatch',
      OptionType.text => 'Text',
      OptionType.longText => 'Long text',
      OptionType.date => 'Date',
      OptionType.photoUpload => 'Photo upload',
      OptionType.quantity => 'Quantity',
    };

/// What the customer sees in the app (SRS §5.9 table).
String optionTypeHint(OptionType type) => switch (type) {
      OptionType.imageVariant => 'Tiles with an image and a label (frame colour, size)',
      OptionType.textVariant => 'Pill chips (30x30cm)',
      OptionType.colorSwatch => 'Round colour dots (text colour)',
      OptionType.text => 'One-line text with a character limit (name)',
      OptionType.longText => 'Multi-line text with a character limit (notes)',
      OptionType.date => 'Date picker',
      OptionType.photoUpload => 'Customer photo slots (1–10)',
      OptionType.quantity => 'Quantity stepper in the bottom bar',
    };

/// Id used when a group has no English label yet.
String _groupIdFallback(OptionType type) => switch (type) {
      OptionType.imageVariant => 'image',
      OptionType.textVariant => 'variant',
      OptionType.colorSwatch => 'color',
      OptionType.text => 'text',
      OptionType.longText => 'notes',
      OptionType.date => 'date',
      OptionType.photoUpload => 'photos',
      OptionType.quantity => 'quantity',
    };

const maxPhotoSlots = 10;

/// [ProductDraft.validate]'s message when no gift type is chosen.
const giftForRequiredMessage = 'Choose who it is a gift for (at least one).';

/// One entry of the image list. [storageIndex] is the `{n}` of
/// `products/{productId}/{n}.jpg`; it never changes, so reordering or
/// removing images never makes an upload overwrite an image still in use.
class ImageSlot {
  ImageSlot(this.storageIndex, [this.url]);
  final int storageIndex;
  String? url;

  bool get isEmpty => (url ?? '').trim().isEmpty;
}

/// Editable copy of an [OptionValue].
class OptionValueDraft {
  OptionValueDraft({
    this.id = '',
    this.idLocked = false,
    this.label = LocalizedText.empty,
    this.imageUrl,
    this.hex,
    this.priceDelta = 0,
    this.stock,
    this.preparationDaysOverride,
  });

  factory OptionValueDraft.fromValue(OptionValue v) => OptionValueDraft(
        id: v.id,
        idLocked: v.id.isNotEmpty,
        label: v.label,
        imageUrl: v.imageUrl,
        hex: v.hex,
        priceDelta: v.priceDelta,
        stock: v.stock,
        preparationDaysOverride: v.preparationDaysOverride,
      );

  /// Auto from the English label until the product is saved, then fixed
  /// (carts and orders reference it).
  String id;
  bool idLocked;
  LocalizedText label;
  String? imageUrl;
  String? hex;
  int priceDelta;
  int? stock;
  int? preparationDaysOverride;

  OptionValue toValue(OptionType type) {
    final url = imageUrl?.trim();
    final colour = hex?.trim();
    return OptionValue(
      id: id,
      label: label,
      imageUrl: type == OptionType.imageVariant && url != null && url.isNotEmpty ? url : null,
      hex: type == OptionType.colorSwatch && colour != null && colour.isNotEmpty ? colour.toUpperCase() : null,
      priceDelta: priceDelta,
      stock: stock,
      preparationDaysOverride: preparationDaysOverride,
    );
  }
}

/// Editable copy of an [OptionGroup]. The type is chosen when the group is
/// added and doesn't change.
class OptionGroupDraft {
  OptionGroupDraft({
    required this.type,
    this.id = '',
    this.idLocked = false,
    this.label = LocalizedText.empty,
    this.required = false,
    this.maxLength,
    this.minPhotos,
    this.maxPhotos,
    List<OptionValueDraft>? values,
    this.expanded = true,
  }) : values = values ?? [];

  /// A new group with sensible defaults for its type.
  factory OptionGroupDraft.newOf(OptionType type) => switch (type) {
        OptionType.text => OptionGroupDraft(type: type, maxLength: 50),
        OptionType.longText => OptionGroupDraft(type: type, maxLength: 500),
        OptionType.photoUpload => OptionGroupDraft(type: type, minPhotos: 1, maxPhotos: 4),
        OptionType.quantity =>
          OptionGroupDraft(type: type, label: const LocalizedText('Quantity', ar: 'الكمية', ku: 'بڕ')),
        _ => OptionGroupDraft(type: type),
      };

  factory OptionGroupDraft.fromGroup(OptionGroup g) => OptionGroupDraft(
        type: g.type,
        id: g.id,
        idLocked: g.id.isNotEmpty,
        label: g.label,
        required: g.required,
        maxLength: g.maxLength,
        minPhotos: g.minPhotos,
        maxPhotos: g.maxPhotos,
        values: g.values.map(OptionValueDraft.fromValue).toList(),
        expanded: false,
      );

  final OptionType type;
  String id;
  bool idLocked;
  LocalizedText label;
  bool required;
  int? maxLength;
  int? minPhotos;
  int? maxPhotos;
  final List<OptionValueDraft> values;

  /// Editor-only: whether the card is open.
  bool expanded;

  bool get hasValues => optionTypeHasValues(type);
  bool get isTextInput => type == OptionType.text || type == OptionType.longText;

  /// Gives every unsaved value an id from its English label, unique in the group.
  void normalizeValueIds() {
    final taken = {for (final v in values) if (v.idLocked) v.id};
    for (final v in values) {
      if (v.idLocked) continue;
      final base = slugify(v.label.en);
      v.id = uniqueId(base.isEmpty ? 'value' : base, taken);
      taken.add(v.id);
    }
  }

  /// [sortOrder] = position in the editor (SRS §5.9: groups render in `sortOrder`).
  OptionGroup toGroup(int sortOrder) => OptionGroup(
        id: id,
        type: type,
        label: label,
        required: required,
        sortOrder: sortOrder,
        maxLength: isTextInput ? maxLength : null,
        minPhotos: type == OptionType.photoUpload ? minPhotos : null,
        maxPhotos: type == OptionType.photoUpload ? maxPhotos : null,
        values: hasValues ? [for (final v in values) v.toValue(type)] : const [],
      );
}

/// The product editor's working state (SRS §6.4, §9 "Products"). Mutable:
/// the editor changes it in place and rebuilds; [toModel] produces the
/// [ProductModel] that is saved.
class ProductDraft {
  ProductDraft({
    this.id,
    this.title = LocalizedText.empty,
    this.description = LocalizedText.empty,
    this.storeId,
    List<String>? categoryIds,
    List<ImageSlot>? images,
    this.price,
    this.compareAtPrice,
    this.availability = ProductAvailability.sameDay,
    this.preparationDays,
    List<String>? availableCities,
    this.stock,
    this.isActive = true,
    this.isFeatured = false,
    List<String>? tags,
    List<GiftAudience>? giftFor,
    List<OptionGroupDraft>? groups,
    this.salesCount = 0,
    this.viewCount = 0,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    int? nextImageIndex,
  })  : categoryIds = categoryIds ?? [],
        images = images ?? [],
        availableCities = availableCities ?? [],
        tags = tags ?? [],
        giftFor = giftFor ?? [],
        groups = groups ?? [],
        _nextImageIndex = nextImageIndex ?? (images?.length ?? 0);

  factory ProductDraft.fromModel(ProductModel p) {
    final slots = <ImageSlot>[];
    var next = p.images.length;
    for (var i = 0; i < p.images.length; i++) {
      final n = storageIndexOf(p.images[i]);
      if (n != null && n >= next) next = n + 1;
    }
    final used = <int>{};
    for (var i = 0; i < p.images.length; i++) {
      var n = storageIndexOf(p.images[i]);
      if (n == null || used.contains(n)) n = next++;
      used.add(n);
      slots.add(ImageSlot(n, p.images[i]));
    }
    return ProductDraft(
      id: p.id,
      title: p.title,
      description: p.description,
      storeId: p.storeId.isEmpty ? null : p.storeId,
      categoryIds: List.of(p.categoryIds),
      images: slots,
      price: p.price,
      compareAtPrice: p.compareAtPrice,
      availability: p.availability,
      preparationDays: p.preparationDays,
      availableCities: List.of(p.availableCities),
      stock: p.stock,
      isActive: p.isActive,
      isFeatured: p.isFeatured,
      tags: List.of(p.tags),
      giftFor: List.of(p.giftFor),
      groups: p.optionGroups.map(OptionGroupDraft.fromGroup).toList(),
      salesCount: p.salesCount,
      viewCount: p.viewCount,
      ratingAvg: p.ratingAvg,
      ratingCount: p.ratingCount,
      nextImageIndex: next,
    );
  }

  /// `{n}` of a Storage download URL for `products/{id}/{n}.ext`, else null.
  static int? storageIndexOf(String url) {
    String path;
    try {
      path = Uri.decodeFull(url); // download URLs encode the object path: products%2F{id}%2F{n}.jpg
    } on ArgumentError {
      path = url;
    }
    final match = RegExp(r'products/[^/?#]+/(\d+)\.[a-zA-Z]+(?:[?#]|$)').firstMatch(path);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  /// Saved document id; null until the product is first saved.
  String? id;
  LocalizedText title;
  LocalizedText description;
  String? storeId;
  final List<String> categoryIds;
  final List<ImageSlot> images;
  int? price;
  int? compareAtPrice;
  ProductAvailability availability;

  /// Ignored (saved as 0) while availability is same day.
  int? preparationDays;
  final List<String> availableCities;
  int? stock;
  bool isActive;
  bool isFeatured;
  final List<String> tags;

  /// Who it is a gift for (SRS §5.8a): at least one. New products start with
  /// none, so the admin always chooses; kept in [GiftAudience] order.
  final List<GiftAudience> giftFor;
  final List<OptionGroupDraft> groups;

  // Owned by the app / functions, carried only so [toModel] is complete. The
  // repository never writes them on update.
  final int salesCount;
  final int viewCount;
  final double ratingAvg;
  final int ratingCount;

  int _nextImageIndex;

  bool get isNew => id == null;

  ImageSlot addImageSlot([String? url]) {
    final slot = ImageSlot(_nextImageIndex++, url);
    images.add(slot);
    return slot;
  }

  /// Unsaved groups and values get ids from their English labels (unique in
  /// the product / group); saved ones keep theirs.
  void normalizeIds() {
    final taken = {for (final g in groups) if (g.idLocked) g.id};
    for (final g in groups) {
      if (!g.idLocked) {
        final base = slugify(g.label.en);
        g.id = uniqueId(base.isEmpty ? _groupIdFallback(g.type) : base, taken);
        taken.add(g.id);
      }
      g.normalizeValueIds();
    }
  }

  /// After a successful save: ids are now referenced by carts and orders.
  void lockIds() {
    normalizeIds();
    for (final g in groups) {
      g.idLocked = true;
      for (final v in g.values) {
        v.idLocked = true;
      }
    }
  }

  /// Turns [audience] on or off, keeping [giftFor] in [GiftAudience] order
  /// (stable `giftFor` / `forKeys`, so re-saving never looks like a change).
  void setGiftFor(GiftAudience audience, bool selected) {
    final next = {...giftFor};
    selected ? next.add(audience) : next.remove(audience);
    giftFor
      ..clear()
      ..addAll(GiftAudience.values.where(next.contains));
  }

  int get effectivePreparationDays =>
      availability == ProductAvailability.sameDay ? 0 : (preparationDays ?? 0);

  /// Every problem that blocks saving, in form order; empty = valid.
  List<String> validate() {
    normalizeIds();
    final errors = <String>[];
    if (title.en.trim().isEmpty) errors.add('English title is required.');
    if ((storeId ?? '').isEmpty) errors.add('Choose a store.');
    if (giftFor.isEmpty) errors.add(giftForRequiredMessage);
    if (price == null || price! <= 0) errors.add('Price must be greater than 0.');
    if (compareAtPrice != null && price != null && compareAtPrice! <= price!) {
      errors.add('Compare-at price must be greater than the price (or empty).');
    }
    if (preparationDays != null && preparationDays! < 0) errors.add('Preparation days can’t be negative.');
    if (availability == ProductAvailability.preparationDays && (preparationDays ?? 0) <= 0) {
      errors.add('Preparation days must be at least 1 when availability is “Preparation days”.');
    }
    if (stock != null && stock! < 0) errors.add('Stock can’t be negative.');

    if (groups.where((g) => g.type == OptionType.quantity).length > 1) {
      errors.add('Only one Quantity group is allowed.');
    }
    final groupIds = <String>{};
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final name = 'Option group ${i + 1} (${g.label.en.trim().isEmpty ? optionTypeLabel(g.type) : g.label.en.trim()})';
      if (!groupIds.add(g.id)) errors.add('$name: id “${g.id}” is used by another group.');
      if (g.label.en.trim().isEmpty) errors.add('$name: English label is required.');
      if (g.isTextInput && g.maxLength != null && g.maxLength! < 1) {
        errors.add('$name: max length must be at least 1 (or empty for no limit).');
      }
      if (g.type == OptionType.photoUpload) {
        final min = g.minPhotos, max = g.maxPhotos;
        if (min == null || max == null || min < 1 || min > max || max > maxPhotoSlots) {
          errors.add('$name: photos must satisfy 1 ≤ min ≤ max ≤ $maxPhotoSlots.');
        }
      }
      if (!g.hasValues) continue;
      if (g.values.isEmpty) errors.add('$name: add at least one value.');
      final valueIds = <String>{};
      for (var j = 0; j < g.values.length; j++) {
        final v = g.values[j];
        final valueName = '$name, value ${j + 1}${v.label.en.trim().isEmpty ? '' : ' (${v.label.en.trim()})'}';
        if (!valueIds.add(v.id)) errors.add('$valueName: id “${v.id}” is used by another value.');
        if (v.label.en.trim().isEmpty) errors.add('$valueName: English label is required.');
        if (g.type == OptionType.colorSwatch && !hexColorPattern.hasMatch(v.hex?.trim() ?? '')) {
          errors.add('$valueName: colour must be #RRGGBB.');
        }
        if (v.stock != null && v.stock! < 0) errors.add('$valueName: stock can’t be negative.');
        if (v.preparationDaysOverride != null && v.preparationDaysOverride! < 0) {
          errors.add('$valueName: preparation days can’t be negative.');
        }
      }
    }
    return errors;
  }

  /// The product as saved under [productId]. Empty image slots are dropped.
  ProductModel toModel(String productId) {
    normalizeIds();
    return ProductModel(
      id: productId,
      title: _trimmed(title),
      description: _trimmed(description),
      storeId: storeId ?? '',
      categoryIds: List.unmodifiable(categoryIds),
      images: [for (final s in images) if (!s.isEmpty) s.url!.trim()],
      price: price ?? 0,
      compareAtPrice: compareAtPrice,
      availability: availability,
      preparationDays: effectivePreparationDays,
      availableCities: List.unmodifiable(availableCities),
      stock: stock,
      isActive: isActive,
      isFeatured: isFeatured,
      tags: List.unmodifiable(tags),
      giftFor: List.unmodifiable(GiftAudience.values.where(giftFor.contains)),
      salesCount: salesCount,
      viewCount: viewCount,
      ratingAvg: ratingAvg,
      ratingCount: ratingCount,
      optionGroups: [for (var i = 0; i < groups.length; i++) groups[i].toGroup(i)],
    );
  }

  /// Compared against the last saved state to detect unsaved changes.
  String fingerprint() => jsonEncode(toModel(id ?? '').toMap());

  static LocalizedText _trimmed(LocalizedText t) {
    String? opt(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return LocalizedText(t.en.trim(), ar: opt(t.ar), ku: opt(t.ku));
  }
}

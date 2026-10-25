import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../models/cart_item_model.dart';
import '../../../models/product_model.dart';

/// A photo picked for a `photoUpload` group: compressed bytes in memory until
/// Add to Cart uploads them (SRS §5.9).
@immutable
class PickedPhoto {
  const PickedPhoto(this.bytes, {this.name = 'photo.jpg'});
  final Uint8List bytes;
  final String name;
}

/// What the customer chose for one option group.
@immutable
class OptionSelection {
  const OptionSelection({this.valueId, this.text, this.date, this.photos = const []});

  final String? valueId;
  final String? text;
  final DateTime? date;
  final List<PickedPhoto> photos;

  bool get isEmpty =>
      valueId == null && (text == null || text!.trim().isEmpty) && date == null && photos.isEmpty;
}

enum OptionIssueKind { missing, tooLong, notEnoughPhotos, unavailable }

@immutable
class OptionIssue {
  const OptionIssue(this.groupId, this.kind);
  final String groupId;
  final OptionIssueKind kind;

  @override
  bool operator ==(Object other) => other is OptionIssue && other.groupId == groupId && other.kind == kind;

  @override
  int get hashCode => Object.hash(groupId, kind);

  @override
  String toString() => 'OptionIssue($groupId, ${kind.name})';
}

/// The option-group engine (SRS §5.9): selections, validation, pricing and
/// preparation time for one product. Immutable; every change returns a copy.
@immutable
class ProductConfiguration {
  const ProductConfiguration({required this.product, this.selections = const {}, this.qty = 1});

  final ProductModel product;
  final Map<String, OptionSelection> selections;
  final int qty;

  static const maxQtyCap = 99;

  /// Groups the customer fills in, in display order (`quantity` lives in the bottom bar).
  List<OptionGroup> get inputGroups =>
      product.optionGroups.where((g) => g.type != OptionType.quantity).toList();

  OptionSelection selectionFor(String groupId) => selections[groupId] ?? const OptionSelection();

  ProductConfiguration _with(String groupId, OptionSelection selection) =>
      ProductConfiguration(product: product, selections: {...selections, groupId: selection}, qty: qty);

  /// Tapping the selected value again clears it (optional groups).
  ProductConfiguration select(String groupId, String valueId) {
    final current = selectionFor(groupId).valueId;
    return _with(groupId, OptionSelection(valueId: current == valueId ? null : valueId));
  }

  ProductConfiguration setText(String groupId, String text) => _with(groupId, OptionSelection(text: text));
  ProductConfiguration setDate(String groupId, DateTime? date) => _with(groupId, OptionSelection(date: date));
  ProductConfiguration setPhotos(String groupId, List<PickedPhoto> photos) =>
      _with(groupId, OptionSelection(photos: List.unmodifiable(photos)));

  ProductConfiguration setQty(int value) =>
      ProductConfiguration(product: product, selections: selections, qty: value.clamp(1, maxQty));

  OptionValue? selectedValue(OptionGroup group) => group.valueById(selectionFor(group.id).valueId);

  static bool isValueAvailable(OptionValue value) => value.stock == null || value.stock! > 0;

  /// (price + Σ selected priceDelta) — SRS §5.9.
  int get unitPrice {
    var price = product.price;
    for (final g in inputGroups) {
      price += selectedValue(g)?.priceDelta ?? 0;
    }
    return price;
  }

  int get lineTotal => unitPrice * qty;

  /// Longest of the product's and the selected values' preparation days.
  int get preparationDays {
    var days = product.preparationDays;
    for (final g in inputGroups) {
      final override = selectedValue(g)?.preparationDaysOverride;
      if (override != null) days = math.max(days, override);
    }
    return days;
  }

  /// Bounded by product stock, every selected value's stock, and [maxQtyCap].
  int get maxQty {
    var max = product.stock ?? maxQtyCap;
    for (final g in inputGroups) {
      final stock = selectedValue(g)?.stock;
      if (stock != null) max = math.min(max, stock);
    }
    return math.max(1, math.min(max, maxQtyCap));
  }

  /// Every problem, in group display order (SRS §5.9: required groups are
  /// checked on Add to Cart; the screen scrolls to the first one).
  List<OptionIssue> validate() {
    final issues = <OptionIssue>[];
    for (final g in inputGroups) {
      final s = selectionFor(g.id);
      switch (g.type) {
        case OptionType.imageVariant || OptionType.textVariant || OptionType.colorSwatch:
          final value = g.valueById(s.valueId);
          if (value == null) {
            if (g.required) issues.add(OptionIssue(g.id, OptionIssueKind.missing));
          } else if (!isValueAvailable(value)) {
            issues.add(OptionIssue(g.id, OptionIssueKind.unavailable));
          }
        case OptionType.text || OptionType.longText:
          final text = s.text?.trim() ?? '';
          if (text.isEmpty) {
            if (g.required) issues.add(OptionIssue(g.id, OptionIssueKind.missing));
          } else if (g.maxLength != null && text.runes.length > g.maxLength!) {
            issues.add(OptionIssue(g.id, OptionIssueKind.tooLong));
          }
        case OptionType.date:
          if (s.date == null && g.required) issues.add(OptionIssue(g.id, OptionIssueKind.missing));
        case OptionType.photoUpload:
          final min = g.minPhotos ?? (g.required ? 1 : 0);
          if (s.photos.isEmpty && g.required) {
            issues.add(OptionIssue(g.id, OptionIssueKind.missing));
          } else if (s.photos.isNotEmpty && s.photos.length < min) {
            issues.add(OptionIssue(g.id, OptionIssueKind.notEnoughPhotos));
          }
        case OptionType.quantity:
          break;
      }
    }
    return issues;
  }

  bool get isValid => validate().isEmpty;

  bool get hasPhotos => inputGroups.any((g) => selectionFor(g.id).photos.isNotEmpty);

  /// Photos to upload, per group, in slot order.
  Map<String, List<PickedPhoto>> get photosByGroup => {
        for (final g in inputGroups)
          if (selectionFor(g.id).photos.isNotEmpty) g.id: selectionFor(g.id).photos,
      };

  /// Snapshot for the cart line (SRS §6.5). [uploadedUrls] maps a photo group
  /// to its Storage download URLs.
  List<CartSelection> toCartSelections({Map<String, List<String>> uploadedUrls = const {}}) {
    final out = <CartSelection>[];
    for (final g in inputGroups) {
      final s = selectionFor(g.id);
      if (s.isEmpty) continue;
      final value = g.valueById(s.valueId);
      out.add(CartSelection(
        groupId: g.id,
        type: g.type,
        label: g.label,
        valueId: value?.id,
        valueLabel: value?.label,
        hex: value?.hex,
        text: (s.text?.trim().isEmpty ?? true) ? null : s.text!.trim(),
        date: s.date,
        urls: uploadedUrls[g.id] ?? const [],
        priceDelta: value?.priceDelta ?? 0,
      ));
    }
    return out;
  }
}

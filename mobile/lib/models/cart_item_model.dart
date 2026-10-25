import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// `carts/{uid}/items/{itemId}` (SRS §6.5) — also the guest's local cart line.
///
/// Pricing (SRS §5.9): [unitPrice] = product price + Σ selection priceDelta,
/// [lineTotal] = unitPrice × qty. Both are snapshots; `placeOrder` re-prices
/// server-side.
class CartItemModel {
  const CartItemModel({
    required this.id,
    required this.productId,
    required this.storeId,
    required this.titleSnapshot,
    this.imageSnapshot,
    required this.unitPrice,
    required this.qty,
    this.selections = const [],
    this.preparationDays = 0,
    this.addedAt,
  });

  final String id;
  final String productId;
  final String storeId;
  final LocalizedText titleSnapshot;
  final String? imageSnapshot;
  final int unitPrice;
  final int qty;
  final List<CartSelection> selections;
  final int preparationDays;
  final DateTime? addedAt;

  int get lineTotal => unitPrice * qty;

  /// Unit price for a base product price plus the selected options.
  static int computeUnitPrice(int basePrice, List<CartSelection> selections) =>
      basePrice + selections.fold<int>(0, (sum, s) => sum + s.priceDelta);

  factory CartItemModel.fromMap(String id, Map<String, dynamic> map) => CartItemModel(
        id: id,
        productId: map['productId'] as String? ?? '',
        storeId: map['storeId'] as String? ?? '',
        titleSnapshot: LocalizedText.fromMap(map, 'titleSnapshot'),
        imageSnapshot: FirestoreParse.stringOrNull(map['imageSnapshot']),
        unitPrice: FirestoreParse.integer(map['unitPrice']),
        qty: FirestoreParse.integer(map['qty'], 1),
        selections:
            FirestoreParse.mapList(map['selections']).map(CartSelection.fromMap).toList(),
        preparationDays: FirestoreParse.integer(map['preparationDays']),
        addedAt: FirestoreParse.date(map['addedAt']),
      );

  /// Without `addedAt` — the writer sets a server timestamp.
  Map<String, dynamic> toMap() => {
        'productId': productId,
        'storeId': storeId,
        ...titleSnapshot.toMap('titleSnapshot'),
        'imageSnapshot': imageSnapshot,
        'unitPrice': unitPrice,
        'qty': qty,
        'selections': selections.map((s) => s.toMap()).toList(),
        'lineTotal': lineTotal,
        'preparationDays': preparationDays,
      };

  CartItemModel copyWith({int? qty, int? unitPrice, DateTime? addedAt}) => CartItemModel(
        id: id,
        productId: productId,
        storeId: storeId,
        titleSnapshot: titleSnapshot,
        imageSnapshot: imageSnapshot,
        unitPrice: unitPrice ?? this.unitPrice,
        qty: qty ?? this.qty,
        selections: selections,
        preparationDays: preparationDays,
        addedAt: addedAt ?? this.addedAt,
      );

  /// "Frame: Walnut · Text: Happy B-day · 2 photos" (SRS §5.10) — built by the
  /// UI with localized labels; this gives the raw parts in order.
  int get photoCount => selections.fold(0, (n, s) => n + s.urls.length);

  /// Same product with identical selections → re-adding increments qty (SRS §5.9).
  bool isSameConfiguration(CartItemModel other) {
    if (productId != other.productId || selections.length != other.selections.length) {
      return false;
    }
    final mine = {for (final s in selections) s.groupId: s.signature};
    for (final s in other.selections) {
      if (mine[s.groupId] != s.signature) return false;
    }
    return true;
  }
}

/// One customization choice captured on a cart line (SRS §5.9 table).
class CartSelection {
  const CartSelection({
    required this.groupId,
    required this.type,
    required this.label,
    this.valueId,
    this.valueLabel,
    this.hex,
    this.text,
    this.date,
    this.urls = const [],
    this.priceDelta = 0,
  });

  final String groupId;
  final OptionType type;

  /// The option group's label (e.g. "Frame Color").
  final LocalizedText label;
  final String? valueId;
  final LocalizedText? valueLabel;
  final String? hex;
  final String? text;
  final DateTime? date;

  /// Uploaded photo URLs (`photoUpload`).
  final List<String> urls;
  final int priceDelta;

  factory CartSelection.fromMap(Map<String, dynamic> map) {
    final valueLabel = LocalizedText.fromMap(map, 'valueLabel');
    return CartSelection(
      groupId: map['groupId'] as String? ?? '',
      type: FirestoreParse.enumValue(OptionType.values, map['type'], OptionType.text),
      label: LocalizedText.fromMap(map, 'label'),
      valueId: FirestoreParse.stringOrNull(map['valueId']),
      valueLabel: valueLabel.isEmpty ? null : valueLabel,
      hex: FirestoreParse.stringOrNull(map['hex']),
      text: FirestoreParse.stringOrNull(map['text']),
      date: FirestoreParse.date(map['date']),
      urls: FirestoreParse.stringList(map['urls']),
      priceDelta: FirestoreParse.integer(map['priceDelta']),
    );
  }

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'type': type.name,
        ...label.toMap('label'),
        if (valueId != null) 'valueId': valueId,
        if (valueLabel != null) ...valueLabel!.toMap('valueLabel'),
        if (hex != null) 'hex': hex,
        if (text != null) 'text': text,
        if (date != null) 'date': date!.toIso8601String(),
        if (urls.isNotEmpty) 'urls': urls,
        'priceDelta': priceDelta,
      };

  /// What makes two selections "identical" for cart merging.
  String get signature =>
      '${type.name}|${valueId ?? ''}|${text ?? ''}|${date?.toIso8601String() ?? ''}|${urls.join(',')}';
}

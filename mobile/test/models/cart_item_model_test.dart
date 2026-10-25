import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';

CartSelection _frame(String valueId, int delta) => CartSelection(
      groupId: 'frame',
      type: OptionType.imageVariant,
      label: const LocalizedText('Frame Color'),
      valueId: valueId,
      valueLabel: LocalizedText(valueId),
      priceDelta: delta,
    );

CartSelection _text(String text) => CartSelection(
      groupId: 'text1',
      type: OptionType.text,
      label: const LocalizedText('Text 1'),
      text: text,
    );

CartItemModel _item(List<CartSelection> selections, {int qty = 1, String id = 'i1'}) =>
    CartItemModel(
      id: id,
      productId: 'p1',
      storeId: 's1',
      titleSnapshot: const LocalizedText('Frame'),
      unitPrice: CartItemModel.computeUnitPrice(35000, selections),
      qty: qty,
      selections: selections,
    );

void main() {
  group('cart pricing (SRS §5.9: (price + Σ priceDelta) × qty)', () {
    test('unit price adds every option delta', () {
      expect(CartItemModel.computeUnitPrice(35000, [_frame('walnut', 5000), _text('Hi')]), 40000);
    });

    test('line total multiplies by quantity', () {
      expect(_item([_frame('walnut', 5000)], qty: 3).lineTotal, 120000);
    });

    test('toMap stores the computed line total', () {
      expect(_item([_frame('walnut', 5000)], qty: 2).toMap()['lineTotal'], 80000);
    });
  });

  group('merging identical configurations (SRS §5.9)', () {
    test('same product + same selections in any order → same configuration', () {
      final a = _item([_frame('walnut', 5000), _text('Happy B-day')]);
      final b = _item([_text('Happy B-day'), _frame('walnut', 5000)], id: 'i2');
      expect(a.isSameConfiguration(b), isTrue);
    });

    test('different value, text or photo → different line', () {
      final base = _item([_frame('walnut', 5000), _text('Happy B-day')]);
      expect(base.isSameConfiguration(_item([_frame('black', 0), _text('Happy B-day')])), isFalse);
      expect(base.isSameConfiguration(_item([_frame('walnut', 5000), _text('Hi')])), isFalse);
      expect(base.isSameConfiguration(_item([_frame('walnut', 5000)])), isFalse);
    });
  });

  test('round-trips through a Firestore map', () {
    final item = _item([
      _frame('walnut', 5000),
      const CartSelection(
        groupId: 'photos',
        type: OptionType.photoUpload,
        label: LocalizedText('Upload your photos', ar: 'ارفع صورك'),
        urls: ['u1', 'u2'],
      ),
      CartSelection(
        groupId: 'date',
        type: OptionType.date,
        label: const LocalizedText('Date'),
        date: DateTime(2026, 12, 25),
      ),
    ], qty: 2);
    final again = CartItemModel.fromMap('i1', item.toMap());
    expect(again.toMap(), item.toMap());
    expect(again.selections[1].label.resolve('ar'), 'ارفع صورك');
    expect(again.selections[2].date, DateTime(2026, 12, 25));
    expect(again.isSameConfiguration(item), isTrue);
  });
}

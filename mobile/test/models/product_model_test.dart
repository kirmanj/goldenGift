import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/product_model.dart';

Map<String, dynamic> _frameDoc() => {
      'title': 'Wooden Frame',
      'titleAr': 'إطار خشبي',
      'titleKu': 'چوارچێوەی دار',
      'storeId': 'golden-gift-home',
      'categoryIds': ['frames'],
      'images': ['https://example.com/1.jpg', 'https://example.com/2.jpg'],
      'price': 35000,
      'compareAtPrice': 40000.0, // doubles from other writers must parse
      'isFeatured': true,
      'availability': 'preparationDays',
      'preparationDays': 2,
      'availableCities': ['erbil', 'duhok'],
      'stock': 3,
      'optionGroups': [
        {
          'id': 'notes',
          'type': 'longText',
          'label': 'Notes',
          'sortOrder': 5,
          'maxLength': 500,
        },
        {
          'id': 'text-color',
          'type': 'colorSwatch',
          'label': 'Text Color',
          'labelAr': 'لون النص',
          'required': true,
          'sortOrder': 1,
          'values': [
            for (final (i, hex) in ['#000000', '#FFFFFF', '#C9A227', '#D32F2F', '#2E9E5B', '#2F6FD3'].indexed)
              {'id': 'c$i', 'label': 'C$i', 'hex': hex, 'priceDelta': i == 2 ? 2000 : 0},
          ],
        },
      ],
    };

void main() {
  group('ProductModel', () {
    test('parses trilingual fields, numbers and option groups', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      expect(p.title.resolve('ar'), 'إطار خشبي');
      expect(p.title.resolve('ckb'), 'چوارچێوەی دار');
      expect(p.description.resolve('ar'), ''); // missing everywhere → empty, not null
      expect(p.compareAtPrice, 40000);
      expect(p.availability, ProductAvailability.preparationDays);
      expect(p.mainImage, 'https://example.com/1.jpg');
    });

    test('option groups are sorted by sortOrder', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      expect(p.optionGroups.map((g) => g.id), ['text-color', 'notes']);
      expect(p.optionGroups.first.required, isTrue);
      expect(p.optionGroups.first.valueById('c2')?.priceDelta, 2000);
    });

    test('discount percent is rounded (SRS §4.4: 35 vs 40 → 13%)', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      expect(p.hasDiscount, isTrue);
      expect(p.discountPercent, 13);
    });

    test('no discount when compareAtPrice is missing or not higher', () {
      final doc = _frameDoc()..['compareAtPrice'] = 35000;
      expect(ProductModel.fromMap('p1', doc).discountPercent, 0);
      doc.remove('compareAtPrice');
      expect(ProductModel.fromMap('p1', doc).hasDiscount, isFalse);
    });

    test('colour dots come from the first swatch group, max 5', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      expect(p.colorDots, ['#000000', '#FFFFFF', '#C9A227', '#D32F2F', '#2E9E5B']);
    });

    test('city restriction', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      expect(p.isAvailableIn('erbil'), isTrue);
      expect(p.isAvailableIn('baghdad'), isFalse);
      final open = ProductModel.fromMap('p2', _frameDoc()..['availableCities'] = <String>[]);
      expect(open.isAvailableIn('baghdad'), isTrue);
    });

    test('stock and availability', () {
      expect(ProductModel.fromMap('p', _frameDoc()..['stock'] = 0).isOutOfStock, isTrue);
      expect(ProductModel.fromMap('p', _frameDoc()..['availability'] = 'outOfStock').isOutOfStock,
          isTrue);
      expect(ProductModel.fromMap('p', _frameDoc()..['stock'] = null).isOutOfStock, isFalse);
    });

    test('unknown enum strings fall back instead of throwing', () {
      final doc = _frameDoc()..['availability'] = 'somethingNew';
      expect(ProductModel.fromMap('p', doc).availability, ProductAvailability.sameDay);
    });

    test('toMap → fromMap round-trips', () {
      final p = ProductModel.fromMap('p1', _frameDoc());
      final again = ProductModel.fromMap('p1', p.toMap());
      expect(again.toMap(), p.toMap());
      expect(again.optionGroups.first.values.length, 6);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

/// The option-group engine (SRS §5.9): validation, pricing, preparation days.
ProductModel _frame({int? stock}) => ProductModel(
      id: 'frame',
      title: const LocalizedText('Frame'),
      storeId: 'golden-gift-home',
      price: 35000,
      preparationDays: 2,
      stock: stock,
      optionGroups: const [
        OptionGroup(id: 'color', type: OptionType.imageVariant, label: LocalizedText('Frame Color'), required: true, sortOrder: 0, values: [
          OptionValue(id: 'walnut', label: LocalizedText('Walnut'), priceDelta: 5000, preparationDaysOverride: 4),
          OptionValue(id: 'black', label: LocalizedText('Black')),
          OptionValue(id: 'gold', label: LocalizedText('Gold'), stock: 0),
        ]),
        OptionGroup(id: 'size', type: OptionType.textVariant, label: LocalizedText('Size'), sortOrder: 1, values: [
          OptionValue(id: 'l', label: LocalizedText('40x40cm'), priceDelta: 3000, stock: 3),
        ]),
        OptionGroup(id: 'ink', type: OptionType.colorSwatch, label: LocalizedText('Text Color'), sortOrder: 2, values: [
          OptionValue(id: 'red', label: LocalizedText('Red'), hex: '#D32F2F'),
        ]),
        OptionGroup(id: 'text1', type: OptionType.text, label: LocalizedText('Text 1'), required: true, maxLength: 12, sortOrder: 3),
        OptionGroup(id: 'notes', type: OptionType.longText, label: LocalizedText('Notes'), maxLength: 500, sortOrder: 4),
        OptionGroup(id: 'date', type: OptionType.date, label: LocalizedText('Date'), sortOrder: 5),
        OptionGroup(id: 'photos', type: OptionType.photoUpload, label: LocalizedText('Upload your photos'), required: true, minPhotos: 2, maxPhotos: 4, sortOrder: 6),
        OptionGroup(id: 'qty', type: OptionType.quantity, label: LocalizedText('Quantity'), sortOrder: 7),
      ],
    );

PickedPhoto _photo() => PickedPhoto(Uint8List.fromList([1, 2, 3]));

void main() {
  test('quantity groups are not inputs (they live in the bottom bar)', () {
    final c = ProductConfiguration(product: _frame());
    expect(c.inputGroups.map((g) => g.id), ['color', 'size', 'ink', 'text1', 'notes', 'date', 'photos']);
  });

  group('validation', () {
    test('every missing required group, in display order', () {
      expect(ProductConfiguration(product: _frame()).validate(), const [
        OptionIssue('color', OptionIssueKind.missing),
        OptionIssue('text1', OptionIssueKind.missing),
        OptionIssue('photos', OptionIssueKind.missing),
      ]);
    });

    test('text longer than maxLength, too few photos, an out-of-stock value', () {
      final c = ProductConfiguration(product: _frame())
          .select('color', 'gold')
          .setText('text1', 'Happy birthday!!')
          .setPhotos('photos', [_photo()]);
      expect(c.validate(), const [
        OptionIssue('color', OptionIssueKind.unavailable),
        OptionIssue('text1', OptionIssueKind.tooLong),
        OptionIssue('photos', OptionIssueKind.notEnoughPhotos),
      ]);
    });

    test('whitespace-only text counts as missing; emoji count as one character', () {
      final c = ProductConfiguration(product: _frame()).setText('text1', '   ');
      expect(c.validate(), contains(const OptionIssue('text1', OptionIssueKind.missing)));
      final emoji = ProductConfiguration(product: _frame()).setText('text1', '🎁' * 12);
      expect(emoji.validate(), isNot(contains(const OptionIssue('text1', OptionIssueKind.tooLong))));
    });

    test('a complete configuration is valid', () {
      final c = ProductConfiguration(product: _frame())
          .select('color', 'walnut')
          .setText('text1', 'Happy B-day')
          .setPhotos('photos', [_photo(), _photo()]);
      expect(c.validate(), isEmpty);
      expect(c.isValid, isTrue);
      expect(c.hasPhotos, isTrue);
    });
  });

  group('pricing (price + Σ priceDelta) × qty', () {
    test('adds selected deltas', () {
      final c = ProductConfiguration(product: _frame()).select('color', 'walnut').select('size', 'l');
      expect(c.unitPrice, 43000);
      expect(c.setQty(2).lineTotal, 86000);
    });

    test('tapping the selected value again clears it', () {
      final c = ProductConfiguration(product: _frame()).select('color', 'walnut').select('color', 'walnut');
      expect(c.selectionFor('color').valueId, isNull);
      expect(c.unitPrice, 35000);
    });
  });

  test('preparation days take the longest override', () {
    final c = ProductConfiguration(product: _frame());
    expect(c.preparationDays, 2);
    expect(c.select('color', 'walnut').preparationDays, 4);
    expect(c.select('color', 'black').preparationDays, 2);
  });

  test('quantity is limited by product and value stock', () {
    expect(ProductConfiguration(product: _frame()).maxQty, ProductConfiguration.maxQtyCap);
    expect(ProductConfiguration(product: _frame(stock: 5)).maxQty, 5);
    final withSize = ProductConfiguration(product: _frame(stock: 5)).select('size', 'l');
    expect(withSize.maxQty, 3);
    expect(withSize.setQty(10).qty, 3);
    expect(withSize.setQty(0).qty, 1);
  });

  test('cart selections snapshot labels, values, text, date and uploaded photo URLs', () {
    final c = ProductConfiguration(product: _frame())
        .select('color', 'walnut')
        .select('ink', 'red')
        .setText('text1', '  Happy B-day ')
        .setDate('date', DateTime(2026, 12, 25))
        .setPhotos('photos', [_photo(), _photo()]);
    final selections = c.toCartSelections(uploadedUrls: {
      'photos': ['u1', 'u2'],
    });
    expect(selections.map((s) => s.groupId), ['color', 'ink', 'text1', 'date', 'photos']);
    expect(selections[0].valueLabel!.en, 'Walnut');
    expect(selections[0].priceDelta, 5000);
    expect(selections[1].hex, '#D32F2F');
    expect(selections[2].text, 'Happy B-day');
    expect(selections[3].date, DateTime(2026, 12, 25));
    expect(selections[4].urls, ['u1', 'u2']);
    expect(c.photosByGroup.keys, ['photos']);
  });
}

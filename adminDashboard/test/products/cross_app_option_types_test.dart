import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/features/products/data/products_admin_repository.dart';
import 'package:golden_gift_admin/features/products/domain/product_draft.dart';

import 'products_test_helpers.dart';

/// SRS §10 Phase 5 exit criterion: "a product using every option type renders
/// and validates correctly in the app". Built with the editor's model code,
/// saved through the dashboard repository, read back with the app's
/// `ProductModel.fromMap` and checked with the app's option engine.
void main() {
  ProductDraft everyOptionType() {
    final draft = ProductDraft(
      title: const LocalizedText('Personalised Wedding Frame', ar: 'إطار زفاف مخصص', ku: 'چوارچێوەی زەماوەند'),
      description: const LocalizedText('Walnut frame with your photos.\nEngraved name.'),
      storeId: 'golden-gift-home',
      categoryIds: ['frames', 'wedding'],
      price: 30000,
      compareAtPrice: 36000,
      availability: ProductAvailability.preparationDays,
      preparationDays: 2,
      availableCities: ['erbil'],
      stock: 20,
      tags: ['Anniversary'],
      giftFor: [GiftAudience.women, GiftAudience.men],
    )..addImageSlot('https://example.test/frame-1.jpg');
    draft.groups.addAll([
      OptionGroupDraft.newOf(OptionType.imageVariant)
        ..label = const LocalizedText('Frame Colour', ar: 'لون الإطار')
        ..required = true
        ..values.addAll([
          OptionValueDraft(
            label: const LocalizedText('Walnut'),
            imageUrl: 'https://example.test/walnut.jpg',
            priceDelta: 5000,
            preparationDaysOverride: 4,
          ),
          OptionValueDraft(label: const LocalizedText('Black'), imageUrl: 'https://example.test/black.jpg'),
        ]),
      OptionGroupDraft.newOf(OptionType.textVariant)
        ..label = const LocalizedText('Size')
        ..values.addAll([
          OptionValueDraft(label: const LocalizedText('30x30cm')),
          OptionValueDraft(label: const LocalizedText('20x20cm'), priceDelta: -2000, stock: 3),
        ]),
      OptionGroupDraft.newOf(OptionType.colorSwatch)
        ..label = const LocalizedText('Text Colour')
        ..values.addAll([
          OptionValueDraft(label: const LocalizedText('Gold'), hex: '#c9a227'),
          OptionValueDraft(label: const LocalizedText('Sold-out Red'), hex: '#C62828', stock: 0),
        ]),
      OptionGroupDraft.newOf(OptionType.text)
        ..label = const LocalizedText('Name')
        ..required = true
        ..maxLength = 12,
      OptionGroupDraft.newOf(OptionType.longText)..label = const LocalizedText('Notes'),
      OptionGroupDraft.newOf(OptionType.date)..label = const LocalizedText('Date'),
      OptionGroupDraft.newOf(OptionType.photoUpload)
        ..label = const LocalizedText('Upload your photos')
        ..required = true
        ..minPhotos = 2
        ..maxPhotos = 4,
      OptionGroupDraft.newOf(OptionType.quantity),
    ]);
    return draft;
  }

  final photo = PickedPhoto(Uint8List.fromList(const [1, 2, 3]));

  test('a product with all 8 option types is saved and read back by the app’s option engine', () async {
    final db = RecordingFirestore();
    final repo = ProductsAdminRepository(db);
    final draft = everyOptionType();
    expect(draft.validate(), isEmpty);

    final id = await repo.newProductId(draft.title.en);
    await repo.save(draft.toModel(id), isNew: true, adminUid: testAdmin.uid);
    expect(db.commits.single, ['set products/$id', startsWith('set admin_audit_log/')]);

    final stored = (await db.doc('products/$id').get()).data()!;
    final product = ProductModel.fromMap(id, stored);

    // Structure the app renders: every type, in builder order.
    expect(product.optionGroups.map((g) => g.type), OptionType.values);
    expect(product.optionGroups.map((g) => g.sortOrder), [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(product.optionGroups.map((g) => g.id),
        ['frame-colour', 'size', 'text-colour', 'name', 'notes', 'date', 'upload-your-photos', 'quantity']);
    expect(product.optionGroups[0].label, const LocalizedText('Frame Colour', ar: 'لون الإطار'));
    expect(product.optionGroups[0].values.map((v) => v.imageUrl),
        ['https://example.test/walnut.jpg', 'https://example.test/black.jpg']);
    expect(product.optionGroups[1].values.map((v) => v.id), ['30x30cm', '20x20cm']);
    expect(product.optionGroups[2].values.first.hex, '#C9A227');
    expect(product.colorDots, ['#C9A227', '#C62828']);
    expect(product.optionGroups[4].maxLength, 500, reason: 'long text default');
    expect(product.optionGroups[6].minPhotos, 2);
    expect(product.optionGroups[6].maxPhotos, 4);
    expect(product.preparationDays, 2);
    expect(product.images, ['https://example.test/frame-1.jpg']);

    final config = ProductConfiguration(product: product);

    // Input groups come back in order (quantity lives in the bottom bar).
    expect(config.inputGroups.map((g) => g.id),
        ['frame-colour', 'size', 'text-colour', 'name', 'notes', 'date', 'upload-your-photos']);

    // Required groups are reported missing, in display order.
    expect(config.validate(), const [
      OptionIssue('frame-colour', OptionIssueKind.missing),
      OptionIssue('name', OptionIssueKind.missing),
      OptionIssue('upload-your-photos', OptionIssueKind.missing),
    ]);

    // maxLength is enforced (12).
    expect(config.setText('name', 'Kirman & Lana').validate(), contains(const OptionIssue('name', OptionIssueKind.tooLong)));
    expect(config.setText('name', 'Kirman Lana!').validate().where((i) => i.groupId == 'name'), isEmpty);

    // Photo minimum, value stock.
    expect(config.setPhotos('upload-your-photos', [photo]).validate(),
        contains(const OptionIssue('upload-your-photos', OptionIssueKind.notEnoughPhotos)));
    expect(config.select('text-colour', 'sold-out-red').validate(),
        contains(const OptionIssue('text-colour', OptionIssueKind.unavailable)));

    // priceDelta (incl. negative) and preparationDaysOverride apply.
    final picked = config.select('frame-colour', 'walnut').select('size', '20x20cm');
    expect(picked.unitPrice, 30000 + 5000 - 2000);
    expect(picked.preparationDays, 4);
    expect(picked.maxQty, 3, reason: 'bounded by the 20x20cm value stock');
    expect(config.select('frame-colour', 'black').preparationDays, 2);

    // A complete configuration is valid.
    final complete = picked
        .select('text-colour', 'gold')
        .setText('name', 'Lana')
        .setPhotos('upload-your-photos', [photo, photo]);
    expect(complete.isValid, isTrue);
    expect(complete.setQty(2).lineTotal, 66000);

    // The derived query fields are exactly what the app computes.
    final derived = ProductDerived.of(product);
    derived.forEach((key, value) => expect(stored[key], value, reason: key));
    expect(stored['hasDiscount'], isTrue);
    expect(stored['cityKeys'], ['erbil']);
    expect(stored['catCityKeys'], ['frames|erbil', 'wedding|erbil']);
    expect(stored['searchKeywords'], containsAll(['personalised', 'wedding', 'frame', 'anniversary', 'اطار']));
    // Gift types: the app reads them back and filters on forKeys (SRS §5.8a).
    expect(product.giftFor, [GiftAudience.men, GiftAudience.women], reason: 'enum order, whatever the input order');
    expect(stored['giftFor'], ['men', 'women']);
    expect(stored['forKeys'], containsAll(['men', 'women|cat:wedding', 'men|city:erbil', 'women|cat:frames|city:erbil']));
  });

  test('re-editing keeps saved group and value ids even when labels change', () async {
    final db = RecordingFirestore();
    final repo = ProductsAdminRepository(db);
    final id = await repo.newProductId('Personalised Wedding Frame');
    await repo.save(everyOptionType().toModel(id), isNew: true, adminUid: testAdmin.uid);

    final draft = ProductDraft.fromModel((await repo.load(id))!);
    draft.groups[0]
      ..label = const LocalizedText('Frame Finish')
      ..values.first.label = const LocalizedText('Dark Walnut')
      ..values.add(OptionValueDraft(label: const LocalizedText('Walnut'))); // same label as a saved value
    draft.groups.insert(0, OptionGroupDraft.newOf(OptionType.text)..label = const LocalizedText('Name'));
    expect(draft.validate(), isEmpty);
    await repo.save(draft.toModel(id), isNew: false, adminUid: testAdmin.uid);

    final product = (await repo.load(id))!;
    expect(product.optionGroups.map((g) => g.id).take(3), ['name-2', 'frame-colour', 'size']);
    expect(product.optionGroups[1].values.map((v) => v.id), ['walnut', 'black', 'walnut-2']);
    expect(product.optionGroups[1].label.en, 'Frame Finish');
    // The app still resolves an old cart selection by its ids.
    final config = ProductConfiguration(product: product).select('frame-colour', 'walnut');
    expect(config.selectedValue(product.optionGroups[1])?.label.en, 'Dark Walnut');
    expect(config.unitPrice, 35000);
  });
}

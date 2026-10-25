import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift_admin/features/products/data/products_admin_repository.dart';
import 'package:golden_gift_admin/features/products/domain/product_draft.dart';
import 'package:golden_gift_admin/features/products/domain/product_search.dart';

/// The editor's model-building and validation rules (SRS §6.4, §9 "Products").
void main() {
  ProductDraft valid() => ProductDraft(
        title: const LocalizedText('Gift Box'),
        storeId: 'golden-gift-home',
        price: 25000,
        giftFor: [GiftAudience.men],
      );

  group('slugify / uniqueId', () {
    test('kebab-case ASCII like the seeded ids', () {
      expect(slugify("Mother's Day Mug!"), 'mothers-day-mug');
      expect(slugify('  Rose  Gold -- Ring '), 'rose-gold-ring');
      expect(slugify('30x30cm'), '30x30cm');
      expect(slugify('كوب'), '');
      expect(slugify('a' * 80), hasLength(60));
    });

    test('unique with -2, -3 …', () {
      expect(uniqueId('large', {}), 'large');
      expect(uniqueId('large', {'large', 'large-2'}), 'large-3');
    });
  });

  group('ids', () {
    test('auto from the English label, unique within the group; fallback by type', () {
      final g = OptionGroupDraft.newOf(OptionType.textVariant)
        ..values.addAll([
          OptionValueDraft(label: const LocalizedText('Large')),
          OptionValueDraft(label: const LocalizedText('Large')),
          OptionValueDraft(),
        ]);
      final draft = valid()..groups.addAll([g, OptionGroupDraft.newOf(OptionType.photoUpload)]);
      draft.normalizeIds();
      expect(g.id, 'variant');
      expect(g.values.map((v) => v.id), ['large', 'large-2', 'value']);
      expect(draft.groups[1].id, 'photos');
    });

    test('saved ids never change; new ones avoid them', () {
      final g = OptionGroupDraft.newOf(OptionType.textVariant)..label = const LocalizedText('Size');
      g.values.add(OptionValueDraft(label: const LocalizedText('Small')));
      final draft = valid()..groups.add(g);
      draft.lockIds();
      g.label = const LocalizedText('Dimensions');
      g.values.first.label = const LocalizedText('Tiny');
      g.values.add(OptionValueDraft(label: const LocalizedText('Small')));
      draft.groups.add(OptionGroupDraft.newOf(OptionType.text)..label = const LocalizedText('Size'));
      draft.normalizeIds();
      expect(g.id, 'size');
      expect(g.values.map((v) => v.id), ['small', 'small-2']);
      expect(draft.groups[1].id, 'size-2');
    });
  });

  group('validate', () {
    test('a minimal product is valid', () => expect(valid().validate(), isEmpty));

    test('title, store, price, compare-at, preparation days', () {
      final d = ProductDraft(compareAtPrice: 1000, availability: ProductAvailability.preparationDays);
      expect(d.validate(), [
        'English title is required.',
        'Choose a store.',
        'Choose who it is a gift for (at least one).',
        'Price must be greater than 0.',
        'Preparation days must be at least 1 when availability is “Preparation days”.',
      ]);
      d
        ..title = const LocalizedText('X')
        ..storeId = 's'
        ..price = 1000
        ..preparationDays = 3
        ..setGiftFor(GiftAudience.companies, true);
      expect(d.validate(), ['Compare-at price must be greater than the price (or empty).']);
      d.compareAtPrice = 1500;
      expect(d.validate(), isEmpty);
    });

    test('value groups need values, labels and valid hex; photo bounds; one quantity group', () {
      final d = valid()
        ..groups.addAll([
          OptionGroupDraft.newOf(OptionType.imageVariant)..label = const LocalizedText('Frame'),
          OptionGroupDraft.newOf(OptionType.colorSwatch)
            ..label = const LocalizedText('Ink')
            ..values.addAll([
              OptionValueDraft(label: const LocalizedText('Red'), hex: 'red'),
              OptionValueDraft(hex: '#00FF00'),
            ]),
          OptionGroupDraft.newOf(OptionType.photoUpload)
            ..label = const LocalizedText('Photos')
            ..minPhotos = 3
            ..maxPhotos = 2,
          OptionGroupDraft.newOf(OptionType.text),
          OptionGroupDraft.newOf(OptionType.quantity),
          OptionGroupDraft.newOf(OptionType.quantity),
        ]);
      expect(d.validate(), [
        'Only one Quantity group is allowed.',
        'Option group 1 (Frame): add at least one value.',
        'Option group 2 (Ink), value 1 (Red): colour must be #RRGGBB.',
        'Option group 2 (Ink), value 2: English label is required.',
        'Option group 3 (Photos): photos must satisfy 1 ≤ min ≤ max ≤ 10.',
        'Option group 4 (Text): English label is required.',
      ]);
    });

    test('duplicate ids from hand-edited data are reported', () {
      const p = ProductModel(
        id: 'p',
        title: LocalizedText('P'),
        storeId: 's',
        price: 1000,
        giftFor: [GiftAudience.women],
        optionGroups: [
          OptionGroup(id: 'size', type: OptionType.textVariant, label: LocalizedText('Size'), values: [
            OptionValue(id: 's', label: LocalizedText('S')),
            OptionValue(id: 's', label: LocalizedText('Small')),
          ]),
          OptionGroup(id: 'size', type: OptionType.date, label: LocalizedText('Date'), sortOrder: 1),
        ],
      );
      expect(ProductDraft.fromModel(p).validate(), [
        'Option group 1 (Size), value 2 (Small): id “s” is used by another value.',
        'Option group 2 (Date): id “size” is used by another group.',
      ]);
    });
  });

  group('gift for (SRS §5.8a)', () {
    test('required: a new product starts with none, so the admin must choose', () {
      final d = ProductDraft(title: const LocalizedText('Mug'), storeId: 's', price: 1000);
      expect(d.giftFor, isEmpty);
      expect(d.validate(), ['Choose who it is a gift for (at least one).']);
      d.setGiftFor(GiftAudience.women, true);
      expect(d.validate(), isEmpty);
      d.setGiftFor(GiftAudience.women, false);
      expect(d.validate(), contains(giftForRequiredMessage));
    });

    test('a product saved before Phase 11 (no giftFor) must pick one before saving', () {
      const old = ProductModel(id: 'old', title: LocalizedText('Old'), storeId: 's', price: 1000);
      final d = ProductDraft.fromModel(old);
      expect(d.giftFor, isEmpty);
      expect(d.validate(), [giftForRequiredMessage]);
    });

    test('kept in GiftAudience order, without duplicates; saved as enum names with forKeys', () {
      final d = valid()
        ..setGiftFor(GiftAudience.companies, true)
        ..setGiftFor(GiftAudience.companies, true)
        ..setGiftFor(GiftAudience.men, false)
        ..setGiftFor(GiftAudience.women, true)
        ..categoryIds.add('mugs');
      expect(d.giftFor, [GiftAudience.women, GiftAudience.companies]);
      final m = d.toModel('mug');
      expect(m.giftFor, [GiftAudience.women, GiftAudience.companies]);
      expect(m.toMap()['giftFor'], ['women', 'companies']);
      final data = ProductsAdminRepository.productData(m);
      expect(data['forKeys'], [
        'women', 'women|cat:mugs', 'women|city:all', 'women|cat:mugs|city:all',
        'companies', 'companies|cat:mugs', 'companies|city:all', 'companies|cat:mugs|city:all',
      ]);
      expect(data['forKeys'], ProductDerived.of(m)['forKeys']);
    });

    test('unsaved-changes fingerprint follows the gift types', () {
      final d = valid();
      final before = d.fingerprint();
      d.setGiftFor(GiftAudience.companies, true);
      expect(d.fingerprint(), isNot(before));
      d.setGiftFor(GiftAudience.companies, false);
      expect(d.fingerprint(), before);
    });
  });

  group('toModel', () {
    test('same day saves 0 preparation days; empty image slots dropped; type-specific fields only', () {
      final d = valid()
        ..preparationDays = 5
        ..addImageSlot('https://example.test/a.jpg')
        ..addImageSlot()
        ..addImageSlot('  ')
        ..groups.addAll([
          OptionGroupDraft.newOf(OptionType.date)
            ..label = const LocalizedText('Date')
            ..maxLength = 9
            ..values.add(OptionValueDraft(label: const LocalizedText('ignored'))),
          OptionGroupDraft.newOf(OptionType.textVariant)
            ..label = const LocalizedText('Size')
            ..values.add(OptionValueDraft(label: const LocalizedText('L'), hex: '#FFFFFF', imageUrl: 'x')),
        ]);
      final m = d.toModel('gift-box');
      expect(m.preparationDays, 0);
      expect(m.images, ['https://example.test/a.jpg']);
      expect(m.optionGroups[0].maxLength, isNull);
      expect(m.optionGroups[0].values, isEmpty);
      expect(m.optionGroups[1].values.single.hex, isNull);
      expect(m.optionGroups[1].values.single.imageUrl, isNull);
      d.availability = ProductAvailability.outOfStock;
      expect(d.toModel('gift-box').preparationDays, 5);
    });

    test('round-trips a saved product unchanged', () {
      const p = ProductModel(
        id: 'mug',
        title: LocalizedText('Mug', ar: 'كوب'),
        description: LocalizedText('Ceramic'),
        storeId: 's',
        categoryIds: ['mugs'],
        images: ['https://example.test/1.jpg'],
        price: 15000,
        compareAtPrice: 18000,
        availability: ProductAvailability.preparationDays,
        preparationDays: 2,
        availableCities: ['erbil'],
        stock: 4,
        isFeatured: true,
        salesCount: 12,
        tags: ['tea'],
        giftFor: [GiftAudience.men, GiftAudience.companies],
        optionGroups: [
          OptionGroup(id: 'ink', type: OptionType.colorSwatch, label: LocalizedText('Ink'), required: true, values: [
            OptionValue(id: 'red', label: LocalizedText('Red'), hex: '#C62828', priceDelta: 500, stock: 2),
          ]),
          OptionGroup(id: 'name', type: OptionType.text, label: LocalizedText('Name'), maxLength: 20, sortOrder: 1),
        ],
      );
      final draft = ProductDraft.fromModel(p);
      expect(draft.toModel('mug').toMap(), p.toMap());
      expect(draft.fingerprint(), ProductDraft.fromModel(p).fingerprint());
    });
  });

  test('image storage index comes from the download URL, so new uploads never overwrite', () {
    const url = 'https://firebasestorage.googleapis.com/v0/b/gg/o/products%2Fmug%2F3.jpg?alt=media&token=t';
    expect(ProductDraft.storageIndexOf(url), 3);
    expect(ProductDraft.storageIndexOf('https://picsum.photos/seed/x/800/800'), isNull);
    expect(ProductDraft.storageIndexOf('https://x/o/products%2Fmug%2Foptions%2Fa-b.jpg?alt=media'), isNull);
    final d = ProductDraft.fromModel(const ProductModel(
      id: 'mug',
      title: LocalizedText('Mug'),
      storeId: 's',
      price: 1,
      images: [url, 'https://picsum.photos/seed/x/800/800'],
    ));
    expect(d.images.map((s) => s.storageIndex), [3, 4]);
    expect(d.addImageSlot().storageIndex, 5);
  });

  group('search', () {
    const p = ProductModel(
      id: 'custom-photo-mug',
      title: LocalizedText('Custom Photo Mug', ar: 'كوب صورة'),
      storeId: 's',
      price: 1,
      tags: ['Ceramic'],
    );

    test('client filter: every word, part of a word, any language, id or tag', () {
      expect(matchesProductSearch(p, 'pho mu'), isTrue);
      expect(matchesProductSearch(p, 'CERAMIC'), isTrue);
      expect(matchesProductSearch(p, 'custom-photo'), isTrue);
      expect(matchesProductSearch(p, 'کوب'), isTrue, reason: 'Kurdish keyboard ک matches Arabic ك');
      expect(matchesProductSearch(p, 'frame'), isFalse);
    });

    test('server lookup only for a single token', () {
      expect(singleSearchKeyword(' Mug '), 'mug');
      expect(singleSearchKeyword('photo mug'), isNull);
      expect(singleSearchKeyword('m'), isNull);
    });
  });
}

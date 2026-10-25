import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/reels/data/reel_derived.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/reel_model.dart';

/// Same cases as functions/test/reelDerived.test.ts (fixture `reelKeys`): the
/// dashboard and onReelWrite / onProductWrite must derive identical fields.
void main() {
  final fixture = jsonDecode(File('test/fixtures/product_query_keys.json').readAsStringSync())
      as Map<String, dynamic>;
  final reelKeys = fixture['reelKeys'] as Map<String, dynamic>;

  group('ReelKeys.filterKey', () {
    for (final c in (reelKeys['filterKey'] as List).cast<Map<String, dynamic>>()) {
      test('${c['category']} + ${c['audience']}', () {
        final audience = c['audience'] as String?;
        expect(
          ReelKeys.filterKey(
            categoryId: c['category'] as String?,
            audience: audience == null ? null : GiftAudience.values.byName(audience),
          ),
          c['filterKey'],
        );
      });
    }
  });

  group('ReelDerived.fieldsFor', () {
    for (final c in (reelKeys['derived'] as List).cast<Map<String, dynamic>>()) {
      final product = c['product'] as Map<String, dynamic>?;
      test('${product?['title']} (active: ${(c['reel'] as Map)['isActive']})', () {
        expect(
          ReelDerived.fieldsFor(
            isActive: (c['reel'] as Map)['isActive'] as bool,
            product: product == null ? null : ProductModel.fromMap('p', product),
          ),
          c['output'],
        );
      });
    }

    test('the derived map round-trips through ReelModel.fromMap', () {
      final c = (reelKeys['derived'] as List).first as Map<String, dynamic>;
      final derived = ReelDerived.fieldsFor(
          isActive: true, product: ProductModel.fromMap('p', c['product'] as Map<String, dynamic>));
      final reel = ReelModel.fromMap('r1', {'productId': 'p', 'videoUrl': 'https://v/1.mp4', ...derived});
      expect(reel.visible, isTrue);
      expect(reel.product!.price, 30000);
      expect(reel.product!.hasDiscount, isTrue);
      expect(reel.giftFor, [GiftAudience.men, GiftAudience.women]);
      expect(reel.filterKeys, contains(ReelKeys.filterKey(categoryId: 'love', audience: GiftAudience.women)));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/promo_rules.dart';
import 'package:golden_gift/models/promo_code_model.dart';

/// Same cases as the server (functions/src/orders/promoRules.ts).
void main() {
  final cases = (jsonDecode(File('test/fixtures/promo_cases.json').readAsStringSync()) as Map)['cases'] as List;

  for (final c in cases.cast<Map<String, dynamic>>()) {
    test(c['name'], () {
      final promoMap = c['promo'] as Map<String, dynamic>?;
      final promo = promoMap == null
          ? null
          : PromoCodeModel.fromMap(promoMap['code'] as String, {
              ...promoMap,
              if (promoMap['expiresAt'] != null) 'expiresAt': DateTime.parse(promoMap['expiresAt'] as String),
            });
      final lines = [
        for (final l in (c['lines'] as List).cast<Map<String, dynamic>>())
          PromoLine(
            productId: l['productId'] as String,
            storeId: l['storeId'] as String,
            categoryIds: (l['categoryIds'] as List).cast<String>(),
            lineTotal: l['lineTotal'] as int,
          ),
      ];
      final result = PromoRules.evaluate(
        promo,
        lines: lines,
        now: DateTime.parse(c['now'] as String),
        userUsageCount: c['userUsageCount'] as int,
        userOrderCount: c['userOrderCount'] as int,
      );
      final expected = c['expected'] as Map<String, dynamic>;
      if (expected.containsKey('rejection')) {
        expect(result.rejection?.name, expected['rejection']);
        expect(result.discount, 0);
      } else {
        expect(result.rejection, isNull);
        expect(result.discount, expected['discount']);
      }
    });
  }

  test('codes are normalized to upper case without spaces', () {
    expect(PromoCodeModel.normalize(' gold 10 '), 'GOLD10');
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/order_model.dart';

/// The same fixture is checked by functions/test/orderTransitions.test.ts, so
/// the dashboard offers exactly the status moves `updateOrderItems` accepts
/// (SRS §5.12, §9 Seller view).
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/order_status_transitions.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('flow', () {
    expect([for (final s in OrderStatusX.flow) s.name], fixture['flow']);
  });

  test('every status is in the fixture', () {
    expect(
      (fixture['allowedNext'] as Map<String, dynamic>).keys.toSet(),
      {for (final s in OrderStatus.values) s.name},
    );
  });

  for (final status in OrderStatus.values) {
    test('allowedNext(${status.name})', () {
      expect([for (final s in status.allowedNext) s.name], (fixture['allowedNext'] as Map<String, dynamic>)[status.name]);
    });
  }
}

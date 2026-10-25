import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/app_dates.dart';
import 'package:golden_gift/features/checkout/domain/checkout_rules.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/localized_text.dart';

/// The same fixture is checked by functions/test/checkoutRules.test.ts, so the
/// Checkout screen offers exactly the dates and slots `placeOrder` accepts
/// (SRS §5.11). Every `now` in it is Iraq wall-clock time.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/checkout_rules_cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  List<DeliverySlot> slotsOf(Object? raw) => raw == null
      ? DeliverySlot.defaults
      : [
          for (final s in (raw as List).cast<Map<String, dynamic>>())
            DeliverySlot(
              id: s['id'] as String,
              label: LocalizedText(s['id'] as String),
              from: s['from'] as String,
              to: s['to'] as String,
            ),
        ];

  test('default slots match the server defaults', () {
    expect(
      [for (final s in DeliverySlot.defaults) {'id': s.id, 'from': s.from, 'to': s.to}],
      fixture['defaultSlots'],
    );
  });

  group('earliestDeliveryDate', () {
    for (final c in (fixture['earliestDeliveryDate'] as List).cast<Map<String, dynamic>>()) {
      test('${c['now']} cut-off "${c['sameDayCutoff']}" +${c['maxPreparationDays']} days', () {
        final earliest = CheckoutRules.earliestDeliveryDate(
          now: DateTime.parse(c['now'] as String),
          maxPreparationDays: c['maxPreparationDays'] as int,
          sameDayCutoff: c['sameDayCutoff'] as String,
        );
        expect(AppDates.isoDate(earliest), c['earliest']);
      });
    }
  });

  group('availableSlots', () {
    for (final c in (fixture['availableSlots'] as List).cast<Map<String, dynamic>>()) {
      test('${c['date']} at ${c['now']}', () {
        final slots = CheckoutRules.availableSlots(
          DateTime.parse(c['date'] as String),
          DateTime.parse(c['now'] as String),
          slotsOf(c['slots']),
        );
        expect([for (final s in slots) s.id], c['available']);
      });
    }
  });

  group('deliveryDates', () {
    for (final c in (fixture['deliveryDates'] as List).cast<Map<String, dynamic>>()) {
      test('${c['earliest']} → ${c['last']}', () {
        final dates = CheckoutRules.deliveryDates(DateTime.parse(c['earliest'] as String));
        expect(dates.length, c['count']);
        expect(AppDates.isoDate(dates.first), c['earliest']);
        expect(AppDates.isoDate(dates.last), c['last']);
      });
    }
  });
}

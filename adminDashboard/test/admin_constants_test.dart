import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift_admin/core/constants/admin_constants.dart';
import 'package:golden_gift_admin/core/constants/firestore_paths.dart';

/// Full mobile ↔ admin parity is checked in mobile/test/core/shared_constants_parity_test.dart.
void main() {
  test('stored enum values use the SRS §6.15 spellings', () {
    expect(OrderStatus.values.map((e) => e.name), contains('readyForDelivery'));
    expect(PaymentMethod.values.map((e) => e.name), ['cashOnDelivery', 'wallet', 'card', 'fastPay', 'zainCash']);
    expect(AdminConstants.currencyCode, 'IQD');
  });

  test('admin-only collections are defined', () {
    expect(FirestorePaths.admins, 'admins');
    expect(FirestorePaths.adminAuditLog, 'admin_audit_log');
    expect(FirestorePaths.orderHistory('o1'), 'orders/o1/status_history');
  });
}

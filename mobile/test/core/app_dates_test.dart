import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/app_dates.dart';

void main() {
  test('formats without intl locale data', () {
    final d = DateTime(2026, 3, 7, 9, 5);
    expect(AppDates.isoDate(d), '2026-03-07');
    expect(AppDates.display(d), '07/03/2026');
    expect(AppDates.displayWithTime(d), '07/03/2026 09:05');
  });
}

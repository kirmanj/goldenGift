import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/app_dates.dart';

void main() {
  test('iraqNow is UTC+3 wall-clock time whatever the device zone', () {
    final t = AppDates.iraqNow(DateTime.utc(2026, 10, 21, 22, 30));
    expect([t.year, t.month, t.day, t.hour, t.minute], [2026, 10, 22, 1, 30]);
    expect(t.isUtc, isFalse);
  });
}

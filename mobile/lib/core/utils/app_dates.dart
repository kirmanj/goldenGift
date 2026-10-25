/// Date formats that never depend on `intl` locale data (which has no `ckb`
/// and must be initialized before use). Western digits, as on the reference screens.
class AppDates {
  AppDates._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 2026-11-02 — wire format (orders.deliveryDate, function payloads).
  static String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// 02/11/2026 — what customers see (SRS §5.23 "dd/mm/yyyy").
  static String display(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

  /// 02/11/2026 14:05
  static String displayWithTime(DateTime d) => '${display(d)} ${_two(d.hour)}:${_two(d.minute)}';

  /// Iraq has one time zone, UTC+3 with no daylight saving. Delivery dates,
  /// slots and the same-day cut-off are Iraq wall-clock times on the server
  /// (`placeOrder`), so checkout uses this — not the device's zone. Returned
  /// as a plain (local-kind) DateTime holding Iraq's wall-clock fields.
  static DateTime iraqNow([DateTime? utcNow]) {
    final t = (utcNow ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }
}

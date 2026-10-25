import 'package:intl/intl.dart';

/// IQD formatting — 0 decimal places, thousands separator.
/// Always use this; never format prices manually.
class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _fmt = NumberFormat('#,##0', 'en_US');

  static String format(num amount, {String code = 'IQD'}) =>
      '${_fmt.format(amount)} $code';

  static String formatCompact(num amount) => _fmt.format(amount);
}

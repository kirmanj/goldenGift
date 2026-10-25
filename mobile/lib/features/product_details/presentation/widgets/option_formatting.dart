import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Display helpers shared by Product Details and the Cart.

/// 15/03/2026 in every language (no intl locale data — there is none for `ckb`).
String formatOptionDate(DateTime date) => AppDates.display(date);

/// Option dates are stored as UTC noon so the calendar day survives any time
/// zone the cart / order is read in.
DateTime optionDateValue(DateTime picked) => DateTime.utc(picked.year, picked.month, picked.day, 12);

/// "+5,000 IQD" / "−2,000 IQD"; null when the option doesn't change the price.
String? priceDeltaLabel(int delta) {
  if (delta == 0) return null;
  return '${delta > 0 ? '+' : '−'}${CurrencyFormatter.format(delta.abs())}';
}

/// `#RRGGBB` / `#AARRGGBB` → Color; null when missing or malformed.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Error-red for small hint text: the base red in light mode, lifted towards
/// white in dark mode so it keeps ≥ 4.5:1 on the black background.
Color errorTextColor(BuildContext context) => AppColors.isDark(context)
    ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), AppColors.error)
    : AppColors.error;

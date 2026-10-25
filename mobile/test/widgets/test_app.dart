import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';

/// Wraps [child] in a MaterialApp with the real Golden Gift themes and
/// localizations (incl. the Kurdish fallback) inside a Scaffold.
Widget testApp(
  Widget child, {
  Locale locale = const Locale('en'),
  bool dark = false,
  double? width,
  double textScale = 1,
}) {
  return MaterialApp(
    locale: locale,
    theme: AppTheme.lightTheme(locale),
    darkTheme: AppTheme.darkTheme(locale),
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...KurdishFallbackLocalizations.delegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: app!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

/// Swatch hexes used by [discountedProduct] (6 values; cards show 5).
const swatchHexes = ['#E53935', '#8E24AA', '#EC407A', '#1E88E5', '#FDD835', '#43A047'];

/// Discounted (35,000 / 40,000 → 13%), featured, colour swatches, no
/// images (so tests never touch the network).
ProductModel discountedProduct() => ProductModel(
      id: 'p1',
      storeId: 's1',
      title: const LocalizedText(
        'Floral Candle Chest With A Long Name That Wraps',
        ar: 'صندوق شموع الورود باسم طويل جداً يلتف على سطرين',
        ku: 'سندوقی مۆمی گوڵ بە ناوێکی درێژ',
      ),
      price: 35000,
      compareAtPrice: 40000,
      isFeatured: true,
      optionGroups: [
        OptionGroup(
          id: 'color',
          type: OptionType.colorSwatch,
          label: const LocalizedText('Color'),
          values: [
            for (final hex in swatchHexes)
              OptionValue(id: hex, label: LocalizedText(hex), hex: hex),
          ],
        ),
      ],
    );

ProductModel plainProduct() => const ProductModel(
      id: 'p2',
      storeId: 's1',
      title: LocalizedText('Red Roses Bouquet'),
      price: 29000,
    );

ProductModel outOfStockProduct() => const ProductModel(
      id: 'p3',
      storeId: 's1',
      title: LocalizedText('Leather Keychain'),
      price: 12000,
      availability: ProductAvailability.outOfStock,
    );

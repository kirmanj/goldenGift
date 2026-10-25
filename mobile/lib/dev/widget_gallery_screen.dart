import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/providers/locale_provider.dart';
import '../core/providers/theme_provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_text_styles.dart';
import '../core/widgets/widgets.dart';
import '../l10n/l10n.dart';
import '../models/localized_text.dart';
import '../models/product_model.dart';

/// Dev-only gallery of every Phase 1 reusable widget (SRS §10 Phase 1),
/// with app-bar toggles for light/dark theme and en/ar/ckb language so
/// each widget can be checked in all six combinations. Route: /dev/gallery.
/// Section headings are plain English on purpose (developer tool).
class WidgetGalleryScreen extends ConsumerStatefulWidget {
  const WidgetGalleryScreen({super.key});

  @override
  ConsumerState<WidgetGalleryScreen> createState() => _WidgetGalleryScreenState();
}

class _WidgetGalleryScreenState extends ConsumerState<WidgetGalleryScreen> {
  final Set<String> _wishlist = {'p2'};
  int _selectedChip = 0;
  bool _loading = false;
  bool _heart = false;
  String _query = '';

  static const _languages = AppConstants.supportedLocales;

  static String _img(String seed, [int w = 600, int h = 600]) =>
      'https://picsum.photos/seed/$seed/$w/$h';

  static final List<ProductModel> _products = [
    ProductModel(
      id: 'p1',
      storeId: 'demo',
      title: const LocalizedText(
        'Floral Candle Chest',
        ar: 'صندوق شموع الورود',
        ku: 'سندوقی مۆمی گوڵ',
      ),
      images: [_img('candle')],
      price: 35000,
      compareAtPrice: 40000,
      isFeatured: true,
      optionGroups: const [
        OptionGroup(
          id: 'color',
          type: OptionType.colorSwatch,
          label: LocalizedText('Color', ar: 'اللون', ku: 'ڕەنگ'),
          values: [
            OptionValue(id: 'red', label: LocalizedText('Red'), hex: '#E53935'),
            OptionValue(id: 'purple', label: LocalizedText('Purple'), hex: '#8E24AA'),
            OptionValue(id: 'pink', label: LocalizedText('Pink'), hex: '#EC407A'),
            OptionValue(id: 'blue', label: LocalizedText('Blue'), hex: '#1E88E5'),
            OptionValue(id: 'yellow', label: LocalizedText('Yellow'), hex: '#FDD835'),
            OptionValue(id: 'green', label: LocalizedText('Green'), hex: '#43A047'),
          ],
        ),
      ],
    ),
    ProductModel(
      id: 'p2',
      storeId: 'demo',
      title: const LocalizedText(
        'Romantic Red Roses & Chocolate Bouquet',
        ar: 'باقة ورود حمراء رومانسية مع الشوكولاتة',
        ku: 'چەپکە گوڵی سووری ڕۆمانسی لەگەڵ چکلێت',
      ),
      images: [_img('roses')],
      price: 29000,
    ),
    ProductModel(
      id: 'p3',
      storeId: 'demo',
      title: const LocalizedText(
        'Handmade Engraved Leather Keychain',
        ar: 'ميدالية جلدية محفورة يدوياً',
        ku: 'کلیلدانی چەرمی هەڵکۆڵراوی دەستکرد',
      ),
      images: [_img('leather')],
      price: 12000,
      availability: ProductAvailability.outOfStock,
    ),
    const ProductModel(
      id: 'p4',
      storeId: 'demo',
      title: LocalizedText(
        'Personalized Wooden Photo Frame With Engraved Names And Date',
        ar: 'إطار صور خشبي مخصص مع أسماء وتاريخ محفور',
        ku: 'چوارچێوەی وێنەی دارینی تایبەت بە ناو و بەرواری هەڵکۆڵراو',
      ),
      price: 1250000,
      compareAtPrice: 1500000,
    ),
  ];

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ref.watch(localeProvider);
    final dark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: 'Widget Gallery',
        actions: [
          GGCircleButton(
            icon: dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            tooltip: dark ? 'Switch to light' : 'Switch to dark',
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .setMode(dark ? ThemeMode.light : ThemeMode.dark),
          ),
          GGCircleButton(
            tooltip: 'Language: ${locale.languageCode}',
            onPressed: () {
              final i = _languages.indexOf(locale.languageCode);
              ref.read(localeProvider.notifier).setLocale(_languages[(i + 1) % _languages.length]);
            },
            child: Text(
              locale.languageCode.toUpperCase(),
              style: AppTextStyles.label.copyWith(
                fontSize: 13,
                color: AppColors.gold(context),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding.copyWith(bottom: AppSpacing.xxl * 2),
        children: [
          const _Section(
            title: 'GGLogo',
            children: [
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.md,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GGLogo(),
                  GGLogo(size: 40, direction: Axis.horizontal),
                  GGLogo(size: 48, showWordmark: false),
                ],
              ),
            ],
          ),
          _Section(
            title: 'GGAppBar · GGCircleButton',
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: GGAppBar(
                  title: l10n.productDetails,
                  showBack: true,
                  onBack: () => _toast('Back'),
                  cartCount: 3,
                  onCartTap: () => _toast(l10n.cart),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                children: [
                  GGCircleButton(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Notifications',
                    onPressed: () => _toast('Bell'),
                  ),
                  GGCircleButton(
                    icon: Icons.shopping_bag_outlined,
                    iconColor: AppColors.gold(context),
                    tooltip: l10n.cart,
                    badgeCount: 120,
                    onPressed: () => _toast(l10n.cart),
                  ),
                  const GGCircleButton(icon: Icons.tune_rounded, tooltip: 'Disabled'),
                ],
              ),
            ],
          ),
          _Section(
            title: 'PrimaryButton · OutlineButton',
            children: [
              Row(
                children: [
                  Text('isLoading',
                      style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                  const Spacer(),
                  Switch.adaptive(
                    value: _loading,
                    activeTrackColor: AppColors.gold(context),
                    onChanged: (v) => setState(() => _loading = v),
                  ),
                ],
              ),
              PrimaryButton(
                label: l10n.addToCart,
                icon: Icons.shopping_bag_outlined,
                isLoading: _loading,
                onPressed: () => _toast(l10n.addToCart),
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(label: '${l10n.signUp} (disabled)', onPressed: null),
              const SizedBox(height: AppSpacing.sm),
              OutlineButton(
                label: l10n.inviteFriends,
                icon: Icons.person_add_alt_1_outlined,
                isLoading: _loading,
                onPressed: () => _toast(l10n.inviteFriends),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlineButton(label: '${l10n.cancel} (disabled)', onPressed: null),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  PrimaryButton(
                    label: l10n.share,
                    icon: Icons.ios_share_rounded,
                    expand: false,
                    height: 44,
                    onPressed: () => _toast(l10n.share),
                  ),
                  OutlineButton(
                    label: l10n.apply,
                    expand: false,
                    height: 44,
                    onPressed: () => _toast(l10n.apply),
                  ),
                ],
              ),
            ],
          ),
          _Section(
            title: 'GGInput',
            children: [
              GGInput(label: l10n.yourName, hint: l10n.enterYourName),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: l10n.email,
                hint: l10n.enterYourEmail,
                initialValue: 'not-an-email',
                errorText: 'Enter a valid email address',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: l10n.mobileNumber,
                hint: l10n.enterYourNumber,
                keyboardType: TextInputType.phone,
                prefix: const _CountryCodeStub(code: AppConstants.defaultCountryCode),
              ),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: 'Text 1',
                hint: l10n.customizeTextHint,
                maxLength: 50,
                showCounter: true,
              ),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: l10n.notes,
                hint: l10n.writeYourIdeaHere,
                multiline: true,
                minLines: 3,
                maxLength: 500,
                showCounter: true,
              ),
            ],
          ),
          _Section(
            title: 'GGSearchBar',
            children: [
              GGSearchBar(
                hint: l10n.searchForProduct,
                onChanged: (q) => setState(() => _query = q),
                onFilterTap: () => _toast(l10n.filter),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Debounced (400 ms) query: "$_query"',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
              ),
              const SizedBox(height: AppSpacing.md),
              GGSearchBar(
                readOnly: true,
                hint: l10n.aiGiftSearchHint,
                onTap: () => _toast(l10n.aiGiftSearch),
              ),
            ],
          ),
          _Section(
            title: 'CategoryChip',
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (i, chip) in [
                      (l10n.all, null, null),
                      ('Flowers', Icons.local_florist_outlined, null),
                      ('Handmade', null, _img('handmade', 96, 96)),
                      ('Birthdays', Icons.cake_outlined, null),
                      ('Magnets', null, _img('magnet', 96, 96)),
                      ('Easter Day', Icons.egg_outlined, null),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.sm),
                      CategoryChip(
                        label: chip.$1,
                        icon: chip.$2,
                        imageUrl: chip.$3,
                        comingSoon: chip.$1 == 'Easter Day',
                        selected: _selectedChip == i,
                        onTap: () => setState(() => _selectedChip = i),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          _Section(
            title: 'CategoryTile',
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  const columns = 4;
                  const gap = AppSpacing.sm + AppSpacing.xs;
                  final cell = (c.maxWidth - gap * (columns - 1)) / columns;
                  final tiles = [
                    CategoryTile(label: 'Flowers', iconUrl: _img('bouquet', 200, 200)),
                    CategoryTile(label: 'Anniversary', iconUrl: _img('party', 200, 200)),
                    const CategoryTile(label: 'Birthdays', icon: Icons.cake_outlined),
                    const CategoryTile(label: 'Magnets', icon: Icons.push_pin_outlined),
                    const CategoryTile(label: 'Golden Gift Home', icon: Icons.home_outlined),
                    const CategoryTile(label: 'Easter Day', icon: Icons.egg_outlined, comingSoon: true),
                    const CategoryTile(label: 'Wall Decorations', icon: Icons.photo_outlined),
                    CategoryTile.more(onTap: () => _toast(l10n.allCategories)),
                  ];
                  return GridView.count(
                    crossAxisCount: columns,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: gap,
                    childAspectRatio: cell / CategoryTile.heightFor(context, cell),
                    children: tiles,
                  );
                },
              ),
            ],
          ),
          _Section(
            title: 'SectionHeader · ProductCard',
            children: [
              SectionHeader(title: l10n.popular, onViewAll: () => _toast(l10n.viewAll)),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, c) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _products.length,
                  gridDelegate: ProductCard.gridDelegate(context, c.maxWidth),
                  itemBuilder: (context, i) {
                    final p = _products[i];
                    return ProductCard(
                      product: p,
                      isWishlisted: _wishlist.contains(p.id),
                      onTap: () => _toast(p.id),
                      onWishlistChanged: (v) => setState(
                        () => v ? _wishlist.add(p.id) : _wishlist.remove(p.id),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SectionHeader(title: '${l10n.featured} (no View All)'),
            ],
          ),
          _Section(
            title: 'BannerCarousel',
            children: [
              BannerCarousel(
                imageUrls: [
                  _img('banner-gold', 1600, 700),
                  _img('banner-gift', 1600, 700),
                  _img('banner-flowers', 1600, 700),
                ],
                onTap: (i) => _toast('Banner $i'),
              ),
            ],
          ),
          _Section(
            title: 'InfoBanner',
            children: [
              InfoBanner(type: InfoBannerType.warning, message: l10n.preparationDays(2)),
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(type: InfoBannerType.success, message: l10n.sameDayShipping),
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(type: InfoBannerType.info, message: l10n.availableOnlyIn('Erbil, Duhok')),
              const SizedBox(height: AppSpacing.sm),
              InfoBanner(type: InfoBannerType.error, message: l10n.somethingWentWrong),
            ],
          ),
          _Section(
            title: 'PriceText · DiscountBadge · FeaturedBadge · WishlistHeart',
            children: [
              const PriceText(price: 35000, oldPrice: 40000, discountPercent: 13),
              const SizedBox(height: AppSpacing.sm),
              const PriceText(price: 12000),
              const SizedBox(height: AppSpacing.sm),
              const PriceText(price: 40000, oldPrice: 55000, size: PriceTextSize.large),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const DiscountBadge(percent: 13),
                  const DiscountBadge(percent: 27, large: true),
                  const FeaturedBadge(),
                  WishlistHeart(isActive: _heart, onChanged: (v) => setState(() => _heart = v)),
                  WishlistHeart(isActive: true, size: 40, onChanged: (_) {}),
                ],
              ),
            ],
          ),
          _Section(
            title: 'EmptyState',
            children: [
              _Framed(
                child: EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: l10n.emptyCartTitle,
                  subtitle: l10n.emptyCartSubtitle,
                  ctaLabel: l10n.startShopping,
                  onCta: () => _toast(l10n.startShopping),
                ),
              ),
            ],
          ),
          _Section(
            title: 'ErrorState',
            children: [
              _Framed(child: ErrorState(onRetry: () => _toast(l10n.retry))),
            ],
          ),
          const _Section(
            title: 'SkeletonLoader',
            children: [
              SkeletonLoader.line(width: 180),
              SizedBox(height: AppSpacing.sm),
              SkeletonLoader.line(width: 120, height: 12),
              SizedBox(height: AppSpacing.md),
              SkeletonLoader.box(height: 120, radius: AppRadius.lg),
              SizedBox(height: AppSpacing.md),
              SkeletonLoader.list(count: 2),
              SizedBox(height: AppSpacing.md),
              SkeletonLoader.productGrid(count: 2),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textMuted(context),
            ),
          ),
          Divider(height: AppSpacing.md, color: AppColors.line(context)),
          ...children,
        ],
      ),
    );
  }
}

class _Framed extends StatelessWidget {
  const _Framed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
      ),
      child: child,
    );
  }
}

/// Stand-in for the Phase 2 country-code picker inside [GGInput.prefix].
class _CountryCodeStub extends StatelessWidget {
  const _CountryCodeStub({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsetsDirectional.only(start: AppSpacing.md, end: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.field(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            code,
            textDirection: TextDirection.ltr,
            style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
          ),
          Icon(Icons.arrow_drop_down_rounded, color: AppColors.gold(context)),
        ],
      ),
    );
  }
}

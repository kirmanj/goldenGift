import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/core/providers/session_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/callable.dart';
import 'package:golden_gift/core/services/image_upload_service.dart';
import 'package:golden_gift/features/addresses/presentation/providers/address_map_providers.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/payments/presentation/providers/payment_providers.dart';
import 'package:golden_gift/features/product_details/data/photo_service.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/products/data/product_derived.dart';
import 'package:golden_gift/features/products/data/product_search_repository.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/features/referrals/presentation/providers/referral_providers.dart';
import 'package:golden_gift/features/secret_santa/presentation/providers/secret_santa_providers.dart';
import 'package:golden_gift/main.dart';
import 'package:golden_gift/models/address_model.dart';
import 'package:golden_gift/features/reels/data/reel_derived.dart';
import 'package:golden_gift/models/cart_item_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/order_model.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_test_overrides.dart';
import '../helpers/auth_fakes.dart';
import '../helpers/fake_video_player.dart';

/// Phase 10 QA harness: pumps the REAL app (`GoldenGiftApp`, real route list
/// via `buildAppRouter`, `MaxWidthFrame`) on one location, without Firebase:
/// a [FakeFirebaseFirestore] seeded with a complete customer world
/// ([seedQaWorld]), fake Auth / Functions / Storage / platform seams, and the
/// real app fonts (Nunito, Vazirmatn) so text measures like on a device.

// ─── Viewports ───────────────────────────────────────────────────────────────

class QaViewport {
  const QaViewport(this.name, this.size, {this.textScale = 1, this.dpr = 3});
  final String name;
  final Size size;
  final double textScale;
  final double dpr;

  /// iPhone 14-class phone at 100 % text.
  static const phone = QaViewport('390x844', Size(390, 844));

  /// Small phone at the SRS §8 maximum text scale (130 %).
  static const smallLargeText = QaViewport('320x640@1.3', Size(320, 640), textScale: 1.3, dpr: 2);

  /// iPad portrait: MaxWidthFrame caps the app at 600 px.
  static const tablet = QaViewport('1024x1366', Size(1024, 1366), dpr: 2);

  /// Phone width, tall enough that most of a screen is on screen at once
  /// (the accessibility guidelines only check what is laid out and visible).
  static const tallPhone = QaViewport('390x2000', Size(390, 2000), dpr: 2);

  @override
  String toString() => name;
}

const qaLocales = ['en', 'ar', 'ckb'];
const qaThemes = [ThemeMode.light, ThemeMode.dark];

// ─── Fonts ───────────────────────────────────────────────────────────────────

bool _fontsLoaded = false;

/// Loads the bundled app fonts so layout (and contrast sampling) uses real
/// glyph metrics instead of the square test font. Once per test file.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Nunito', ['Nunito-Regular.ttf', 'Nunito-SemiBold.ttf', 'Nunito-Bold.ttf']);
  await family('Vazirmatn', ['Vazirmatn-Regular.ttf', 'Vazirmatn-Bold.ttf']);
  _fontsLoaded = true;
}

// ─── Seeded world ────────────────────────────────────────────────────────────

const qaUid = 'u1';
final qaNow = DateTime(2026, 10, 21, 9);
Timestamp _ts(DateTime d) => Timestamp.fromDate(d);

const _lorem = LocalizedText(
  'Handmade in Erbil from solid walnut, engraved with your names and wrapped in our signature gold box.',
  ar: 'مصنوع يدويًا في أربيل من خشب الجوز، محفور بأسمائكم ومغلف بعلبتنا الذهبية المميزة.',
  ku: 'بە دەست لە هەولێر لە داری گوێز دروستکراوە، ناوەکانتانی لەسەر هەڵکەندراوە و لە سندوقە زێڕینەکەماندا پێچراوە.',
);

/// A frame using all 8 option types (SRS §5.9) with a discount.
const qaFrame = ProductModel(
  id: 'frame',
  title: LocalizedText(
    'Personalized Magnetic Photo Frame with Engraved Names',
    ar: 'إطار صور مغناطيسي مخصص مع أسماء محفورة',
    ku: 'چوارچێوەی وێنەی موگناتیسی تایبەت لەگەڵ ناوی هەڵکەندراو',
  ),
  description: _lorem,
  storeId: 's1',
  categoryIds: ['frames', 'birthdays'],
  // All three gift types: the longest "Gift for" line (SRS §5.8a).
  giftFor: GiftAudience.values,
  price: 35000,
  compareAtPrice: 42000,
  isFeatured: true,
  availability: ProductAvailability.preparationDays,
  preparationDays: 2,
  salesCount: 120,
  ratingAvg: 4.6,
  ratingCount: 18,
  optionGroups: [
    OptionGroup(
      id: 'frame',
      type: OptionType.imageVariant,
      label: LocalizedText('Frame Color', ar: 'لون الإطار', ku: 'ڕەنگی چوارچێوە'),
      required: true,
      sortOrder: 0,
      values: [
        OptionValue(id: 'walnut', label: LocalizedText('Walnut', ar: 'جوز', ku: 'گوێز'), priceDelta: 5000, preparationDaysOverride: 4),
        OptionValue(id: 'black', label: LocalizedText('Black', ar: 'أسود', ku: 'ڕەش')),
        OptionValue(id: 'gold', label: LocalizedText('Gold', ar: 'ذهبي', ku: 'ئاڵتوونی'), stock: 0),
      ],
    ),
    OptionGroup(
      id: 'size',
      type: OptionType.textVariant,
      label: LocalizedText('Size', ar: 'الحجم', ku: 'قەبارە'),
      sortOrder: 1,
      values: [
        OptionValue(id: 's30', label: LocalizedText('30x30cm')),
        OptionValue(id: 's40', label: LocalizedText('40x40cm'), priceDelta: 3000, stock: 3),
      ],
    ),
    OptionGroup(
      id: 'ink',
      type: OptionType.colorSwatch,
      label: LocalizedText('Text Color', ar: 'لون النص', ku: 'ڕەنگی دەق'),
      sortOrder: 2,
      values: [
        OptionValue(id: 'red', label: LocalizedText('Red', ar: 'أحمر', ku: 'سوور'), hex: '#E53935'),
        OptionValue(id: 'gold', label: LocalizedText('Gold', ar: 'ذهبي', ku: 'زێڕین'), hex: '#E3C04A'),
        OptionValue(id: 'black', label: LocalizedText('Black', ar: 'أسود', ku: 'ڕەش'), hex: '#222222'),
        OptionValue(id: 'white', label: LocalizedText('White', ar: 'أبيض', ku: 'سپی'), hex: '#FFFFFF', stock: 0),
      ],
    ),
    OptionGroup(
      id: 'text1',
      type: OptionType.text,
      label: LocalizedText('Name on the frame', ar: 'الاسم على الإطار', ku: 'ناو لەسەر چوارچێوە'),
      required: true,
      maxLength: 12,
      sortOrder: 3,
    ),
    OptionGroup(
      id: 'notes',
      type: OptionType.longText,
      label: LocalizedText('Notes', ar: 'ملاحظات', ku: 'تێبینی'),
      maxLength: 500,
      sortOrder: 4,
    ),
    OptionGroup(
      id: 'date',
      type: OptionType.date,
      label: LocalizedText('Special date', ar: 'تاريخ مميز', ku: 'بەرواری تایبەت'),
      sortOrder: 5,
    ),
    OptionGroup(
      id: 'photos',
      type: OptionType.photoUpload,
      label: LocalizedText('Upload your photos', ar: 'حمّل صورك', ku: 'وێنەکانت باربکە'),
      required: true,
      minPhotos: 2,
      maxPhotos: 4,
      sortOrder: 6,
    ),
    OptionGroup(
      id: 'qty',
      type: OptionType.quantity,
      label: LocalizedText('Quantity', ar: 'الكمية', ku: 'ژمارە'),
      sortOrder: 7,
    ),
  ],
);

ProductModel _simple(
  String id,
  String en,
  String ar,
  String ku, {
  required int price,
  int? compareAt,
  List<String> categories = const ['mugs'],
  bool featured = false,
  ProductAvailability availability = ProductAvailability.sameDay,
  int prepDays = 0,
  int sales = 10,
  double rating = 0,
  int ratingCount = 0,
  List<String> cities = const [],
  String storeId = 's1',
  List<GiftAudience> giftFor = const [GiftAudience.men, GiftAudience.women],
}) =>
    ProductModel(
      id: id,
      title: LocalizedText(en, ar: ar, ku: ku),
      description: _lorem,
      storeId: storeId,
      categoryIds: categories,
      price: price,
      compareAtPrice: compareAt,
      isFeatured: featured,
      availability: availability,
      preparationDays: prepDays,
      salesCount: sales,
      ratingAvg: rating,
      ratingCount: ratingCount,
      availableCities: cities,
      giftFor: giftFor,
      optionGroups: const [
        OptionGroup(
          id: 'name',
          type: OptionType.text,
          label: LocalizedText('Name', ar: 'الاسم', ku: 'ناو'),
          maxLength: 20,
        ),
      ],
    );

const _reelCaption = LocalizedText(
  'Engraved with your names and lit by a warm glow — the frame our customers in Erbil order most for anniversaries. ✨',
  ar: 'محفور بأسمائكم ومضاء بوهج دافئ — الإطار الأكثر طلبًا من عملائنا في أربيل لذكرى الزواج. ✨',
  ku: 'بە ناوەکانتان هەڵکەندراوە و بە ڕووناکییەکی گەرم دەدرەوشێتەوە — ئەو چوارچێوەیەی کڕیارانمان لە هەولێر زۆرترین داوای دەکەن بۆ یادی هاوسەرگیری. ✨',
);

final qaProducts = <ProductModel>[
  qaFrame,
  _simple('mug', 'Photo Mug', 'كوب بالصورة', 'کوپی وێنە',
      price: 15000, compareAt: 20000, featured: true, sales: 300, rating: 4.2, ratingCount: 3),
  _simple('roses', 'Red Roses Bouquet with Golden Ribbon and Card', 'باقة ورد أحمر مع شريط ذهبي وبطاقة',
      'چەپکە گوڵی سوور لەگەڵ شریتی زێڕین و کارت',
      price: 45000, categories: ['flowers'], featured: true, sales: 250, storeId: 's2'),
  _simple('box', 'Engraved Wooden Jewelry Box', 'صندوق مجوهرات خشبي محفور', 'سندوقی خشڵی داری هەڵکەندراو',
      price: 65000, categories: ['leather', 'birthdays'], availability: ProductAvailability.preparationDays,
      prepDays: 3, sales: 80, cities: ['erbil']),
  _simple('candle', 'Scented Candle', 'شمعة معطرة', 'مۆمی بۆنخۆش', price: 9000, categories: ['candles'], sales: 60),
  _simple('keychain', 'Leather Keychain', 'ميدالية جلدية', 'کلیلدانی چەرم',
      price: 6000, compareAt: 8000, categories: ['keychains'], sales: 40),
  _simple('magnet', 'Kurdistan Flag Magnet', 'مغناطيس علم كردستان', 'مەگنەتی ئاڵای کوردستان',
      price: 4000, categories: ['magnets', 'kurdistan'], sales: 30),
  _simple('soldout', 'Limited Gold Plated Necklace', 'قلادة مطلية بالذهب', 'ملوانکەی زێڕکراو',
      price: 125000, categories: ['birthdays'], availability: ProductAvailability.outOfStock, sales: 5),
];

const qaCategories = [
  ('flowers', 'Flowers', 'زهور', 'گوڵ'),
  ('mugs', 'Mugs', 'أكواب', 'کوپ'),
  ('birthdays', 'Birthdays', 'أعياد الميلاد', 'ڕۆژی لەدایکبوون'),
  ('magnets', 'Magnets', 'مغناطيس', 'مەگنەت'),
  ('leather', 'Leather', 'جلود', 'چەرم'),
  ('frames', 'Frames', 'إطارات', 'چوارچێوە'),
  ('candles', 'Candles', 'شموع', 'مۆم'),
  ('keychains', 'Keychains', 'ميداليات', 'کلیلدان'),
  ('kurdistan', 'Kurdistan Souvenirs', 'هدايا كردستان التذكارية', 'دیاری یادگاری کوردستان'),
];

/// A coming-soon category of the seeded world, and a subcategory under it.
const qaComingSoonCategory = 'easter';
const qaComingSoonSubcategory = 'easter-eggs';

const qaProfile = UserModel(
  uid: qaUid,
  name: 'Sara Ahmed',
  email: 'sara.ahmed@example.com',
  phone: '7501234567',
  city: 'erbil',
  gender: 'female',
  referralCode: 'ZQC8YC',
  profileCompleted: true,
  totalOrders: 4,
);

AddressModel qaAddress(String id, {String label = 'Home', String city = 'erbil', bool isDefault = false}) =>
    AddressModel(
      id: id,
      label: label,
      name: 'Sara Ahmed',
      phone: '+9647501234567',
      city: city,
      area: 'Ankawa',
      street: '100m Road, near Family Mall',
      building: 'B12',
      floor: '3',
      notes: 'Call before arriving',
      isDefault: isDefault,
    );

CartItemModel _line(String id, ProductModel p, {int qty = 1, List<CartSelection> selections = const []}) =>
    CartItemModel(
      id: id,
      productId: p.id,
      storeId: p.storeId,
      titleSnapshot: p.title,
      unitPrice: CartItemModel.computeUnitPrice(p.price, selections),
      qty: qty,
      selections: selections,
      preparationDays: p.preparationDays,
      addedAt: DateTime(2026, 10, 20, 10),
    );

final qaFrameSelections = [
  const CartSelection(
    groupId: 'frame',
    type: OptionType.imageVariant,
    label: LocalizedText('Frame Color', ar: 'لون الإطار', ku: 'ڕەنگی چوارچێوە'),
    valueId: 'walnut',
    valueLabel: LocalizedText('Walnut', ar: 'جوز', ku: 'گوێز'),
    priceDelta: 5000,
  ),
  const CartSelection(
    groupId: 'ink',
    type: OptionType.colorSwatch,
    label: LocalizedText('Text Color', ar: 'لون النص', ku: 'ڕەنگی دەق'),
    valueId: 'red',
    valueLabel: LocalizedText('Red', ar: 'أحمر', ku: 'سوور'),
    hex: '#E53935',
  ),
  const CartSelection(
    groupId: 'text1',
    type: OptionType.text,
    label: LocalizedText('Name on the frame', ar: 'الاسم على الإطار', ku: 'ناو لەسەر چوارچێوە'),
    text: 'Sara & Karwan',
  ),
  CartSelection(
    groupId: 'date',
    type: OptionType.date,
    label: const LocalizedText('Special date', ar: 'تاريخ مميز', ku: 'بەرواری تایبەت'),
    date: DateTime(2026, 11, 14),
  ),
  const CartSelection(
    groupId: 'photos',
    type: OptionType.photoUpload,
    label: LocalizedText('Upload your photos', ar: 'حمّل صورك', ku: 'وێنەکانت باربکە'),
    urls: ['', ''],
  ),
];

Map<String, dynamic> _orderItem(CartItemModel line, OrderStatus status) =>
    OrderItem(line: line, status: status).toMap();

/// Writes the whole customer world for [qaUid] into [db]. [empty]: only the
/// settings, the profile and a zero wallet — every list shows its empty state.
Future<FakeFirebaseFirestore> seedQaWorld([FakeFirebaseFirestore? firestore, bool empty = false]) async {
  final db = firestore ?? FakeFirebaseFirestore();
  final batch = db.batch();
  void set(String path, Map<String, dynamic> data) => batch.set(db.doc(path), data);

  // app_settings
  set('app_settings/general', {
    'supportPhone': '+9647501112233',
    'whatsapp': '+9647501112233',
    'email': 'support@goldengift.app',
    'instagram': 'goldengift.iq',
    'sameDayCutoff': '14:00',
    'minOrder': 0,
    'maintenanceMode': false,
  });
  set('app_settings/cities', {
    'items': [
      {'id': 'erbil', 'name': 'Erbil', 'nameAr': 'أربيل', 'nameKu': 'هەولێر', 'deliveryFee': 5000, 'isActive': true},
      {'id': 'duhok', 'name': 'Duhok', 'nameAr': 'دهوك', 'nameKu': 'دهۆک', 'deliveryFee': 4000, 'isActive': true},
      {
        'id': 'sulaymaniyah',
        'name': 'Sulaymaniyah',
        'nameAr': 'السليمانية',
        'nameKu': 'سلێمانی',
        'deliveryFee': 6000,
        'isActive': true,
      },
      {'id': 'baghdad', 'name': 'Baghdad', 'nameAr': 'بغداد', 'nameKu': 'بەغدا', 'deliveryFee': 8000, 'isActive': false},
    ],
  });
  set('app_settings/referral', {'joinBonus': 5000, 'orderBonus': 10000, 'maxReferralsPerMonth': 10, 'creditsExpiryDays': 90});
  set('app_settings/payments', {'cashOnDelivery': true, 'wallet': true, 'card': false, 'fastPay': false, 'zainCash': false});
  set('app_settings/search', {});

  if (empty) {
    set('users/$qaUid', {...qaProfile.toCreateMap(), 'referralCode': 'ZQC8YC', 'profileCompleted': true});
    set('wallets/$qaUid', {'balance': 0, 'credits': 0, 'currency': 'IQD'});
    await batch.commit();
    return db;
  }

  // Catalogue
  for (var i = 0; i < qaCategories.length; i++) {
    final c = qaCategories[i];
    set('categories/${c.$1}', {
      'title': c.$2,
      'titleAr': c.$3,
      'titleKu': c.$4,
      'type': i < 3 ? 'occasion' : 'productType',
      'sortOrder': i + 1,
      'isActive': true,
      'productCount': 12,
    });
  }
  // "Coming soon" (SRS §5.7a): in the Home grid / Discover chips (sortOrder 2),
  // with a note, and a subcategory that inherits the state.
  set('categories/$qaComingSoonCategory', {
    'title': 'Easter Day',
    'titleAr': 'عيد الفصح',
    'titleKu': 'جەژنی ئیستەر',
    'type': 'occasion',
    'sortOrder': 2,
    'isActive': true,
    'productCount': 0,
    'comingSoon': true,
    'comingSoonNote': 'Arriving before Easter — painted eggs, baskets and more',
    'comingSoonNoteAr': 'تصل قبل عيد الفصح — بيض ملوّن وسلال والمزيد',
    'comingSoonNoteKu': 'پێش جەژنی ئیستەر دەگات — هێلکەی ڕەنگکراو، سەبەتە و زیاتر',
    'comingSoonSince': _ts(DateTime(2026, 10, 20)),
  });
  set('categories/$qaComingSoonSubcategory', {
    'title': 'Painted Eggs',
    'titleAr': 'بيض ملوّن',
    'titleKu': 'هێلکەی ڕەنگکراو',
    'sortOrder': 20,
    'isActive': true,
    'parentId': qaComingSoonCategory,
  });
  set('stores/s1', {
    'name': 'Golden Crafts Erbil',
    'nameAr': 'الحرف الذهبية أربيل',
    'nameKu': 'دەستکاری زێڕینی هەولێر',
    'status': StoreStatus.active.name,
    'city': 'erbil',
    'ownerUid': 'seller1',
  });
  set('stores/s2', {
    'name': 'Duhok Flowers',
    'nameAr': 'زهور دهوك',
    'nameKu': 'گوڵی دهۆک',
    'status': StoreStatus.active.name,
    'city': 'duhok',
    'ownerUid': 'seller2',
  });
  for (var i = 0; i < qaProducts.length; i++) {
    final p = qaProducts[i];
    set('products/${p.id}', {
      ...p.toMap(),
      ...ProductDerived.of(p),
      'createdAt': _ts(DateTime(2026, 10, 1 + i)),
    });
  }
  // Reels (SRS §5.27): the longest caption on the frame, none on the roses,
  // and a hidden one that must never show.
  for (final (i, (id, product, caption, active)) in [
    ('r-frame', qaFrame, _reelCaption, true),
    ('r-roses', qaProducts[2], null, true),
    ('r-box', qaProducts[3], null, true),
    ('r-hidden', qaProducts[4], null, false),
  ].indexed) {
    set('reels/$id', {
      'productId': product.id,
      'videoUrl': 'https://video.test/$id.mp4',
      'posterUrl': '',
      if (caption != null) ...caption.toMap('caption'),
      'isActive': active,
      'createdAt': _ts(DateTime(2026, 10, 20 - i)),
      ...ReelDerived.fieldsFor(isActive: active, product: product),
    });
  }
  for (final b in BannerPlacement.values) {
    set('banners/b-${b.name}', {
      'imageUrl': '',
      'placement': b.name,
      'action': {'type': 'route', 'value': '/special-requests'},
      'sortOrder': 0,
      'isActive': true,
    });
  }
  // Reviews: three approved on the mug, one pending.
  Future<void> review(String id, int rating, String name, String text, {bool approved = true}) async =>
      set('products/mug/reviews/$id', {
        'productId': 'mug',
        'userId': 'u-$id',
        'userName': name,
        'storeId': 's1',
        'rating': rating,
        'text': text,
        'images': const <String>[],
        'orderId': 'o-$id',
        'isApproved': approved,
        'createdAt': _ts(DateTime(2026, 10, 10 + rating)),
      });
  await review('a', 5, 'Karwan Ali', 'Beautiful print, arrived the same day. My mother loved it!');
  await review('b', 4, 'Lana', 'Good quality.');
  await review('c', 3, 'Dilan Omar', 'The colours were a bit darker than in the photo but still nice.');
  await review('d', 1, 'Spam', 'pending', approved: false);

  // The customer
  set('users/$qaUid', {...qaProfile.toCreateMap(), 'referralCode': 'ZQC8YC', 'totalOrders': 4, 'profileCompleted': true});
  set('wallets/$qaUid', {'balance': 12500, 'credits': 7500, 'currency': 'IQD'});
  final txns = [
    ('t1', 'referralCredit', 5000, 'credits', 'Referral bonus: Karwan', DateTime(2026, 10, 2, 9, 30)),
    ('t2', 'orderPayment', -20000, 'balance', null, DateTime(2026, 10, 5, 18)),
    ('t3', 'refund', 17500, 'balance', null, DateTime(2026, 10, 8, 12)),
    ('t4', 'giftCardRedeem', 25000, 'balance', null, DateTime(2026, 10, 12, 20)),
    ('t5', 'creditExpiry', -2500, 'credits', null, DateTime(2026, 10, 15, 0)),
    ('t6', 'adminAdjustment', 5000, 'credits', 'Sorry for the late delivery', DateTime(2026, 10, 18, 11)),
    ('t7', 'topUp', 10000, 'balance', null, DateTime(2026, 10, 19, 16)),
  ];
  for (final t in txns) {
    set('wallets/$qaUid/transactions/${t.$1}', {
      'type': t.$2,
      'amount': t.$3,
      'bucket': t.$4,
      if (t.$5 != null) 'title': t.$5,
      'orderId': t.$2 == 'orderPayment' || t.$2 == 'refund' ? 'o1' : null,
      'balanceAfter': 12500,
      'creditsAfter': 7500,
      'createdAt': _ts(t.$6),
    });
  }
  set('users/$qaUid/addresses/a1', qaAddress('a1', isDefault: true).toMap());
  set('users/$qaUid/addresses/a2', qaAddress('a2', label: 'Work — Duhok office', city: 'duhok').toMap());

  // Cart (signed-in: Firestore)
  final frameLine = _line('c1', qaFrame, selections: qaFrameSelections);
  final mugLine = _line('c2', qaProducts[1], qty: 2);
  for (final l in [frameLine, mugLine]) {
    set('carts/$qaUid/items/${l.id}', {...l.toMap(), 'addedAt': _ts(l.addedAt!)});
  }

  // Wishlists: a named list plus two gifts.
  set('wishlists/$qaUid', {
    'lists': [
      {'id': 'l1', 'name': 'Mum', 'createdAt': _ts(DateTime(2026, 10, 1))},
    ],
  });
  for (final (i, p) in [qaProducts[1], qaProducts[2]].indexed) {
    set('wishlists/$qaUid/items/${p.id}', {
      'productId': p.id,
      ...p.title.toMap('title'),
      'image': null,
      'price': p.price,
      'compareAtPrice': p.compareAtPrice,
      'listId': i == 0 ? 'default' : 'l1',
      'addedAt': _ts(DateTime(2026, 10, 3 + i)),
    });
  }

  // Orders in several states, plus a gift-card order.
  Map<String, dynamic> order(String number, OrderStatus status, DateTime at, {Map<String, dynamic> extra = const {}}) => {
        'orderNumber': number,
        'userId': qaUid,
        'storeIds': ['s1'],
        'items': [_orderItem(frameLine, status), _orderItem(mugLine, status)],
        'subtotal': 70000,
        'discount': 7000,
        'promoCode': 'WELCOME10',
        'creditsUsed': 2500,
        'walletUsed': 0,
        'deliveryFee': 5000,
        'total': 65500,
        'status': status.name,
        'paymentMethod': 'cashOnDelivery',
        'paymentStatus': 'pending',
        'createdAt': _ts(at),
        'deliveryDate': '2026-10-23',
        'deliverySlot': 'evening',
        'address': qaAddress('a1').toMap(),
        'isGift': true,
        'giftMessage': 'Happy birthday Mum! With all our love.',
        ...extra,
      };
  set('orders/o1', order('GG-2610-00042', OrderStatus.pending, DateTime(2026, 10, 21, 8)));
  set('orders/o2', order('GG-2610-00038', OrderStatus.outForDelivery, DateTime(2026, 10, 19, 15)));
  set('orders/o3', order('GG-2610-00021', OrderStatus.delivered, DateTime(2026, 10, 10, 12)));
  set('orders/o4', order('GG-2610-00017', OrderStatus.cancelledByBuyer, DateTime(2026, 10, 7, 9),
      extra: {'cancelReason': 'Ordered by mistake', 'refundedCredits': 2500, 'refundedBalance': 5000}));
  set('orders/o5', {
    ...order('GG-2610-00044', OrderStatus.confirmed, DateTime(2026, 10, 20, 19)),
    'items': [
      {
        'id': 'gc',
        'productId': '',
        'storeId': '',
        'titleSnapshot': 'Gift card',
        'titleSnapshotAr': 'بطاقة هدية',
        'titleSnapshotKu': 'کارتی دیاری',
        'unitPrice': 50000,
        'qty': 1,
        'status': 'confirmed',
      },
    ],
    'storeIds': <String>[],
    'subtotal': 50000,
    'discount': 0,
    'promoCode': null,
    'creditsUsed': 0,
    'deliveryFee': 0,
    'total': 50000,
    'orderType': 'giftCard',
    'paymentMethod': 'wallet',
    'paymentStatus': 'paid',
    'address': null,
    'deliveryDate': null,
    'deliverySlot': null,
    'isGift': false,
    'giftMessage': null,
    'giftCard': {
      'templateId': 't1',
      'amount': 50000,
      'recipientName': 'Lana Karim',
      'recipientPhone': '+9647701234567',
      'recipientEmail': null,
    },
  });
  for (final (id, statuses) in [
    ('o1', [OrderStatus.pending]),
    ('o2', [OrderStatus.pending, OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.readyForDelivery, OrderStatus.outForDelivery]),
    ('o3', [OrderStatus.pending, OrderStatus.confirmed, OrderStatus.preparing, OrderStatus.readyForDelivery, OrderStatus.outForDelivery, OrderStatus.delivered]),
    ('o4', [OrderStatus.pending, OrderStatus.cancelledByBuyer]),
    ('o5', [OrderStatus.pending, OrderStatus.confirmed]),
  ]) {
    for (final (i, s) in statuses.indexed) {
      set('orders/$id/status_history/h$i', {
        'status': s.name,
        'byRole': i == 0 ? 'customer' : 'admin',
        'note': s == OrderStatus.outForDelivery ? 'Driver Ahmed, 0750 555 1234' : null,
        'at': _ts(DateTime(2026, 10, 10 + i, 9 + i)),
      });
    }
  }

  // Online payment (Phase 9, ZainCash): an unpaid order with its pending
  // session (due in 20 min), a failed session and a paid top-up.
  set('orders/o6', order('GG-2610-00045', OrderStatus.pending, DateTime(2026, 10, 21, 8, 40), extra: {
    'paymentMethod': 'zainCash',
    'paymentDueBy': _ts(qaNow.add(const Duration(minutes: 20))),
  }));
  set('orders/o6/status_history/h0', {'status': 'pending', 'byRole': 'customer', 'note': null, 'at': _ts(DateTime(2026, 10, 21, 8, 40))});
  Map<String, dynamic> paymentSession(String purpose, String status, int amount, {String? orderId, String? number}) => {
        'uid': qaUid,
        'purpose': purpose,
        'orderId': orderId,
        'orderNumber': number,
        'amount': amount,
        'currency': 'IQD',
        'gateway': 'zainCash',
        'status': status,
        'payUrl': 'https://test.zaincash.iq/transaction/pay?id=t1',
        'creditedToWallet': purpose == 'topUp' && status == 'paid',
        'expiresAt': _ts(qaNow.add(const Duration(minutes: 20))),
        'createdAt': _ts(DateTime(2026, 10, 21, 8, 40)),
      };
  set('payment_sessions/zc-pending', paymentSession('order', 'pending', 65500, orderId: 'o6', number: 'GG-2610-00045'));
  set('payment_sessions/zc-failed', paymentSession('order', 'failed', 65500, orderId: 'o4', number: 'GG-2610-00017'));
  set('payment_sessions/zc-topup', paymentSession('topUp', 'paid', 50000));

  // Notifications: unread with a route, read, broadcast.
  set('notifications/n1', {
    'userId': qaUid,
    'title': 'Your order is out for delivery',
    'titleAr': 'طلبك في الطريق إليك',
    'titleKu': 'داواکارییەکەت لە ڕێگادایە',
    'body': 'GG-2610-00038 will arrive this evening between 6 and 10 pm.',
    'bodyAr': 'سيصل الطلب GG-2610-00038 مساء اليوم.',
    'bodyKu': 'داواکاری GG-2610-00038 ئەمڕۆ ئێوارە دەگات.',
    'type': 'orderStatus',
    'isRead': false,
    'createdAt': _ts(qaNow.subtract(const Duration(minutes: 5))),
    'data': {'route': '/orders/o2', 'id': 'o2'},
  });
  set('notifications/n2', {
    'userId': qaUid,
    'title': 'Order confirmed',
    'titleAr': 'تم تأكيد الطلب',
    'titleKu': 'داواکاری پشتڕاستکرایەوە',
    'body': 'We are preparing your gift.',
    'type': 'orderStatus',
    'isRead': true,
    'createdAt': _ts(DateTime(2026, 10, 20, 12)),
  });
  set('notifications/n3', {
    'userId': 'all',
    'title': 'Valentine collection is here',
    'titleAr': 'مجموعة عيد الحب وصلت',
    'titleKu': 'کۆکراوەی ڕۆژی خۆشەویستی گەیشت',
    'body': 'Up to 30% off engraved gifts this week only.',
    'type': 'broadcast',
    'isRead': false,
    'createdAt': _ts(DateTime(2026, 10, 15, 12)),
  });

  // Promo codes
  set('promo_codes/WELCOME10', {
    'code': 'WELCOME10',
    'title': 'Welcome gift',
    'titleAr': 'هدية الترحيب',
    'titleKu': 'دیاری بەخێرهاتن',
    'description': 'Save 10% on your first order, up to 15,000 IQD.',
    'descriptionAr': 'وفر 10% على طلبك الأول.',
    'descriptionKu': '10% لە یەکەم داواکاریت پاشەکەوت بکە.',
    'type': 'percent',
    'value': 10,
    'maxDiscount': 15000,
    'isPublic': true,
    'isActive': true,
    'perUserLimit': 1,
    'usageCount': 3,
    'firstOrderOnly': true,
    'categoryIds': <String>[],
    'expiresAt': _ts(DateTime(2026, 12, 31)),
  });
  set('promo_codes/FLAT5000', {
    'code': 'FLAT5000',
    'title': '5,000 IQD off',
    'titleAr': 'خصم 5,000 دينار',
    'titleKu': '5,000 دینار داشکاندن',
    'description': 'On orders above 50,000 IQD.',
    'descriptionAr': 'للطلبات فوق 50,000 دينار.',
    'descriptionKu': 'بۆ داواکاری سەروو 50,000 دینار.',
    'type': 'fixed',
    'value': 5000,
    'minOrder': 50000,
    'isPublic': true,
    'isActive': true,
    'perUserLimit': 3,
    'usageCount': 0,
    'firstOrderOnly': false,
    'categoryIds': ['frames'],
  });

  // Referrals made by the customer
  for (final (id, status, name) in [('r1', 'completed', 'Karwan Ali'), ('r2', 'pending', 'Lana'), ('r3', 'cancelled', null)]) {
    set('referrals/$id', {
      'referrerUid': qaUid,
      'referredUid': 'x$id',
      'code': 'ZQC8YC',
      'status': status,
      if (name != null) 'referredName': name,
      'createdAt': _ts(DateTime(2026, 10, 2)),
    });
  }

  // Gift cards
  set('gift_card_templates/t1', {
    'name': 'Golden Classic',
    'nameAr': 'كلاسيك ذهبي',
    'nameKu': 'کلاسیکی زێڕین',
    'presetAmounts': [15000, 25000, 50000, 100000],
    'minAmount': 10000,
    'maxAmount': 500000,
    'sortOrder': 0,
    'isActive': true,
  });
  set('gift_card_templates/t2', {
    'name': 'Happy Birthday',
    'nameAr': 'عيد ميلاد سعيد',
    'nameKu': 'ڕۆژی لەدایکبوونت پیرۆز',
    'presetAmounts': [25000, 50000],
    'minAmount': 0,
    'maxAmount': 0,
    'sortOrder': 1,
    'isActive': true,
    'gradientStart': '#9C7A14',
    'gradientEnd': '#E3C04A',
  });
  Map<String, dynamic> card(Map<String, dynamic> data) => {
        'templateId': 't1',
        'templateName': 'Golden Classic',
        'templateNameAr': 'كلاسيك ذهبي',
        'templateNameKu': 'کلاسیکی زێڕین',
        'amount': 25000,
        'balance': 25000,
        'purchaserUid': 'someone',
        'recipientName': 'Sara Ahmed',
        ...data,
      };
  set('gift_cards/g1', card({
    'code': 'ABCDEFGHJKLM',
    'recipientUid': qaUid,
    'status': 'sent',
    'message': 'Happy birthday! Buy yourself something golden.',
    'sentAt': _ts(DateTime(2026, 10, 1)),
    'expiresAt': _ts(DateTime(2027, 10, 1)),
  }));
  set('gift_cards/g2', card({
    'code': 'ZZZZYYYYXXXX',
    'recipientUid': qaUid,
    'status': 'redeemed',
    'balance': 0,
    'sentAt': _ts(DateTime(2026, 9, 1)),
    'redeemedAt': _ts(DateTime(2026, 9, 2)),
  }));
  set('gift_cards/g3', card({
    'code': 'QQQQWWWWEEEE',
    'purchaserUid': qaUid,
    'recipientName': 'Omar Abdulrahman Mustafa',
    'status': 'pending',
    'amount': 50000,
    'balance': 50000,
    'orderId': 'o5',
    'scheduledAt': _ts(DateTime(2026, 11, 1, 9)),
  }));

  // Special requests (+ a message thread on the quoted one)
  Map<String, dynamic> request(String status, String text, {Map<String, dynamic> extra = const {}}) => {
        'userId': qaUid,
        'type': 'gift',
        'text': text,
        'images': const <String>[],
        'status': status,
        'lastMessageBy': 'admin',
        'createdAt': _ts(DateTime(2026, 10, 18, 12)),
        ...extra,
      };
  set('special_requests/r1', request('quoted',
      'A wooden box engraved with our names and wedding date, with space for two rings and a small letter.',
      extra: {
        'quoteAmount': 90000,
        'quoteNote': 'Walnut wood, 2 names + date, ready in 3 days.',
        'quotedAt': _ts(DateTime(2026, 10, 19, 10)),
        'lastMessageAt': _ts(DateTime(2026, 10, 19, 10)),
      }));
  set('special_requests/r2', request('submitted', 'Custom cake topper with our logo', extra: {'lastMessageBy': 'customer'}));
  set('special_requests/r3', request('rejected', 'Live puppy delivery', extra: {'rejectReason': 'We cannot deliver animals.'}));
  set('special_requests/r4', request('accepted', 'Gold name necklace', extra: {'orderId': 'o2', 'quoteAmount': 120000}));
  for (final (i, (role, text)) in [
    ('customer', 'Can it be ready before Friday?'),
    ('admin', 'Yes — we can deliver Thursday evening in Erbil.'),
  ].indexed) {
    set('special_requests/r1/messages/m$i', {
      'senderUid': role == 'admin' ? 'admin1' : qaUid,
      'role': role,
      'text': text,
      'images': const <String>[],
      'at': _ts(DateTime(2026, 10, 18, 13 + i)),
    });
  }

  // Secret Santa: an open group the customer organises, and a drawn one.
  const names = {qaUid: 'Sara Ahmed', 'u2': 'Karwan Ali', 'u3': 'Lana', 'u4': 'Dilan Omar Abdullah'};
  void group(String id, String name, String status, String organiser, String code) {
    set('secret_santa_groups/$id', {
      'name': name,
      'type': id == 'g1' ? 'work' : 'family',
      'budget': id == 'g1' ? 25000 : 0,
      'exchangeDate': _ts(DateTime(2026, 12, 24)),
      'organiserUid': organiser,
      'status': status,
      'inviteCode': code,
      'memberUids': names.keys.toList(),
      if (status == 'drawn') 'drawnAt': _ts(DateTime(2026, 11, 1)),
      'createdAt': _ts(DateTime(2026, 10, 1)),
    });
    for (final (i, uid) in names.keys.indexed) {
      set('secret_santa_groups/$id/members/$uid', {
        'name': names[uid],
        'joinedAt': _ts(DateTime(2026, 10, 1, 10, i)),
        if (uid == qaUid) 'wishlistNote': 'Anything with gold, or a scented candle.',
      });
    }
  }

  group('g1', 'Office Party 2026 — Erbil Team', 'open', qaUid, 'ABCD2345');
  group('g2', 'Family Eid', 'drawn', 'u2', 'WXYZ6789');
  set('secret_santa_groups/g2/assignments/$qaUid', {
    'assigneeUid': 'u3',
    'assigneeName': 'Lana',
    'assigneeWishlistNote': 'A silver bracelet or a book of Kurdish poetry.',
    'drawnAt': _ts(DateTime(2026, 11, 1)),
  });

  await batch.commit();
  return db;
}

// ─── Fakes ───────────────────────────────────────────────────────────────────

/// Every callable fails like an undeployed function (`not-found`), which the
/// app must degrade from gracefully.
Future<Object?> qaCallable(String name, Map<String, dynamic> data) async =>
    throw FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');

/// `users/{uid}` straight from the fake Firestore.
class QaUserRepository extends Fake implements UserRepository {
  QaUserRepository(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<UserModel?> watch(String uid) =>
      _db.doc('users/$uid').snapshots().map((s) => s.exists ? UserModel.fromMap(uid, s.data()!) : null);

  @override
  Future<UserModel?> fetch(String uid) async {
    final s = await _db.doc('users/$uid').get();
    return s.exists ? UserModel.fromMap(uid, s.data()!) : null;
  }
}

/// Order reads from the fake Firestore; the functions are "not deployed".
class QaOrdersRepository extends Fake implements OrdersRepository {
  QaOrdersRepository(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<List<OrderModel>> watchMine(String uid) => _db
      .collection('orders')
      .where('userId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => [for (final d in s.docs) OrderModel.fromMap(d.id, d.data())]);

  @override
  Stream<OrderModel?> watch(String orderId) =>
      _db.doc('orders/$orderId').snapshots().map((s) => s.exists ? OrderModel.fromMap(s.id, s.data()!) : null);

  @override
  Stream<List<StatusHistoryEntry>> watchHistory(String orderId) => _db
      .collection('orders/$orderId/status_history')
      .orderBy('at')
      .snapshots()
      .map((s) => [for (final d in s.docs) StatusHistoryEntry.fromMap(d.data())]);

  @override
  Future<PlacedOrder> placeOrder(PlaceOrderRequest request) async => throw OrderFailure.from(
      FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'));

  @override
  Future<void> cancelOrder(String orderId, {String? reason}) async => throw OrderFailure.from(
      FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'));
}

class _QaPhotoService extends Fake implements PhotoService {
  @override
  Future<PickedPhoto?> pick(ImageSource source) async => null;
}

class _QaUploads extends Fake implements ImageUploadService {}

class _QaAvatarPicker implements AvatarPicker {
  @override
  Future<Uint8List?> pick(ImageSource source) async => null;
}

// ─── Pump ────────────────────────────────────────────────────────────────────

class QaApp {
  QaApp(this.container, this.router, this.firestore);
  final ProviderContainer container;
  final GoRouter router;
  final FakeFirebaseFirestore firestore;
  String get location => router.state.uri.toString();
}

/// Pumps the real app at [location] in [locale] / [theme] on [viewport].
Future<QaApp> pumpQaApp(
  WidgetTester tester, {
  required String location,
  Object? extra,
  bool guest = false,
  String locale = 'en',
  ThemeMode theme = ThemeMode.light,
  QaViewport viewport = QaViewport.phone,
  FakeFirebaseFirestore? firestore,
  Map<String, Object> prefs = const {},
  CallableInvoker callable = qaCallable,

  /// Serves the app this instead of the seeded fake (e.g. a read counter).
  FirebaseFirestore Function(FakeFirebaseFirestore db)? wrapFirestore,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = viewport.size * viewport.dpr;
  tester.view.devicePixelRatio = viewport.dpr;
  tester.platformDispatcher.textScaleFactorTestValue = viewport.textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  SharedPreferences.setMockInitialValues({
    'locale': locale,
    'theme_mode': theme.name,
    PrefsKeys.onboardingDone: true,
    PrefsKeys.signedInBefore: true,
    if (guest) PrefsKeys.guestMode: true,
    ...prefs,
  });
  final sharedPrefs = await SharedPreferences.getInstance();
  PackageInfo.setMockInitialValues(
    appName: 'Golden Gift',
    packageName: 'com.goldengift.golden_gift',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  final db = firestore ?? await seedQaWorld();
  final served = wrapFirestore?.call(db) ?? db;
  // No video decoder in tests (Reels tab).
  FakeVideoPlayerPlatform.install();
  final User? user = guest ? null : FakeUser(uid: qaUid, phoneNumber: '+9647501234567', displayName: 'Sara Ahmed');

  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(sharedPrefs, firestore: served, user: user),
    appRouterProvider.overrideWith((ref) => buildAppRouter(ref, initialLocation: location, initialExtra: extra)),
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: user)),
    userRepositoryProvider.overrideWithValue(QaUserRepository(served)),
    ordersRepositoryProvider.overrideWithValue(QaOrdersRepository(served)),
    callableInvokerProvider.overrideWithValue(callable),
    httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('offline', 503))),
    photoServiceProvider.overrideWithValue(_QaPhotoService()),
    imageUploadServiceProvider.overrideWithValue(_QaUploads()),
    avatarPickerProvider.overrideWithValue(_QaAvatarPicker()),
    externalLinkOpenerProvider.overrideWithValue((_) async => true),
    appVersionLabelProvider.overrideWith((ref) async => '1.0.0 (1)'),
    shareTextProvider.overrideWithValue((text, {subject, origin}) async {}),
    secretSantaShareProvider.overrideWithValue((text, {subject, origin}) async {}),
    checkoutClockProvider.overrideWithValue(() => qaNow),
    secretSantaClockProvider.overrideWithValue(() => qaNow),
    paymentClockProvider.overrideWithValue(PaymentClock(now: () => qaNow, tick: null)),
    mapsEnabledProvider.overrideWithValue(false),
    ...overrides,
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const GoldenGiftApp()));
  await settle(tester);
  return QaApp(container, container.read(appRouterProvider), db);
}

/// Pumps until nothing is scheduled, or [maxFrames] (shimmers and carousels
/// animate forever, so pumpAndSettle would time out).
/// Always runs [minFrames] first: Firestore / auth futures resolve between
/// frames without scheduling one.
Future<void> settle(WidgetTester tester, {int minFrames = 6, int maxFrames = 30}) async {
  await tester.pump();
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= minFrames && !tester.binding.hasScheduledFrame) return;
  }
}

/// Scrolls every on-screen scrollable (outer first, then the ones that
/// appear) to its end in steps of 80 % of its viewport, so lazily built
/// list items are laid out — and checked — too. [onStep] runs after each step.
/// [axis] limits it to vertical (or horizontal) lists.
Future<void> scrollThrough(WidgetTester tester, {FutureOr<void> Function()? onStep, Axis? axis}) async {
  final done = <ScrollPosition>{};
  for (var round = 0; round < 4; round++) {
    var scrolled = false;
    for (final state in tester.stateList<ScrollableState>(find.byType(Scrollable)).toList()) {
      if (!state.mounted) continue;
      final p = state.position;
      if (axis != null && axisDirectionToAxis(p.axisDirection) != axis) continue;
      if (!done.add(p) || !p.hasContentDimensions || p.maxScrollExtent <= p.minScrollExtent) continue;
      for (var step = 0; step < 60 && state.mounted && p.pixels < p.maxScrollExtent; step++) {
        p.jumpTo(math.min(p.pixels + p.viewportDimension * 0.8, p.maxScrollExtent));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await onStep?.call();
        scrolled = true;
      }
    }
    if (!scrolled) return;
  }
}

/// Unmounts the app and disposes its providers so timers (carousels, the
/// OTP countdown) are cancelled before the test ends.
Future<void> unmountQaApp(WidgetTester tester, QaApp app) async {
  await tester.pumpWidget(const SizedBox.shrink());
  app.container.dispose();
  await tester.pump(const Duration(seconds: 1));
}

// ─── Error and text checks ──────────────────────────────────────────────────

/// Runs [body] while recording every FlutterError (overflows, build
/// exceptions, missing localizations) instead of failing on the first one.
Future<List<FlutterErrorDetails>> captureFlutterErrors(Future<void> Function() body) async {
  final errors = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

/// One line per distinct error: the message plus the widget (file:line)
/// that caused it, when Flutter reports one.
String describeErrors(List<FlutterErrorDetails> errors) => {
      for (final e in errors) '• ${e.exceptionAsString().split('\n').first}${_culprit(e)}',
    }.join('\n');

String _culprit(FlutterErrorDetails e) {
  final text = e.toString();
  final match = RegExp(r'relevant error-causing widget was:\s*\n?\s*(.+)').firstMatch(text);
  final where = RegExp(r'file:///[^\s)]+/lib/[^\s)]+').firstMatch(match?.group(1) ?? text);
  if (where != null) return ' @ ${where.group(0)!.replaceFirst(RegExp(r'.*/lib/'), 'lib/')}';
  return e.context == null ? '' : ' (${e.context.toString().split('\n').first})';
}

Set<String>? _arbKeys;

/// Every message key of app_en.arb.
Set<String> arbKeys() => _arbKeys ??= {
      for (final k in (jsonDecode(File('assets/lang/app_en.arb').readAsStringSync()) as Map<String, dynamic>).keys)
        if (!k.startsWith('@')) k,
    };

/// All text currently laid out (Text, RichText, editable fields), onstage or not.
List<String> renderedTexts(WidgetTester tester) => [
      for (final w in tester.widgetList<RichText>(find.byType(RichText, skipOffstage: false)))
        w.text.toPlainText(includeSemanticsLabels: false, includePlaceholders: false),
      for (final w in tester.widgetList<EditableText>(find.byType(EditableText, skipOffstage: false)))
        w.controller.text,
    ];

final _rawPlaceholder = RegExp(r'\{[a-zA-Z_]\w*\}');
final _nullWord = RegExp(r'(^|[^A-Za-z])(null|undefined|NaN|Infinity)([^A-Za-z]|$)');

/// Texts that leak implementation: raw l10n keys, "null", "Instance of …",
/// unreplaced `{placeholders}`.
List<String> textProblems(WidgetTester tester) {
  final keys = arbKeys();
  final problems = <String>{};
  for (final t in renderedTexts(tester)) {
    final s = t.trim();
    if (s.isEmpty) continue;
    if (keys.contains(s) && s.contains(RegExp('[A-Z]'))) problems.add('raw l10n key: "$s"');
    if (_nullWord.hasMatch(s)) problems.add('null-ish value: "$s"');
    if (s.contains('Instance of')) problems.add('toString leak: "$s"');
    if (s.contains('LocalizedText(')) problems.add('toString leak: "$s"');
    if (_rawPlaceholder.hasMatch(s)) problems.add('unreplaced placeholder: "$s"');
  }
  return problems.toList();
}

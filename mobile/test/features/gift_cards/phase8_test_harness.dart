import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/providers/app_settings_providers.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/services/image_upload_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/addresses/presentation/screens/address_form_screen.dart';
import 'package:golden_gift/features/addresses/presentation/screens/addresses_screen.dart';
import 'package:golden_gift/features/checkout/presentation/providers/checkout_providers.dart';
import 'package:golden_gift/features/gift_cards/data/gift_cards_repository.dart';
import 'package:golden_gift/features/gift_cards/presentation/screens/gift_card_designer_screen.dart';
import 'package:golden_gift/features/gift_cards/presentation/screens/gift_card_shop_screen.dart';
import 'package:golden_gift/features/gift_cards/presentation/screens/my_gift_cards_screen.dart';
import 'package:golden_gift/features/gift_cards/presentation/widgets/home_gift_cards_section.dart';
import 'package:golden_gift/features/partners/data/partner_repository.dart';
import 'package:golden_gift/features/partners/presentation/screens/become_partner_screen.dart';
import 'package:golden_gift/features/product_details/data/photo_service.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/special_requests/data/special_requests_repository.dart';
import 'package:golden_gift/features/special_requests/presentation/screens/accept_quote_screen.dart';
import 'package:golden_gift/features/special_requests/presentation/screens/special_request_details_screen.dart';
import 'package:golden_gift/features/special_requests/presentation/screens/special_requests_screen.dart';
import 'package:golden_gift/features/support/presentation/screens/contact_us_screen.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';
import '../checkout/phase6_test_harness.dart' show testCities;

export '../checkout/phase6_test_harness.dart' show l10nFor, primaryButton, seedAddress, testAddress, testCities;

/// Firebase-free harness for the Phase 8 screens (gift cards, special
/// requests, Contact Us form, Become a Partner) inside a real GoRouter. The
/// repositories are the real classes on a FakeFirebaseFirestore with a
/// scripted [FakeCallable]; uploads and photo picking are faked. Stub routes
/// render where navigation went: `/order-success/o1` → "order success o1",
/// `/wallet` → "wallet", `/orders/o9` → "order o9", `/sign-in` → "/sign-in".

/// A 1×1 transparent PNG (decodes everywhere).
final testPhotoBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// Records every callable and answers from a per-function script: each entry
/// is a response map or an error to throw; [defaults] when the script is empty.
class FakeCallable {
  final calls = <(String, Map<String, dynamic>)>[];
  final scripts = <String, List<Object>>{};
  final defaults = <String, Object?>{
    'purchaseGiftCard': {'orderId': 'o1', 'orderNumber': 'GG-2610-00009', 'total': 25000},
    'redeemGiftCard': {'giftCardId': 'g1', 'amount': 25000, 'credits': 30000},
    'acceptQuote': {'orderId': 'o2', 'orderNumber': 'GG-2610-00010', 'total': 95000, 'deliveryDate': '2026-10-23'},
    'submitPartnerApplication': {'storeId': 's-new'},
  };

  /// Holds the next call open until completed.
  Completer<void>? gate;

  void script(String name, List<Object> results) => scripts[name] = [...results];

  List<Map<String, dynamic>> callsTo(String name) => [for (final c in calls) if (c.$1 == name) c.$2];

  Future<Object?> call(String name, Map<String, dynamic> data) async {
    calls.add((name, data));
    if (gate != null) await gate!.future;
    final queue = scripts[name];
    final next = (queue == null || queue.isEmpty) ? defaults[name] : queue.removeAt(0);
    if (next is Exception || next is Error) throw next!;
    return next;
  }
}

class FakeUploads implements ImageUploadService {
  final folders = <String>[];
  final counts = <int>[];
  Object? error;

  @override
  Future<List<String>> upload(String folder, List<PickedPhoto> photos, {ValueChanged<double>? onProgress}) async {
    folders.add(folder);
    counts.add(photos.length);
    onProgress?.call(0.5);
    if (error != null) throw error!;
    onProgress?.call(1);
    return [for (var i = 0; i < photos.length; i++) 'https://img/$folder/${i + 1}.jpg'];
  }
}

class FakePhotoService extends Fake implements PhotoService {
  int picks = 0;
  Object? error;

  @override
  Future<PickedPhoto?> pick(ImageSource source) async {
    picks++;
    if (error != null) throw error!;
    return PickedPhoto(testPhotoBytes, name: 'p$picks.jpg');
  }
}

const testProfile = UserModel(uid: 'u1', name: 'Sara Ahmed', phone: '7501234567', city: 'erbil');

class Phase8Harness {
  Phase8Harness({
    required this.container,
    required this.router,
    required this.firestore,
    required this.callable,
    required this.uploads,
    required this.photos,
    required this.openedLinks,
  });

  final ProviderContainer container;
  final GoRouter router;
  final FakeFirebaseFirestore firestore;
  final FakeCallable callable;
  final FakeUploads uploads;
  final FakePhotoService photos;
  final List<Uri> openedLinks;

  FakeAnalytics get analytics => container.read(analyticsServiceProvider) as FakeAnalytics;
  String get location => router.state.uri.toString();
}

Future<Phase8Harness> pumpPhase8(
  WidgetTester tester, {
  required String initialPath,
  bool guest = false,
  FakeFirebaseFirestore? firestore,
  FakeCallable? callable,
  UserModel? profile = testProfile,
  List<CityModel> cities = testCities,
  GeneralSettings settings = const GeneralSettings(),
  PaymentSettings payments = const PaymentSettings(),
  DateTime? now,
  String locale = 'en',
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 2400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = firestore ?? FakeFirebaseFirestore();
  final User? user = guest ? null : FakeUser(uid: 'u1');
  final call = callable ?? FakeCallable();
  final uploads = FakeUploads();
  final photos = FakePhotoService();
  final opened = <Uri>[];
  final clock = now ?? DateTime(2026, 10, 21, 9);

  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(prefs, firestore: db, user: user),
    citiesProvider.overrideWith((ref) => Stream.value(cities)),
    generalSettingsProvider.overrideWith((ref) => Stream.value(settings)),
    paymentSettingsProvider.overrideWith((ref) => Stream.value(payments)),
    checkoutClockProvider.overrideWithValue(() => clock),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(guest ? null : profile)),
    externalLinkOpenerProvider.overrideWithValue((uri) async {
      opened.add(uri);
      return true;
    }),
    giftCardsRepositoryProvider.overrideWithValue(GiftCardsRepository(db, call.call)),
    specialRequestsRepositoryProvider.overrideWithValue(SpecialRequestsRepository(db, uploads, call.call)),
    partnerRepositoryProvider.overrideWithValue(PartnerRepository(db, call.call)),
    imageUploadServiceProvider.overrideWithValue(uploads),
    photoServiceProvider.overrideWithValue(photos),
  ]);
  addTearDown(container.dispose);

  Widget stub(String text) => Scaffold(body: Center(child: Text(text)));

  final router = GoRouter(
    initialLocation: initialPath,
    routes: [
      GoRoute(
        path: '/home-test',
        builder: (_, __) => const Scaffold(body: CustomScrollView(slivers: [HomeGiftCardsSection()])),
      ),
      GoRoute(path: AppRoutes.giftCards, builder: (_, __) => const MyGiftCardsScreen()),
      GoRoute(path: AppRoutes.giftCardsShop, builder: (_, __) => const GiftCardShopScreen()),
      GoRoute(
        path: AppRoutes.giftCardDesigner,
        builder: (_, state) => GiftCardDesignerScreen(templateId: state.pathParameters['templateId']!),
      ),
      GoRoute(path: AppRoutes.specialRequests, builder: (_, __) => const SpecialRequestsScreen()),
      GoRoute(
        path: AppRoutes.specialRequestDetails,
        builder: (_, state) => SpecialRequestDetailsScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.specialRequestAccept,
        builder: (_, state) => AcceptQuoteScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.becomePartner, builder: (_, __) => const BecomePartnerScreen()),
      GoRoute(path: AppRoutes.contactUs, builder: (_, __) => const ContactUsScreen()),
      GoRoute(
        path: AppRoutes.addresses,
        builder: (_, state) => AddressesScreen(selectMode: state.uri.queryParameters['select'] == '1'),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (_, state) => AddressFormScreen(addressId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: AppRoutes.orderSuccess, builder: (_, state) => stub('order success ${state.pathParameters['id']}')),
      GoRoute(path: AppRoutes.orderDetails, builder: (_, state) => stub('order ${state.pathParameters['id']}')),
      GoRoute(path: AppRoutes.wallet, builder: (_, __) => stub('wallet')),
      GoRoute(path: AppRoutes.main, builder: (_, state) => stub('main tab ${state.uri.queryParameters['tab']}')),
      for (final path in [AppRoutes.signIn, AppRoutes.signUp]) GoRoute(path: path, builder: (_, __) => stub(path)),
    ],
  );

  final appLocale = Locale(locale);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      locale: appLocale,
      theme: AppTheme.lightTheme(appLocale),
      darkTheme: AppTheme.darkTheme(appLocale),
      themeMode: themeMode,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return Phase8Harness(
    container: container,
    router: router,
    firestore: db,
    callable: call,
    uploads: uploads,
    photos: photos,
    openedLinks: opened,
  );
}

/// Types into the TextField inside the widget with [key] (GGInput / PhoneField).
Future<void> enterIn(WidgetTester tester, String key, String text) async {
  final field = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) => tapVisible(tester, find.byKey(ValueKey(key)));

/// Picks a photo from the gallery through the (fake) photo service.
Future<void> addPhoto(WidgetTester tester, String addKey, AppLocalizations l10n) async {
  await tapKey(tester, addKey);
  await tester.tap(find.text(l10n.chooseFromGallery));
  await tester.pumpAndSettle();
}

Future<void> seedTemplate(
  FakeFirebaseFirestore db,
  String id, {
  String name = 'Golden Classic',
  List<int> presets = const [15000, 25000, 100000],
  int min = 10000,
  int max = 500000,
  int sortOrder = 0,
  String? gradientStart,
  String? gradientEnd,
}) =>
    db.doc('gift_card_templates/$id').set({
      'name': name,
      'nameAr': 'كلاسيك ذهبي',
      'nameKu': 'کلاسیکی زێڕین',
      'presetAmounts': presets,
      'minAmount': min,
      'maxAmount': max,
      'sortOrder': sortOrder,
      'isActive': true,
      'gradientStart': gradientStart,
      'gradientEnd': gradientEnd,
    });

Future<void> seedWallet(FakeFirebaseFirestore db, {int balance = 0, int credits = 0}) =>
    db.doc('wallets/u1').set({'balance': balance, 'credits': credits, 'currency': 'IQD'});

Future<void> seedRequest(
  FakeFirebaseFirestore db,
  String id, {
  String text = 'A wooden box with our names',
  String status = 'submitted',
  String type = 'gift',
  String? lastMessageBy = 'customer',
  int? quoteAmount,
  String? quoteNote,
  String? orderId,
  List<String> images = const [],
  DateTime? createdAt,
  String userId = 'u1',
}) =>
    db.doc('special_requests/$id').set({
      'userId': userId,
      'type': type,
      'text': text,
      'images': images,
      'status': status,
      'quoteAmount': quoteAmount,
      'quoteNote': quoteNote,
      'orderId': orderId,
      'lastMessageBy': lastMessageBy,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 20, 12)),
    });

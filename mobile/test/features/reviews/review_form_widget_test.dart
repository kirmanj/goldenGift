import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/services/image_upload_service.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/product_details/data/photo_service.dart';
import 'package:golden_gift/features/product_details/domain/product_configuration.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_providers.dart';
import 'package:golden_gift/features/reviews/presentation/providers/review_providers.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/review_form_sheet.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/star_rating.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/review_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';
import '../product_details/shop_test_harness.dart' show FakePhotoService;

AppLocalizations _l10n(String code) => lookupAppLocalizations(Locale(code));
final _en = _l10n('en');

class FakeUploads implements ImageUploadService {
  final calls = <(String, int)>[];
  Object? error;

  @override
  Future<List<String>> upload(String folder, List<PickedPhoto> photos, {ValueChanged<double>? onProgress}) async {
    calls.add((folder, photos.length));
    if (error != null) throw error!;
    return [for (var i = 0; i < photos.length; i++) 'https://storage.test/$folder/${i + 1}.jpg'];
  }
}

const _target = ReviewTarget(
  productId: 'frame',
  orderId: 'o1',
  storeId: 's1',
  productTitle: LocalizedText('Photo Frame', ar: 'إطار صور', ku: 'چوارچێوەی وێنە'),
);

class _Harness {
  _Harness(this.db, this.uploads, this.photos, this.results);
  final FakeFirebaseFirestore db;
  final FakeUploads uploads;
  final FakePhotoService photos;
  final List<bool> results;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  ReviewModel? existing,
  String locale = 'en',
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(size.width * 3, size.height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = FakeFirebaseFirestore();
  final uploads = FakeUploads();
  final photos = FakePhotoService();
  final results = <bool>[];
  final appLocale = Locale(locale);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...appTestOverridesSync(prefs, firestore: db, user: FakeUser(uid: 'u1')),
      currentUserProfileProvider
          .overrideWith((ref) => Stream.value(const UserModel(uid: 'u1', name: 'Sara Ahmed', phone: '+9647501234567'))),
      photoServiceProvider.overrideWithValue(photos),
      imageUploadServiceProvider.overrideWithValue(uploads),
    ],
    child: MaterialApp(
      locale: appLocale,
      theme: AppTheme.lightTheme(appLocale),
      darkTheme: AppTheme.darkTheme(appLocale),
      themeMode: mode,
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
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async => results.add(await showReviewFormSheet(context, target: _target, existing: existing)),
              child: const Text('open form'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
  return _Harness(db, uploads, photos, results);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _addPhoto(WidgetTester tester, [String locale = 'en']) async {
  await _tap(tester, find.byKey(const ValueKey('review-add-photo')));
  await tester.tap(find.text(_l10n(locale).chooseFromGallery));
  await tester.pumpAndSettle();
}

Finder get _text => find.descendant(of: find.byKey(const ValueKey('review-text')), matching: find.byType(TextField));

void main() {
  testWidgets('stars are required: nothing is written without a rating', (tester) async {
    final h = await _pump(tester);
    expect(find.text(_en.reviewFormTitle), findsOneWidget);
    expect(find.text('Photo Frame'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-submit')));
    expect(find.byKey(const ValueKey('review-rating-error')), findsOneWidget);
    expect((await h.db.collection('products/frame/reviews').get()).docs, isEmpty);
    expect(h.results, isEmpty);
  });

  testWidgets('each star is a 44 px button announced as "n stars"', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    for (var i = 1; i <= 5; i++) {
      final size = tester.getSize(find.byKey(ValueKey('review-star-$i')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel(_en.reviewStarButton(i)), findsOneWidget);
    }
    await _tap(tester, find.byKey(const ValueKey('review-star-3')));
    expect(tester.widget<StarRatingInput>(find.byType(StarRatingInput)).value, 3);
    handle.dispose();
  });

  testWidgets('submit: rating, trimmed text, photos uploaded to reviews/{uid}/{orderId}_{productId}', (tester) async {
    final h = await _pump(tester);
    await _tap(tester, find.byKey(const ValueKey('review-star-4')));
    await tester.enterText(_text, '  Beautiful frame, fast delivery  ');
    await _addPhoto(tester);
    await _addPhoto(tester);
    expect(find.byKey(const ValueKey('review-form-photo-1')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('review-submit')));

    expect(h.uploads.calls, [('reviews/u1/o1_frame', 2)]);
    final doc = (await h.db.doc('products/frame/reviews/o1_u1').get()).data()!;
    expect(doc['rating'], 4);
    expect(doc['text'], 'Beautiful frame, fast delivery');
    expect(doc['images'], ['https://storage.test/reviews/u1/o1_frame/1.jpg', 'https://storage.test/reviews/u1/o1_frame/2.jpg']);
    expect(doc['userName'], 'Sara');
    expect(doc['userId'], 'u1');
    expect(doc['storeId'], 's1');
    expect(doc['orderId'], 'o1');
    expect(doc['isApproved'], isFalse);
    expect(h.results, [true]);
    expect(find.byKey(const ValueKey('review-form')), findsNothing);
  });

  testWidgets('at most 3 photos; text stops at 500 with a counter', (tester) async {
    await _pump(tester);
    for (var i = 0; i < ReviewModel.maxImages; i++) {
      await _addPhoto(tester);
    }
    expect(find.byKey(const ValueKey('review-add-photo')), findsNothing);
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('review-form-photo-0')), matching: find.byType(InkResponse)));
    expect(find.byKey(const ValueKey('review-add-photo')), findsOneWidget);

    await tester.enterText(_text, 'x' * 600);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_text).controller!.text.length, ReviewModel.maxText);
    expect(find.text('500/500'), findsOneWidget);
  });

  testWidgets('a failed photo upload writes nothing', (tester) async {
    final h = await _pump(tester);
    h.uploads.error = Exception('storage down');
    await _tap(tester, find.byKey(const ValueKey('review-star-5')));
    await _addPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('review-submit')));
    expect(find.text(_en.photoUploadFailed), findsOneWidget);
    expect((await h.db.doc('products/frame/reviews/o1_u1').get()).exists, isFalse);
    expect(find.byKey(const ValueKey('review-form')), findsOneWidget);
  });

  testWidgets('editing warns about moderation, keeps old photos and uploads new ones to a fresh folder',
      (tester) async {
    const existing = ReviewModel(
      id: 'o1_u1',
      productId: 'frame',
      userId: 'u1',
      userName: 'Sara',
      storeId: 's1',
      rating: 2,
      text: 'Arrived late',
      // Empty URLs render the offline fallback tile (no network in tests).
      images: ['', ''],
      orderId: 'o1',
      isApproved: true,
    );
    final h = await _pump(tester, existing: existing);
    expect(find.text(_en.reviewEdit), findsOneWidget);
    expect(find.byKey(const ValueKey('review-edit-warning')), findsOneWidget);
    expect(find.text(_en.reviewEditWarning), findsOneWidget);
    expect(tester.widget<StarRatingInput>(find.byType(StarRatingInput)).value, 2);
    expect(tester.widget<TextField>(_text).controller!.text, 'Arrived late');

    // Remove the first old photo, add a new one, change the rating.
    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('review-form-photo-0')), matching: find.byType(InkResponse)));
    await _addPhoto(tester);
    await _tap(tester, find.byKey(const ValueKey('review-star-4')));
    await _tap(tester, find.byKey(const ValueKey('review-submit')));

    final folder = h.uploads.calls.single.$1;
    expect(folder, startsWith('reviews/u1/o1_frame/'));
    final doc = (await h.db.doc('products/frame/reviews/o1_u1').get()).data()!;
    expect(doc['rating'], 4);
    expect(doc['images'], ['', 'https://storage.test/$folder/1.jpg']);
    expect(doc['isApproved'], isFalse); // back to moderation
  });

  for (final (locale, mode) in [('ar', ThemeMode.dark), ('ckb', ThemeMode.light)]) {
    testWidgets('renders in $locale (${mode.name})', (tester) async {
      await _pump(tester, locale: locale, mode: mode);
      final l10n = _l10n(locale);
      expect(find.text(l10n.reviewFormTitle), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('review-submit')));
      expect(find.text(l10n.reviewRatingRequired), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(StarRatingInput))), TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in ['en', 'ar', 'ckb']) {
    testWidgets('no overflow at 320 px with 1.3× text ($locale)', (tester) async {
      await _pump(tester, locale: locale, size: const Size(320, 900), textScale: 1.3);
      await _addPhoto(tester, locale);
      await _tap(tester, find.byKey(const ValueKey('review-submit')));
      expect(tester.takeException(), isNull);
    });
  }
}

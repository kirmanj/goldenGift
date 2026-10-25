import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../models/banner_model.dart';
import '../../../../models/category_model.dart';
import '../../../../models/product_model.dart';
import '../../../categories/presentation/providers/categories_providers.dart';
import '../../../products/data/product_query.dart';
import '../../../product_details/data/product_repository.dart';
import '../../../products/data/product_search_repository.dart';

/// Home sections (SRS §5.4). Each section is its own provider, so one failing
/// never blanks the page; all are live Firestore listeners, which render from
/// the offline cache first and update when the server answers.
///
/// Read budget per Home open (SRS §8 ≤ 60 docs), every section limited:
/// banners 8, categories 10, popular 6, featured 6, for you 6, gift cards 4
/// (`homeGiftCardTemplatesProvider`), Discover first page 20 = 60. Guarded
/// by test/qa/home_reads_test.dart.

const homeProductLimit = 6;
const homeCategoryLimit = 10;

/// Active banners read for all four placements together (first by sortOrder).
const homeBannerLimit = 8;

/// Live banners grouped by placement, sorted, inside their schedule.
final homeBannersProvider = StreamProvider<Map<BannerPlacement, List<BannerModel>>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.banners)
      .where('isActive', isEqualTo: true)
      .orderBy('sortOrder')
      .limit(homeBannerLimit)
      .snapshots()
      .map((snap) {
    final now = DateTime.now();
    final banners = [
      for (final d in snap.docs) BannerModel.fromMap(d.id, d.data()),
    ].where((b) => b.isLiveAt(now)).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return {
      for (final placement in BannerPlacement.values)
        placement: banners.where((b) => b.placement == placement).toList(),
    };
  });
});

/// First categories by sortOrder: the 2×4 grid shows 7 + More; Discover chips use all of them.
final homeCategoriesProvider = StreamProvider<List<CategoryModel>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.categories)
      .where('isActive', isEqualTo: true)
      .orderBy('sortOrder')
      .limit(homeCategoryLimit)
      .snapshots()
      .map((snap) {
    final now = DateTime.now();
    return [for (final d in snap.docs) CategoryModel.fromMap(d.id, d.data())]
        .where((c) => c.isVisibleAt(now))
        .toList();
  });
});

Stream<List<ProductModel>> _products(Ref ref, ProductQuery query) => ref
    .watch(firestoreProductSourceProvider)
    .buildQuery(query)
    .limit(homeProductLimit)
    .snapshots()
    .map((QuerySnapshot<Map<String, dynamic>> snap) =>
        [for (final d in snap.docs) ProductModel.fromMap(d.id, d.data())]);

/// The queries behind Popular / Featured / For you — also used by their "View All".
class HomeQueries {
  HomeQueries._();
  static const popular = ProductQuery(sort: ProductSort.popular);
  static const featured = ProductQuery(featuredOnly: true);

  /// "For you" for guests and before any viewing history: newest products.
  static const forYou = ProductQuery(sort: ProductSort.newest);
}

final popularProductsProvider = StreamProvider<List<ProductModel>>((ref) => _products(ref, HomeQueries.popular));
final featuredProductsProvider = StreamProvider<List<ProductModel>>((ref) => _products(ref, HomeQueries.featured));
/// SRS §5.4 item 9: signed-in → popular products from the most-viewed
/// category (device-local history); guests → newest. Also drives "View All".
/// A most-viewed category that is coming soon (§5.7a) is skipped: its
/// "View All" would open the coming-soon page.
final forYouQueryProvider = Provider<ProductQuery>((ref) {
  final signedIn = ref.watch(authStateProvider).valueOrNull != null;
  ref.watch(viewHistoryProvider);
  final top = ref.read(viewHistoryProvider.notifier).topCategory;
  if (!signedIn || top == null) return HomeQueries.forYou;
  if (comingSoonCategoryIn(ref.watch(homeCategoriesProvider).valueOrNull, top) != null) return HomeQueries.forYou;
  return ProductQuery(categoryId: top, sort: ProductSort.popular);
});

final forYouProductsProvider =
    StreamProvider<List<ProductModel>>((ref) => _products(ref, ref.watch(forYouQueryProvider)));

enum Greeting { morning, afternoon, evening }

/// "Good morning / afternoon / evening" by local time (SRS §5.4 item 1).
Greeting greetingFor(DateTime time) {
  final h = time.hour;
  if (h >= 5 && h < 12) return Greeting.morning;
  if (h >= 12 && h < 17) return Greeting.afternoon;
  return Greeting.evening;
}

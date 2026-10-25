import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/audit/audit_log_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/banners/banners_screen.dart';
import '../../features/categories/categories_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/gift_cards/gift_cards_screen.dart';
import '../../features/notifications/broadcast_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/products/import/product_import_screen.dart';
import '../../features/products/product_editor_screen.dart';
import '../../features/products/products_screen.dart';
import '../../features/promo_codes/promo_codes_screen.dart';
import '../../features/reels/reels_screen.dart';
import '../../features/referrals/referrals_screen.dart';
import '../../features/reviews/reviews_screen.dart';
import '../../features/secret_santa/secret_santa_group_screen.dart';
import '../../features/secret_santa/secret_santa_screen.dart';
import '../../features/seller/store_profile_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/special_requests/special_request_detail_screen.dart';
import '../../features/special_requests/special_requests_screen.dart';
import '../../features/stores/store_detail_screen.dart';
import '../../features/stores/stores_screen.dart';
import '../../features/users/user_detail_screen.dart';
import '../../features/users/users_screen.dart';
import 'admin_routes.dart';

/// Flat route list (same convention as the app). Access is gated inside
/// AdminScaffold, so there are no redirects / refreshListenable.
final adminRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AdminRoutes.dashboard,
    routes: [
      GoRoute(path: AdminRoutes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: AdminRoutes.dashboard, builder: (_, __) => const DashboardScreen()),
      GoRoute(path: AdminRoutes.products, builder: (_, __) => const ProductsScreen()),
      GoRoute(
        path: AdminRoutes.productNew,
        onExit: ProductEditorGuard.onExit,
        builder: (_, __) => const ProductEditorScreen(),
      ),
      // Before productEdit, so "/products/import" isn't read as a product id.
      GoRoute(path: AdminRoutes.productImport, builder: (_, __) => const ProductImportScreen()),
      GoRoute(
        path: AdminRoutes.productEdit,
        onExit: ProductEditorGuard.onExit,
        builder: (_, state) => ProductEditorScreen(productId: state.pathParameters['id']),
      ),
      GoRoute(path: AdminRoutes.categories, builder: (_, __) => const CategoriesScreen()),
      GoRoute(path: AdminRoutes.banners, builder: (_, __) => const BannersScreen()),
      GoRoute(path: AdminRoutes.reels, builder: (_, __) => const ReelsScreen()),
      GoRoute(path: AdminRoutes.settings, builder: (_, __) => const SettingsScreen()),
      GoRoute(path: AdminRoutes.auditLog, builder: (_, __) => const AuditLogScreen()),
      GoRoute(path: AdminRoutes.orders, builder: (_, __) => const OrdersScreen()),
      GoRoute(path: AdminRoutes.users, builder: (_, __) => const UsersScreen()),
      GoRoute(
        path: AdminRoutes.userDetail,
        builder: (_, state) => UserDetailScreen(uid: state.pathParameters['id']!),
      ),
      GoRoute(path: AdminRoutes.promoCodes, builder: (_, __) => const PromoCodesScreen()),
      GoRoute(path: AdminRoutes.referrals, builder: (_, __) => const ReferralsScreen()),
      GoRoute(path: AdminRoutes.giftCards, builder: (_, __) => const GiftCardsScreen()),
      GoRoute(path: AdminRoutes.specialRequests, builder: (_, __) => const SpecialRequestsScreen()),
      GoRoute(
        path: AdminRoutes.specialRequestDetail,
        builder: (_, state) => SpecialRequestDetailScreen(requestId: state.pathParameters['id']!),
      ),
      GoRoute(path: AdminRoutes.stores, builder: (_, __) => const StoresScreen()),
      GoRoute(
        path: AdminRoutes.storeDetail,
        builder: (_, state) => StoreDetailScreen(storeId: state.pathParameters['id']!),
      ),
      GoRoute(path: AdminRoutes.storeProfile, builder: (_, __) => const StoreProfileScreen()),
      GoRoute(path: AdminRoutes.reviews, builder: (_, __) => const ReviewsScreen()),
      GoRoute(path: AdminRoutes.secretSanta, builder: (_, __) => const SecretSantaScreen()),
      GoRoute(
        path: AdminRoutes.secretSantaDetail,
        builder: (_, state) => SecretSantaGroupScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(path: AdminRoutes.notifications, builder: (_, __) => const BroadcastScreen()),
    ],
  );
});

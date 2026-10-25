import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../config/app_features.dart';
import '../../dev/widget_gallery_screen.dart';
import '../../features/addresses/presentation/screens/address_form_screen.dart';
import '../../features/addresses/presentation/screens/addresses_screen.dart';
import '../../features/ai_search/presentation/screens/ai_gift_search_screen.dart';
import '../../features/auth/presentation/providers/auth_flow.dart';
import '../../features/auth/presentation/providers/otp_controller.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/sign_in_screen.dart';
import '../../features/auth/presentation/screens/sign_up_screen.dart';
import '../../features/categories/presentation/screens/all_categories_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../features/gift_cards/presentation/screens/gift_card_designer_screen.dart';
import '../../features/gift_cards/presentation/screens/gift_card_shop_screen.dart';
import '../../features/gift_cards/presentation/screens/my_gift_cards_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/onboarding/presentation/screens/maintenance_screen.dart';
import '../../features/orders/presentation/screens/order_details_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/onboarding/presentation/screens/splash_screen.dart';
import '../../features/onboarding/presentation/screens/update_required_screen.dart';
import '../../features/partners/presentation/screens/become_partner_screen.dart';
import '../../features/payments/presentation/screens/payment_status_screen.dart';
import '../../features/product_details/presentation/screens/product_details_screen.dart';
import '../../features/products/data/product_query.dart';
import '../../features/products/presentation/screens/products_screen.dart';
import '../../features/promo_codes/presentation/screens/promo_codes_screen.dart';
import '../../features/profile/presentation/screens/change_phone_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/profile/presentation/screens/settings_screen.dart';
import '../../features/referrals/presentation/providers/referral_providers.dart';
import '../../features/referrals/presentation/screens/invite_earn_screen.dart';
import '../../features/secret_santa/presentation/screens/secret_santa_group_screen.dart';
import '../../features/secret_santa/presentation/screens/secret_santa_join_screen.dart';
import '../../features/secret_santa/presentation/screens/secret_santa_screen.dart';
import '../../features/special_requests/presentation/screens/accept_quote_screen.dart';
import '../../features/special_requests/presentation/screens/special_request_details_screen.dart';
import '../../features/special_requests/presentation/screens/special_requests_screen.dart';
import '../../features/support/presentation/screens/contact_us_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/wishlist/presentation/screens/wishlist_screen.dart';
import '../../l10n/l10n.dart';
import '../widgets/main_shell.dart';
import '../widgets/placeholder_screen.dart';

/// Route names (SRS §5 — one entry per screen). Flat list, no ShellRoute,
/// no refreshListenable (BB convention: avoids auth-state rebuild loops).
class AppRoutes {
  AppRoutes._();
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const signUp = '/sign-up';               // ?ref=<referral code>
  static const signIn = '/sign-in';
  static const otp = '/otp';                      // extra: OtpArgs
  static const completeProfile = '/complete-profile'; // extra: ProfilePrefill
  static const maintenance = '/maintenance';
  static const updateRequired = '/update-required';
  static const main = '/main';                    // ?tab=0|1|2|3 — MainTab ids (Home · Cart · Profile · Reels)
  static const categories = '/categories';
  static const products = '/products';            // ProductQuery params; ?focus=1 focuses search
  static const productDetails = '/product/:id';
  static const aiGiftSearch = '/ai-gift-search';
  static const checkout = '/checkout';
  static const orderSuccess = '/order-success/:id';
  static const orders = '/orders';
  static const orderDetails = '/orders/:id';
  static const wishlists = '/wishlists';
  static const secretSanta = '/secret-santa';
  static const secretSantaGroup = '/secret-santa/:id';
  static const savedCards = '/saved-cards';
  static const wallet = '/wallet';
  static const inviteAndEarn = '/invite';
  static const specialRequests = '/special-requests';
  static const specialRequestDetails = '/special-requests/:id';
  static const specialRequestAccept = '/special-requests/:id/accept';
  static const addresses = '/addresses';
  static const addressForm = '/addresses/form';   // ?id= to edit
  static const giftCards = '/gift-cards';
  static const giftCardDesigner = '/gift-cards/design/:templateId';
  static const giftCardsShop = '/gift-cards/shop';
  static const promoCodes = '/promo-codes';
  static const notifications = '/notifications';
  static const editProfile = '/profile/edit';
  static const changePhone = '/profile/phone';
  static const settings = '/settings';
  static const contactUs = '/contact-us';
  static const becomePartner = '/become-partner';
  /// Online payment status (SRS §5.11, §5.18); `?status=` = the gateway's hint.
  static const payment = '/payment/:sid';

  /// The gateway's way back into the app, `goldengift://payment?sid=…&status=…`
  /// (`zainCashReturn`, SRS §7; Android intent-filter + iOS URL scheme).
  static const appScheme = 'goldengift';
  static const paymentLinkHost = 'payment';

  /// Share links (SRS §4.6): https://goldengift.app/p/{id} and /r/{code}.
  static const productShareLink = '/p/:id';
  static const referralShareLink = '/r/:code';

  /// Secret Santa invite (SRS §5.16): https://goldengift.app/s/{inviteCode} → join flow.
  static const secretSantaJoinLink = '/s/:code';

  /// Debug builds only.
  static const devGallery = '/dev/gallery';

  static String product(String id) => '/product/$id';
  static String productsFor(ProductQuery query, {bool focusSearch = false}) => Uri(
        path: products,
        queryParameters: {...query.toQueryParameters(), if (focusSearch) 'focus': '1'},
      ).toString();
  static String mainTab(int index) => '$main?tab=$index';
  static String orderSuccessFor(String id) => '/order-success/$id';
  static String order(String id) => '/orders/$id';
  static String secretSantaGroupFor(String id) => '/secret-santa/$id';
  static String secretSantaJoin(String code) => '/s/$code';
  static String specialRequest(String id) => '/special-requests/$id';
  static String giftCardDesign(String templateId) => '/gift-cards/design/$templateId';
  static String specialRequestAcceptFor(String id) => '/special-requests/$id/accept';
  static String paymentFor(String sessionId, {String? status}) =>
      Uri(path: '/payment/$sessionId', queryParameters: status == null ? null : {'status': status}).toString();
}

/// Tab ids of `/main?tab=` (SRS §5.3): stable and independent of the visual
/// order (Home · Reels · Cart · Profile), so links stored in notifications
/// keep opening the same tab.
class MainTab {
  MainTab._();
  static const home = 0;
  static const cart = 1;
  static const profile = 2;
  static const reels = 3;
  static const count = 4;
}

final _sessionId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Maps the gateway's deep link to the payment status page (null = not one).
/// Android / iOS hand the router the whole URI — `goldengift://payment?sid=…`
/// (host `payment`, empty path → `/`); a cold start keeps only
/// `/?sid=…&status=…`. Also accepts `/payment?sid=…`. No / bad sid → Orders.
String? paymentDeepLinkRedirect(Uri uri) {
  final q = uri.queryParameters;
  final isLink = (uri.scheme == AppRoutes.appScheme && uri.host == AppRoutes.paymentLinkHost) ||
      uri.path == '/${AppRoutes.paymentLinkHost}' ||
      ((uri.path == '/' || uri.path.isEmpty) && q.containsKey('sid'));
  if (!isLink) return null;
  final sid = q['sid'] ?? '';
  if (!_sessionId.hasMatch(sid)) return AppRoutes.orders;
  final status = q['status'];
  return AppRoutes.paymentFor(sid, status: status == null || status.isEmpty || status.length > 16 ? null : status);
}

/// Every screen until its phase replaces it (SRS §10): path → placeholder title.
final _placeholders = <String, String Function(AppLocalizations)>{
  AppRoutes.savedCards: (l10n) => l10n.savedCards,
};

final appRouterProvider = Provider<GoRouter>((ref) => buildAppRouter(ref));

/// The app's router: every screen route (SRS §3). Widget tests (the Phase 10
/// route sweep) build it with another [initialLocation] / [initialExtra] so
/// they pump the real route list.
GoRouter buildAppRouter(Ref ref, {String initialLocation = AppRoutes.splash, Object? initialExtra}) {
  return GoRouter(
    initialLocation: initialLocation,
    initialExtra: initialExtra,
    redirect: (_, state) => paymentDeepLinkRedirect(state.uri),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: AppRoutes.maintenance, builder: (_, __) => const MaintenanceScreen()),
      GoRoute(path: AppRoutes.updateRequired, builder: (_, __) => const UpdateRequiredScreen()),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (_, state) => SignUpScreen(referralCode: state.uri.queryParameters['ref']),
      ),
      GoRoute(
        path: AppRoutes.completeProfile,
        redirect: (_, state) => state.extra is ProfilePrefill ? null : AppRoutes.signIn,
        builder: (_, state) => SignUpScreen(prefill: state.extra! as ProfilePrefill),
      ),
      GoRoute(path: AppRoutes.signIn, builder: (_, __) => const SignInScreen()),
      // OTP needs the live verification session; a refresh/deep link without it restarts sign-in.
      GoRoute(
        path: AppRoutes.otp,
        redirect: (_, state) => state.extra is OtpArgs ? null : AppRoutes.signIn,
        builder: (_, state) => OtpScreen(args: state.extra! as OtpArgs),
      ),
      GoRoute(
        path: AppRoutes.main,
        builder: (_, state) => MainShell(
          initialIndex: (int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? MainTab.home).clamp(0, MainTab.count - 1),
        ),
      ),
      GoRoute(path: AppRoutes.categories, builder: (_, __) => const AllCategoriesScreen()),
      GoRoute(
        path: AppRoutes.productDetails,
        builder: (_, state) => ProductDetailsScreen(productId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.wishlists, builder: (_, __) => const WishlistScreen()),
      GoRoute(
        path: AppRoutes.aiGiftSearch,
        // Hidden for now (AppFeatures): old links land on Home.
        redirect: (_, __) => AppFeatures.aiGiftSearch ? null : AppRoutes.mainTab(0),
        builder: (_, __) => const AiGiftSearchScreen(),
      ),
      GoRoute(path: AppRoutes.secretSanta, builder: (_, __) => const SecretSantaScreen()),
      GoRoute(
        path: AppRoutes.secretSantaGroup,
        builder: (_, state) => SecretSantaGroupScreen(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.secretSantaJoinLink,
        builder: (_, state) => SecretSantaJoinScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(path: AppRoutes.checkout, builder: (_, __) => const CheckoutScreen()),
      GoRoute(
        path: AppRoutes.orderSuccess,
        builder: (_, state) => OrderSuccessScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: AppRoutes.orders, builder: (_, __) => const OrdersScreen()),
      GoRoute(
        path: AppRoutes.orderDetails,
        builder: (_, state) => OrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.addresses,
        builder: (_, state) => AddressesScreen(selectMode: state.uri.queryParameters['select'] == '1'),
      ),
      GoRoute(
        path: AppRoutes.addressForm,
        builder: (_, state) => AddressFormScreen(addressId: state.uri.queryParameters['id']),
      ),
      GoRoute(path: AppRoutes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: AppRoutes.contactUs, builder: (_, __) => const ContactUsScreen()),
      GoRoute(
        path: AppRoutes.products,
        builder: (_, state) => ProductsScreen(
          initialQuery: ProductQuery.fromQueryParameters(state.uri.queryParameters),
          focusSearch: state.uri.queryParameters['focus'] == '1',
        ),
      ),
      GoRoute(path: AppRoutes.editProfile, builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: AppRoutes.changePhone, builder: (_, __) => const ChangePhoneScreen()),
      GoRoute(path: AppRoutes.settings, builder: (_, __) => const SettingsScreen()),
      GoRoute(path: AppRoutes.wallet, builder: (_, __) => const WalletScreen()),
      GoRoute(path: AppRoutes.inviteAndEarn, builder: (_, __) => const InviteEarnScreen()),
      GoRoute(path: AppRoutes.promoCodes, builder: (_, __) => const PromoCodesScreen()),
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
      GoRoute(
        path: AppRoutes.payment,
        builder: (_, state) => PaymentStatusScreen(
          sessionId: state.pathParameters['sid']!,
          statusHint: state.uri.queryParameters['status'],
        ),
      ),
      for (final entry in _placeholders.entries)
        GoRoute(
          path: entry.key,
          builder: (context, state) => PlaceholderScreen(
            title: entry.value(AppLocalizations.of(context)!),
            detail: state.pathParameters.isEmpty && state.uri.queryParameters.isEmpty
                ? null
                : {...state.pathParameters, ...state.uri.queryParameters}.toString(),
          ),
        ),
      GoRoute(
        path: AppRoutes.productShareLink,
        redirect: (_, state) => AppRoutes.product(state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.referralShareLink,
        // Signed in → Main with an explanation; otherwise Sign Up pre-filled.
        redirect: (_, state) => referralLinkRedirect(ref, state.pathParameters['code']!),
      ),
      if (kDebugMode)
        GoRoute(
          path: AppRoutes.devGallery,
          builder: (_, __) => const WidgetGalleryScreen(),
        ),
    ],
  );
}

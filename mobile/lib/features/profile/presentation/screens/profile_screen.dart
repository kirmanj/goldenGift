import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/providers/auth_flow.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../wallet/data/wallet_repository.dart';
import '../providers/profile_providers.dart';
import '../widgets/language_sheet.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_menu_tile.dart';

/// Profile tab (SRS §5.13, IMG_4490). Lives inside MainShell's IndexedStack:
/// no back button, and the floating bottom nav overlaps the body, so the
/// list keeps ≥ 100 px of bottom padding.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final showSavedCards = ref.watch(paymentSettingsProvider).valueOrNull?.card ?? false;
    final orderBonus = ref.watch(referralSettingsProvider).valueOrNull?.orderBonus ?? 0;
    // Spendable wallet total (balance + credits), once it has loaded.
    final spendable = signedIn ? ref.watch(walletProvider).valueOrNull?.spendable : null;
    final languageCode = Localizations.localeOf(context).languageCode;
    final bottomPadding = math.max(100.0, MediaQuery.paddingOf(context).bottom + AppSpacing.lg);

    void open(String route) => unawaited(context.push(route));
    Future<void> openAccount(String route) async {
      if (!await requireSignIn(context, ref)) return;
      if (context.mounted) open(route);
    }

    final rows = <Widget>[
      ProfileMenuTile(
        icon: Icons.receipt_long_rounded,
        tone: ProfileTileTone.info,
        title: l10n.orders,
        onTap: () => openAccount(AppRoutes.orders),
      ),
      ProfileMenuTile(
        icon: Icons.favorite_rounded,
        tone: ProfileTileTone.error,
        title: l10n.myWishlists,
        subtitle: l10n.wishlistSubtitle,
        onTap: () => openAccount(AppRoutes.wishlists),
      ),
      ProfileMenuTile(
        icon: Icons.celebration_rounded,
        tone: ProfileTileTone.success,
        title: l10n.secretSanta,
        subtitle: l10n.secretSantaSubtitle,
        onTap: () => openAccount(AppRoutes.secretSanta),
      ),
      if (showSavedCards)
        ProfileMenuTile(
          icon: Icons.credit_card_rounded,
          tone: ProfileTileTone.info,
          title: l10n.savedCards,
          onTap: () => openAccount(AppRoutes.savedCards),
        ),
      ProfileMenuTile(
        icon: Icons.account_balance_wallet_rounded,
        title: l10n.myWallet,
        subtitle: spendable == null ? null : CurrencyFormatter.format(spendable),
        onTap: () => openAccount(AppRoutes.wallet),
      ),
      ProfileMenuTile(
        icon: Icons.group_add_rounded,
        tone: ProfileTileTone.info,
        title: l10n.inviteAndEarn,
        subtitle: orderBonus > 0 ? l10n.inviteAndEarnSubtitle(CurrencyFormatter.format(orderBonus)) : null,
        onTap: () => openAccount(AppRoutes.inviteAndEarn),
      ),
      ProfileMenuTile(
        icon: Icons.redeem_rounded,
        tone: ProfileTileTone.neutral,
        title: l10n.specialRequests,
        onTap: () => openAccount(AppRoutes.specialRequests),
      ),
      ProfileMenuTile(
        icon: Icons.location_on_rounded,
        tone: ProfileTileTone.neutral,
        title: l10n.savedAddresses,
        onTap: () => openAccount(AppRoutes.addresses),
      ),
      ProfileMenuTile(
        icon: Icons.card_giftcard_rounded,
        tone: ProfileTileTone.error,
        title: l10n.myGiftCards,
        onTap: () => openAccount(AppRoutes.giftCards),
      ),
      ProfileMenuTile(
        icon: Icons.confirmation_number_rounded,
        tone: ProfileTileTone.info,
        title: l10n.promoCodes,
        onTap: () => open(AppRoutes.promoCodes),
      ),
      ProfileMenuTile(
        icon: Icons.support_agent_rounded,
        tone: ProfileTileTone.success,
        title: l10n.contactUs,
        onTap: () => open(AppRoutes.contactUs),
      ),
      ProfileMenuTile(
        icon: Icons.storefront_rounded,
        tone: ProfileTileTone.neutral,
        title: l10n.partnerScreenTitle,
        onTap: () => open(AppRoutes.becomePartner),
      ),
      ProfileMenuTile(
        icon: Icons.translate_rounded,
        tone: ProfileTileTone.warning,
        title: l10n.language,
        subtitle: languageName(l10n, languageCode),
        onTap: () => showLanguageSheet(context, ref),
      ),
      ProfileMenuTile(
        icon: Icons.settings_rounded,
        tone: ProfileTileTone.neutral,
        title: l10n.settings,
        onTap: () => open(AppRoutes.settings),
      ),
      if (signedIn)
        ProfileMenuTile(
          key: const ValueKey('profile-logout'),
          icon: Icons.logout_rounded,
          tone: ProfileTileTone.error,
          title: l10n.logout,
          destructive: true,
          showChevron: false,
          onTap: () => _logout(context, ref),
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppColors.isDark(context) ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Stack(
          children: [
            // Soft gold circle in the top-end corner (IMG_4490 background).
            PositionedDirectional(
              top: -140,
              end: -120,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.soft(context).withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: SafeArea(
                bottom: false,
                child: ListView(
                  padding: EdgeInsetsDirectional.only(top: AppSpacing.lg, bottom: bottomPadding),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal),
                      child: _Header(signedIn: signedIn),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader(
                      title: l10n.account,
                      padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: AppSpacing.screenHorizontal),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ...rows,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// SRS AUTH-6: confirm, sign out (clears the local cart, keeps the
  /// language), then Sign In.
  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.logoutConfirm,
      confirmLabel: l10n.logout,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authFlowProvider).signOut();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      return;
    }
    router.go(AppRoutes.signIn);
  }
}

/// Signed-in header, guest card, loading skeleton or error card.
class _Header extends ConsumerWidget {
  const _Header({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (!signedIn) {
      return ProfileMessageCard(
        key: const ValueKey('profile-guest-card'),
        icon: Icons.person_outline_rounded,
        title: l10n.guestProfileTitle,
        body: l10n.guestProfileBody,
        primaryLabel: l10n.signIn,
        onPrimary: () => context.push(AppRoutes.signIn),
        secondaryLabel: l10n.signUp,
        onSecondary: () => context.push(AppRoutes.signUp),
      );
    }
    return ref.watch(currentUserProfileProvider).when(
          loading: () => const ProfileHeaderSkeleton(),
          error: (_, __) => ProfileMessageCard(
            key: const ValueKey('profile-error-card'),
            icon: Icons.cloud_off_rounded,
            title: l10n.somethingWentWrong,
            primaryLabel: l10n.retry,
            primaryIcon: Icons.refresh_rounded,
            onPrimary: () => ref.invalidate(currentUserProfileProvider),
          ),
          data: (profile) => profile == null
              // Signed in but `users/{uid}` doesn't exist (sign-up was left
              // half-way): finish it on the Complete Profile screen.
              ? ProfileMessageCard(
                  key: const ValueKey('profile-complete-card'),
                  icon: Icons.person_add_alt_1_rounded,
                  title: l10n.completeProfileTitle,
                  body: l10n.completeProfileSubtitle,
                  primaryLabel: l10n.next,
                  onPrimary: () => _completeProfile(context, ref),
                )
              : ProfileHeader(
                  profile: profile,
                  onEdit: () => context.push(AppRoutes.editProfile),
                  onAddPhone: () => context.push(AppRoutes.changePhone),
                ),
        );
  }

  void _completeProfile(BuildContext context, WidgetRef ref) {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      context.push(AppRoutes.signIn);
      return;
    }
    final providers = user.providerData.map((p) => p.providerId).toSet();
    final method = providers.contains('google.com')
        ? SignInMethod.google
        : providers.contains('apple.com')
            ? SignInMethod.apple
            : SignInMethod.phone;
    final phone = user.phoneNumber;
    final (dial, national) =
        phone == null || phone.isEmpty ? (AppConstants.defaultCountryCode, null) : splitE164(phone);
    context.push(
      AppRoutes.completeProfile,
      extra: ProfilePrefill(
        method: method,
        name: user.displayName,
        email: user.email,
        phone: national,
        countryCode: dial,
      ),
    );
  }
}

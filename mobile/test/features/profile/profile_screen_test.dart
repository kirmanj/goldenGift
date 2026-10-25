import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/providers/locale_provider.dart';
import 'package:golden_gift/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/profile_screen.dart';
import 'package:golden_gift/features/profile/presentation/screens/settings_screen.dart';
import 'package:golden_gift/features/profile/presentation/widgets/profile_header.dart';
import 'package:golden_gift/features/profile/presentation/widgets/profile_menu_tile.dart';
import 'package:golden_gift/models/app_settings_model.dart';
import 'package:golden_gift/models/user_model.dart';
import 'package:golden_gift/models/wallet_model.dart';

import 'profile_test_harness.dart';

void main() {
  final en = l10nFor('en');

  group('ProfileScreen — guest', () {
    testWidgets('shows the Sign In card and no Logout', (tester) async {
      await pumpProfileApp(tester, signedIn: false);

      expect(find.byKey(const ValueKey('profile-guest-card')), findsOneWidget);
      expect(find.text(en.guestProfileTitle), findsOneWidget);
      expect(find.text(en.signIn), findsOneWidget);
      expect(find.text(en.signUp), findsOneWidget);
      expect(find.text(en.logout), findsNothing);
      expect(find.text(en.edit), findsNothing);
      // Guest-friendly rows are still listed.
      expect(find.text(en.promoCodes), findsOneWidget);
      expect(find.text(en.settings), findsOneWidget);
    });

    testWidgets('Sign In opens the sign-in route', (tester) async {
      await pumpProfileApp(tester, signedIn: false);
      await tester.tap(find.text(en.signIn));
      await tester.pumpAndSettle();
      expect(find.text('/sign-in'), findsOneWidget);
    });

    testWidgets('account-only rows ask to sign in instead of navigating', (tester) async {
      await pumpProfileApp(tester, signedIn: false);
      await tester.tap(find.text(en.orders));
      await tester.pumpAndSettle();
      expect(find.text(en.signInToContinue), findsOneWidget);
      expect(find.text('/orders'), findsNothing);
    });

    testWidgets('no wallet subtitle for guests', (tester) async {
      await pumpProfileApp(tester, signedIn: false, wallet: const WalletModel(balance: 12000));
      expect(find.textContaining('IQD'), findsNothing);
    });

    testWidgets('guest-friendly rows navigate directly', (tester) async {
      await pumpProfileApp(tester, signedIn: false);
      await tester.tap(find.text(en.promoCodes));
      await tester.pumpAndSettle();
      expect(find.text('/promo-codes'), findsOneWidget);
    });
  });

  group('ProfileScreen — signed in', () {
    testWidgets('header shows name, LTR phone and Edit; Edit opens Edit Profile', (tester) async {
      await pumpProfileApp(tester);

      expect(find.text('Krmanj'), findsOneWidget);
      final phone = find.text('+964 750 544 8229');
      expect(phone, findsOneWidget);
      expect(tester.widget<Text>(phone).textDirection, TextDirection.ltr);
      expect(find.text('K'), findsOneWidget); // initial on gold, no photo
      expect(find.text(en.logout), findsOneWidget);

      await tester.tap(find.text(en.edit));
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('account without a phone shows "Add mobile number"', (tester) async {
      await pumpProfileApp(tester, user: testUser(phone: ''));
      expect(find.text(en.addPhoneNumber), findsOneWidget);
      await tester.tap(find.text(en.addPhoneNumber));
      await tester.pumpAndSettle();
      expect(find.text(en.changePhoneTitle), findsOneWidget);
    });

    testWidgets('account rows navigate when signed in', (tester) async {
      await pumpProfileApp(tester);
      await tester.tap(find.text(en.myWallet));
      await tester.pumpAndSettle();
      expect(find.text('/wallet'), findsOneWidget);
    });

    testWidgets('rows follow the SRS order', (tester) async {
      await pumpProfileApp(tester, payments: const PaymentSettings(card: true));
      final titles = [
        en.orders,
        en.myWishlists,
        en.secretSanta,
        en.savedCards,
        en.myWallet,
        en.inviteAndEarn,
        en.specialRequests,
        en.savedAddresses,
        en.myGiftCards,
        en.promoCodes,
        en.contactUs,
        en.language,
        en.settings,
        en.logout,
      ];
      final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
      expect(ys, orderedEquals([...ys]..sort()));
      expect(find.text(en.wishlistSubtitle), findsOneWidget);
      expect(find.text(en.secretSantaSubtitle), findsOneWidget);
    });

    testWidgets('Saved Cards is hidden unless card payments are enabled', (tester) async {
      await pumpProfileApp(tester);
      expect(find.text(en.savedCards), findsNothing);
    });

    testWidgets('Saved Cards shows when card payments are enabled', (tester) async {
      await pumpProfileApp(tester, payments: const PaymentSettings(card: true));
      expect(find.text(en.savedCards), findsOneWidget);
    });

    testWidgets('Invite & Earn subtitle shows the formatted order bonus', (tester) async {
      await pumpProfileApp(tester, referral: const ReferralSettings(orderBonus: 5000));
      expect(find.text('Earn 5,000 IQD per friend'), findsOneWidget);
    });

    testWidgets('Invite & Earn has no subtitle when the bonus is 0', (tester) async {
      await pumpProfileApp(tester);
      expect(find.textContaining('per friend'), findsNothing);
      expect(find.text(en.inviteAndEarn), findsOneWidget);
    });

    testWidgets('My Wallet subtitle shows the spendable balance (balance + credits)', (tester) async {
      await pumpProfileApp(tester, wallet: const WalletModel(balance: 12000, credits: 5000));
      final row = find.ancestor(of: find.text(en.myWallet), matching: find.byType(ProfileMenuTile));
      expect(find.descendant(of: row, matching: find.text('17,000 IQD')), findsOneWidget);
    });

    testWidgets('My Wallet subtitle reads 0 IQD until the wallet exists', (tester) async {
      await pumpProfileApp(tester);
      final row = find.ancestor(of: find.text(en.myWallet), matching: find.byType(ProfileMenuTile));
      expect(find.descendant(of: row, matching: find.text('0 IQD')), findsOneWidget);
    });

    testWidgets('Logout confirms, signs out and opens Sign In', (tester) async {
      final app = await pumpProfileApp(tester);
      await tester.tap(find.text(en.logout));
      await tester.pumpAndSettle();
      expect(find.text(en.logoutConfirm), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(en.logout)));
      await tester.pumpAndSettle();
      expect(app.authFlow.signOutCalls, 1);
      expect(find.text('/sign-in'), findsOneWidget);
    });

    testWidgets('cancelling Logout keeps the session', (tester) async {
      final app = await pumpProfileApp(tester);
      await tester.tap(find.text(en.logout));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      expect(app.authFlow.signOutCalls, 0);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('Settings row opens Settings', (tester) async {
      await pumpProfileApp(tester);
      await tester.tap(find.text(en.settings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('ProfileScreen — loading and errors', () {
    testWidgets('shows a skeleton header while the profile loads', (tester) async {
      final controller = StreamController<UserModel?>();
      addTearDown(controller.close);
      await pumpProfileApp(tester, profileStream: () => controller.stream, settle: false);
      await tester.pump();
      expect(find.byType(ProfileHeaderSkeleton), findsOneWidget);
      expect(find.text(en.edit), findsNothing);
    });

    testWidgets('shows a retry card when the profile fails to load', (tester) async {
      await pumpProfileApp(tester, profileStream: () => Stream.error(Exception('offline')));
      expect(find.byKey(const ValueKey('profile-error-card')), findsOneWidget);
      expect(find.text(en.retry), findsOneWidget);
      // Logout stays reachable.
      expect(find.text(en.logout), findsOneWidget);
    });

    testWidgets('signed in without a profile document offers to complete it', (tester) async {
      await pumpProfileApp(tester, profileStream: () => Stream.value(null));
      expect(find.byKey(const ValueKey('profile-complete-card')), findsOneWidget);
      expect(find.text(en.completeProfileTitle), findsOneWidget);
    });
  });

  group('Language sheet', () {
    testWidgets('switching to Arabic applies immediately and saves the locale', (tester) async {
      final app = await pumpProfileApp(tester);
      await tester.tap(find.text(en.language));
      await tester.pumpAndSettle();
      expect(find.text(en.chooseLanguage), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget); // English is current

      await tester.tap(find.byKey(const ValueKey('language-ar')));
      await tester.pumpAndSettle();

      expect(app.container.read(localeProvider).languageCode, 'ar');
      expect(Directionality.of(tester.element(find.byType(ProfileScreen))), TextDirection.rtl);
      expect(find.text(l10nFor('ar').account), findsOneWidget);
      expect(app.users.fieldUpdates.single.$1, 'u1');
      expect(app.users.fieldUpdates.single.$2, {'locale': 'ar'});
    });

    testWidgets('guests can switch language without a profile write', (tester) async {
      final app = await pumpProfileApp(tester, signedIn: false);
      await tester.tap(find.text(en.language));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-ckb')));
      await tester.pumpAndSettle();
      expect(app.container.read(localeProvider).languageCode, 'ckb');
      expect(app.users.fieldUpdates, isEmpty);
    });
  });

  group('ProfileScreen — RTL, dark mode, small screens', () {
    for (final locale in ['ar', 'ckb']) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('renders in $locale (${mode.name}) at 320 px with 130 % text', (tester) async {
          await pumpProfileApp(
            tester,
            locale: locale,
            themeMode: mode,
            size: const Size(320, 2000),
            textScale: 1.3,
            payments: const PaymentSettings(card: true),
            referral: const ReferralSettings(orderBonus: 5000),
          );
          final context = tester.element(find.byType(ProfileScreen));
          expect(Directionality.of(context), TextDirection.rtl);
          expect(Theme.of(context).brightness, mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
          expect(find.text(l10nFor(locale).account), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('guest card renders in ckb dark at 320 px with 130 % text', (tester) async {
      await pumpProfileApp(
        tester,
        signedIn: false,
        locale: 'ckb',
        themeMode: ThemeMode.dark,
        size: const Size(320, 2000),
        textScale: 1.3,
      );
      expect(find.text(l10nFor('ckb').guestProfileTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long names do not overflow in English dark mode', (tester) async {
      await pumpProfileApp(
        tester,
        user: testUser(name: 'Muhammad Abdulrahman Al-Kurdistani Long Name'),
        themeMode: ThemeMode.dark,
        size: const Size(320, 2000),
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

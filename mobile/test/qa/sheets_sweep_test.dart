import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/auth/presentation/widgets/sign_in_required_sheet.dart';
import 'package:golden_gift/features/orders/presentation/widgets/order_dialogs.dart';
import 'package:golden_gift/features/payments/presentation/widgets/top_up_sheet.dart';
import 'package:golden_gift/features/product_details/presentation/widgets/photo_upload_grid.dart';
import 'package:golden_gift/features/products/data/product_query.dart';
import 'package:golden_gift/features/products/presentation/widgets/product_filter_sheet.dart';
import 'package:golden_gift/features/reels/data/reels_repository.dart';
import 'package:golden_gift/features/reels/presentation/widgets/reels_filter_sheet.dart';
import 'package:golden_gift/features/profile/presentation/widgets/language_sheet.dart';
import 'package:golden_gift/features/profile/presentation/widgets/profile_dialogs.dart';
import 'package:golden_gift/features/profile/presentation/widgets/profile_pickers.dart';
import 'package:golden_gift/features/referrals/presentation/widgets/referral_reward_sheet.dart';
import 'package:golden_gift/features/referrals/presentation/widgets/referral_rules_sheet.dart';
import 'package:golden_gift/features/reviews/presentation/providers/review_providers.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/product_reviews_section.dart';
import 'package:golden_gift/features/reviews/presentation/widgets/review_form_sheet.dart';
import 'package:golden_gift/features/secret_santa/presentation/widgets/secret_santa_create_sheet.dart';
import 'package:golden_gift/features/wishlist/presentation/widgets/wishlist_list_sheets.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import 'qa_harness.dart';

/// Phase 10 sweep of every bottom sheet, dialog and popup menu (SRS §8):
/// opened on top of the real app in {en, ar, ckb} × {light, dark} ×
/// {390×844 @100 %, 320×640 @130 %}; fails on any FlutterError (overflow,
/// exception), on leaked raw keys / "null" and — at phone size — on tap
/// targets under 48 dp or without a label. Sheets are scrolled to their end
/// so every row is laid out.

typedef OpenSheet = FutureOr<void> Function(WidgetTester tester, BuildContext context, WidgetRef ref);

class SheetCase {
  const SheetCase(this.name, this.open,
      {this.host = '/main?tab=0', this.guest = false, this.callable, this.tapTargetException});
  final String name;
  final OpenSheet open;
  final String host;
  final bool guest;
  final Future<Object?> Function(String name, Map<String, dynamic> data)? callable;

  /// Why the 48 dp check is skipped (framework widgets only).
  final String? tapTargetException;
}

/// Starts [show] without awaiting its result (the sheet stays open).
void _show(Future<Object?> Function() show) => unawaited(show());

/// Taps the widget with [key], first scrolling the page's list until it is
/// built (lazy lists only build what is on screen).
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
}

AppLocalizations _l10n(BuildContext context) => AppLocalizations.of(context)!;

final sheetCases = <SheetCase>[
  SheetCase('sign in to continue', (t, c, r) => _show(() => requireSignIn(c, r)), guest: true),
  SheetCase('product filter', (t, c, r) => _show(() => showProductFilterSheet(c, const ProductQuery()))),
  SheetCase(
    'reels filter',
    (t, c, r) => _show(() => showReelsFilterSheet(
        c, const ReelFilter(categoryId: 'mugs', priceBands: {1, 4}, giftFor: GiftAudience.companies))),
    host: '/main?tab=3',
  ),
  SheetCase(
    'country code picker',
    (t, c, r) async {
      await t.tap(find.text('+964').first);
    },
    host: '/sign-in',
    guest: true,
  ),
  SheetCase(
    'referral rules',
    (t, c, r) => _show(() => showReferralRulesSheet(
        c, const ReferralSettings(joinBonus: 5000, orderBonus: 10000, maxReferralsPerMonth: 10, creditsExpiryDays: 90))),
  ),
  SheetCase('referral reward', (t, c, r) => _show(() => showReferralRewardSheet(c))),
  SheetCase('avatar source', (t, c, r) => _show(() => showAvatarSourceSheet(c))),
  SheetCase('city picker', (t, c, r) => _show(() => showCityPickerSheet(c, selectedId: 'erbil'))),
  SheetCase(
    'delete account confirm',
    (t, c, r) => _show(() => showConfirmDialog(c,
        title: _l10n(c).deleteAccountTitle,
        message: _l10n(c).deleteAccountBody,
        confirmLabel: _l10n(c).deleteAccountConfirm,
        destructive: true)),
  ),
  SheetCase('language', (t, c, r) => _show(() => showLanguageSheet(c, r))),
  SheetCase('cancel order', (t, c, r) => _show(() => showCancelOrderDialog(c))),
  SheetCase('photo viewer', (t, c, r) => _show(() => showPhotoViewer(c, const ['', '']))),
  SheetCase('photo source', (t, c, r) => _show(() => showPhotoSourceSheet(c))),
  SheetCase(
    'wishlist list picker',
    (t, c, r) => _show(() => showWishlistListPicker(c, title: _l10n(c).wishlistChooseList, selectedId: 'default')),
  ),
  SheetCase(
    'wishlist new list',
    (t, c, r) => _show(() =>
        showWishlistListNameDialog(c, title: _l10n(c).wishlistNewList, confirmLabel: _l10n(c).wishlistCreateList)),
  ),
  SheetCase('wishlist delete list', (t, c, r) => _show(() => confirmDeleteWishlistList(c, 'Mum'))),
  SheetCase(
    'wishlist list menu',
    (t, c, r) async {
      await _tapKey(t, 'wishlist-chip-l1');
      await settle(t);
      await _tapKey(t, 'wishlist-list-menu');
    },
    host: '/wishlists',
  ),
  SheetCase(
    'review form',
    (t, c, r) => _show(() => showReviewFormSheet(c,
        target: ReviewTarget(productId: 'mug', orderId: 'o3', storeId: 's1', productTitle: qaProducts[1].title))),
  ),
  SheetCase('all reviews', (t, c, r) => _show(() => showAllReviewsSheet(c, qaProducts[1]))),
  SheetCase('secret santa create', (t, c, r) => _show(() => showSecretSantaCreateSheet(c))),
  SheetCase('secret santa draw confirm', (t, c, r) => _tapKey(t, 'santa-draw'), host: '/secret-santa/g1'),
  SheetCase('secret santa wish note', (t, c, r) => _tapKey(t, 'santa-edit-note'), host: '/secret-santa/g1'),
  SheetCase(
    'gift card redeemed',
    (t, c, r) => _tapKey(t, 'redeem-g1'),
    host: '/gift-cards',
    callable: (name, data) async => {'giftCardId': 'g1', 'amount': 25000, 'credits': 32500},
  ),
  SheetCase('address menu', (t, c, r) => _tapKey(t, 'address-menu-a2'), host: '/addresses'),
  SheetCase(
    'address delete confirm',
    (t, c, r) async {
      await _tapKey(t, 'address-menu-a2');
      await settle(t);
      await t.tap(find.text(_l10n(c).delete).last);
    },
    host: '/addresses',
  ),
  SheetCase('wallet top-up', (t, c, r) => _show(() => startWalletTopUp(c, r)), host: '/wallet'),
  SheetCase(
    'date picker',
    (t, c, r) => _show(() => showDatePicker(
        context: c, firstDate: DateTime(2026), lastDate: DateTime(2027, 12, 31), initialDate: DateTime(2026, 10, 21))),
    tapTargetException: "Material's calendar grid: day cells are dialog width / 7 = 47.7 dp at 390 px",
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final sheet in sheetCases) {
    for (final locale in qaLocales) {
      for (final theme in qaThemes) {
        for (final viewport in [QaViewport.phone, QaViewport.smallLargeText]) {
          testWidgets('${sheet.name} · $locale · ${theme.name} · $viewport', (tester) async {
            final problems = <String>{};
            final a11y = <String>{};
            var opened = false;
            // Tap targets and labels of the open sheet (phone size; the
            // small viewport is about layout).
            final semantics =
                viewport == QaViewport.phone && sheet.tapTargetException == null ? tester.ensureSemantics() : null;
            final errors = await captureFlutterErrors(() async {
              final app = await pumpQaApp(
                tester,
                location: sheet.host,
                guest: sheet.guest,
                locale: locale,
                theme: theme,
                viewport: viewport,
                callable: sheet.callable ?? qaCallable,
              );
              final host = tester.element(find.byType(Scaffold).last);
              await sheet.open(tester, host, _refOf(tester));
              await settle(tester);
              // A sheet, dialog or menu route now covers the page.
              opened = !(ModalRoute.of(host)?.isCurrent ?? true);
              problems.addAll(textProblems(tester));
              if (semantics != null) {
                for (final g in [androidTapTargetGuideline, labeledTapTargetGuideline]) {
                  final result = await g.evaluate(tester);
                  if (!result.passed) a11y.add(result.reason!);
                }
              }
              await scrollThrough(tester, onStep: () => problems.addAll(textProblems(tester)));
              await unmountQaApp(tester, app);
            });
            semantics?.dispose();
            expect(describeErrors(errors), isEmpty);
            expect(problems, isEmpty);
            expect(a11y, isEmpty);
            expect(opened, isTrue, reason: 'the sheet / dialog did not open');
          });
        }
      }
    }
  }
}

WidgetRef _refOf(WidgetTester tester) =>
    tester.element(find.byWidgetPredicate((w) => w is ConsumerWidget || w is ConsumerStatefulWidget).last)
        as WidgetRef;

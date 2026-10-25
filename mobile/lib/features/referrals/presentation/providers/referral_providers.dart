import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/app_settings_model.dart';
import '../../../auth/data/datasources/auth_repository.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/referrals_repository.dart';

// ─── Sharing ────────────────────────────────────────────────────────────────

/// Opens the system share sheet (tests override it).
typedef ShareTextFn = Future<void> Function(String text, {String? subject, Rect? origin});

final shareTextProvider = Provider<ShareTextFn>(
  (ref) => (text, {subject, origin}) async {
    await Share.share(text, subject: subject, sharePositionOrigin: origin);
  },
);

/// The localized invite text: code + `https://goldengift.app/r/{code}` (SRS §4.6).
String referralShareText(AppLocalizations l10n, String code, ReferralSettings settings) {
  final link = ReferralsRepository.link(code);
  return settings.joinBonus > 0
      ? l10n.referralShareText(CurrencyFormatter.format(settings.joinBonus), code, link)
      : l10n.referralShareTextNoBonus(code, link);
}

/// "you'll both get X" — or who gets what when the two bonuses differ;
/// null when there is no reward.
String? referralRewardLine(AppLocalizations l10n, ReferralSettings s) {
  final friend = s.joinBonus;
  final you = s.orderBonus;
  if (friend > 0 && you > 0) {
    return friend == you
        ? l10n.referralBothGet(CurrencyFormatter.format(you))
        : l10n.referralEachGets(CurrencyFormatter.format(friend), CurrencyFormatter.format(you));
  }
  if (you > 0) return l10n.referralYouGet(CurrencyFormatter.format(you));
  if (friend > 0) return l10n.referralFriendGets(CurrencyFormatter.format(friend));
  return null;
}

/// Shares [code] through the system sheet and logs `referral_share` (SRS §4.7).
Future<void> shareReferral(BuildContext context, WidgetRef ref, String code) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final settings = ref.read(referralSettingsProvider).valueOrNull ?? const ReferralSettings();
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.referralShare, {'method': 'share'}));
  try {
    await ref.read(shareTextProvider)(
      referralShareText(l10n, code, settings),
      subject: l10n.referralShareSubject,
      origin: origin,
    );
  } catch (_) {
    messenger?.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
  }
}

/// Copies [code], confirms with "Copied" and logs `referral_share` (method copy).
Future<void> copyReferralCode(BuildContext context, WidgetRef ref, String code) async {
  final messenger = ScaffoldMessenger.of(context);
  final copied = AppLocalizations.of(context)!.codeCopied;
  unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.referralShare, {'method': 'copy'}));
  await Clipboard.setData(ClipboardData(text: code));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(copied)));
}

// ─── Home referral sheet (SRS §5.4 item 13) ─────────────────────────────────

/// Counts app opens and remembers whether the referral sheet was shown, per
/// install. Keys deliberately don't start with `cart_` (they survive logout).
class ReferralSheetTracker {
  ReferralSheetTracker._(this._prefs, this.opens);

  static const opensKey = 'referral_sheet_opens';
  static const shownKey = 'referral_sheet_shown';

  final SharedPreferences _prefs;

  /// App opens including this one.
  final int opens;

  /// Counts this process start as one open.
  factory ReferralSheetTracker.open(SharedPreferences prefs) {
    final opens = (prefs.getInt(opensKey) ?? 0) + 1;
    unawaited(prefs.setInt(opensKey, opens));
    return ReferralSheetTracker._(prefs, opens);
  }

  bool get shown => _prefs.getBool(shownKey) ?? false;

  /// From the second open on, until it has been shown once.
  bool get eligible => opens >= 2 && !shown;

  Future<void> markShown() => _prefs.setBool(shownKey, true);
}

/// Created once per process (first read by Home), which is what counts an
/// open. Null when preferences are unavailable.
final referralSheetTrackerProvider = Provider<ReferralSheetTracker?>((ref) {
  try {
    return ReferralSheetTracker.open(ref.watch(sharedPreferencesProvider));
  } catch (_) {
    return null;
  }
});

/// True when Home should show the referral sheet now: 2nd+ open, never shown
/// on this install, signed in, and at least one bonus configured.
final referralSheetDueProvider = Provider<bool>((ref) {
  final tracker = ref.watch(referralSheetTrackerProvider);
  if (tracker == null || !tracker.eligible) return false;
  if (!ref.watch(isSignedInProvider)) return false;
  final settings = ref.watch(referralSettingsProvider).valueOrNull;
  return settings != null && (settings.joinBonus > 0 || settings.orderBonus > 0);
});

// ─── /r/{code} while signed in ──────────────────────────────────────────────

/// Set when a signed-in customer opens a referral link; Home explains that
/// codes are for new accounts and clears it.
final referralLinkNoticeProvider = StateProvider<bool>((ref) => false);

/// Where `/r/{code}` goes (SRS §4.6): Sign Up with the code pre-filled, or —
/// for a signed-in customer — Main with an explanation.
String referralLinkRedirect(Ref<Object?> ref, String code) {
  // A cold start from the link runs this before the auth stream's first
  // event: fall back to the restored session instead of treating it as a guest.
  final auth = ref.read(authStateProvider);
  final signedIn = (auth.hasValue ? auth.value : ref.read(authRepositoryProvider).currentUser) != null;
  if (signedIn) {
    // Deferred: a redirect can run while the router builds, and providers
    // must not change mid-build.
    scheduleMicrotask(() => ref.read(referralLinkNoticeProvider.notifier).state = true);
    return AppRoutes.main;
  }
  return Uri(path: AppRoutes.signUp, queryParameters: {'ref': code}).toString();
}

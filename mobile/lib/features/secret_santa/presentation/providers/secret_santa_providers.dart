import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/secret_santa_model.dart';
import '../../../products/data/product_query.dart';
import '../../data/secret_santa_repository.dart';

/// Opens the system share sheet (tests override it).
typedef SecretSantaShareFn = Future<void> Function(String text, {String? subject, Rect? origin});

final secretSantaShareProvider = Provider<SecretSantaShareFn>(
  (ref) => (text, {subject, origin}) async {
    await Share.share(text, subject: subject, sharePositionOrigin: origin);
  },
);

/// "Now" for the exchange-date rule (tests pin it).
final secretSantaClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Budget presets (IQD) of the create form.
const secretSantaBudgetPresets = <int>[10000, 25000, 50000, 100000];

/// The localized invite: group name, the `https://goldengift.app/s/{code}`
/// link and the code (SRS §5.16, §4.6).
String secretSantaShareText(AppLocalizations l10n, SecretSantaGroup group) =>
    l10n.secretSantaShareText(group.name, group.joinLink, group.inviteCode);

/// A typed or pasted invite ("abcd 2345", or the whole join link) as the
/// 8-character code, or null when it can't be one.
String? normalizeInviteCode(String input) {
  var text = input.trim();
  final link = RegExp(r'/s/([A-Za-z0-9]+)').firstMatch(text);
  if (link != null) text = link.group(1)!;
  final code = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code) ? code : null;
}

/// "Shop for them": products whose price band starts within the budget
/// (SRS §5.16, PriceBands); no budget = every product.
ProductQuery shopForThemQuery(int budget) {
  if (budget <= 0) return const ProductQuery();
  return ProductQuery(priceBands: {
    for (var band = 0; band < PriceBands.count; band++)
      if (PriceBands.rangeOf(band).$1 <= budget) band,
  });
}

String secretSantaFailureMessage(AppLocalizations l10n, SecretSantaFailureReason reason) => switch (reason) {
      SecretSantaFailureReason.notFound => l10n.secretSantaErrorNotFound,
      SecretSantaFailureReason.alreadyDrawn => l10n.secretSantaErrorAlreadyDrawn,
      SecretSantaFailureReason.tooFewMembers => l10n.secretSantaDrawHint(SecretSantaGroup.minMembers),
      SecretSantaFailureReason.full => l10n.secretSantaErrorFull,
      SecretSantaFailureReason.impossible => l10n.secretSantaErrorImpossible,
      SecretSantaFailureReason.notOrganiser => l10n.secretSantaErrorNotOrganiser,
      SecretSantaFailureReason.unavailable => l10n.secretSantaErrorUnavailable,
      SecretSantaFailureReason.rateLimited => l10n.authErrorTooManyRequests,
      SecretSantaFailureReason.unknown => l10n.somethingWentWrong,
    };

String secretSantaTypeLabel(AppLocalizations l10n, SecretSantaType type) => switch (type) {
      SecretSantaType.family => l10n.secretSantaTypeFamily,
      SecretSantaType.friends => l10n.secretSantaTypeFriends,
      SecretSantaType.work => l10n.secretSantaTypeWork,
    };

IconData secretSantaTypeIcon(SecretSantaType type) => switch (type) {
      SecretSantaType.family => Icons.family_restroom_rounded,
      SecretSantaType.friends => Icons.groups_rounded,
      SecretSantaType.work => Icons.work_outline_rounded,
    };

String secretSantaStatusLabel(AppLocalizations l10n, SecretSantaStatus status) => switch (status) {
      SecretSantaStatus.open => l10n.secretSantaStatusOpen,
      SecretSantaStatus.drawn => l10n.secretSantaStatusDrawn,
      SecretSantaStatus.closed => l10n.secretSantaStatusClosed,
    };

/// "25,000 IQD per gift" or "No budget".
String secretSantaBudgetLabel(AppLocalizations l10n, int budget) =>
    budget > 0 ? l10n.secretSantaBudgetValue(CurrencyFormatter.format(budget)) : l10n.secretSantaNoBudget;

/// "Exchange on 24/12/2026", or null without a date.
String? secretSantaDateLabel(AppLocalizations l10n, DateTime? date) =>
    date == null ? null : l10n.secretSantaExchangeOn(AppDates.display(date));

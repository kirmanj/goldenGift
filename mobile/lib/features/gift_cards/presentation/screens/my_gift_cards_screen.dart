import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/localized_text_ext.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/gift_card_model.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../checkout/presentation/providers/checkout_providers.dart' show checkoutClockProvider;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../orders/presentation/widgets/order_status_chip.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/gift_cards_repository.dart';
import '../widgets/gift_card_face.dart';
import '../widgets/gift_card_labels.dart';

/// My Gift Cards (SRS §5.22): a "Have a code?" box, then Received / Sent
/// tabs. Received cards show code (copy), balance, expiry and status, and
/// **Redeem** moves the balance into wallet credits (`redeemGiftCard`).
class MyGiftCardsScreen extends ConsumerStatefulWidget {
  const MyGiftCardsScreen({super.key});

  @override
  ConsumerState<MyGiftCardsScreen> createState() => _MyGiftCardsScreenState();
}

class _MyGiftCardsScreenState extends ConsumerState<MyGiftCardsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _code = TextEditingController();
  String? _codeError;

  /// Code currently being redeemed ('' = from the code box).
  String? _redeeming;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onTab() {
    if (!_tabs.indexIsChanging) setState(() {});
  }

  Future<void> _redeemTyped() async {
    final l10n = AppLocalizations.of(context)!;
    final code = GiftCardsRepository.normalizeCode(_code.text);
    if (code.isEmpty) {
      setState(() => _codeError = l10n.errorRequired);
      return;
    }
    if (code.length != 12) {
      setState(() => _codeError = l10n.giftCardCodeInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    final error = await _redeem(code, fromField: true);
    if (!mounted) return;
    setState(() => _codeError = error);
    if (error == null) _code.clear();
  }

  /// Returns the failure message (null on success).
  Future<String?> _redeem(String code, {required bool fromField}) async {
    if (_redeeming != null) return null;
    final l10n = AppLocalizations.of(context)!;
    if (!await requireSignIn(context, ref)) return null;
    if (!mounted) return null;
    setState(() => _redeeming = fromField ? '' : code);
    try {
      final result = await ref.read(giftCardsRepositoryProvider).redeem(code);
      if (mounted) unawaited(_showRedeemed(result));
      return null;
    } on RedeemFailure catch (f) {
      final message = redeemFailureMessage(l10n, f.reason);
      if (mounted && !fromField) showOrderSnack(context, message);
      return message;
    } catch (_) {
      if (mounted && !fromField) showOrderSnack(context, l10n.somethingWentWrong);
      return l10n.somethingWentWrong;
    } finally {
      if (mounted) setState(() => _redeeming = null);
    }
  }

  Future<void> _showRedeemed(RedeemResult result) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.card(context),
        showDragHandle: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        builder: (_) => _RedeemedSheet(amount: result.amount),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authStateProvider);
    final signedIn = ref.watch(isSignedInProvider);

    Widget body;
    if (auth.isLoading) {
      body = const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: SkeletonLoader.list(count: 3),
      );
    } else if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.card_giftcard_rounded);
    } else {
      body = _list(context, l10n);
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.myGiftCards,
        actions: [
          GGCircleButton(
            key: const ValueKey('open-gift-shop'),
            icon: Icons.storefront_outlined,
            iconColor: AppColors.gold(context),
            tooltip: l10n.giftCardShopTitle,
            onPressed: () => context.push(AppRoutes.giftCardsShop),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _list(BuildContext context, AppLocalizations l10n) {
    final received = _tabs.index == 0;
    final async = ref.watch(received ? receivedGiftCardsProvider : purchasedGiftCardsProvider);
    final now = ref.watch(checkoutClockProvider)();
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);

    final List<Widget> items;
    if (async.hasError && !async.hasValue) {
      items = [
        ErrorState(
          onRetry: () => ref.invalidate(received ? receivedGiftCardsProvider : purchasedGiftCardsProvider),
        ),
      ];
    } else if (!async.hasValue) {
      items = const [SkeletonLoader.list(count: 3)];
    } else if (async.requireValue.isEmpty) {
      items = [
        EmptyState(
          key: ValueKey(received ? 'received-empty' : 'sent-empty'),
          title: received ? l10n.giftCardsReceivedEmptyTitle : l10n.giftCardsSentEmptyTitle,
          subtitle: received ? l10n.giftCardsReceivedEmptyBody : l10n.giftCardsSentEmptyBody,
          icon: Icons.card_giftcard_rounded,
          ctaLabel: received ? null : l10n.giftCardDesignCta,
          onCta: received ? null : () => context.push(AppRoutes.giftCardsShop),
        ),
      ];
    } else {
      items = [
        for (final card in async.requireValue)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: GiftCardTile(
              key: ValueKey('gift-card-${card.id}'),
              card: card,
              received: received,
              now: now,
              redeeming: _redeeming == card.code,
              onRedeem: _redeeming != null ? null : () => _redeem(card.code, fromField: false),
            ),
          ),
      ];
    }

    return ListView(
      key: const ValueKey('my-gift-cards-list'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        OrderSection(
          title: l10n.giftCardHaveCode,
          icon: Icons.redeem_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GGInput(
                key: const ValueKey('redeem-code'),
                hint: 'XXXX-XXXX-XXXX',
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                errorText: _codeError,
                onChanged: (_) {
                  if (_codeError != null) setState(() => _codeError = null);
                },
                onSubmitted: (_) => _redeemTyped(),
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              PrimaryButton(
                key: const ValueKey('redeem-code-button'),
                label: l10n.giftCardRedeem,
                icon: Icons.redeem_rounded,
                height: 48,
                isLoading: _redeeming == '',
                onPressed: _redeeming != null ? null : _redeemTyped,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card(context),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.line(context)),
          ),
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: TabBar(
            key: const ValueKey('gift-card-tabs'),
            controller: _tabs,
            dividerHeight: 0,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: AppColors.gold(context), borderRadius: BorderRadius.circular(AppRadius.pill)),
            labelColor: AppColors.textOnPrimary,
            unselectedLabelColor: AppColors.textMuted(context),
            labelStyle: AppTextStyles.label.copyWith(
              fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
            ),
            tabs: [
              Tab(key: const ValueKey('tab-received'), text: l10n.giftCardsReceived),
              Tab(key: const ValueKey('tab-sent'), text: l10n.giftCardsSent),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...items,
      ],
    );
  }
}

/// One gift card: the gradient face (name + amount) over a details panel
/// with status, code + copy, balance, expiry and Redeem (received) or the
/// recipient and send date (sent).
class GiftCardTile extends StatelessWidget {
  const GiftCardTile({
    super.key,
    required this.card,
    required this.received,
    required this.now,
    this.redeeming = false,
    this.onRedeem,
  });

  final GiftCardModel card;
  final bool received;
  final DateTime now;
  final bool redeeming;
  final VoidCallback? onRedeem;

  void _copy(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(Clipboard.setData(ClipboardData(text: card.formattedCode)));
    showOrderSnack(context, l10n.codeCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = card.templateName.of(context);
    final muted = AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context));
    final (fg, bg) = orderStatusColors(context, giftCardStatusTone(card.status));
    final redeemable = received && card.isRedeemable(now);
    final sendDate = card.sentAt ?? card.scheduledAt;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: GiftCardFace.compactHeight(context),
            child: GiftCardFace(
              compact: true,
              gradient: giftCardGradientFor(card.gradientStart, card.gradientEnd),
              title: name.isEmpty ? l10n.giftCards : name,
              amount: CurrencyFormatter.format(card.amount),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      key: ValueKey('gift-card-status-${card.status.name}'),
                      label: giftCardStatusLabel(l10n, card, received: received),
                      fg: fg,
                      bg: bg,
                    ),
                    if (received)
                      Text(
                        l10n.giftCardBalance(CurrencyFormatter.format(card.balance)),
                        style: AppTextStyles.label.copyWith(color: AppColors.goldText(context)),
                      ),
                  ],
                ),
                if (received && card.code.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.formattedCode,
                          key: ValueKey('gift-card-code-${card.id}'),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: AppTextStyles.heading3.copyWith(letterSpacing: 1.6, color: AppColors.text(context)),
                        ),
                      ),
                      GGCircleButton(
                        key: ValueKey('copy-code-${card.id}'),
                        icon: Icons.copy_rounded,
                        size: 40,
                        iconSize: 18,
                        iconColor: AppColors.gold(context),
                        tooltip: l10n.promoCopyCode,
                        onPressed: () => _copy(context),
                      ),
                    ],
                  ),
                ],
                if (!received && card.recipientName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(l10n.giftCardTo(card.recipientName),
                      style: AppTextStyles.label.copyWith(color: AppColors.text(context))),
                ],
                if (!received && sendDate != null)
                  Text(
                    card.sentAt != null
                        ? l10n.giftCardSentOn(AppDates.display(sendDate))
                        : l10n.giftCardScheduledFor(AppDates.display(sendDate)),
                    style: muted,
                  ),
                if (received && card.message.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    card.message.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: muted.copyWith(fontStyle: FontStyle.italic),
                  ),
                ],
                if (card.expiresAt != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(l10n.expiresOn(AppDates.display(card.expiresAt!)), style: muted),
                ],
                if (redeemable) ...[
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                  PrimaryButton(
                    key: ValueKey('redeem-${card.id}'),
                    label: l10n.giftCardRedeemToCredits,
                    icon: Icons.redeem_rounded,
                    height: 48,
                    isLoading: redeeming,
                    onPressed: onRedeem,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RedeemedSheet extends StatelessWidget {
  const _RedeemedSheet({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey('redeemed-sheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
              child: Icon(Icons.celebration_rounded, color: AppColors.gold(context), size: 36),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              header: true,
              child: Text(
                l10n.giftCardRedeemedTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.giftCardRedeemedBody(CurrencyFormatter.format(amount)),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              key: const ValueKey('redeemed-view-wallet'),
              label: l10n.giftCardViewWallet,
              icon: Icons.account_balance_wallet_outlined,
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.wallet);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlineButton(label: l10n.done, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_dates.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/special_request_model.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/special_requests_repository.dart';
import '../widgets/special_request_widgets.dart';

/// One special request (SRS §5.17): what I asked for (text + photos, full
/// screen on tap), where it stands, Golden Gift's quote with **Accept quote**
/// and the message thread — Golden Gift on the start side in soft gold, me on
/// the end side — with a reply box while the request is open.
class SpecialRequestDetailsScreen extends ConsumerStatefulWidget {
  const SpecialRequestDetailsScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<SpecialRequestDetailsScreen> createState() => _SpecialRequestDetailsScreenState();
}

class _SpecialRequestDetailsScreenState extends ConsumerState<SpecialRequestDetailsScreen> {
  final _reply = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context)!;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    setState(() => _sending = true);
    try {
      await ref.read(specialRequestsRepositoryProvider).sendMessage(uid: uid, requestId: widget.requestId, text: text);
      _reply.clear();
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authStateProvider);
    final signedIn = ref.watch(isSignedInProvider);

    Widget body;
    if (auth.isLoading) {
      body = const _Skeleton();
    } else if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.lightbulb_outline_rounded);
    } else {
      final async = ref.watch(specialRequestProvider(widget.requestId));
      if (async.hasError && !async.hasValue) {
        body = CenteredScroll(
          child: ErrorState(onRetry: () => ref.invalidate(specialRequestProvider(widget.requestId))),
        );
      } else if (!async.hasValue) {
        body = const _Skeleton();
      } else if (async.requireValue == null) {
        body = CenteredScroll(
          child: EmptyState(
            key: const ValueKey('sr-not-found'),
            title: l10n.srNotFound,
            icon: Icons.lightbulb_outline_rounded,
          ),
        );
      } else {
        body = _content(context, l10n, async.requireValue!);
      }
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.srDetailsTitle),
      body: body,
    );
  }

  Widget _content(BuildContext context, AppLocalizations l10n, SpecialRequestModel r) {
    final messages = ref.watch(specialRequestMessagesProvider(r.id));
    final muted = AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context));
    final closed = isClosedRequest(r);
    final showQuote = (r.quoteAmount ?? 0) > 0 &&
        (r.status == SpecialRequestStatus.quoted ||
            r.status == SpecialRequestStatus.accepted ||
            r.status == SpecialRequestStatus.completed);
    final bottom = math.max(AppSpacing.lg, closed ? MediaQuery.paddingOf(context).bottom + AppSpacing.md : 0.0);

    final list = ListView(
      key: const ValueKey('sr-details-list'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        OrderSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SpecialRequestStatusChip(status: r.status),
                  if (r.type == SpecialRequestType.support) const SupportTypeChip(),
                  if (r.createdAt != null) Text(AppDates.display(r.createdAt!), style: muted),
                ],
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Text(
                r.text,
                key: const ValueKey('sr-text-full'),
                style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context)),
              ),
              if (r.images.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                RequestImageStrip(urls: r.images),
              ],
            ],
          ),
        ),
        if (r.type == SpecialRequestType.gift) ...[
          const SizedBox(height: AppSpacing.md),
          RequestStatusSteps(status: r.status),
        ] else if (r.status == SpecialRequestStatus.rejected) ...[
          const SizedBox(height: AppSpacing.md),
          RequestStatusSteps(status: r.status),
        ],
        if (showQuote) ...[
          const SizedBox(height: AppSpacing.md),
          _QuoteCard(request: r),
        ],
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(l10n.srMessages,
              style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...messages.when(
          loading: () => const [SkeletonLoader.list(count: 2)],
          error: (_, __) => [ErrorState(onRetry: () => ref.invalidate(specialRequestMessagesProvider(r.id)))],
          data: (list) => list.isEmpty
              ? [Text(l10n.srNoMessages, key: const ValueKey('sr-no-messages'), style: muted)]
              : [for (final m in list) _Bubble(key: ValueKey('msg-${m.id}'), message: m)],
        ),
        if (closed) ...[
          const SizedBox(height: AppSpacing.md),
          InfoBanner(key: const ValueKey('sr-closed'), message: l10n.srClosedNote, icon: Icons.lock_outline_rounded),
        ],
      ],
    );

    if (closed) return list;
    return Column(
      children: [
        Expanded(child: list),
        _ReplyBar(controller: _reply, sending: _sending, onSend: _send),
      ],
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.request});
  final SpecialRequestModel request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final r = request;
    final note = (r.quoteNote ?? '').trim();
    return Container(
      key: const ValueKey('sr-quote'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.soft(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.gold(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.request_quote_outlined, color: AppColors.gold(context)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.srQuoteTitle,
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            CurrencyFormatter.format(r.quoteAmount ?? 0),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.start,
            style: AppTextStyles.heading2.copyWith(color: AppColors.goldText(context)),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.srQuoteDeliveryNote,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context)),
          ),
          if (r.canAcceptQuote) ...[
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              key: const ValueKey('accept-quote'),
              label: l10n.srAcceptQuote,
              icon: Icons.check_circle_outline_rounded,
              onPressed: () => context.push(AppRoutes.specialRequestAcceptFor(r.id)),
            ),
          ] else if (r.orderId != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlineButton(
              key: const ValueKey('sr-view-order'),
              label: l10n.srViewOrder,
              icon: Icons.receipt_long_outlined,
              onPressed: () => context.push(AppRoutes.order(r.orderId!)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.message});
  final SpecialRequestMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final admin = message.isFromAdmin;
    const r = Radius.circular(AppRadius.lg);
    const tail = Radius.circular(AppRadius.xs);
    final at = message.at;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: admin ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
        child: FractionallySizedBox(
          widthFactor: 0.82,
          alignment: admin ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
          child: Align(
            alignment: admin ? AlignmentDirectional.centerStart : AlignmentDirectional.centerEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xxs),
              decoration: BoxDecoration(
                color: admin ? AppColors.soft(context) : AppColors.card(context),
                border: Border.all(color: admin ? AppColors.gold(context).withValues(alpha: 0.5) : AppColors.line(context)),
                borderRadius: BorderRadiusDirectional.only(
                  topStart: admin ? tail : r,
                  topEnd: admin ? r : tail,
                  bottomStart: r,
                  bottomEnd: r,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    admin ? l10n.appTitle : l10n.srYou,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: admin ? AppColors.goldText(context) : AppColors.textMuted(context),
                    ),
                  ),
                  if (message.text.isNotEmpty)
                    Text(message.text, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.text(context))),
                  if (message.images.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    RequestImageStrip(urls: message.images, size: 64),
                  ],
                  if (at != null)
                    Text(
                      AppDates.displayWithTime(at),
                      textDirection: TextDirection.ltr,
                      style: AppTextStyles.bodySmall.copyWith(fontSize: 11, color: AppColors.textMuted(context)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card(context),
        border: Border(top: BorderSide(color: AppColors.line(context))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: GGInput(
                  key: const ValueKey('sr-reply'),
                  hint: l10n.srReplyHint,
                  controller: controller,
                  multiline: true,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: SpecialRequestModel.maxText,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final canSend = controller.text.trim().isNotEmpty && !sending;
                  return GGCircleButton(
                    key: const ValueKey('sr-send'),
                    icon: Icons.send_rounded,
                    iconColor: canSend ? AppColors.gold(context) : AppColors.textMuted(context),
                    tooltip: l10n.srSend,
                    onPressed: canSend ? onSend : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
        physics: NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
        child: Column(
          children: [
            SkeletonLoader.box(height: 140, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonLoader.list(count: 3),
          ],
        ),
      );
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/secret_santa_model.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/secret_santa_repository.dart';
import '../providers/secret_santa_providers.dart';
import '../widgets/secret_santa_widgets.dart';

/// One Secret Santa group (SRS §5.16, `/secret-santa/:id`): header, invite
/// card (while open), the organiser's Draw button, after the draw "You're
/// buying for …" with their wish note and Shop for them, my wish note and the
/// members. Only the signed-in member's own assignment is ever read.
class SecretSantaGroupScreen extends ConsumerWidget {
  const SecretSantaGroupScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final appBar = GGAppBar(
      title: l10n.secretSanta,
      showBack: true,
      onBack: () => popOrGo(context, AppRoutes.secretSanta),
    );
    Widget body;
    if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.redeem_rounded);
    } else {
      final uid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';
      body = ref.watch(secretSantaGroupProvider(groupId)).when(
            loading: () => const SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.sm),
              child: SkeletonLoader.list(count: 4),
            ),
            error: (_, __) => CenteredScroll(
              child: ErrorState(onRetry: () => ref.invalidate(secretSantaGroupProvider(groupId))),
            ),
            data: (group) => group == null || !group.memberUids.contains(uid)
                ? CenteredScroll(
                    child: EmptyState(
                      key: const ValueKey('santa-not-member'),
                      title: l10n.secretSantaNotMember,
                      icon: Icons.lock_outline_rounded,
                      ctaLabel: l10n.secretSanta,
                      onCta: () => context.go(AppRoutes.secretSanta),
                    ),
                  )
                : _GroupDetails(group: group, uid: uid),
          );
    }
    return Scaffold(backgroundColor: AppColors.bg(context), appBar: appBar, body: body);
  }
}

class _GroupDetails extends ConsumerWidget {
  const _GroupDetails({required this.group, required this.uid});

  final SecretSantaGroup group;
  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    const gap = SizedBox(height: AppSpacing.md);
    final open = group.status == SecretSantaStatus.open;
    final members = ref.watch(secretSantaMembersProvider(group.id));
    final me = members.valueOrNull?.where((m) => m.uid == uid).firstOrNull;
    return ListView(
      key: const ValueKey('santa-group-details'),
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        _GroupHeader(group: group, uid: uid),
        gap,
        if (group.status == SecretSantaStatus.drawn) ...[
          _AssignmentCard(group: group),
          gap,
        ],
        if (open) ...[
          _InviteCard(group: group),
          gap,
          _DrawSection(group: group, uid: uid),
          gap,
        ],
        _WishNoteCard(groupId: group.id, uid: uid, note: me?.wishlistNote, loaded: members.hasValue),
        gap,
        _MembersCard(group: group, uid: uid, members: members),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.uid});

  final SecretSantaGroup group;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final date = secretSantaDateLabel(l10n, group.exchangeDate);
    return OrderSection(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SecretSantaTypeAvatar(type: group.type, size: 56),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    group.name,
                    key: const ValueKey('santa-group-name-title'),
                    style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${secretSantaTypeLabel(l10n, group.type)} · ${secretSantaBudgetLabel(l10n, group.budget)}',
                  style: AppTextStyles.bodyMedium.copyWith(color: muted),
                ),
                if (date != null) Text(date, style: AppTextStyles.bodyMedium.copyWith(color: muted)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    SecretSantaStatusChip(status: group.status),
                    if (group.isOrganiser(uid))
                      SecretSantaPill.organiser(
                        context,
                        l10n.secretSantaOrganiserBadge,
                        key: const ValueKey('santa-organiser-badge'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Invite code in large letter-spaced gold, Copy and Share link.
class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.group});

  final SecretSantaGroup group;

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = AppLocalizations.of(context)!.codeCopied;
    await Clipboard.setData(ClipboardData(text: group.inviteCode));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    unawaited(ref.read(analyticsServiceProvider).log(AnalyticsEvents.share, {
      'content_type': 'secret_santa',
      'item_id': group.id,
      'method': 'system_share',
    }));
    try {
      await ref.read(secretSantaShareProvider)(
        secretSantaShareText(l10n, group),
        subject: l10n.secretSantaShareSubject,
        origin: origin,
      );
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return OrderSection(
      title: l10n.secretSantaInviteTitle,
      icon: Icons.mail_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.secretSantaInviteBody,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.soft(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.gold(context).withValues(alpha: 0.6)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                group.inviteCode,
                key: const ValueKey('santa-invite-code'),
                textDirection: TextDirection.ltr,
                style: AppTextStyles.heading1.copyWith(
                  letterSpacing: 6,
                  fontWeight: FontWeight.w800,
                  color: AppColors.goldText(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlineButton(
                  key: const ValueKey('santa-copy-code'),
                  label: l10n.secretSantaCopyCode,
                  icon: Icons.copy_rounded,
                  height: 48,
                  onPressed: () => unawaited(_copy(context)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Builder(
                  builder: (buttonContext) => PrimaryButton(
                    key: const ValueKey('santa-share-link'),
                    label: l10n.secretSantaShareLink,
                    icon: Icons.ios_share_rounded,
                    height: 48,
                    onPressed: () => unawaited(_share(buttonContext, ref)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Organiser: Draw (enabled from 3 members, confirm first). Others: waiting.
class _DrawSection extends ConsumerStatefulWidget {
  const _DrawSection({required this.group, required this.uid});

  final SecretSantaGroup group;
  final String uid;

  @override
  ConsumerState<_DrawSection> createState() => _DrawSectionState();
}

class _DrawSectionState extends ConsumerState<_DrawSection> {
  bool _drawing = false;

  Future<void> _draw() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card(dialogContext),
        title: Text(
          l10n.secretSantaDrawConfirmTitle,
          style: AppTextStyles.heading3.copyWith(color: AppColors.text(dialogContext)),
        ),
        content: Text(
          l10n.secretSantaDrawConfirmBody,
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(dialogContext)),
        ),
        actions: [
          TextButton(
            key: const ValueKey('santa-draw-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel, style: TextStyle(color: AppColors.textMuted(dialogContext))),
          ),
          TextButton(
            key: const ValueKey('santa-draw-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              l10n.secretSantaDraw,
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldText(dialogContext)),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _drawing = true);
    try {
      await ref.read(secretSantaRepositoryProvider).draw(widget.group.id);
      if (mounted) showOrderSnack(context, l10n.secretSantaDrawDone);
    } on SecretSantaFailure catch (f) {
      if (mounted) showOrderSnack(context, secretSantaFailureMessage(l10n, f.reason));
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _drawing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = widget.group;
    final muted = AppColors.textMuted(context);
    if (!group.isOrganiser(widget.uid)) {
      return InfoBanner(
        key: const ValueKey('santa-waiting'),
        message: l10n.secretSantaWaitingForDraw,
        icon: Icons.hourglass_top_rounded,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          key: const ValueKey('santa-draw'),
          label: l10n.secretSantaDraw,
          icon: Icons.shuffle_rounded,
          isLoading: _drawing,
          onPressed: group.canDraw ? _draw : null,
        ),
        if (!group.canDraw) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.secretSantaDrawHint(SecretSantaGroup.minMembers),
            key: const ValueKey('santa-draw-hint'),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall.copyWith(color: muted),
          ),
        ],
      ],
    );
  }
}

/// After the draw: "You're buying for {name}", their wish note and Shop for
/// them (products within the budget).
class _AssignmentCard extends ConsumerWidget {
  const _AssignmentCard({required this.group});

  final SecretSantaGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final assignment = ref.watch(mySecretSantaAssignmentProvider(group.id)).valueOrNull;
    if (assignment == null) {
      return InfoBanner(
        key: const ValueKey('santa-draw-pending'),
        message: l10n.secretSantaDrawPending,
        icon: Icons.redeem_rounded,
      );
    }
    final note = assignment.assigneeWishlistNote?.trim() ?? '';
    const onGold = AppColors.textOnPrimary;
    return Container(
      key: const ValueKey('santa-assignment'),
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.redeem_rounded, color: onGold),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.secretSantaBuyingFor(assignment.assigneeName),
                    style: AppTextStyles.heading3.copyWith(color: onGold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.secretSantaOnlyYou,
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600, color: onGold),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.card(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.secretSantaTheirWish,
                  style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  note.isEmpty ? l10n.secretSantaNoWishNote : note,
                  key: const ValueKey('santa-assignee-note'),
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: note.isEmpty ? AppColors.textMuted(context) : AppColors.text(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Material(
            color: AppColors.card(context),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('santa-shop-for-them'),
              onTap: () => unawaited(context.push(AppRoutes.productsFor(shopForThemQuery(group.budget)))),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_bag_outlined, color: AppColors.goldText(context)),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          l10n.secretSantaShopForThem,
                          style: AppTextStyles.button.copyWith(color: AppColors.goldText(context)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// My own wish note (shown to whoever draws me), editable.
class _WishNoteCard extends ConsumerWidget {
  const _WishNoteCard({required this.groupId, required this.uid, required this.note, required this.loaded});

  final String groupId;
  final String uid;
  final String? note;
  final bool loaded;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _WishNoteDialog(initial: note ?? ''),
    );
    if (text == null || !context.mounted) return;
    try {
      await ref.read(secretSantaRepositoryProvider).setWishlistNote(groupId, uid, text);
      if (context.mounted) showOrderSnack(context, l10n.secretSantaWishNoteSaved);
    } catch (_) {
      if (context.mounted) showOrderSnack(context, l10n.somethingWentWrong);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = note?.trim() ?? '';
    return OrderSection(
      title: l10n.secretSantaMyWishNote,
      icon: Icons.favorite_border_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            current.isEmpty ? l10n.secretSantaWishNoteEmpty : current,
            key: const ValueKey('santa-my-note'),
            style: AppTextStyles.bodyMedium.copyWith(
              color: current.isEmpty ? AppColors.textMuted(context) : AppColors.text(context),
            ),
          ),
          if (loaded)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('santa-edit-note'),
                onPressed: () => unawaited(_edit(context, ref)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldText(context),
                  minimumSize: const Size.square(AppSpacing.minTapTarget),
                ),
                icon: Icon(current.isEmpty ? Icons.add_rounded : Icons.edit_outlined, size: 18),
                label: Text(
                  current.isEmpty ? l10n.secretSantaAddNote : l10n.edit,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WishNoteDialog extends StatefulWidget {
  const _WishNoteDialog({required this.initial});
  final String initial;

  @override
  State<_WishNoteDialog> createState() => _WishNoteDialogState();
}

class _WishNoteDialogState extends State<_WishNoteDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AppColors.card(context),
      title: Text(l10n.secretSantaMyWishNote, style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
      content: SingleChildScrollView(
        child: GGInput(
          key: const ValueKey('santa-note-input'),
          hint: l10n.secretSantaWishNoteHint,
          controller: _text,
          multiline: true,
          minLines: 3,
          maxLines: 6,
          maxLength: SecretSantaMember.maxWishlistNote,
          showCounter: true,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel, style: TextStyle(color: AppColors.textMuted(context))),
        ),
        TextButton(
          key: const ValueKey('santa-note-save'),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
          child: Text(l10n.save, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldText(context))),
        ),
      ],
    );
  }
}

/// Names only (and who organises) — never anyone's assignment or wish note.
class _MembersCard extends StatelessWidget {
  const _MembersCard({required this.group, required this.uid, required this.members});

  final SecretSantaGroup group;
  final String uid;
  final AsyncValue<List<SecretSantaMember>> members;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final list = members.valueOrNull;
    final count = list?.length ?? group.memberUids.length;
    return OrderSection(
      title: l10n.secretSantaMembersOf(count, SecretSantaGroup.maxMembers),
      icon: Icons.people_outline_rounded,
      child: list == null
          ? const SkeletonLoader.list(count: 2)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) Divider(height: AppSpacing.md, color: AppColors.line(context)),
                  _MemberRow(
                    member: list[i],
                    isMe: list[i].uid == uid,
                    isOrganiser: group.isOrganiser(list[i].uid),
                  ),
                ],
              ],
            ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isMe, required this.isOrganiser});

  final SecretSantaMember member;
  final bool isMe;
  final bool isOrganiser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = member.name.trim().isEmpty ? '—' : member.name.trim();
    return Row(
      key: ValueKey('santa-member-${member.uid}'),
      children: [
        ExcludeSemantics(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
            child: Text(
              name.characters.first.toUpperCase(),
              style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.goldText(context)),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
        Expanded(
          child: Text(
            isMe ? '$name (${l10n.secretSantaYou})' : name,
            style: AppTextStyles.label.copyWith(color: AppColors.text(context)),
          ),
        ),
        if (isOrganiser) ...[
          const SizedBox(width: AppSpacing.sm),
          SecretSantaPill.organiser(context, l10n.secretSantaOrganiser),
        ],
      ],
    );
  }
}

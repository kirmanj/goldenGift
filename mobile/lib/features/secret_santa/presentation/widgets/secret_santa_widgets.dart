import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/secret_santa_model.dart';
import '../providers/secret_santa_providers.dart';

/// Open (soft gold) · Drawn (success) · Closed (muted).
class SecretSantaStatusChip extends StatelessWidget {
  const SecretSantaStatusChip({super.key, required this.status});

  final SecretSantaStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (bg, fg) = switch (status) {
      SecretSantaStatus.open => (AppColors.soft(context), AppColors.goldText(context)),
      SecretSantaStatus.drawn => (
          InfoBanner.softColor(context, InfoBannerType.success),
          AppColors.isDark(context)
              ? Color.alphaBlend(AppColors.white.withValues(alpha: 0.35), AppColors.success)
              : Color.alphaBlend(AppColors.black.withValues(alpha: 0.3), AppColors.success),
        ),
      SecretSantaStatus.closed => (AppColors.field(context), AppColors.textMuted(context)),
    };
    return SecretSantaPill(
      key: ValueKey('santa-status-${status.name}'),
      label: secretSantaStatusLabel(l10n, status),
      background: bg,
      foreground: fg,
    );
  }
}

/// Small rounded label (status, "You're the organiser").
class SecretSantaPill extends StatelessWidget {
  const SecretSantaPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  /// The gold "You're the organiser" / "Organiser" badge.
  factory SecretSantaPill.organiser(BuildContext context, String label, {Key? key}) => SecretSantaPill(
        key: key,
        label: label,
        icon: Icons.star_rounded,
        background: AppColors.soft(context),
        foreground: AppColors.goldText(context),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + AppSpacing.xxs, vertical: AppSpacing.xxs + 1),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w700, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// Group type icon in a soft-gold circle.
class SecretSantaTypeAvatar extends StatelessWidget {
  const SecretSantaTypeAvatar({super.key, required this.type, this.size = 48});

  final SecretSantaType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: secretSantaTypeLabel(AppLocalizations.of(context)!, type),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
        child: Icon(secretSantaTypeIcon(type), size: size * 0.5, color: AppColors.gold(context)),
      ),
    );
  }
}

/// My groups ▸ one group: type icon, name, budget, exchange date, members,
/// status and the organiser badge.
class SecretSantaGroupCard extends StatelessWidget {
  const SecretSantaGroupCard({super.key, required this.group, required this.uid, required this.onTap});

  final SecretSantaGroup group;
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AppColors.textMuted(context);
    final date = secretSantaDateLabel(l10n, group.exchangeDate);
    return Material(
      color: AppColors.card(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: AppColors.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('santa-group-${group.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SecretSantaTypeAvatar(type: group.type),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.text(context)),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      [
                        secretSantaTypeLabel(l10n, group.type),
                        secretSantaBudgetLabel(l10n, group.budget),
                        l10n.secretSantaMembersCount(group.memberUids.length),
                      ].join(' · '),
                      style: AppTextStyles.bodySmall.copyWith(color: muted),
                    ),
                    if (date != null)
                      Text(date, style: AppTextStyles.bodySmall.copyWith(color: muted)),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        SecretSantaStatusChip(status: group.status),
                        if (group.isOrganiser(uid)) SecretSantaPill.organiser(context, l10n.secretSantaOrganiserBadge),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // chevron_right mirrors automatically in RTL.
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

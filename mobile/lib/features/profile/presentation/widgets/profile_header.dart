import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/user_model.dart';
import 'profile_formatters.dart';

/// Round avatar: the photo when there is one, otherwise the first letter of
/// the name on gold with dark text (SRS §5.13).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.photoUrl, this.size = 64});

  final String name;
  final String? photoUrl;
  final double size;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: hasPhoto
              ? GGNetworkImage(
                  url: photoUrl,
                  fallbackIcon: Icons.person_rounded,
                  fallbackColor: AppColors.soft(context),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.gold(context)),
                  child: Center(
                    child: _initial.isEmpty
                        ? Icon(Icons.person_rounded, size: size * 0.5, color: AppColors.textOnPrimary)
                        : Text(
                            _initial,
                            textScaler: TextScaler.noScaling,
                            style: AppTextStyles.heading1.copyWith(
                              fontSize: size * 0.42,
                              height: 1,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Signed-in header (IMG_4490): avatar, name, phone and the Edit pill. A
/// Google / Apple account without a phone shows "Add mobile number" instead.
/// On narrow screens or large text the Edit pill moves under the name.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.onEdit,
    required this.onAddPhone,
  });

  final UserModel profile;
  final VoidCallback onEdit;
  final VoidCallback onAddPhone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final font = AppTextStyles.fontFamily(Localizations.localeOf(context));
    final edit = OutlineButton(label: l10n.edit, expand: false, height: AppSpacing.minTapTarget, onPressed: onEdit);
    final details = <Widget>[
      Semantics(
        header: true,
        child: Text(
          profile.name.trim().isEmpty ? l10n.guest : profile.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.sectionTitle.copyWith(color: AppColors.text(context)),
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      if (profile.hasPhone)
        Text(
          formatPhoneForDisplay(profile.countryCode, profile.phone),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
        )
      else
        TextButton.icon(
          onPressed: onAddPhone,
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: Text(l10n.addPhoneNumber),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.goldText(context),
            minimumSize: const Size.square(AppSpacing.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            alignment: AlignmentDirectional.centerStart,
            textStyle: AppTextStyles.link.copyWith(fontFamily: font),
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 300 * textScale;
        final avatar = ProfileAvatar(
          name: profile.name,
          photoUrl: profile.photoUrl,
          size: compact ? 56 : 64,
        );
        return Row(
          crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            avatar,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...details,
                  if (compact) ...[const SizedBox(height: AppSpacing.sm), edit],
                ],
              ),
            ),
            if (!compact) ...[const SizedBox(width: AppSpacing.sm), edit],
          ],
        );
      },
    );
  }
}

/// Placeholder header while the profile stream loads.
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context)!.loading,
      child: const Row(
        children: [
          SkeletonLoader.box(width: 64, height: 64, radius: AppRadius.pill),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader.line(width: 150, height: 20),
                SizedBox(height: AppSpacing.sm),
                SkeletonLoader.line(width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card shown in place of the header: guest "Sign In / Sign Up" (SRS
/// §5.13), load error with Retry, or "complete your account".
class ProfileMessageCard extends StatelessWidget {
  const ProfileMessageCard({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.primaryIcon,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData? primaryIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line(context)),
        boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.gold(context), size: 26),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        body!,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md + AppSpacing.xs),
          PrimaryButton(label: primaryLabel, icon: primaryIcon, height: 52, onPressed: onPrimary),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlineButton(label: secondaryLabel!, height: 52, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

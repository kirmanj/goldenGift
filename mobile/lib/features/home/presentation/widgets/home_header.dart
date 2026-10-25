import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_features.dart';
import '../../../../core/router/app_router.dart';
import '../../../notifications/data/notifications_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../providers/home_providers.dart';

/// Home header card (SRS §5.4 item 1, IMG_4476): gold gradient, greeting by
/// local time + first name (or "Guest"), bell button and the AI Gift Search
/// entry. Everything on the gold is dark ([AppColors.textOnPrimary]).
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  /// [AppColors.headerGradient], mirrored in RTL (deep gold on the start side).
  static LinearGradient get _gradient => LinearGradient(
        colors: AppColors.headerGradient.colors,
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final profile = ref.watch(currentUserProfileProvider);
    final firstName = profile.valueOrNull?.firstName ?? '';
    // Blank (not "Guest") while a signed-in profile is still loading.
    final name = profile.isLoading && !profile.hasValue ? '' : (firstName.isEmpty ? l10n.guest : firstName);
    final greeting = switch (greetingFor(DateTime.now())) {
      Greeting.morning => l10n.goodMorning,
      Greeting.afternoon => l10n.goodAfternoon,
      Greeting.evening => l10n.goodEvening,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.sm,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: _gradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: AppColors.isDark(context) ? null : AppElevation.soft,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Stack(
            children: [
              const PositionedDirectional(top: -70, end: -50, child: _Glow(size: 200)),
              const PositionedDirectional(bottom: -90, end: 70, child: _Glow(size: 160)),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greeting,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                // Full-strength dark text: at 80 % it was ≈3.7:1 on the
                                // gradient's dark start (SRS §8 needs 4.5:1; now ≈4.8:1).
                                style: AppTextStyles.bodyLarge.copyWith(
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: AppColors.textOnPrimary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.heading1.copyWith(color: AppColors.textOnPrimary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        _BellButton(
                          tooltip: l10n.notifications,
                          hasUnread: ref.watch(unreadNotificationsProvider) > 0,
                          onPressed: () => context.push(AppRoutes.notifications),
                        ),
                      ],
                    ),
                    if (AppFeatures.aiGiftSearch) ...[
                      const SizedBox(height: AppSpacing.md),
                      const AiGiftSearchBar(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft light circle decorating the gradient (IMG_4476).
/// Bell with a gold dot while there are unread notifications (SRS §4.5, IMG_4488).
class _BellButton extends StatelessWidget {
  const _BellButton({required this.tooltip, required this.hasUnread, required this.onPressed});
  final String tooltip;
  final bool hasUnread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GGCircleButton(
          icon: Icons.notifications_none_rounded,
          size: 48,
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (hasUnread)
          PositionedDirectional(
            top: 10,
            end: 12,
            child: IgnorePointer(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.gold(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card(context), width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.white.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

/// The surface "AI Gift Search" bar inside the header: sparkle in a soft-gold
/// square, title, hint and a direction-aware gold arrow. Opens AI Gift Search
/// (SRS §5.6).
class AiGiftSearchBar extends StatelessWidget {
  const AiGiftSearchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);
    final soft = AppColors.soft(context);
    void open() => context.push(AppRoutes.aiGiftSearch);

    return Semantics(
      button: true,
      label: '${l10n.aiGiftSearch}. ${l10n.aiGiftSearchHint}',
      excludeSemantics: true,
      onTap: open,
      child: Material(
        color: AppColors.card(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, size: 22, color: gold),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.aiGiftSearch,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        l10n.aiGiftSearchHint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          height: 1.35,
                          color: AppColors.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                  // arrow_forward mirrors automatically in RTL.
                  child: Icon(Icons.arrow_forward_rounded, size: 18, color: gold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

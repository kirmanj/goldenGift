import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import 'home_sections.dart';

/// "Complete your profile to unlock better recommendations" + Go to profile
/// (SRS §5.4 item 11, IMG_4479). Only for a signed-in profile whose
/// `profileCompleted` is false; guests never see it.
class ProfileCompletionCard extends ConsumerWidget {
  const ProfileCompletionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;
    if (profile == null || profile.profileCompleted) return const SliverToBoxAdapter();
    final l10n = AppLocalizations.of(context)!;
    final gold = AppColors.gold(context);

    return SliverPadding(
      padding: HomeLayout.section,
      sliver: SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.soft(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: gold.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.card(context), shape: BoxShape.circle),
                  child: Icon(Icons.auto_awesome_rounded, size: 24, color: gold),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.profileCompletionTitle,
                      style: AppTextStyles.label.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                        color: AppColors.text(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
                    PrimaryButton(
                      label: l10n.goToProfile,
                      expand: false,
                      height: 48,
                      onPressed: () => context.push(AppRoutes.editProfile),
                    ),
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

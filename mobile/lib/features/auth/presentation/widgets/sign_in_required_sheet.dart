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

/// Guards an action that needs an account (SRS AUTH-5). Returns true when the
/// user is signed in; otherwise shows "Sign in to continue" and returns false.
///
///   if (!await requireSignIn(context, ref)) return;
Future<bool> requireSignIn(BuildContext context, WidgetRef ref) async {
  if (ref.read(isSignedInProvider)) return true;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card(context),
    showDragHandle: true,
    // Grows past the default 9/16 height cap (small phones at 130 % text, SRS §8).
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const SignInRequiredSheet(),
  );
  return false;
}

class SignInRequiredSheet extends StatelessWidget {
  const SignInRequiredSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal, 0, AppSpacing.screenHorizontal, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
              child: Icon(Icons.lock_outline_rounded, color: AppColors.gold(context), size: 30),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.signInToContinue,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading3.copyWith(color: AppColors.text(context))),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.signInToContinueBody,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: l10n.signIn,
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.signIn);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlineButton(
              label: l10n.signUp,
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.signUp);
              },
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../data/datasources/auth_repository.dart';

/// Logo, title and subtitle at the top of Sign Up / Sign In (IMG_4475).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const GGLogo(size: 84),
        const SizedBox(height: AppSpacing.lg),
        Text(title,
            textAlign: TextAlign.center,
            style: AppTextStyles.heading1.copyWith(color: AppColors.text(context))),
        const SizedBox(height: AppSpacing.sm),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context))),
      ],
    );
  }
}

/// "Already have an account? **Sign In**" style prompt with a gold link.
class AuthSwitchPrompt extends StatelessWidget {
  const AuthSwitchPrompt({super.key, required this.question, required this.action, required this.onTap});
  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: AppTextStyles.bodyLarge.copyWith(color: AppColors.text(context))),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.goldText(context),
            minimumSize: const Size.square(AppSpacing.minTapTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          ),
          child: Text(action,
              style: AppTextStyles.link.copyWith(
                fontSize: 16,
                color: AppColors.goldText(context),
                fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
              )),
        ),
      ],
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(color: AppColors.line(context)));
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(AppLocalizations.of(context)!.or,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context))),
        ),
        line,
      ],
    );
  }
}

/// "Continue as a guest" (SRS AUTH-5).
class GuestButton extends StatelessWidget {
  const GuestButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.text(context),
        minimumSize: const Size.fromHeight(48),
      ),
      child: Text(
        AppLocalizations.of(context)!.continueAsGuest,
        style: AppTextStyles.label.copyWith(
          color: AppColors.text(context),
          decoration: TextDecoration.underline,
          fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
        ),
      ),
    );
  }
}

/// Google and (on iOS) Apple buttons under "Or" (SRS AUTH-4).
class SocialSignInButtons extends StatelessWidget {
  const SocialSignInButtons({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.busy = false,
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _SocialButton(
          label: l10n.continueWithGoogle,
          icon: SvgPicture.asset('assets/images/google_g.svg', width: 20, height: 20),
          onPressed: busy ? null : onGoogle,
        ),
        if (AuthRepository.appleSignInAvailable) ...[
          const SizedBox(height: AppSpacing.sm),
          _SocialButton(
            label: l10n.continueWithApple,
            icon: Icon(Icons.apple, size: 24, color: AppColors.text(context)),
            onPressed: busy ? null : onApple,
          ),
        ],
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.label, required this.icon, required this.onPressed});
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text(context),
        backgroundColor: AppColors.card(context),
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: AppColors.line(context)),
        shape: const StadiumBorder(),
        textStyle: AppTextStyles.label.copyWith(
          fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

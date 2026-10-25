import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/country_codes.dart';
import '../../../../core/providers/session_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../data/datasources/auth_repository.dart';
import '../providers/auth_flow.dart';
import '../providers/auth_navigation.dart';
import '../providers/otp_controller.dart';
import '../widgets/auth_messages.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/phone_field.dart';

/// Sign In = phone + OTP, with Google / Apple under "Or" (SRS AUTH-4, §5.2).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  CountryCode _country = CountryCodes.iraq;
  ValidationError? _phoneError;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final error = Validators.phone(_phone.text, _country);
    setState(() => _phoneError = error);
    if (error != null || _busy) return;
    setState(() => _busy = true);
    try {
      final session = await ref.read(authRepositoryProvider).sendCode(Validators.e164(_phone.text, _country));
      if (!mounted) return;
      context.push(
        AppRoutes.otp,
        extra: OtpArgs(
          purpose: OtpPurpose.signIn,
          session: session,
          displayPhone: '${_country.dialCode} ${Validators.normalizePhone(_phone.text)}',
        ),
      );
    } on AuthFailure catch (f) {
      if (!mounted) return;
      if (f.reason == AuthFailureReason.invalidPhone) {
        setState(() => _phoneError = ValidationError.invalidPhone);
      } else {
        showAuthError(context, f.reason);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _social(SignInMethod method) async {
    setState(() => _busy = true);
    await runSocialSignIn(context, ref, method);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _continueAsGuest() async {
    await ref.read(guestModeProvider.notifier).set(true);
    if (mounted) context.go(AppRoutes.main);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canPop = context.canPop();
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: canPop ? const GGAppBar() : null,
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, AppSpacing.xl),
            children: [
              AuthHeader(title: l10n.signInTitle, subtitle: l10n.signInSubtitle),
              const SizedBox(height: AppSpacing.xl),
              Text(l10n.signIn, style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
              const SizedBox(height: AppSpacing.md),
              PhoneField(
                controller: _phone,
                country: _country,
                onCountryChanged: (c) => setState(() => _country = c),
                errorText: l10n.validation(_phoneError),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: l10n.signIn, isLoading: _busy, onPressed: _submit),
              const SizedBox(height: AppSpacing.md),
              AuthSwitchPrompt(
                question: l10n.dontHaveAccount,
                action: l10n.signUp,
                onTap: () => context.go(AppRoutes.signUp),
              ),
              const SizedBox(height: AppSpacing.sm),
              const OrDivider(),
              const SizedBox(height: AppSpacing.sm),
              if (!canPop) ...[
                GuestButton(onPressed: _continueAsGuest),
                const SizedBox(height: AppSpacing.sm),
              ],
              SocialSignInButtons(
                busy: _busy,
                onGoogle: () => _social(SignInMethod.google),
                onApple: () => _social(SignInMethod.apple),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Sign Up (SRS §5.2, AUTH-1, IMG_4475). With [prefill] it is the
/// "Complete your account" form for someone already signed in without a
/// profile (new phone number on Sign In, or Google / Apple): no OTP step,
/// the profile is created directly.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.prefill, this.referralCode});

  final ProfilePrefill? prefill;

  /// From a referral link /r/{code} (SRS §4.6).
  final String? referralCode;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  late final _name = TextEditingController(text: widget.prefill?.name);
  late final _email = TextEditingController(text: widget.prefill?.email);
  late final _phone = TextEditingController();
  late final _referral = TextEditingController(text: widget.referralCode);
  late CountryCode _country = CountryCodes.byDialCode(widget.prefill?.countryCode ?? CountryCodes.iraq.dialCode);
  late bool _showReferral = (widget.referralCode ?? '').isNotEmpty;

  ValidationError? _nameError, _emailError, _phoneError, _referralError;
  bool _busy = false;

  bool get _completing => widget.prefill != null;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _referral.dispose();
    super.dispose();
  }

  bool _validate() {
    setState(() {
      _nameError = Validators.name(_name.text);
      _emailError = Validators.email(_email.text);
      _phoneError = _completing ? null : Validators.phone(_phone.text, _country);
      _referralError = Validators.referralCode(_referral.text);
    });
    return _nameError == null && _emailError == null && _phoneError == null && _referralError == null;
  }

  String? get _referralCode {
    final code = Validators.normalizeReferralCode(_referral.text);
    return code.isEmpty ? null : code;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate() || _busy) return;
    setState(() => _busy = true);
    try {
      if (_completing) {
        await _createProfileForSignedInUser();
      } else {
        await _sendCode();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final e164 = Validators.e164(_phone.text, _country);
    try {
      final session = await ref.read(authRepositoryProvider).sendCode(e164);
      if (!mounted) return;
      context.push(
        AppRoutes.otp,
        extra: OtpArgs(
          purpose: OtpPurpose.signUp,
          session: session,
          displayPhone: '${_country.dialCode} ${Validators.normalizePhone(_phone.text)}',
          pending: PendingSignUp(
            name: _name.text.trim(),
            email: _email.text.trim(),
            referralCode: _referralCode,
          ),
        ),
      );
    } on AuthFailure catch (f) {
      if (!mounted) return;
      if (f.reason == AuthFailureReason.invalidPhone) {
        setState(() => _phoneError = ValidationError.invalidPhone);
      } else {
        showAuthError(context, f.reason);
      }
    }
  }

  Future<void> _createProfileForSignedInUser() async {
    final user = ref.read(authRepositoryProvider).currentUser;
    final prefill = widget.prefill!;
    if (user == null) {
      context.go(AppRoutes.signIn);
      return;
    }
    try {
      await ref.read(authFlowProvider).createProfile(
            user,
            method: prefill.method,
            name: _name.text,
            email: _email.text,
            phone: prefill.phone,
            countryCode: prefill.countryCode,
            referralCode: _referralCode,
          );
      if (mounted) context.go(AppRoutes.main);
    } catch (e) {
      if (mounted) showAuthError(context, AuthFailure.from(e).reason);
    }
  }

  Future<void> _continueAsGuest() async {
    await ref.read(guestModeProvider.notifier).set(true);
    if (mounted) context.go(AppRoutes.main);
  }

  Future<void> _social(SignInMethod method) async {
    setState(() => _busy = true);
    await runSocialSignIn(context, ref, method);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final prefill = widget.prefill;
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenHorizontal, AppSpacing.lg, AppSpacing.screenHorizontal, AppSpacing.xl),
            children: [
              AuthHeader(
                title: _completing ? l10n.completeProfileTitle : l10n.createYourAccount,
                subtitle: _completing ? l10n.completeProfileSubtitle : l10n.registerSubtitle,
              ),
              const SizedBox(height: AppSpacing.xl),
              if (!_completing)
                Text(l10n.signUp, style: AppTextStyles.heading2.copyWith(color: AppColors.text(context))),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: l10n.yourName,
                hint: l10n.enterYourName,
                controller: _name,
                errorText: l10n.validation(_nameError),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                maxLength: Validators.nameMax,
              ),
              const SizedBox(height: AppSpacing.md),
              GGInput(
                label: l10n.email,
                hint: l10n.enterYourEmail,
                controller: _email,
                errorText: l10n.validation(_emailError),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_completing)
                PhoneField(
                  controller: _phone,
                  country: _country,
                  onCountryChanged: (c) => setState(() => _country = c),
                  errorText: l10n.validation(_phoneError),
                  onSubmitted: (_) => _submit(),
                )
              else if (prefill!.phoneVerified)
                GGInput(
                  label: l10n.mobileNumber,
                  initialValue: '${prefill.countryCode} ${prefill.phone}',
                  readOnly: true,
                  enabled: false,
                )
              else
                InfoBanner(message: l10n.phoneLaterNote, type: InfoBannerType.info),
              const SizedBox(height: AppSpacing.sm),
              _ReferralSection(
                expanded: _showReferral,
                controller: _referral,
                errorText: l10n.validation(_referralError),
                onExpand: () => setState(() => _showReferral = true),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: _completing ? l10n.save : l10n.signUp,
                isLoading: _busy,
                onPressed: _submit,
              ),
              if (!_completing) ...[
                const SizedBox(height: AppSpacing.md),
                AuthSwitchPrompt(
                  question: l10n.alreadyHaveAccount,
                  action: l10n.signIn,
                  onTap: () => context.go(AppRoutes.signIn),
                ),
                const SizedBox(height: AppSpacing.sm),
                const OrDivider(),
                const SizedBox(height: AppSpacing.sm),
                GuestButton(onPressed: _continueAsGuest),
                const SizedBox(height: AppSpacing.sm),
                SocialSignInButtons(
                  busy: _busy,
                  onGoogle: () => _social(SignInMethod.google),
                  onApple: () => _social(SignInMethod.apple),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.termsAgreement,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted(context))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "🎁 Have a referral code?" link that expands into the code input (AUTH-1).
class _ReferralSection extends StatelessWidget {
  const _ReferralSection({
    required this.expanded,
    required this.controller,
    required this.errorText,
    required this.onExpand,
  });

  final bool expanded;
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: AlignmentDirectional.topStart,
      child: expanded
          ? GGInput(
              label: l10n.referralCodeLabel,
              hint: l10n.referralCodeHint,
              controller: controller,
              errorText: errorText,
              textCapitalization: TextCapitalization.characters,
              maxLength: Validators.referralCodeLength,
            )
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: onExpand,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.goldText(context),
                  minimumSize: const Size.square(AppSpacing.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                ),
                icon: Icon(Icons.card_giftcard_rounded, color: AppColors.gold(context)),
                label: Text(l10n.haveReferralCode,
                    style: AppTextStyles.link.copyWith(
                      color: AppColors.goldText(context),
                      fontFamily: AppTextStyles.fontFamily(Localizations.localeOf(context)),
                    )),
              ),
            ),
    );
  }
}

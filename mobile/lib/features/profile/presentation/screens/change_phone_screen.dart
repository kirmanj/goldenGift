import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/country_codes.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/data/datasources/auth_repository.dart';
import '../../../auth/presentation/providers/otp_controller.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../auth/presentation/widgets/phone_field.dart';
import '../../data/datasources/user_repository.dart';
import '../providers/profile_platform_providers.dart';
import '../providers/profile_providers.dart';
import '../widgets/profile_dialogs.dart';
import '../widgets/profile_formatters.dart';

/// Add or change the mobile number (SRS §5.14, AUTH-4): validate → SMS code
/// → OTP screen (updates the Firebase Auth phone and pops `true`) → write
/// `phone` / `countryCode` to the profile. Mobile only.
class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  final _phone = TextEditingController();
  late CountryCode _country;
  String? _error;
  bool _busy = false;

  /// Set when the Auth phone was verified but writing the profile failed:
  /// the button then only retries that write (no second SMS).
  ({String national, String dialCode})? _verified;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    _country = CountryCodes.byDialCode(profile?.countryCode ?? CountryCodes.iraq.dialCode);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    if (_verified != null) return _saveToProfile(_verified!);

    // Invalid input never reaches Firebase (SRS AUTH-8).
    final invalid = Validators.phone(_phone.text, _country);
    if (invalid != null) {
      setState(() => _error = l10n.validation(invalid));
      return;
    }
    final national = Validators.normalizePhone(_phone.text);
    final country = _country;
    setState(() {
      _busy = true;
      _error = null;
    });

    final PhoneCodeSession session;
    try {
      session = await ref
          .read(authRepositoryProvider)
          .sendCode(Validators.e164(_phone.text, country), forPhoneChange: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.authFailure(AuthFailure.from(e).reason);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final ok = await context.push<bool>(
      AppRoutes.otp,
      extra: OtpArgs(
        purpose: OtpPurpose.changePhone,
        session: session,
        displayPhone: formatPhoneForDisplay(country.dialCode, national),
      ),
    );
    if (ok != true || !mounted) return;
    await _saveToProfile((national: national, dialCode: country.dialCode));
  }

  Future<void> _saveToProfile(({String national, String dialCode}) phone) async {
    final l10n = AppLocalizations.of(context)!;
    final uid = ref.read(currentUserProfileProvider).valueOrNull?.uid;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (uid != null) {
      try {
        await ref.read(userRepositoryProvider).updateFields(uid, {
          'phone': phone.national,
          'countryCode': phone.dialCode,
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _busy = false;
            _verified = phone;
            _error = l10n.somethingWentWrong;
          });
        }
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.phoneUpdated)));
    popOrGoMain(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final supported = ref.watch(phoneChangeSupportedProvider);
    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: l10n.changePhoneTitle),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, AppSpacing.xl),
          children: supported
              ? [
                  Text(
                    l10n.changePhoneSubtitle,
                    style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PhoneField(
                    controller: _phone,
                    country: _country,
                    errorText: _error,
                    enabled: !_busy && _verified == null,
                    autofocus: true,
                    onCountryChanged: (c) => setState(() {
                      _country = c;
                      _error = null;
                    }),
                    onSubmitted: (_) => _sendCode(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    key: const ValueKey('change-phone-send'),
                    label: _verified == null ? l10n.sendCode : l10n.retry,
                    isLoading: _busy,
                    onPressed: _sendCode,
                  ),
                ]
              : [InfoBanner(message: l10n.phoneChangeMobileOnly)],
        ),
      ),
    );
  }
}

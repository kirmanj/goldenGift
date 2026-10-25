import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../providers/auth_navigation.dart';
import '../providers/otp_controller.dart';
import '../widgets/auth_messages.dart';
import '../widgets/otp_input.dart';

/// Wraps [text] in Unicode LEFT-TO-RIGHT ISOLATE … POP DIRECTIONAL ISOLATE so
/// a phone number keeps its digit order inside Arabic / Kurdish sentences.
String _isolateLtr(String text) => '${String.fromCharCode(0x2066)}$text${String.fromCharCode(0x2069)}';

/// 6-digit code, resend after 60 s, Android auto-read (SRS AUTH-2).
/// For [OtpPurpose.changePhone] it pops `true` once the phone is updated.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});
  final OtpArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _verify() => ref.read(otpControllerProvider(widget.args).notifier).verify(_code.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = otpControllerProvider(widget.args);
    final state = ref.watch(provider);

    ref.listen(provider, (previous, next) {
      final result = next.result;
      if (result == null || previous?.result != null) return;
      switch (result) {
        case OtpSignedIn(:final outcome):
          navigateAfterAuth(context, outcome);
        case OtpPhoneUpdated():
          context.pop(true);
      }
    });
    ref.listen(provider.select((s) => s.error), (_, error) {
      if (error != null) _code.clear();
    });

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: const GGAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenHorizontal, vertical: AppSpacing.lg),
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: AppColors.soft(context), shape: BoxShape.circle),
                child: Icon(Icons.sms_outlined, size: 34, color: AppColors.gold(context)),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.otpTitle,
                textAlign: TextAlign.center,
                style: AppTextStyles.heading1.copyWith(color: AppColors.text(context))),
            const SizedBox(height: AppSpacing.sm),
            Text(
              // Keep the number itself left-to-right inside Arabic / Kurdish text.
              l10n.otpSubtitle(_isolateLtr(widget.args.displayPhone)),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textMuted(context)),
            ),
            const SizedBox(height: AppSpacing.xl),
            OtpInput(
              controller: _code,
              length: OtpController.codeLength,
              hasError: state.error != null,
              enabled: !state.verifying,
              semanticLabel: l10n.otpTitle,
              onCompleted: (_) => _verify(),
            ),
            if (state.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.authFailure(state.error!),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.xl),
            ValueListenableBuilder(
              valueListenable: _code,
              builder: (_, value, __) => PrimaryButton(
                label: l10n.otpVerify,
                isLoading: state.verifying,
                onPressed: value.text.length == OtpController.codeLength ? _verify : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: state.canResend
                  ? TextButton(
                      onPressed: () => ref.read(provider.notifier).resend(),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.goldText(context), minimumSize: const Size.square(AppSpacing.minTapTarget)),
                      child: Text(l10n.otpResend),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + AppSpacing.xxs),
                      child: Text(
                        state.resending ? l10n.loading : l10n.otpResendIn(state.secondsLeft),
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
                      ),
                    ),
            ),
            Center(
              child: TextButton(
                onPressed: state.verifying ? null : () => context.pop(),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted(context), minimumSize: const Size.square(AppSpacing.minTapTarget)),
                child: Text(l10n.changeNumber),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

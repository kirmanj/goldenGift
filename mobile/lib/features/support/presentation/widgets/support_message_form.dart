import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/special_request_model.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../special_requests/data/special_requests_repository.dart';
import '../../../special_requests/presentation/screens/special_requests_screen.dart' show readCustomerSnapshot;

/// Contact Us in-app form (SRS §5.24): a message of at most 1000 characters
/// that becomes a `special_requests` doc with `type = support`; the reply
/// thread lives in Special Requests ("View your messages").
class SupportMessageForm extends ConsumerStatefulWidget {
  const SupportMessageForm({super.key});

  @override
  ConsumerState<SupportMessageForm> createState() => _SupportMessageFormState();
}

class _SupportMessageFormState extends ConsumerState<SupportMessageForm> {
  final _text = TextEditingController();
  String? _error;
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final l10n = AppLocalizations.of(context)!;
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _error = l10n.errorRequired);
      return;
    }
    if (!await requireSignIn(context, ref)) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    try {
      final (name, phone) = await readCustomerSnapshot(ref);
      await ref.read(specialRequestsRepositoryProvider).create(
            uid: uid,
            text: text,
            type: SpecialRequestType.support,
            customerName: name,
            customerPhone: phone,
          );
      if (!mounted) return;
      _text.clear();
      setState(() {
        _sent = true;
        _error = null;
      });
    } catch (_) {
      if (mounted) showOrderSnack(context, l10n.somethingWentWrong);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final link = TextButton(
      key: const ValueKey('support-view-messages'),
      onPressed: () => context.push(AppRoutes.specialRequests),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.goldText(context),
        minimumSize: const Size.square(AppSpacing.minTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: Text(l10n.supportViewMessages),
    );

    return OrderSection(
      key: const ValueKey('support-form'),
      title: l10n.supportSendUsMessage,
      icon: Icons.chat_bubble_outline_rounded,
      child: _sent
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoBanner(
                  key: const ValueKey('support-sent'),
                  message: l10n.supportMessageSent,
                  type: InfoBannerType.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    link,
                    TextButton(
                      key: const ValueKey('support-send-another'),
                      onPressed: () => setState(() => _sent = false),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted(context),
                        minimumSize: const Size.square(AppSpacing.minTapTarget),
                      ),
                      child: Text(l10n.supportSendAnother),
                    ),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GGInput(
                  key: const ValueKey('support-message'),
                  hint: l10n.supportMessageHint,
                  controller: _text,
                  multiline: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: SpecialRequestModel.maxText,
                  showCounter: true,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.sentences,
                  errorText: _error,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  key: const ValueKey('support-send'),
                  label: l10n.supportSend,
                  icon: Icons.send_rounded,
                  isLoading: _sending,
                  onPressed: _send,
                ),
                if (ref.watch(isSignedInProvider)) Align(alignment: AlignmentDirectional.centerStart, child: link),
              ],
            ),
    );
  }
}

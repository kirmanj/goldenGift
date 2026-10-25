import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/secret_santa_model.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../auth/presentation/widgets/sign_in_required_sheet.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/secret_santa_repository.dart';
import '../providers/secret_santa_providers.dart';

/// Join a Secret Santa group (SRS §5.16) — from the invite link `/s/:code`
/// or "Join with a code": sign in → name (pre-filled) + optional wish note →
/// `joinSecretSanta` → the group page.
class SecretSantaJoinScreen extends ConsumerStatefulWidget {
  const SecretSantaJoinScreen({super.key, required this.code});

  /// As typed / linked; normalized before use.
  final String code;

  @override
  ConsumerState<SecretSantaJoinScreen> createState() => _SecretSantaJoinScreenState();
}

class _SecretSantaJoinScreenState extends ConsumerState<SecretSantaJoinScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _prefilled = false;
  bool _joining = false;
  String? _nameError;

  late final String? _code = normalizeInviteCode(widget.code);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Fills the name once from the profile (or the sign-in name).
  void _prefill() {
    if (_prefilled) return;
    String name = '';
    try {
      name = ref.read(currentUserProfileProvider).valueOrNull?.name.trim() ?? '';
    } catch (_) {
      name = '';
    }
    if (name.isEmpty) name = ref.read(authStateProvider).valueOrNull?.displayName?.trim() ?? '';
    if (name.isEmpty) return;
    _prefilled = true;
    _name.text = name;
  }

  Future<void> _join() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _code;
    if (code == null) return;
    if (!await requireSignIn(context, ref)) return;
    if (!mounted) return;
    final error = l10n.validation(Validators.name(_name.text));
    setState(() => _nameError = error);
    if (error != null) return;
    final router = GoRouter.of(context);
    setState(() => _joining = true);
    try {
      final groupId = await ref.read(secretSantaRepositoryProvider).join(code, name: _name.text, wishlistNote: _note.text);
      if (!mounted) return;
      if (groupId.isEmpty) {
        showOrderSnack(context, l10n.somethingWentWrong);
        setState(() => _joining = false);
        return;
      }
      showOrderSnack(context, l10n.secretSantaJoined);
      router.pushReplacement(AppRoutes.secretSantaGroupFor(groupId));
    } on SecretSantaFailure catch (f) {
      if (!mounted) return;
      showOrderSnack(context, secretSantaFailureMessage(l10n, f.reason));
      setState(() => _joining = false);
    } catch (_) {
      if (!mounted) return;
      showOrderSnack(context, l10n.somethingWentWrong);
      setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    // Re-check the prefill when the profile arrives.
    ref.watch(currentUserProfileProvider.select((p) => p.valueOrNull?.name));
    if (signedIn) _prefill();
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final code = _code;

    final Widget body;
    if (code == null) {
      body = CenteredScroll(
        child: EmptyState(
          key: const ValueKey('santa-join-invalid'),
          title: l10n.secretSantaInvalidCode,
          icon: Icons.key_off_rounded,
          ctaLabel: l10n.secretSanta,
          onCta: () => context.go(AppRoutes.secretSanta),
        ),
      );
    } else {
      // Guests see the form too; Join asks them to sign in first (AUTH-5).
      body = ListView(
        key: const ValueKey('santa-join-form'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [
          OrderSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.redeem_rounded, size: 40, color: AppColors.gold(context)),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.secretSantaJoinTitle,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading3.copyWith(color: AppColors.text(context)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.secretSantaJoinBody(code),
                  key: const ValueKey('santa-join-body'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          GGInput(
            key: const ValueKey('santa-join-name'),
            label: l10n.yourName,
            hint: l10n.enterYourName,
            controller: _name,
            errorText: _nameError,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          GGInput(
            key: const ValueKey('santa-join-note'),
            label: '${l10n.secretSantaMyWishNote} ${l10n.optionalLabel}',
            hint: l10n.secretSantaWishNoteHint,
            controller: _note,
            multiline: true,
            minLines: 3,
            maxLines: 6,
            maxLength: SecretSantaMember.maxWishlistNote,
            showCounter: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            key: const ValueKey('santa-join-group'),
            label: l10n.secretSantaJoinGroup,
            isLoading: _joining,
            onPressed: () => unawaited(_join()),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(
        title: l10n.secretSanta,
        showBack: true,
        onBack: () => popOrGo(context, AppRoutes.secretSanta),
      ),
      body: body,
    );
  }
}

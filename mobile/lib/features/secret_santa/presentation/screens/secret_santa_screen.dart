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
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../orders/presentation/widgets/order_card.dart' show popOrGo;
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../data/secret_santa_repository.dart';
import '../providers/secret_santa_providers.dart';
import '../widgets/secret_santa_create_sheet.dart';
import '../widgets/secret_santa_widgets.dart';

/// Secret Santa ▸ my groups (SRS §5.16, `/secret-santa`): a card per group,
/// "Create group" and "Join with a code".
class SecretSantaScreen extends ConsumerWidget {
  const SecretSantaScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final id = await showSecretSantaCreateSheet(context);
    if (id != null && id.isNotEmpty && context.mounted) {
      unawaited(context.push(AppRoutes.secretSantaGroupFor(id)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    final appBar = GGAppBar(
      title: l10n.secretSanta,
      showBack: true,
      onBack: () => popOrGo(context, AppRoutes.mainTab(2)),
    );
    if (!signedIn) {
      return Scaffold(
        backgroundColor: AppColors.bg(context),
        appBar: appBar,
        body: const GuestSignInCard(icon: Icons.redeem_rounded),
      );
    }
    final uid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';
    final groups = ref.watch(mySecretSantaGroupsProvider);

    final header = <Widget>[
      Text(
        l10n.secretSantaIntro,
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted(context)),
      ),
      const SizedBox(height: AppSpacing.md),
      PrimaryButton(
        key: const ValueKey('santa-create-open'),
        label: l10n.secretSantaCreateGroup,
        icon: Icons.add_rounded,
        onPressed: () => unawaited(_create(context)),
      ),
      const SizedBox(height: AppSpacing.md),
      const _JoinWithCode(),
      const SizedBox(height: AppSpacing.lg),
    ];

    final List<Widget> content = groups.when(
      loading: () => const [SkeletonLoader.list(count: 3)],
      error: (_, __) => [ErrorState(onRetry: () => ref.invalidate(mySecretSantaGroupsProvider))],
      data: (list) => list.isEmpty
          ? [
              EmptyState(
                key: const ValueKey('santa-empty'),
                title: l10n.secretSantaNoGroupsTitle,
                subtitle: l10n.secretSantaNoGroupsBody,
                icon: Icons.redeem_rounded,
              ),
            ]
          : [
              for (final group in list) ...[
                SecretSantaGroupCard(
                  group: group,
                  uid: uid,
                  onTap: () => unawaited(context.push(AppRoutes.secretSantaGroupFor(group.id))),
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              ],
            ],
    );

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: appBar,
      body: ListView(
        key: const ValueKey('santa-groups'),
        padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
        children: [...header, ...content],
      ),
    );
  }
}

/// Code field + Join → the join flow at `/s/{code}`. Accepts a pasted link.
class _JoinWithCode extends StatefulWidget {
  const _JoinWithCode();

  @override
  State<_JoinWithCode> createState() => _JoinWithCodeState();
}

class _JoinWithCodeState extends State<_JoinWithCode> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join() {
    final l10n = AppLocalizations.of(context)!;
    final code = normalizeInviteCode(_code.text);
    if (code == null) {
      setState(() => _error = l10n.secretSantaInvalidCode);
      return;
    }
    FocusScope.of(context).unfocus();
    unawaited(context.push(AppRoutes.secretSantaJoin(code)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return OrderSection(
      title: l10n.secretSantaJoinWithCode,
      icon: Icons.key_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GGInput(
            key: const ValueKey('santa-join-code'),
            hint: l10n.secretSantaCodeHint,
            controller: _code,
            errorText: _error,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _join(),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          OutlineButton(
            key: const ValueKey('santa-join-submit'),
            label: l10n.secretSantaJoin,
            icon: Icons.login_rounded,
            height: 48,
            onPressed: _join,
          ),
        ],
      ),
    );
  }
}

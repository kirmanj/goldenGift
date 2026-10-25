import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../l10n/l10n.dart';
import '../../data/datasources/auth_repository.dart';
import '../widgets/auth_messages.dart';
import 'auth_flow.dart';

/// Leaves the auth screens for wherever the sign-in outcome points.
void navigateAfterAuth(BuildContext context, AuthOutcome outcome) {
  switch (outcome) {
    case GoToMain():
      context.go(AppRoutes.main);
    case GoToCompleteProfile(:final prefill):
      context.go(AppRoutes.completeProfile, extra: prefill);
  }
}

/// Google / Apple sign-in shared by Sign Up and Sign In (SRS AUTH-4).
/// Returns quietly when the user cancels; shows a snackbar on failure.
Future<void> runSocialSignIn(BuildContext context, WidgetRef ref, SignInMethod method) async {
  final auth = ref.read(authRepositoryProvider);
  try {
    final UserCredential? credential =
        method == SignInMethod.apple ? await auth.signInWithApple() : await auth.signInWithGoogle();
    if (credential?.user == null) return;
    final outcome = await ref.read(authFlowProvider).afterSignIn(credential!.user!, method: method);
    if (context.mounted) navigateAfterAuth(context, outcome);
  } catch (e) {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.authFailure(AuthFailure.from(e).reason))));
  }
}

void showAuthError(BuildContext context, AuthFailureReason reason) {
  final l10n = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(l10n.authFailure(reason))));
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/auth_repository.dart';
import 'auth_flow.dart';

/// Why the OTP screen was opened.
enum OtpPurpose {
  /// Sign Up form → create the profile after verification.
  signUp,

  /// Sign In with a phone number.
  signIn,

  /// Edit Profile / Google-Apple account adding or changing its phone (SRS §5.14, AUTH-4).
  changePhone,
}

/// Arguments passed to the OTP route (GoRouter `extra`).
class OtpArgs {
  const OtpArgs({
    required this.purpose,
    required this.session,
    required this.displayPhone,
    this.pending,
  });

  final OtpPurpose purpose;
  final PhoneCodeSession session;

  /// "+964 750 123 4567" for the subtitle.
  final String displayPhone;
  final PendingSignUp? pending;
}

class OtpState {
  const OtpState({
    required this.session,
    this.secondsLeft = OtpController.resendSeconds,
    this.resending = false,
    this.verifying = false,
    this.error,
    this.result,
  });

  final PhoneCodeSession session;
  final int secondsLeft;
  final bool resending;
  final bool verifying;
  final AuthFailureReason? error;

  /// Set once verification succeeded (signed in, or phone updated).
  final OtpResult? result;

  bool get canResend => secondsLeft == 0 && !resending && !verifying;

  OtpState copyWith({
    PhoneCodeSession? session,
    int? secondsLeft,
    bool? resending,
    bool? verifying,
    AuthFailureReason? error,
    bool clearError = false,
    OtpResult? result,
  }) =>
      OtpState(
        session: session ?? this.session,
        secondsLeft: secondsLeft ?? this.secondsLeft,
        resending: resending ?? this.resending,
        verifying: verifying ?? this.verifying,
        error: clearError ? null : (error ?? this.error),
        result: result ?? this.result,
      );
}

/// What happened after a successful code.
sealed class OtpResult {
  const OtpResult();
}

class OtpSignedIn extends OtpResult {
  const OtpSignedIn(this.outcome);
  final AuthOutcome outcome;
}

class OtpPhoneUpdated extends OtpResult {
  const OtpPhoneUpdated();
}

/// OTP screen logic (SRS AUTH-2): 6-digit code, resend after 60 s. Codes
/// arrive over WhatsApp or SMS (OTPIQ). One instance per OTP screen
/// (autoDispose family on [OtpArgs]).
class OtpController extends StateNotifier<OtpState> {
  OtpController(this._ref, this.args) : super(OtpState(session: args.session)) {
    _startCountdown();
  }

  static const resendSeconds = 60;
  static const codeLength = 6;

  final Ref _ref;
  final OtpArgs args;
  Timer? _timer;

  AuthRepository get _auth => _ref.read(authRepositoryProvider);

  void _startCountdown() {
    _timer?.cancel();
    state = state.copyWith(secondsLeft: resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final left = state.secondsLeft - 1;
      state = state.copyWith(secondsLeft: left < 0 ? 0 : left);
      if (left <= 0) t.cancel();
    });
  }

  Future<void> resend() async {
    if (!state.canResend) return;
    state = state.copyWith(resending: true, clearError: true);
    try {
      final session = await _auth.sendCode(
        state.session.phoneE164,
        forPhoneChange: args.purpose == OtpPurpose.changePhone,
      );
      if (!mounted) return;
      state = state.copyWith(session: session, resending: false);
      _startCountdown();
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(resending: false, error: AuthFailure.from(e).reason);
    }
  }

  /// Verifies a typed code. Ignores incomplete codes (the UI only enables
  /// Verify for 6 digits, so nothing invalid reaches the server).
  Future<void> verify(String code) async {
    if (code.length != codeLength || state.verifying || state.result != null) return;
    state = state.copyWith(verifying: true, clearError: true);
    try {
      if (args.purpose == OtpPurpose.changePhone) {
        await _auth.changePhone(state.session, code);
        if (mounted) state = state.copyWith(verifying: false, result: const OtpPhoneUpdated());
        return;
      }
      final credential = await _auth.confirmCode(state.session, code);
      final outcome = await _ref.read(authFlowProvider).afterSignIn(
            credential.user!,
            method: SignInMethod.phone,
            pending: args.purpose == OtpPurpose.signUp ? args.pending : null,
          );
      if (mounted) state = state.copyWith(verifying: false, result: OtpSignedIn(outcome));
    } catch (e) {
      if (mounted) state = state.copyWith(verifying: false, error: AuthFailure.from(e).reason);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final otpControllerProvider =
    StateNotifierProvider.autoDispose.family<OtpController, OtpState, OtpArgs>(
  (ref, args) => OtpController(ref, args),
);

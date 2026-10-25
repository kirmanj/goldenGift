import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../firebase_options.dart';

/// Why an auth call failed, mapped to a localized message by the UI.
enum AuthFailureReason {
  invalidPhone,
  invalidCode,
  codeExpired,
  tooManyRequests,
  network,
  deliveryFailed,
  phoneInUse,
  providerUnavailable,
  accountDisabled,
  cancelled,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.reason, [this.debugMessage]);
  final AuthFailureReason reason;
  final String? debugMessage;

  /// [verifying]: the error came from checking a code (so `invalid-argument` /
  /// `unauthenticated` mean a bad code, not a bad phone number).
  factory AuthFailure.from(Object error, {bool verifying = false}) {
    if (error is AuthFailure) return error;
    if (error is FirebaseFunctionsException) {
      // Codes thrown by sendOtp / verifyOtp / changePhone (mobile/functions/src/auth).
      final reason = switch (error.code) {
        'invalid-argument' => verifying ? AuthFailureReason.invalidCode : AuthFailureReason.invalidPhone,
        'unauthenticated' => verifying ? AuthFailureReason.invalidCode : AuthFailureReason.unknown,
        'resource-exhausted' => AuthFailureReason.tooManyRequests,
        'unavailable' => AuthFailureReason.deliveryFailed,
        'already-exists' => AuthFailureReason.phoneInUse,
        'permission-denied' => AuthFailureReason.accountDisabled,
        // Function not deployed (no Blaze plan yet) or failing.
        'not-found' || 'unimplemented' || 'internal' => AuthFailureReason.providerUnavailable,
        'deadline-exceeded' => AuthFailureReason.network,
        _ => AuthFailureReason.unknown,
      };
      return AuthFailure(reason, 'functions/${error.code}: ${error.message}');
    }
    if (error is FirebaseAuthException) {
      final reason = switch (error.code) {
        'too-many-requests' || 'quota-exceeded' => AuthFailureReason.tooManyRequests,
        'network-request-failed' => AuthFailureReason.network,
        'credential-already-in-use' || 'account-exists-with-different-credential' ||
        'provider-already-linked' => AuthFailureReason.phoneInUse,
        'operation-not-allowed' || 'app-not-authorized' || 'missing-client-identifier' ||
        'internal-error' || 'invalid-custom-token' || 'custom-token-mismatch' =>
          AuthFailureReason.providerUnavailable,
        'user-disabled' => AuthFailureReason.accountDisabled,
        'web-context-canceled' || 'popup-closed-by-user' || 'cancelled-popup-request' ||
        'canceled' => AuthFailureReason.cancelled,
        _ => AuthFailureReason.unknown,
      };
      return AuthFailure(reason, '${error.code}: ${error.message}');
    }
    return AuthFailure(AuthFailureReason.unknown, '$error');
  }

  @override
  String toString() => 'AuthFailure($reason, $debugMessage)';
}

/// A code sent by `sendOtp` (SRS AUTH-2): OTPIQ delivers it over WhatsApp,
/// falling back to SMS. The code itself only exists on the server.
class PhoneCodeSession {
  const PhoneCodeSession({
    required this.phoneE164,
    this.forPhoneChange = false,
    this.expiresInSeconds = 300,
  });

  final String phoneE164;

  /// Issued for Change Phone (bound to the signed-in user) rather than sign-in.
  final bool forPhoneChange;
  final int expiresInSeconds;
}

/// Firebase Auth + the phone-OTP functions: OTPIQ code → custom token → a
/// normal Firebase session (SRS AUTH-2/4). Google and Apple use Firebase Auth directly.
class AuthRepository {
  AuthRepository(this._auth, this._functions);

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Asks `sendOtp` to deliver a code. [forPhoneChange] requires a signed-in
  /// user and refuses a number that belongs to another account.
  Future<PhoneCodeSession> sendCode(String phoneE164, {bool forPhoneChange = false}) async {
    try {
      final result = await _functions.httpsCallable('sendOtp').call<Map<String, dynamic>>({
        'phone': phoneE164,
        'purpose': forPhoneChange ? 'changePhone' : 'login',
      });
      final expires = result.data['expiresInSeconds'];
      return PhoneCodeSession(
        phoneE164: phoneE164,
        forPhoneChange: forPhoneChange,
        expiresInSeconds: expires is int ? expires : 300,
      );
    } catch (e) {
      throw AuthFailure.from(e);
    }
  }

  /// Trades a correct code for a Firebase session (`verifyOtp` → custom token).
  Future<UserCredential> confirmCode(PhoneCodeSession session, String smsCode) async {
    final String token;
    try {
      final result = await _functions.httpsCallable('verifyOtp').call<Map<String, dynamic>>({
        'phone': session.phoneE164,
        'code': smsCode,
      });
      token = result.data['token'] as String;
    } catch (e) {
      throw AuthFailure.from(e, verifying: true);
    }
    try {
      return await _auth.signInWithCustomToken(token);
    } catch (e) {
      throw AuthFailure.from(e);
    }
  }

  /// Sets or replaces the signed-in user's phone (Edit Profile, SRS §5.14; also
  /// how a Google/Apple account verifies a phone, AUTH-4). The function updates
  /// Firebase Auth and `users/{uid}`; the local user is reloaded afterwards.
  Future<void> changePhone(PhoneCodeSession session, String smsCode) async {
    try {
      await _functions.httpsCallable('changePhone').call<Map<String, dynamic>>({
        'phone': session.phoneE164,
        'code': smsCode,
      });
    } catch (e) {
      throw AuthFailure.from(e, verifying: true);
    }
    try {
      await _auth.currentUser?.reload();
    } catch (_) {
      // The change is saved server-side; a stale local copy refreshes on its own.
    }
  }

  /// Returns null when the user closes the Google sheet.
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) return await _auth.signInWithPopup(GoogleAuthProvider());
      final iosClientId = defaultTargetPlatform == TargetPlatform.iOS
          ? DefaultFirebaseOptions.currentPlatform.iosClientId
          : null;
      if (defaultTargetPlatform == TargetPlatform.iOS && iosClientId == null) {
        // GoogleService-Info.plist has no CLIENT_ID until the Google provider is
        // enabled in the Firebase console and `flutterfire configure` re-run.
        throw const AuthFailure(AuthFailureReason.providerUnavailable, 'missing iOS client id');
      }
      final account = await GoogleSignIn(clientId: iosClientId, scopes: const ['email']).signIn();
      if (account == null) return null;
      final tokens = await account.authentication;
      return await _auth.signInWithCredential(GoogleAuthProvider.credential(
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      ));
    } catch (e) {
      final failure = AuthFailure.from(e);
      if (failure.reason == AuthFailureReason.cancelled) return null;
      throw failure;
    }
  }

  /// Sign in with Apple via Firebase's provider flow (handles the nonce).
  /// Offered on iOS only until an Apple Services ID exists for web/Android.
  Future<UserCredential?> signInWithApple() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    try {
      return kIsWeb ? await _auth.signInWithPopup(provider) : await _auth.signInWithProvider(provider);
    } catch (e) {
      final failure = AuthFailure.from(e);
      if (failure.reason == AuthFailureReason.cancelled) return null;
      throw failure;
    }
  }

  static bool get appleSignInAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn().signOut();
      } catch (_) {
        // Not signed in with Google, or Google isn't configured — nothing to do.
      }
    }
    await _auth.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(firebaseAuthProvider), ref.watch(functionsProvider)),
);

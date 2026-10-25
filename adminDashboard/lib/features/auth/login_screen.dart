import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/country_codes.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/theme/app_spacing.dart';
import 'package:golden_gift/core/utils/validators.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';

enum LoginMethod { email, phone }

/// Sign-in (SRS §9). Staff use email + password; partners (Phase 8) use the
/// phone number of their app account with the same WhatsApp / SMS code as the
/// app (`sendOtp` → `verifyOtp` → custom token). Access itself is decided by
/// the claims (AdminScaffold shows "not an admin" for other accounts).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  LoginMethod _method = LoginMethod.email;
  PhoneCodeSession? _session;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_form.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.code) {
              'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
                'Wrong email or password.',
              'too-many-requests' => 'Too many attempts. Try again later.',
              'operation-not-allowed' => 'Email sign-in is not enabled for this project.',
              'network-request-failed' => 'No connection.',
              _ => 'Sign-in failed (${e.code}).',
            });
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = phoneFailureMessage(e.reason));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithEmail() => _run(() async {
        await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(
              email: _email.text.trim(),
              password: _password.text,
            );
      });

  Future<void> _sendCode() => _run(() async {
        final session =
            await ref.read(authRepositoryProvider).sendCode(Validators.e164(_phone.text, CountryCodes.iraq));
        if (mounted) setState(() => _session = session);
      });

  Future<void> _verifyCode() => _run(() async {
        await ref.read(authRepositoryProvider).confirmCode(_session!, _code.text.trim());
      });

  void _switch(LoginMethod m) => setState(() {
        _method = m;
        _error = null;
        _session = null;
        _code.clear();
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.card_giftcard, size: 48, color: scheme.primary),
                        const SizedBox(height: AppSpacing.sm),
                        Text('Golden Gift Admin',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: AppSpacing.lg),
                        SegmentedButton<LoginMethod>(
                          segments: const [
                            ButtonSegment(value: LoginMethod.email, label: Text('Staff (email)'), icon: Icon(Icons.mail_outline)),
                            ButtonSegment(value: LoginMethod.phone, label: Text('Partner (phone)'), icon: Icon(Icons.storefront_outlined)),
                          ],
                          selected: {_method},
                          onSelectionChanged: _busy ? null : (s) => _switch(s.single),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (_method == LoginMethod.email) ..._emailFields() else ..._phoneFields(),
                        if (_error != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(_error!, key: const ValueKey('login-error'), style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FilledButton(
                          key: const ValueKey('login-submit'),
                          onPressed: _busy
                              ? null
                              : _method == LoginMethod.email
                                  ? _signInWithEmail
                                  : (_session == null ? _sendCode : _verifyCode),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_method == LoginMethod.email
                                  ? 'Sign in'
                                  : (_session == null ? 'Send code' : 'Verify and sign in')),
                        ),
                        if (_method == LoginMethod.phone && _session != null)
                          TextButton(
                            onPressed: _busy ? null : () => setState(() => _session = null),
                            child: const Text('Use another number'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _emailFields() => [
        TextFormField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: (v) => Validators.email(v, required: true) == null ? null : 'Enter a valid email',
        ),
        const SizedBox(height: AppSpacing.md),
        TextFormField(
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _signInWithEmail(),
          validator: (v) => (v == null || v.length < 6) ? 'At least 6 characters' : null,
        ),
      ];

  List<Widget> _phoneFields() => [
        TextFormField(
          controller: _phone,
          enabled: _session == null,
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            prefixText: '+964 ',
            helperText: 'The number of your Golden Gift app account',
          ),
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          validator: (v) => Validators.phone(v, CountryCodes.iraq) == null ? null : 'Enter a valid Iraqi mobile number',
          onFieldSubmitted: (_) => _session == null ? _sendCode() : null,
        ),
        if (_session != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text('We sent a code to ${_session!.phoneE164} on WhatsApp (or SMS).'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _code,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Code'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            autofillHints: const [AutofillHints.oneTimeCode],
            validator: (v) => (v == null || v.trim().length != 6) ? 'Enter the 6-digit code' : null,
            onFieldSubmitted: (_) => _verifyCode(),
          ),
        ],
      ];
}

/// English text for the shared phone-OTP failures.
String phoneFailureMessage(AuthFailureReason reason) => switch (reason) {
      AuthFailureReason.invalidPhone => 'That number is not valid.',
      AuthFailureReason.invalidCode => 'Wrong code. Check it and try again.',
      AuthFailureReason.codeExpired => 'The code expired. Send a new one.',
      AuthFailureReason.tooManyRequests => 'Too many attempts. Try again later.',
      AuthFailureReason.network => 'No connection.',
      AuthFailureReason.deliveryFailed => "We couldn't send the code. Try again in a minute.",
      AuthFailureReason.accountDisabled => 'This account is blocked.',
      AuthFailureReason.providerUnavailable => 'Phone sign-in is not available right now.',
      AuthFailureReason.phoneInUse || AuthFailureReason.cancelled || AuthFailureReason.unknown =>
        'Sign-in failed. Please try again.',
    };

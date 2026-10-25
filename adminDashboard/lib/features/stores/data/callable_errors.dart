import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/services/callable.dart';

/// A callable invoker that resolves the real one only when a call is made, so
/// building a repository never touches Firebase (widget tests on the VM) —
/// tests override [callableInvokerProvider] with a fake.
CallableInvoker lazyCallable(Ref ref) => (name, data) => ref.read(callableInvokerProvider)(name, data);

/// `not-found` is both "this callable isn't deployed" (generic status text)
/// and a function reporting a missing record (specific message).
bool _genericNotFound(String? message) =>
    message == null ||
    message.trim().isEmpty ||
    RegExp(r'^not[ _-]?found$', caseSensitive: false).hasMatch(message.trim());

/// True when [e] means the callable is not deployed (yet) — SRS §7: the
/// dashboard degrades gracefully when a function is unavailable.
bool isCallableMissing(Object e) =>
    e is FirebaseFunctionsException &&
    (const {'unavailable', 'internal', 'unimplemented'}.contains(e.code) ||
        (e.code == 'not-found' && _genericNotFound(e.message)));

/// English message for a failed Phase 8 callable.
String callableErrorMessage(String functionName, Object e, {String action = 'save the change'}) {
  if (isCallableMissing(e)) return 'The $functionName function is not deployed yet.';
  if (e is FirebaseFunctionsException) {
    final message = (e.message?.trim().isEmpty ?? true) ? null : e.message!.trim();
    final reason = e.details is Map ? (e.details as Map)['reason'] : null;
    if (reason == 'awaiting_payment') {
      return "This order is still waiting for its online payment — don't prepare it until it's paid.";
    }
    return switch (e.code) {
      'resource-exhausted' => 'Too many attempts — try again in a few minutes.',
      'permission-denied' => 'Your role is not allowed to do this.${message == null ? '' : ' ($message)'}',
      'unauthenticated' => 'Your session has expired — sign in again.',
      'not-found' => 'Not found: ${message ?? 'the record no longer exists'}.',
      'invalid-argument' => 'Rejected by the server: ${message ?? 'invalid input'}.',
      'failed-precondition' => 'Not possible right now: ${message ?? e.code}.',
      'already-exists' => 'Already done: ${message ?? e.code}.',
      _ => 'Could not $action: ${message ?? e.code}.',
    };
  }
  return 'Could not $action: $e';
}

import 'package:cloud_functions/cloud_functions.dart';

/// `not-found` is what the client sees both when the callable isn't deployed
/// and when a deployed function reports a missing user / wallet. The first
/// carries only the generic status text.
bool _genericNotFound(String? message) =>
    message == null || message.trim().isEmpty || RegExp(r'^not[ _-]?found$', caseSensitive: false).hasMatch(message.trim());

/// True when [e] means the callable [e] came from isn't deployed (yet).
bool isFunctionMissing(Object e) =>
    e is FirebaseFunctionsException &&
    (const {'unavailable', 'internal', 'unimplemented'}.contains(e.code) || (e.code == 'not-found' && _genericNotFound(e.message)));

/// `failed-precondition` with `details.reason` (e.g. `insufficient_funds`).
String? functionErrorReason(Object e) {
  if (e is! FirebaseFunctionsException) return null;
  final details = e.details;
  return details is Map ? details['reason']?.toString() : null;
}

/// English message for a failed callable (SRS §7: the dashboard degrades
/// gracefully when a function is unavailable).
String functionErrorMessage(String functionName, Object e, {String action = 'save the change'}) {
  if (isFunctionMissing(e)) return 'The $functionName function is not deployed yet.';
  if (e is FirebaseFunctionsException) {
    final message = (e.message?.trim().isEmpty ?? true) ? null : e.message!.trim();
    return switch (e.code) {
      'permission-denied' => 'Your admin role is not allowed to do this.${message == null ? '' : ' ($message)'}',
      'unauthenticated' => 'Your session has expired — sign in again.',
      'not-found' => 'Not found: ${message ?? 'the record no longer exists'}.',
      'invalid-argument' => 'Rejected by the server: ${message ?? 'invalid input'}.',
      'failed-precondition' => 'Not possible right now: ${message ?? functionErrorReason(e) ?? e.code}.',
      _ => 'Could not $action: ${message ?? e.code}.',
    };
  }
  return 'Could not $action: $e';
}

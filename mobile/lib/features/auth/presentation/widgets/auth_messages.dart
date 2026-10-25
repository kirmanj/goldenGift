import '../../../../core/utils/validators.dart';
import '../../../../l10n/l10n.dart';
import '../../data/datasources/auth_repository.dart';

/// Localized text for validation and auth failures (SRS AUTH-8: inline,
/// error-red, under the field).
extension AuthMessages on AppLocalizations {
  String? validation(ValidationError? error) => switch (error) {
        null => null,
        ValidationError.required => errorRequired,
        ValidationError.nameTooShort || ValidationError.nameTooLong => errorNameLength,
        ValidationError.invalidEmail => errorInvalidEmail,
        ValidationError.invalidPhone => errorInvalidPhone,
        ValidationError.invalidReferralCode => errorInvalidReferralCode,
      };

  String authFailure(AuthFailureReason reason) => switch (reason) {
        AuthFailureReason.invalidPhone => errorInvalidPhone,
        AuthFailureReason.invalidCode => authErrorInvalidCode,
        AuthFailureReason.codeExpired => authErrorCodeExpired,
        AuthFailureReason.tooManyRequests => authErrorTooManyRequests,
        AuthFailureReason.network => authErrorNetwork,
        AuthFailureReason.deliveryFailed => authErrorDeliveryFailed,
        AuthFailureReason.phoneInUse => authErrorPhoneInUse,
        AuthFailureReason.providerUnavailable => authErrorUnavailable,
        AuthFailureReason.accountDisabled => authErrorAccountDisabled,
        AuthFailureReason.cancelled || AuthFailureReason.unknown => somethingWentWrong,
      };
}

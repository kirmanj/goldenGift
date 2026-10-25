import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/country_codes.dart';
import 'package:golden_gift/core/utils/validators.dart';

/// SRS AUTH-8 — invalid input must be caught before any Firebase call.
void main() {
  const iraq = CountryCodes.iraq;
  final turkey = CountryCodes.byDialCode('+90');

  group('name: 2–50 characters', () {
    test('empty / whitespace → required', () {
      expect(Validators.name(''), ValidationError.required);
      expect(Validators.name('   '), ValidationError.required);
      expect(Validators.name(null), ValidationError.required);
    });
    test('too short / too long', () {
      expect(Validators.name('A'), ValidationError.nameTooShort);
      expect(Validators.name('A' * 51), ValidationError.nameTooLong);
    });
    test('valid incl. Arabic / Kurdish and trimming', () {
      expect(Validators.name('Jo'), isNull);
      expect(Validators.name('  سارا أحمد  '), isNull);
      expect(Validators.name('کرمانج'), isNull);
      expect(Validators.name('A' * 50), isNull);
    });
  });

  group('email: optional, valid when given', () {
    test('empty is fine unless required', () {
      expect(Validators.email(''), isNull);
      expect(Validators.email(null), isNull);
      expect(Validators.email('', required: true), ValidationError.required);
    });
    for (final ok in ['sara@example.com', 'a.b+gift@mail.co.uk', 'x_y@sub.domain.iq']) {
      test('valid: $ok', () => expect(Validators.email(ok), isNull));
    }
    for (final bad in ['sara', 'sara@', '@example.com', 'sara@example', 'sa ra@example.com', 'sara@@example.com', 'a..b@example.com', 'sara@-example.com']) {
      test('invalid: $bad', () => expect(Validators.email(bad), ValidationError.invalidEmail));
    }
  });

  group('phone', () {
    test('normalizes trunk 0, spaces and Arabic/Persian digits', () {
      expect(Validators.normalizePhone('0750 123 4567'), '7501234567');
      expect(Validators.normalizePhone('٠٧٥٠١٢٣٤٥٦٧'), '7501234567');
      expect(Validators.normalizePhone('۷۵۰۱۲۳۴۵۶۷'), '7501234567');
      expect(Validators.normalizePhone('(750) 123-4567'), '7501234567');
    });
    test('Iraq: 10 digits starting with 7', () {
      expect(Validators.phone('7501234567', iraq), isNull);
      expect(Validators.phone('07701234567', iraq), isNull);
      expect(Validators.phone('750123456', iraq), ValidationError.invalidPhone);
      expect(Validators.phone('75012345678', iraq), ValidationError.invalidPhone);
      expect(Validators.phone('6501234567', iraq), ValidationError.invalidPhone);
      expect(Validators.phone('', iraq), ValidationError.required);
    });
    test('other countries use their own length', () {
      expect(Validators.phone('5321234567', turkey), isNull);
      expect(Validators.phone('532123456', turkey), ValidationError.invalidPhone);
      expect(Validators.phone('12345678', CountryCodes.byDialCode('+961')), isNull);
      expect(Validators.phone('1234567', CountryCodes.byDialCode('+961')), isNull);
    });
    test('E.164', () {
      expect(Validators.e164('0750 123 4567', iraq), '+9647501234567');
    });
    test('unknown dial code falls back to Iraq', () {
      expect(CountryCodes.byDialCode('+000'), iraq);
    });
  });

  group('referral code: optional, 6 letters/digits', () {
    test('empty is fine', () => expect(Validators.referralCode(''), isNull));
    test('normalized to upper case without spaces', () {
      expect(Validators.normalizeReferralCode(' ab3 d9k '), 'AB3D9K');
      expect(Validators.referralCode('ab3d9k'), isNull);
    });
    test('wrong length or characters', () {
      expect(Validators.referralCode('AB3D9'), ValidationError.invalidReferralCode);
      expect(Validators.referralCode('AB3D9KX'), ValidationError.invalidReferralCode);
      expect(Validators.referralCode('AB-D9K'), ValidationError.invalidReferralCode);
    });
  });
}

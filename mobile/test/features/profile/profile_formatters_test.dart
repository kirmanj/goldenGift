import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/features/profile/presentation/widgets/profile_formatters.dart';

void main() {
  group('formatPhoneForDisplay', () {
    test('groups an Iraqi number 3-3-4', () {
      expect(formatPhoneForDisplay('+964', '7505448229'), '+964 750 544 8229');
    });

    test('handles shorter national numbers', () {
      expect(formatPhoneForDisplay('+963', '912345678'), '+963 912 345 678');
      expect(formatPhoneForDisplay('+961', '1234567'), '+961 123 4567');
      expect(formatPhoneForDisplay('+965', '1234'), '+965 1234');
    });

    test('ignores spaces and empty numbers', () {
      expect(formatPhoneForDisplay('+964', '750 544 8229'), '+964 750 544 8229');
      expect(formatPhoneForDisplay('+964', ''), '+964');
    });
  });

  group('birthday', () {
    test('formats dd/MM/yyyy with Western digits', () {
      expect(formatBirthday(DateTime(1995, 3, 5)), '05/03/1995');
    });

    test('is stored as UTC noon of the picked day', () {
      final value = birthdayValue(DateTime(2001, 12, 31));
      expect(value.isUtc, isTrue);
      expect([value.year, value.month, value.day, value.hour], [2001, 12, 31, 12]);
    });

    test('sameDay compares calendar days only', () {
      expect(sameDay(DateTime(1995, 3, 5, 23), DateTime.utc(1995, 3, 5, 12)), isTrue);
      expect(sameDay(DateTime(1995, 3, 5), DateTime(1995, 3, 6)), isFalse);
      expect(sameDay(null, null), isTrue);
      expect(sameDay(null, DateTime(1995)), isFalse);
    });
  });
}

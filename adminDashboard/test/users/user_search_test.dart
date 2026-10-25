import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift_admin/features/users/data/user_search.dart';
import 'package:golden_gift_admin/features/users/data/users_admin_repository.dart';

import 'users_test_helpers.dart';

void main() {
  group('normalizeIraqiPhone', () {
    const expected = PhoneSearch(e164: '+9647501234567', national: '7501234567');

    test('accepts every common Iraqi spelling', () {
      for (final input in [
        '07501234567',
        '0750 123 4567',
        '750-123-4567',
        '7501234567',
        '+9647501234567',
        '+964 750 123 4567',
        '00964 750 123 4567',
        '9647501234567',
        '+964 0750 123 4567',
        '(0750) 123-4567',
        '٠٧٥٠١٢٣٤٥٦٧', // Arabic-Indic digits
        '۰۷۵۰۱۲۳۴۵۶۷', // Extended Arabic-Indic digits
      ]) {
        expect(normalizeIraqiPhone(input), expected, reason: input);
      }
    });

    test('rejects landlines, short numbers, other countries and emails', () {
      for (final input in ['', '066 123 4567', '75012345', '75012345678', '+44 7700 900123', 'a@b.com', '+1 750 123 4567']) {
        expect(normalizeIraqiPhone(input), isNull, reason: input);
      }
    });
  });

  group('UserSearchQuery.parse', () {
    test('empty input lists the newest users', () {
      expect(UserSearchQuery.parse('   ').mode, UserSearchMode.recent);
    });

    test('an Iraqi phone matches the national number and the E.164 form', () {
      final q = UserSearchQuery.parse(' 0750 123 4567 ');
      expect(q.mode, UserSearchMode.phone);
      expect(q.text, '+9647501234567');
      expect(q.phoneValues, ['7501234567', '+9647501234567']);
      expect(q.isIraqiPhone, isTrue);
    });

    test('other phone-looking input is matched as typed', () {
      final q = UserSearchQuery.parse('+44 7700 900123');
      expect(q.mode, UserSearchMode.phone);
      expect(q.isIraqiPhone, isFalse);
      expect(q.phoneValues, ['447700900123', '+447700900123']);
    });

    test('an email is lower-cased', () {
      final q = UserSearchQuery.parse(' Sara@Example.COM ');
      expect(q.mode, UserSearchMode.email);
      expect(q.text, 'sara@example.com');
    });

    test('anything else is a case-sensitive name prefix', () {
      expect(UserSearchQuery.parse('Sara').mode, UserSearchMode.name);
      expect(UserSearchQuery.parse('Sara').text, 'Sara');
      // Too few digits to be a phone.
      expect(UserSearchQuery.parse('12').mode, UserSearchMode.name);
      expect(UserSearchQuery.parse('Sara').description, contains('case-sensitive'));
    });
  });

  group('UsersAdminRepository.watchList', () {
    Future<FakeFirebaseFirestore> seeded() async {
      final db = FakeFirebaseFirestore();
      await seedUser(db, 'u1', userMap(createdAt: DateTime(2026, 10, 1)));
      await seedUser(db, 'u2',
          userMap(name: 'Karwan', phone: '+9647709998877', email: 'karwan@example.com', createdAt: DateTime(2026, 10, 3)));
      await seedUser(db, 'u3', userMap(name: 'sarbast', phone: '7811112222', email: 'x@y.z', createdAt: DateTime(2026, 10, 2)));
      return db;
    }

    Future<List<String>> ids(FakeFirebaseFirestore db, String input, {int limit = 50}) async => [
          for (final u in await UsersAdminRepository(db, FakeCalls().call).watchList(UserSearchQuery.parse(input), limit: limit).first)
            u.uid,
        ];

    test('recent: newest first, limited to the page', () async {
      final db = await seeded();
      expect(await ids(db, ''), ['u2', 'u3', 'u1']);
      expect(await ids(db, '', limit: 2), ['u2', 'u3']);
    });

    test('phone: finds national-number and E.164 docs from any spelling', () async {
      final db = await seeded();
      expect(await ids(db, '0750 123 4567'), ['u1']);
      expect(await ids(db, '+964 770 999 8877'), ['u2']);
      expect(await ids(db, '0770 000 0000'), isEmpty);
    });

    test('email: exact, case-insensitive input', () async {
      final db = await seeded();
      expect(await ids(db, 'KARWAN@example.com'), ['u2']);
    });

    test('name: prefix, case-sensitive', () async {
      final db = await seeded();
      expect(await ids(db, 'Sar'), ['u1']);
      expect(await ids(db, 'sar'), ['u3']);
      expect(await ids(db, 'Kar'), ['u2']);
    });

    test('a minimal user doc still parses and matches by name', () async {
      final db = FakeFirebaseFirestore();
      await seedUser(db, 'u9', {'name': 'Old', 'phone': '7500000000', 'createdAt': Timestamp.fromDate(DateTime(2025))});
      expect(await ids(db, 'Old'), ['u9']);
    });
  });
}

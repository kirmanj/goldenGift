import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/models/gift_card_model.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/gift_cards/data/gift_cards_admin_repository.dart';
import 'package:golden_gift_admin/features/stores/data/callable_errors.dart';

import '../products/products_test_helpers.dart' show RecordingFirestore;
import '../seller/phase8_test_harness.dart';

GiftCardTemplateModel template({
  String id = 't1',
  String name = 'Birthday',
  String? ar,
  String? start,
  String? end,
  List<int> presets = const [15000, 25000],
  int min = 0,
  int max = 0,
  int sortOrder = 0,
  bool active = true,
}) =>
    GiftCardTemplateModel(
      id: id,
      name: LocalizedText(name, ar: ar),
      gradientStart: start,
      gradientEnd: end,
      presetAmounts: presets,
      minAmount: min,
      maxAmount: max,
      sortOrder: sortOrder,
      isActive: active,
    );

Future<void> seedCard(FirebaseFirestore db, String id,
        {String code = 'ABCDEFGHJKLM', String status = 'sent', String templateId = 't1', DateTime? createdAt, int balance = 25000}) =>
    db.doc(FirestorePaths.giftCardDoc(id)).set({
      'code': code,
      'templateId': templateId,
      'amount': 25000,
      'balance': balance,
      'purchaserUid': 'buyer-1',
      'recipientName': 'Lana',
      'recipientPhone': '+9647701112233',
      'status': status,
      'orderId': 'o1',
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime(2026, 10, 1)),
    });

void main() {
  group('template rules', () {
    test('a valid template passes; presets are normalised', () {
      expect(validateTemplate(template()), isEmpty);
      expect(validateTemplate(template(presets: const [], min: 1000, max: 500000)), isEmpty);
      expect(normalizePresetAmounts([25000, 0, 15000, 25000, -5]), [15000, 25000]);
    });

    test('name, gradient hex and gradient pairs', () {
      expect(validateTemplate(template(name: ' ')), contains('English name is required.'));
      expect(validateTemplate(template(start: '#12345', end: '#123456')), contains('Gradient start must be a #RRGGBB colour.'));
      expect(validateTemplate(template(start: '#C9A227')),
          contains('Set both gradient colours, or neither for the gold shimmer.'));
      expect(validateTemplate(template(start: '#C9A227', end: '#9c7a14')), isEmpty);
      expect(isHexColor('#C9A227'), isTrue);
      expect(isHexColor('C9A227'), isFalse);
      expect(normalizeHex('c9a227'), '#C9A227');
      expect(normalizeHex('  '), isNull);
      expect(colorFromHex('#zzzzzz'), isNull);
    });

    test('amount rules: positive unique presets, custom min ≥ 1,000 and max ≥ min, something to buy', () {
      expect(validateTemplate(template(presets: const [0])), contains('Preset amounts must be positive.'));
      expect(validateTemplate(template(presets: const [5000, 5000])), contains('Preset amounts must be unique.'));
      expect(validateTemplate(template(min: 500, max: 9000)).single, startsWith('The minimum custom amount is at least'));
      expect(validateTemplate(template(min: 5000, max: 1000)), contains('The maximum custom amount must be at least the minimum.'));
      expect(validateTemplate(template(presets: const [])), contains('Add a preset amount or allow custom amounts.'));
      expect(validateTemplate(template(sortOrder: -1)), contains('Sort order cannot be negative.'));
    });

    test('the amounts label', () {
      expect(templateAmountsLabel(template(min: 10000, max: 500000)), '15,000 · 25,000 or custom 10,000–500,000 IQD');
    });
  });

  group('template writes', () {
    test('create = template + audit in ONE batch', () async {
      final db = RecordingFirestore();
      await GiftCardsAdminRepository(db, FakeCallables().call)
          .createTemplate(template(start: '#C9A227', end: '#9C7A14'), adminUid: 'admin-1');
      expect(db.commits, hasLength(1));
      expect(db.commits.single.first, 'set gift_card_templates/t1');
      expect(db.commits.single.last, startsWith('set admin_audit_log/'));
      final saved = (await db.doc('gift_card_templates/t1').get()).data()!;
      expect(saved['presetAmounts'], [15000, 25000]);
      expect(saved['gradientStart'], '#C9A227');
      expect(saved['createdAt'], isNotNull);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'giftCardTemplate.create');
      expect(audit['target'], 'gift_card_templates/t1');
    });

    test('create refuses an invalid template and writes nothing', () async {
      final db = RecordingFirestore();
      await expectLater(
        GiftCardsAdminRepository(db, FakeCallables().call).createTemplate(template(presets: const []), adminUid: 'a'),
        throwsA(isA<GiftCardValidationException>()),
      );
      expect(db.commits, isEmpty);
    });

    test('update writes before / after and deletes a cleared translation', () async {
      final db = RecordingFirestore();
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      final before = template(ar: 'عيد ميلاد');
      await repo.createTemplate(before, adminUid: 'admin-1');
      db.commits.clear();
      await repo.updateTemplate(before, template(name: 'Happy birthday', presets: const [10000]), adminUid: 'admin-1');
      expect(db.commits.single, hasLength(2));
      final saved = (await db.doc('gift_card_templates/t1').get()).data()!;
      expect(saved['name'], 'Happy birthday');
      expect(saved.containsKey('nameAr'), isFalse);
      expect(saved['presetAmounts'], [10000]);
      final audit = (await auditEntries(db)).firstWhere((a) => a['action'] == 'giftCardTemplate.update');
      expect((audit['before'] as Map)['name'], 'Birthday');
      expect((audit['after'] as Map)['name'], 'Happy birthday');
    });

    test('delete is refused while an issued card references the template', () async {
      final db = RecordingFirestore();
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      await repo.createTemplate(template(), adminUid: 'admin-1');
      await seedCard(db, 'c1');
      db.commits.clear();
      await expectLater(repo.deleteTemplate(template(), adminUid: 'admin-1'), throwsA(isA<TemplateInUseException>()));
      expect(db.commits, isEmpty);
      expect((await db.doc('gift_card_templates/t1').get()).exists, isTrue);

      await repo.setTemplateActive(template(), false, adminUid: 'admin-1');
      expect((await db.doc('gift_card_templates/t1').get()).data()!['isActive'], isFalse);
      expect(db.commits.single, hasLength(2));
    });

    test('an unused template is deleted with its audit entry', () async {
      final db = RecordingFirestore();
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      await repo.createTemplate(template(id: 't2'), adminUid: 'admin-1');
      await seedCard(db, 'c1', templateId: 'other');
      db.commits.clear();
      await repo.deleteTemplate(template(id: 't2'), adminUid: 'admin-1');
      expect(db.commits.single.first, 'delete gift_card_templates/t2');
      expect((await auditEntries(db)).map((a) => a['action']), contains('giftCardTemplate.delete'));
    });

    test('reorder rewrites sortOrder of moved templates in one batch with one entry', () async {
      final db = RecordingFirestore();
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      for (final (i, id) in ['a', 'b', 'c'].indexed) {
        await repo.createTemplate(template(id: id, sortOrder: i), adminUid: 'admin-1');
      }
      db.commits.clear();
      final list = GiftCardsAdminRepository.sortTemplates(await repo.watchTemplates().first);
      final moved = await repo.reorder([list[1], list[0], list[2]], adminUid: 'admin-1');
      expect(moved, 2);
      expect(db.commits.single, hasLength(3)); // 2 updates + audit
      final order = GiftCardsAdminRepository.sortTemplates(await repo.watchTemplates().first).map((t) => t.id);
      expect(order, ['b', 'a', 'c']);
      expect((await auditEntries(db)).last['action'], 'giftCardTemplate.reorder');
    });
  });

  group('issued cards', () {
    test('lists newest first, filters by status and finds an exact normalised code', () async {
      final db = FakeFirebaseFirestore();
      await seedCard(db, 'old', code: 'AAAABBBBCCCC', createdAt: DateTime(2026, 9, 1));
      await seedCard(db, 'new', code: 'DDDDEEEEFFFF', status: 'redeemed', createdAt: DateTime(2026, 10, 2));
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      expect((await repo.watchCards().first).map((c) => c.id), ['new', 'old']);
      expect((await repo.watchCards(status: GiftCardStatus.sent).first).map((c) => c.id), ['old']);
      expect((await repo.watchByCode(' aaaa-bbbb-cccc ').first).map((c) => c.id), ['old']);
      expect(await repo.watchByCode('AAAABBBB').first, isEmpty);
    });

    test('disable = status + reason + audit in one batch; only pending / sent cards', () async {
      final db = RecordingFirestore();
      await seedCard(db, 'c1');
      await seedCard(db, 'c2', status: 'redeemed');
      final repo = GiftCardsAdminRepository(db, FakeCallables().call);
      final card = (await repo.watchCard('c1').first)!;
      await repo.disableCard(card, reason: ' Reported stolen ', adminUid: 'admin-1');
      expect(db.commits.single, ['update gift_cards/c1', startsWith('set admin_audit_log/')]);
      final saved = (await db.doc('gift_cards/c1').get()).data()!;
      expect(saved['status'], 'disabled');
      expect(saved['disabledReason'], 'Reported stolen');
      expect(saved['disabledBy'], 'admin-1');
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'giftCard.disable');
      expect(audit['before'], {'status': 'sent', 'balance': 25000});
      expect(audit['after'], {'status': 'disabled', 'reason': 'Reported stolen'});

      final redeemed = (await repo.watchCard('c2').first)!;
      expect(() => repo.disableCard(redeemed, reason: 'Nope', adminUid: 'admin-1'), throwsStateError);
      expect(() => repo.disableCard(card, reason: 'x', adminUid: 'admin-1'), throwsArgumentError);
      expect(canDisableCard(GiftCardStatus.pending), isTrue);
      expect(canDisableCard(GiftCardStatus.expired), isFalse);
    });
  });

  group('manual issue', () {
    final now = DateTime(2026, 10, 21, 10);
    ManualGiftCardIssue req({int amount = 25000, String name = 'Lana', String? phone, String? email, String message = '', DateTime? expires}) =>
        ManualGiftCardIssue(
          templateId: 't1',
          amount: amount,
          recipientName: name,
          recipientPhone: phone,
          recipientEmail: email,
          message: message,
          expiresAt: expires ?? ManualGiftCardIssue.defaultExpiry(now),
        );

    test('validates the amount against the template unless overridden', () {
      expect(req().validate(template: template(), overrideAmount: false, now: now), isEmpty);
      final bad = req(amount: 30000).validate(template: template(), overrideAmount: false, now: now);
      expect(bad.single, contains('does not accept 30,000 IQD'));
      expect(req(amount: 30000).validate(template: template(), overrideAmount: true, now: now), isEmpty);
      expect(req(amount: 30000).validate(template: template(min: 10000, max: 50000), overrideAmount: false, now: now), isEmpty);
      expect(req().validate(template: null, overrideAmount: false, now: now), contains('Choose a template.'));
    });

    test('recipient, message and expiry rules', () {
      final errors = req(
        name: 'L',
        phone: '123',
        email: 'not-an-email',
        message: 'x' * 201,
        expires: now.subtract(const Duration(days: 1)),
      ).validate(template: template(), overrideAmount: false, now: now);
      expect(errors, containsAll([
        'Recipient name is required.',
        'The recipient phone is not valid.',
        'The recipient email is not valid.',
        'Keep the message under 200 characters.',
        'The expiry must be in the future.',
      ]));
    });

    test('payload: E.164 phone, lower-case email, ISO expiry, empty fields dropped', () {
      final expires = DateTime.utc(2027, 10, 21, 20, 59, 59);
      final p = req(phone: '0770 111 2233', email: ' Lana@Example.COM ', message: ' Enjoy! ', expires: expires).toPayload();
      expect(p, {
        'templateId': 't1',
        'amount': 25000,
        'recipientName': 'Lana',
        'recipientPhone': '+9647701112233',
        'recipientEmail': 'lana@example.com',
        'message': 'Enjoy!',
        'expiresAt': '2027-10-21T20:59:59.000Z',
      });
      expect(req().toPayload().containsKey('recipientPhone'), isFalse);
      expect(ManualGiftCardIssue.defaultExpiry(now), DateTime(2027, 10, 21, 23, 59, 59));
    });

    test('issue calls adminIssueGiftCard and returns the formatted code', () async {
      final calls = FakeCallables()..responses['adminIssueGiftCard'] = {'giftCardId': 'g9', 'code': 'QWERTYUIOPAS'};
      final issued = await GiftCardsAdminRepository(FakeFirebaseFirestore(), calls.call).issue(req());
      expect(calls.calls.single.$1, 'adminIssueGiftCard');
      expect(issued.giftCardId, 'g9');
      expect(issued.formattedCode, 'QWER-TYUI-OPAS');
    });

    test('a missing function reads as "not deployed yet"', () {
      expect(callableErrorMessage('adminIssueGiftCard', FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND')),
          'The adminIssueGiftCard function is not deployed yet.');
      expect(callableErrorMessage('adminIssueGiftCard', FirebaseFunctionsException(code: 'unavailable', message: 'x')),
          'The adminIssueGiftCard function is not deployed yet.');
      expect(callableErrorMessage('x', FirebaseFunctionsException(code: 'not-found', message: 'Template t1 not found')),
          'Not found: Template t1 not found.');
    });

    test('roles', () {
      expect(GiftCardsAccess.canIssue(AdminRole.finance), isTrue);
      expect(GiftCardsAccess.canIssue(AdminRole.content), isFalse);
      expect(GiftCardsAccess.canEditTemplates(AdminRole.content), isTrue);
      expect(GiftCardsAccess.canOverrideAmount(AdminRole.ops), isFalse);
      expect(GiftCardsAccess.canOverrideAmount(AdminRole.superAdmin), isTrue);
    });
  });
}

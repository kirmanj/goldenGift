import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/features/gift_cards/data/gift_cards_admin_repository.dart';
import 'package:golden_gift_admin/features/gift_cards/gift_cards_screen.dart';

import '../seller/phase8_test_harness.dart';
import 'gift_cards_data_test.dart' show seedCard, template;

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  final repo = GiftCardsAdminRepository(db, FakeCallables().call);
  await repo.createTemplate(template(id: 't1', name: 'Birthday', sortOrder: 0), adminUid: 'seed');
  await repo.createTemplate(template(id: 't2', name: 'Wedding', sortOrder: 1, start: '#1A1A1C', end: '#C9A227'), adminUid: 'seed');
  await seedCard(db, 'c1', code: 'AAAABBBBCCCC', createdAt: DateTime(2026, 10, 2));
  await seedCard(db, 'c2', code: 'DDDDEEEEFFFF', status: 'redeemed', createdAt: DateTime(2026, 10, 1));
  return db;
}

Finder byKeyField(String key) => find.byKey(ValueKey(key));

Future<void> openIssuedTab(WidgetTester tester) async {
  await tester.tap(find.text('Issued cards'));
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

void main() {
  testWidgets('templates tab: sortOrder, create through the dialog (batch + audit)', (tester) async {
    final db = await seeded();
    final before = (await auditEntries(db)).length;
    await pumpPhase8(tester, const GiftCardsScreen(), db: db, size: const Size(1440, 1200));

    final birthday = tester.getTopLeft(find.text('Birthday').last);
    final wedding = tester.getTopLeft(find.text('Wedding').last);
    expect(birthday.dx < wedding.dx || birthday.dy < wedding.dy, isTrue);

    await tester.tap(find.text('New template'));
    await settle(tester);
    // Save with nothing → the rules list shows.
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.textContaining('English name is required.'), findsOneWidget);

    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Name · English *'), 'Eid');
    await tester.enterText(byKeyField('presetInput'), '50000');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('50,000 IQD'), findsWidgets); // chip + live preview
    await tester.tap(find.text('Create'));
    await settle(tester);

    final docs = (await db.collection('gift_card_templates').get()).docs;
    final created = docs.firstWhere((d) => d.data()['name'] == 'Eid').data();
    expect(created['presetAmounts'], [50000]);
    expect(created['sortOrder'], 2);
    final audit = await auditEntries(db);
    expect(audit.length, before + 1);
    expect(audit.last['action'], 'giftCardTemplate.create');
  });

  testWidgets('deleting a template that cards use offers to deactivate it', (tester) async {
    final db = await seeded();
    await pumpPhase8(tester, const GiftCardsScreen(), db: db, size: const Size(1440, 1200));
    await tester.tap(find.byTooltip('Delete template').first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('This template is in use'), findsOneWidget);
    await tester.tap(find.text('Deactivate'));
    await settle(tester);
    expect((await db.doc('gift_card_templates/t1').get()).data()!['isActive'], isFalse);
    expect((await db.doc('gift_card_templates/t1').get()).exists, isTrue);
  });

  testWidgets('issued cards: list, status filter, code search, drawer and disable', (tester) async {
    final db = await seeded();
    await pumpPhase8(tester, const GiftCardsScreen(), db: db, size: const Size(1440, 1200));
    await openIssuedTab(tester);
    expect(find.text('AAAA-BBBB-CCCC'), findsOneWidget);
    expect(find.text('DDDD-EEEE-FFFF'), findsOneWidget);

    // Code search (typed lower-case without dashes).
    await tester.enterText(byKeyField('cardCodeSearch'), 'ddddeeeeffff');
    await tester.tap(find.text('Find'));
    await settle(tester);
    expect(find.text('AAAA-BBBB-CCCC'), findsNothing);
    expect(find.text('DDDD-EEEE-FFFF'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear code search'));
    await settle(tester);

    // Status filter.
    await tester.tap(find.text('All statuses'));
    await settle(tester);
    await tester.tap(find.text('Redeemed').last);
    await settle(tester);
    expect(find.text('AAAA-BBBB-CCCC'), findsNothing);
    await tester.tap(find.text('Redeemed').first);
    await settle(tester);
    await tester.tap(find.text('All statuses').last);
    await settle(tester);

    // Wide rows carry the purchaser / order links.
    expect(find.widgetWithText(TextButton, 'Purchaser'), findsNWidgets(2));
    expect(find.widgetWithText(TextButton, 'Order'), findsNWidgets(2));

    // Drawer (side panel at 1440) + disable with a reason.
    await tester.tap(find.text('AAAA-BBBB-CCCC'));
    await settle(tester);
    expect(find.text('Disable card'), findsOneWidget);
    await tester.tap(find.text('Disable card'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await settle(tester);
    expect(find.text('A reason is required.'), findsOneWidget);
    await tester.enterText(byKeyField('reasonField'), 'Customer reported it lost');
    await tester.tap(find.widgetWithText(FilledButton, 'Disable'));
    await settle(tester);
    final saved = (await db.doc('gift_cards/c1').get()).data()!;
    expect(saved['status'], 'disabled');
    expect(saved['disabledReason'], 'Customer reported it lost');
    expect((await auditEntries(db)).last['action'], 'giftCard.disable');

    // The drawer's purchaser link goes to the Users module.
    await tester.tap(find.widgetWithText(TextButton, 'buyer-1'));
    await settle(tester);
    expect(find.text('visited: /users/buyer-1'), findsOneWidget);
  });

  testWidgets('manual issue sends the payload and shows the code', (tester) async {
    final db = await seeded();
    final calls = FakeCallables()..responses['adminIssueGiftCard'] = {'giftCardId': 'g9', 'code': 'QWERTYUIOPAS'};
    await pumpPhase8(tester, const GiftCardsScreen(), db: db, calls: calls, size: const Size(1440, 1400));
    await openIssuedTab(tester);
    await tester.tap(find.text('Issue gift card'));
    await settle(tester);

    await tester.tap(byKeyField('issueTemplate'));
    await settle(tester);
    await tester.tap(find.text('Birthday').last);
    await settle(tester);
    // The first preset is picked; choose the other one.
    await tester.tap(find.widgetWithText(ChoiceChip, '25,000 IQD'));
    await tester.enterText(byKeyField('issueName'), 'Lana');
    await tester.enterText(byKeyField('issuePhone'), '0770 111 2233');
    await tester.enterText(byKeyField('issueMessage'), 'Happy birthday!');
    await settle(tester);
    await tester.tap(find.text('Issue card'));
    await settle(tester);

    final payload = calls.payloadsFor('adminIssueGiftCard').single;
    expect(payload['templateId'], 't1');
    expect(payload['amount'], 25000);
    expect(payload['recipientName'], 'Lana');
    expect(payload['recipientPhone'], '+9647701112233');
    expect(payload['message'], 'Happy birthday!');
    expect(DateTime.parse(payload['expiresAt'] as String).isAfter(DateTime.now().add(const Duration(days: 360))), isTrue);
    expect(find.text('QWER-TYUI-OPAS'), findsOneWidget);
    expect(find.byTooltip('Copy code'), findsOneWidget);
  });

  testWidgets('manual issue: an amount the template does not offer is refused (non-super)', (tester) async {
    final db = await seeded();
    final calls = FakeCallables();
    await pumpPhase8(tester, const GiftCardsScreen(),
        db: db, calls: calls, session: staffSession(AdminRole.finance), size: const Size(1440, 1400));
    await openIssuedTab(tester);
    await tester.tap(find.text('Issue gift card'));
    await settle(tester);
    await tester.tap(byKeyField('issueTemplate'));
    await settle(tester);
    await tester.tap(find.text('Birthday').last);
    await settle(tester);
    await tester.enterText(byKeyField('issueAmount'), '30000');
    await tester.enterText(byKeyField('issueName'), 'Lana');
    expect(byKeyField('issueOverride'), findsNothing);
    await tester.tap(find.text('Issue card'));
    await settle(tester);
    expect(find.textContaining('does not accept 30,000 IQD'), findsOneWidget);
    expect(calls.calls, isEmpty);
  });

  testWidgets('manual issue explains a function that is not deployed', (tester) async {
    final db = await seeded();
    final calls = FakeCallables()..errors['adminIssueGiftCard'] = FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND');
    await pumpPhase8(tester, const GiftCardsScreen(), db: db, calls: calls, size: const Size(1440, 1400));
    await openIssuedTab(tester);
    await tester.tap(find.text('Issue gift card'));
    await settle(tester);
    await tester.tap(byKeyField('issueTemplate'));
    await settle(tester);
    await tester.tap(find.text('Birthday').last);
    await settle(tester);
    await tester.enterText(byKeyField('issueName'), 'Lana');
    await tester.tap(find.text('Issue card'));
    await settle(tester);
    expect(find.textContaining('The adminIssueGiftCard function is not deployed yet.'), findsOneWidget);
  });

  for (final (mode, size) in layoutMatrix) {
    testWidgets('lays out in ${mode.name} at ${size.width.toInt()} px (both tabs, drawer)', (tester) async {
      final db = await seeded();
      final errors = await errorsOutsideCoreNav(() async {
        await pumpPhase8(tester, const GiftCardsScreen(), db: db, mode: mode, size: size);
        expect(find.text('Wedding'), findsWidgets);
        await openIssuedTab(tester);
        await tester.tap(find.text('AAAA-BBBB-CCCC'));
        await settle(tester);
        expect(find.text('Disable card'), findsOneWidget);
      });
      expect(errors, isEmpty);
    });
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/models/app_settings_model.dart';

import '../profile/profile_test_harness.dart';

/// SRS §5.21: ZainCash is a mobile wallet, not a card gateway — Saved Cards
/// stays hidden until `app_settings/payments.card` is on.
void main() {
  final en = l10nFor('en');

  testWidgets('ZainCash on, card off → no Saved Cards row', (tester) async {
    await pumpProfileApp(tester, payments: const PaymentSettings(zainCash: true));
    expect(find.text(en.myWallet), findsOneWidget);
    expect(find.text(en.savedCards), findsNothing);
  });

  testWidgets('card on → Saved Cards row', (tester) async {
    await pumpProfileApp(tester, payments: const PaymentSettings(zainCash: true, card: true));
    expect(find.text(en.savedCards), findsOneWidget);
  });
}

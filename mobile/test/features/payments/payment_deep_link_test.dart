import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_gift/core/localization/kurdish_fallback_localizations.dart';
import 'package:golden_gift/core/router/app_router.dart';
import 'package:golden_gift/core/theme/app_theme.dart';
import 'package:golden_gift/features/orders/data/orders_repository.dart';
import 'package:golden_gift/features/payments/presentation/screens/payment_status_screen.dart';
import 'package:golden_gift/features/profile/presentation/providers/profile_platform_providers.dart';
import 'package:golden_gift/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/app_test_overrides.dart';
import '../../helpers/auth_fakes.dart';
import '../checkout/phase6_test_harness.dart' show FakeOrdersRepository, l10nFor;
import 'payments_test_harness.dart';

/// The gateway's way back (`zainCashReturn` → `goldengift://payment?sid=…&status=…`)
/// through the REAL app router, as Android / iOS deliver it.

Future<GoRouter> _pumpRealRouter(WidgetTester tester, {required String initialLocation}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = FakeFirebaseFirestore();
  final calls = FakePaymentCalls(db);
  await calls.call('createPaymentSession', {'purpose': 'topUp', 'amount': 25000}); // ps1
  await calls.call('createPaymentSession', {'purpose': 'topUp', 'amount': 50000}); // ps2
  final routerProvider = Provider<GoRouter>((ref) => buildAppRouter(ref, initialLocation: initialLocation));
  final container = ProviderContainer(overrides: [
    ...appTestOverridesSync(prefs, firestore: db, user: FakeUser(uid: 'u1')),
    ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository(db)),
    externalLinkOpenerProvider.overrideWithValue((_) async => true),
    ...paymentOverrides(calls),
  ]);
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  addTearDown(router.dispose);
  const locale = Locale('en');
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      theme: AppTheme.lightTheme(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...KurdishFallbackLocalizations.delegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// What the engine sends when the OS opens the app with a link (warm start).
Future<void> _platformOpens(WidgetTester tester, String location) async {
  final message = const JSONMethodCodec().encodeMethodCall(
    MethodCall('pushRouteInformation', <String, Object?>{'location': location, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

PaymentStatusScreen _statusScreen(WidgetTester tester) => tester.widget(find.byType(PaymentStatusScreen));

void main() {
  final en = l10nFor('en');

  testWidgets('goldengift://payment?sid=…&status=paid opens the status page for that session', (tester) async {
    final router = await _pumpRealRouter(tester, initialLocation: AppRoutes.paymentFor('ps1'));
    expect(_statusScreen(tester).sessionId, 'ps1');
    expect(find.text('25,000 IQD'), findsOneWidget);

    await _platformOpens(tester, 'goldengift://payment?sid=ps2&status=paid');
    expect(_statusScreen(tester).sessionId, 'ps2');
    expect(_statusScreen(tester).statusHint, 'paid');
    expect(router.state.uri.toString(), '/payment/ps2?status=paid');
    // The hint is not trusted: the session is still pending.
    expect(find.text(en.paymentWaitingTitle), findsOneWidget);
    expect(find.text('50,000 IQD'), findsOneWidget);
  });

  testWidgets('cold start: GoRouter keeps only /?sid=…&status=… — still the status page', (tester) async {
    await _pumpRealRouter(tester, initialLocation: '/?sid=ps2&status=pending');
    expect(_statusScreen(tester).sessionId, 'ps2');
    expect(_statusScreen(tester).statusHint, 'pending');
  });

  testWidgets('a link without a session id goes to Orders', (tester) async {
    final router = await _pumpRealRouter(tester, initialLocation: AppRoutes.paymentFor('ps1'));
    await _platformOpens(tester, 'goldengift://payment?status=error');
    expect(router.state.uri.toString(), AppRoutes.orders);
    expect(find.byType(PaymentStatusScreen), findsNothing);
  });
}

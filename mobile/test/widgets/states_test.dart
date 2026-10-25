import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/widgets/widgets.dart';

import 'test_app.dart';

void main() {
  group('EmptyState', () {
    testWidgets('shows title, subtitle and fires the CTA', (tester) async {
      var taps = 0;
      await tester.pumpWidget(testApp(EmptyState(
        title: 'Your Golden Gift cart is feeling lonely!',
        subtitle: 'Start designing your perfect gifts now!',
        ctaLabel: 'Start Shopping',
        onCta: () => taps++,
      )));

      expect(find.text('Your Golden Gift cart is feeling lonely!'), findsOneWidget);
      expect(find.text('Start designing your perfect gifts now!'), findsOneWidget);
      await tester.tap(find.text('Start Shopping'));
      expect(taps, 1);
    });

    testWidgets('no CTA without a label', (tester) async {
      await tester.pumpWidget(testApp(const EmptyState(title: 'Nothing here')));
      expect(find.byType(PrimaryButton), findsNothing);
    });

    testWidgets('renders in dark mode and RTL without errors', (tester) async {
      await tester.pumpWidget(testApp(
        EmptyState(title: 'Empty', subtitle: 'Sub', ctaLabel: 'Go', onCta: () {}),
        dark: true,
        locale: const Locale('ckb'),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('ErrorState', () {
    testWidgets('defaults to the localized message and retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(testApp(ErrorState(onRetry: () => retries++)));

      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('custom message, no Retry without callback', (tester) async {
      await tester.pumpWidget(testApp(const ErrorState(message: 'Offline')));
      expect(find.text('Offline'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsNothing);
    });
  });

  group('SkeletonLoader', () {
    for (final dark in [false, true]) {
      testWidgets('presets render (${dark ? 'dark' : 'light'})', (tester) async {
        await tester.pumpWidget(testApp(
          const Column(
            children: [
              SkeletonLoader.line(width: 120),
              SkeletonLoader.box(width: 80, height: 80),
              SkeletonLoader.list(count: 2),
              SkeletonLoader.productGrid(count: 2),
            ],
          ),
          dark: dark,
          width: 360,
        ));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('InfoBanner', () {
    testWidgets('all types render in light and dark', (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(testApp(
          Column(
            children: [
              for (final t in InfoBannerType.values) InfoBanner(type: t, message: t.name),
            ],
          ),
          dark: dark,
        ));
        for (final t in InfoBannerType.values) {
          expect(find.text(t.name), findsOneWidget);
        }
      }
    });
  });
}

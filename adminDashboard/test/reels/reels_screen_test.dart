import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/models/reel_model.dart';
import 'package:golden_gift_admin/core/router/admin_routes.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/web/video_probe.dart';
import 'package:golden_gift_admin/core/widgets/admin_scaffold.dart';
import 'package:golden_gift_admin/features/reels/data/reel_media.dart';
import 'package:golden_gift_admin/features/reels/reel_widgets.dart';
import 'package:golden_gift_admin/features/reels/reels_screen.dart';

import '../seller/phase8_test_harness.dart';
import 'reels_test_helpers.dart';

/// Three reels: active (newest), hidden, and active with an inactive product.
Future<FakeFirebaseFirestore> reelsWorld() async {
  final db = FakeFirebaseFirestore();
  await seedReelProducts(db);
  await seedReel(db, reel('r-new', caption: 'Your names, engraved in gold — a gift they keep for years'),
      product: reelProduct('engraved-mug', 'Engraved Mug'), createdAt: DateTime(2026, 10, 23));
  await seedReel(db, reel('r-hidden', productId: 'walnut-frame', active: false, durationMs: 75000),
      product: reelProduct('walnut-frame', 'Walnut Frame'), createdAt: DateTime(2026, 10, 22));
  await seedReel(db, reel('r-pen', productId: 'old-pen', durationMs: null),
      product: reelProduct('old-pen', 'Old Pen', active: false), createdAt: DateTime(2026, 10, 21));
  return db;
}

Finder badge(String label) => find.descendant(of: find.byType(ReelStatusBadge), matching: find.text(label));

Future<void> openMenu(WidgetTester tester, String reelId) async {
  await tester.tap(find.descendant(of: find.byKey(ValueKey('reel-$reelId')), matching: find.byTooltip('Reel actions')));
  await settle(tester);
}

/// Waits out the picker's 350 ms search debounce.
Future<void> settleSearch(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await settle(tester);
}

Future<Map<String, dynamic>?> reelDoc(FakeFirebaseFirestore db, String id) async =>
    (await db.doc('reels/$id').get()).data();

void main() {
  group('grid', () {
    testWidgets('newest first with status, duration, product and caption; filter chips', (tester) async {
      final db = await reelsWorld();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(FakeReelMediaStore()));
      expect(find.byType(ReelCard), findsNWidgets(3));
      final ids = [for (final c in tester.widgetList<ReelCard>(find.byType(ReelCard))) c.reel.id];
      expect(ids, ['r-new', 'r-hidden', 'r-pen']);
      expect(badge('Active'), findsOneWidget);
      expect(badge('Hidden'), findsOneWidget);
      expect(badge('Product unavailable'), findsOneWidget);
      expect(find.text('Engraved Mug'), findsOneWidget);
      expect(find.textContaining('Your names, engraved'), findsOneWidget);
      expect(find.byKey(const ValueKey('duration-r-new')), findsOneWidget);
      expect(find.text('0:23'), findsOneWidget);
      expect(find.text('1:15'), findsOneWidget);
      expect(find.byKey(const ValueKey('duration-r-pen')), findsNothing, reason: 'unknown duration');
      expect(find.text('All (3)'), findsOneWidget);
      expect(find.text('Active (2)'), findsOneWidget, reason: 'Product unavailable reels are active');
      expect(find.text('Hidden (1)'), findsOneWidget);
      expect(find.text('New reel'), findsOneWidget);

      await tester.tap(find.text('Hidden (1)'));
      await settle(tester);
      expect([for (final c in tester.widgetList<ReelCard>(find.byType(ReelCard))) c.reel.id], ['r-hidden']);
      await tester.tap(find.text('Active (2)'));
      await settle(tester);
      expect([for (final c in tester.widgetList<ReelCard>(find.byType(ReelCard))) c.reel.id], ['r-new', 'r-pen']);
    });

    testWidgets('empty states', (tester) async {
      final db = FakeFirebaseFirestore();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(FakeReelMediaStore()));
      expect(find.text('No reels yet — add the first product video with New reel.'), findsOneWidget);
      expect(find.byType(ReelCard), findsNothing);

      await seedReelProducts(db);
      await seedReel(db, reel('r1'), product: reelProduct('engraved-mug', 'Engraved Mug'), createdAt: DateTime(2026));
      await settle(tester);
      await tester.tap(find.text('Hidden (0)'));
      await settle(tester);
      expect(find.text('No hidden reels.'), findsOneWidget);
    });

    testWidgets('Hide / Activate from the card menu', (tester) async {
      final db = await reelsWorld();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(FakeReelMediaStore()));
      await openMenu(tester, 'r-new');
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Hide'));
      await settle(tester);
      expect((await reelDoc(db, 'r-new'))!['isActive'], isFalse);
      expect((await reelDoc(db, 'r-new'))!['visible'], isFalse);
      expect(find.text('Reel hidden'), findsOneWidget);
      expect(badge('Hidden'), findsNWidgets(2));

      await openMenu(tester, 'r-hidden');
      await tester.tap(find.text('Activate'));
      await settle(tester);
      expect((await reelDoc(db, 'r-hidden'))!['visible'], isTrue);
      expect((await auditEntries(db)).map((a) => a['action']), ['reel.update', 'reel.update']);
    });

    testWidgets('Delete asks first, then removes the doc and its files', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(media));
      await openMenu(tester, 'r-pen');
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Delete this reel?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await reelDoc(db, 'r-pen'), isNotNull);

      await openMenu(tester, 'r-pen');
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);
      expect(await reelDoc(db, 'r-pen'), isNull);
      expect(media.deleted, ['r-pen']);
      expect((await auditEntries(db)).single['action'], 'reel.delete');
      expect(find.byType(ReelCard), findsNWidgets(2));
      expect(find.text('Reel deleted'), findsOneWidget);
    });

    for (final (mode, size) in layoutMatrix) {
      testWidgets('lays out in ${mode.name} at ${size.width.toInt()} px (grid + editor)', (tester) async {
        final db = await reelsWorld();
        final errors = await errorsOutsideCoreNav(() async {
          await pumpPhase8(tester, const ReelsScreen(),
              db: db,
              mode: mode,
              size: size,
              overrides: reelOverrides(FakeReelMediaStore(),
                  video: PickedReelFile('a-very-long-file-name-for-the-reel-video-of-the-mug.mp4', fakeMp4),
                  probe: const VideoProbe(durationMs: 75000, width: 1920, height: 1080)));
          expect(find.byType(ReelCard), findsNWidgets(3));
          await tester.tap(find.text('New reel'));
          await settle(tester);
          await tester.tap(find.byKey(const ValueKey('pickReelVideo')));
          await settle(tester);
          expect(find.text('Not vertical 9:16 — the app crops it to fill the screen.'), findsOneWidget);
          expect(find.text('Longer than the recommended 60 s.'), findsOneWidget);
          expect(find.text('No frame could be captured for the poster — use Replace poster.'), findsOneWidget);
        });
        expect(errors, isEmpty);
      });
    }
  });

  group('access', () {
    testWidgets('finance gets the role notice and no nav entry; content sees both', (tester) async {
      final db = await reelsWorld();
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, session: staffSession(AdminRole.finance), size: const Size(1440, 1000));
      expect(find.text('Your role (finance) cannot open Reels.'), findsOneWidget);
      expect(find.byType(ReelCard), findsNothing);
      expect(find.text('New reel'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Reels'), findsNothing, reason: 'hidden from the finance nav');
      expect(find.widgetWithText(ListTile, 'Banners'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, session: staffSession(AdminRole.content), size: const Size(1440, 1000));
      expect(find.byType(ReelCard), findsNWidgets(3));
      expect(find.widgetWithText(ListTile, 'Reels'), findsOneWidget);
    });

    testWidgets('partner accounts never see Reels', (tester) async {
      final db = await reelsWorld();
      await seedStore(db, 'store-a', ownerUid: sellerSession.uid);
      await pumpPhase8(tester, const ReelsScreen(), db: db, session: sellerSession, size: const Size(1440, 1000));
      expect(find.text('This module is not available to partner accounts.'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Reels'), findsNothing);
      expect(find.byType(ReelCard), findsNothing);
    });

    test('the nav entry sits after Banners and is staff-only', () {
      final routes = adminNavItems.map((i) => i.route).toList();
      expect(routes.indexOf(AdminRoutes.reels), routes.indexOf(AdminRoutes.banners) + 1);
      final item = adminNavItems.firstWhere((i) => i.route == AdminRoutes.reels);
      expect(item.label, 'Reels');
      expect(item.sellerVisible, isFalse);
      expect(item.staffRoles, {AdminRole.superAdmin, AdminRole.ops, AdminRole.content});
    });
  });

  group('editor', () {
    testWidgets('a new reel needs a product and a video', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(media));
      await tester.tap(find.text('New reel'));
      await settle(tester);
      expect(find.text('New reel'), findsNWidgets(2), reason: 'FAB + dialog title');
      expect(find.text(ReelFileRules.videoHint), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue, reason: 'Active by default');

      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.text('Choose the product this reel shows.'), findsWidgets);
      expect(find.text('Choose the video (MP4).'), findsWidgets);
      expect(media.uploads, 0);
      expect((await db.collection('reels').get()).docs, hasLength(3));
      expect(await auditEntries(db), isEmpty);
    });

    testWidgets('a picked file that is not MP4 is refused', (tester) async {
      final db = await reelsWorld();
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, overrides: reelOverrides(FakeReelMediaStore(), video: PickedReelFile('clip.mov', fakeMp4)));
      await tester.tap(find.text('New reel'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pickReelVideo')));
      await settle(tester);
      expect(find.text('Videos must be MP4 files (.mp4).'), findsOneWidget);
      expect(find.text('clip.mov · 2 KB'), findsNothing);
    });

    testWidgets('create: search the product, upload with progress, poster from the video, one batch', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore()..holdVideo = Completer<void>();
      final probed = <Uint8List>[];
      await pumpPhase8(tester, const ReelsScreen(),
          db: db,
          overrides: reelOverrides(media,
              video: PickedReelFile('mug.mp4', fakeMp4), probe: verticalProbe, probed: probed));
      await tester.tap(find.text('New reel'));
      await settle(tester);

      expect(find.text('Newest products'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reelProductSearch')), 'walnut');
      await settleSearch(tester);
      expect(find.byKey(const ValueKey('pickProduct-walnut-frame')), findsOneWidget);
      expect(find.byKey(const ValueKey('pickProduct-engraved-mug')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pickProduct-walnut-frame')));
      await settle(tester);
      expect(find.text('Change'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pickReelVideo')));
      await settle(tester);
      expect(probed.single, fakeMp4);
      expect(find.text('mug.mp4 · 2 KB'), findsOneWidget);
      expect(find.text('Duration 0:23 · 1080 × 1920 (9:16)'), findsOneWidget);
      expect(find.textContaining('Not vertical'), findsNothing);
      final preview = tester.widget<ReelPosterImage>(find.byKey(const ValueKey('reelPosterPreview')));
      expect(preview.bytes, verticalProbe.poster, reason: 'the captured frame is the poster');

      await tester.enterText(find.widgetWithText(TextFormField, 'Caption · English'), 'Walnut, engraved for you');
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.byKey(const ValueKey('reelUploadProgress')), findsOneWidget);
      expect(find.text('Uploading video… 50 %'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('reelUploadProgress'))).value, 0.5);

      media.holdVideo!.complete();
      await settle(tester);
      expect(find.text('Reel created'), findsOneWidget);
      expect(find.byType(ReelCard), findsNWidgets(4));

      final id = media.videos.keys.single;
      expect(media.videos[id], fakeMp4);
      expect(media.posters[id]!.$2, 'image/jpeg');
      final stored = (await reelDoc(db, id))!;
      expect(stored['productId'], 'walnut-frame');
      expect(stored['videoUrl'], startsWith('https://storage.test/reels/$id.mp4'));
      expect(stored['posterUrl'], startsWith('https://storage.test/reels/$id.jpg'));
      expect(stored['durationMs'], 23400);
      expect(stored['aspectRatio'], 0.5625);
      expect(stored['caption'], 'Walnut, engraved for you');
      expect(stored['isActive'], isTrue);
      expect(stored['visible'], isTrue);
      expect(stored['createdBy'], testAdmin.uid);
      expect(stored['filterKeys'], contains('cat:frames|for:women'));
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'reel.create');
      expect(audit['target'], 'reels/$id');
    });

    testWidgets('a video the browser can’t read can still be saved, without poster / duration', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore();
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, overrides: reelOverrides(media, video: PickedReelFile('hevc.mp4', fakeMp4)));
      await tester.tap(find.text('New reel'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pickProduct-engraved-mug')));
      await tester.tap(find.byKey(const ValueKey('pickReelVideo')));
      await settle(tester);
      expect(find.textContaining('This browser could not read the video'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      final id = media.videos.keys.single;
      final stored = (await reelDoc(db, id))!;
      expect(stored['posterUrl'], isNull);
      expect(stored['durationMs'], isNull);
      expect(stored['aspectRatio'], isNull);
      expect(stored['isActive'], isFalse);
      expect(stored['visible'], isFalse);
      expect(media.posters, isEmpty);
    });

    testWidgets('a failed upload keeps the dialog open; retrying saves', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore()..videoError = StateError('network down');
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, overrides: reelOverrides(media, video: PickedReelFile('mug.mp4', fakeMp4), probe: verticalProbe));
      await tester.tap(find.text('New reel'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pickProduct-engraved-mug')));
      await tester.tap(find.byKey(const ValueKey('pickReelVideo')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.textContaining('Could not save: Bad state: network down'), findsOneWidget);
      expect((await db.collection('reels').get()).docs, hasLength(3));
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.text('Reel created'), findsOneWidget);
      expect(media.videos, hasLength(1));
    });

    testWidgets('edit without a new video keeps video and poster; Replace poster overrides it', (tester) async {
      final db = await reelsWorld();
      final media = FakeReelMediaStore();
      await pumpPhase8(tester, const ReelsScreen(),
          db: db, overrides: reelOverrides(media, poster: PickedReelFile('cover.png', tinyPng)));
      await tester.tap(find.byKey(const ValueKey('reel-r-new')));
      await settle(tester);
      expect(find.text('Edit reel'), findsOneWidget);
      expect(find.text('Engraved Mug'), findsWidgets);
      expect(find.text('Duration 0:23 · 9:16'), findsOneWidget);
      expect(find.text('Replace video'), findsOneWidget);
      final before = (await reelDoc(db, 'r-new'))!;

      await tester.enterText(find.widgetWithText(TextFormField, 'Caption · English'), 'Updated caption');
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.text('Reel saved'), findsOneWidget);
      var stored = (await reelDoc(db, 'r-new'))!;
      expect(stored['caption'], 'Updated caption');
      expect(stored['videoUrl'], before['videoUrl']);
      expect(stored['posterUrl'], before['posterUrl']);
      expect(stored['durationMs'], 23400);
      expect(stored['createdBy'], 'admin-0');
      expect(media.uploads, 0);

      await tester.tap(find.byKey(const ValueKey('reel-r-new')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pickReelPoster')));
      await settle(tester);
      expect(find.text('Poster: cover.png'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      stored = (await reelDoc(db, 'r-new'))!;
      expect(media.posters['r-new']!.$2, 'image/png');
      expect(stored['posterUrl'], startsWith('https://storage.test/reels/r-new.jpg'));
      expect(stored['videoUrl'], before['videoUrl']);
      expect((await auditEntries(db)).map((a) => a['action']), ['reel.update', 'reel.update']);
    });

    testWidgets('a reel whose product was deleted must pick another one', (tester) async {
      final db = await reelsWorld();
      await db.doc('products/old-pen').delete();
      await pumpPhase8(tester, const ReelsScreen(), db: db, overrides: reelOverrides(FakeReelMediaStore()));
      await tester.tap(find.byKey(const ValueKey('reel-r-pen')));
      await settle(tester);
      expect(find.text('The linked product “old-pen” no longer exists — choose another one.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      expect(find.text('Choose the product this reel shows.'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('pickProduct-engraved-mug')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('saveReel')));
      await settle(tester);
      final stored = ReelModel.fromMap('r-pen', (await reelDoc(db, 'r-pen'))!);
      expect(stored.productId, 'engraved-mug');
      expect(stored.visible, isTrue);
    });
  });
}

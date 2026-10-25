import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/features/reels/data/reel_derived.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/reel_model.dart';
import 'package:golden_gift_admin/core/session/admin_session.dart';
import 'package:golden_gift_admin/core/web/video_probe.dart';
import 'package:golden_gift_admin/features/reels/data/reel_media.dart';
import 'package:golden_gift_admin/features/reels/data/reels_admin_repository.dart';

import '../products/products_test_helpers.dart' show RecordingFirestore, auditEntries, seedProduct;
import 'reels_test_helpers.dart';

/// Save logic of the Reels module (SRS §6.4a, §9 Reels): one batch per change
/// with its audit entry, derived fields from the freshly read product.
void main() {
  late RecordingFirestore db;
  late FakeReelMediaStore media;
  late ReelsAdminRepository repo;

  setUp(() async {
    db = RecordingFirestore();
    media = FakeReelMediaStore();
    repo = ReelsAdminRepository(db, media);
    await seedReelProducts(db);
    db.commits.clear();
  });

  Future<Map<String, dynamic>> doc(String id) async => (await db.doc('reels/$id').get()).data()!;

  group('create', () {
    test('writes the reel + derived fields + createdBy / timestamps and a reel.create entry in ONE batch', () async {
      final id = repo.newId();
      expect(id, hasLength(20));
      await repo.save(
        reel(id, caption: 'Your names, engraved', captionAr: 'أسماؤكم محفورة'),
        isNew: true,
        adminUid: 'admin-1',
      );

      expect(db.commits, [
        ['set reels/$id', startsWith('set admin_audit_log/')],
      ]);
      final stored = await doc(id);
      expect(stored['productId'], 'engraved-mug');
      expect(stored['videoUrl'], 'https://storage.test/reels/$id.mp4');
      expect(stored['posterUrl'], 'https://storage.test/reels/$id.jpg');
      expect(stored['durationMs'], 23400);
      expect(stored['aspectRatio'], 9 / 16);
      expect(stored['caption'], 'Your names, engraved');
      expect(stored['captionAr'], 'أسماؤكم محفورة');
      expect(stored.containsKey('captionKu'), isFalse);
      expect(stored['isActive'], isTrue);
      expect(stored['createdBy'], 'admin-1');
      expect(stored['createdAt'], isA<Timestamp>());
      expect(stored['updatedAt'], isA<Timestamp>());

      // Derived from the product, exactly as the app's ReelDerived computes them.
      final product = reelProduct('engraved-mug', 'Engraved Mug', compareAtPrice: 30000);
      ReelDerived.fieldsFor(isActive: true, product: product).forEach((k, v) => expect(stored[k], v, reason: k));
      expect(stored['storeId'], 'golden-gift-home');
      expect(stored['visible'], isTrue);
      expect(stored['categoryIds'], ['mugs']);
      expect(stored['giftFor'], ['men', 'women']);
      expect(stored['priceBand'], 1);
      expect(stored['filterKeys'], ['cat:mugs', 'for:men', 'for:women', 'cat:mugs|for:men', 'cat:mugs|for:women']);
      expect(stored['product'], {
        'title': 'Engraved Mug',
        'titleAr': 'Engraved Mug ع',
        'image': 'https://cdn.goldengift.test/engraved-mug.jpg',
        'price': 25000,
        'compareAtPrice': 30000,
        'isActive': true,
      });

      final model = ReelModel.fromMap(id, stored);
      expect(reelStatusOf(model), ReelStatus.active);

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'reel.create');
      expect(audit['target'], 'reels/$id');
      expect(audit['adminUid'], 'admin-1');
      expect(audit['before'], isNull);
      final after = audit['after'] as Map;
      expect(after['filterKeys'], stored['filterKeys']);
      expect(after['createdBy'], 'admin-1');
      expect(after.containsKey('createdAt') || after.containsKey('updatedAt'), isFalse);
    });

    test('an inactive product makes an active reel "Product unavailable" (visible false)', () async {
      await repo.save(reel('r1', productId: 'old-pen'), isNew: true, adminUid: 'admin-1');
      final stored = await doc('r1');
      expect(stored['isActive'], isTrue);
      expect(stored['visible'], isFalse);
      expect(stored['filterKeys'], ['cat:mugs', 'for:companies', 'cat:mugs|for:companies']);
      expect(reelStatusOf(ReelModel.fromMap('r1', stored)), ReelStatus.productUnavailable);
    });

    test('nothing is written without a product, a video or with a product that is gone', () async {
      await expectLater(
        repo.save(reel('r1', productId: ''), isNew: true, adminUid: 'admin-1'),
        throwsA(isA<ReelValidationException>()
            .having((e) => e.errors, 'errors', contains('Choose the product this reel shows.'))),
      );
      await expectLater(
        repo.save(
            ReelModel(id: 'r1', productId: 'engraved-mug', videoUrl: ' ', caption: LocalizedText('x' * 151)),
            isNew: true,
            adminUid: 'admin-1'),
        throwsA(isA<ReelValidationException>().having((e) => e.errors, 'errors', [
          'Choose the video (MP4).',
          'The English caption is longer than 150 characters.',
        ])),
      );
      await expectLater(
        repo.save(reel('r1', productId: 'deleted-product'), isNew: true, adminUid: 'admin-1'),
        throwsA(isA<ReelValidationException>().having((e) => e.errors.single, 'error', contains('no longer exists'))),
      );
      expect(db.commits, isEmpty);
      expect((await db.collection('reels').get()).docs, isEmpty);
    });
  });

  group('update', () {
    test('re-reads the product, keeps createdBy / createdAt, deletes cleared translations, audits before / after',
        () async {
      await seedReel(db, reel('r1', caption: 'Old', captionAr: 'قديم'),
          product: reelProduct('engraved-mug', 'Engraved Mug'), createdAt: DateTime(2026, 10, 1));
      // The product changed since the reel was written.
      await db.doc('products/engraved-mug').update({'price': 120000, 'giftFor': ['companies']});
      db.commits.clear();

      await repo.save(reel('r1', productId: 'engraved-mug', caption: 'New caption'), isNew: false, adminUid: 'admin-2');

      expect(db.commits, [
        ['update reels/r1', startsWith('set admin_audit_log/')],
      ]);
      final stored = await doc('r1');
      expect(stored['caption'], 'New caption');
      expect(stored.containsKey('captionAr'), isFalse, reason: 'a cleared translation is deleted');
      expect(stored['createdBy'], 'admin-0');
      expect((stored['createdAt'] as Timestamp).toDate(), DateTime(2026, 10, 1));
      expect((stored['updatedAt'] as Timestamp).toDate().isAfter(DateTime(2026, 10, 1)), isTrue);
      expect(stored['priceBand'], 3);
      expect((stored['product'] as Map)['price'], 120000);
      expect(stored['giftFor'], ['companies']);
      expect(stored['filterKeys'], ['cat:mugs', 'for:companies', 'cat:mugs|for:companies']);

      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'reel.update');
      expect(audit['adminUid'], 'admin-2');
      final before = audit['before'] as Map, after = audit['after'] as Map;
      expect(before['caption'], 'Old');
      expect(before['captionAr'], 'قديم');
      expect(after['caption'], 'New caption');
      expect(after.containsKey('captionAr'), isFalse);
      expect(after['createdBy'], 'admin-0');
      expect(before['priceBand'], 1);
      expect(after['priceBand'], 3);
      for (final m in [before, after]) {
        expect(m.containsKey('createdAt') || m.containsKey('updatedAt'), isFalse);
      }
    });

    test('a reel deleted meanwhile is not resurrected', () async {
      await expectLater(
        repo.save(reel('gone'), isNew: false, adminUid: 'admin-1'),
        throwsA(isA<ReelNotFoundException>()),
      );
      expect(db.commits, isEmpty);
    });
  });

  group('activate / hide', () {
    test('hide: isActive + visible + derived fields in one audited batch', () async {
      await seedReel(db, reel('r1'), product: reelProduct('engraved-mug', 'Engraved Mug'), createdAt: DateTime(2026));
      db.commits.clear();
      await repo.setActive('r1', false, adminUid: 'admin-1');

      expect(db.commits.single, ['update reels/r1', startsWith('set admin_audit_log/')]);
      final stored = await doc('r1');
      expect(stored['isActive'], isFalse);
      expect(stored['visible'], isFalse);
      expect(stored['filterKeys'], isNotEmpty, reason: 'derived fields are kept current');
      expect(stored['createdBy'], 'admin-0');
      expect(reelStatusOf(ReelModel.fromMap('r1', stored)), ReelStatus.hidden);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'reel.update');
      expect((audit['before'] as Map)['isActive'], isTrue);
      expect((audit['before'] as Map)['visible'], isTrue);
      expect((audit['after'] as Map)['isActive'], isFalse);
      expect((audit['after'] as Map)['visible'], isFalse);
    });

    test('activating a reel whose product is gone keeps it invisible ("Product unavailable")', () async {
      await seedReel(db, reel('r1', productId: 'walnut-frame', active: false),
          product: reelProduct('walnut-frame', 'Walnut Frame'), createdAt: DateTime(2026));
      await db.doc('products/walnut-frame').delete();
      await repo.setActive('r1', true, adminUid: 'admin-1');
      final stored = await doc('r1');
      expect(stored['isActive'], isTrue);
      expect(stored['visible'], isFalse);
      expect(stored['product'], isNull);
      expect(stored['filterKeys'], isEmpty);
      expect(reelStatusOf(ReelModel.fromMap('r1', stored)), ReelStatus.productUnavailable);
    });
  });

  group('delete', () {
    test('doc + reel.delete audit in one batch, then both Storage files', () async {
      await seedReel(db, reel('r1', caption: 'Bye'), product: reelProduct('engraved-mug', 'Engraved Mug'),
          createdAt: DateTime(2026));
      db.commits.clear();
      final warning = await repo.delete('r1', adminUid: 'admin-1');
      expect(warning, isNull);
      expect(db.commits, [
        ['delete reels/r1', startsWith('set admin_audit_log/')],
      ]);
      expect((await db.doc('reels/r1').get()).exists, isFalse);
      expect(media.deleted, ['r1']);
      final audit = (await auditEntries(db)).single;
      expect(audit['action'], 'reel.delete');
      expect(audit['target'], 'reels/r1');
      expect((audit['before'] as Map)['caption'], 'Bye');
      expect(audit['after'], isNull);
    });

    test('a Storage failure is reported but the reel stays deleted', () async {
      await seedReel(db, reel('r1'), product: reelProduct('engraved-mug', 'Engraved Mug'), createdAt: DateTime(2026));
      media.deleteError = StateError('permission-denied');
      final warning = await repo.delete('r1', adminUid: 'admin-1');
      expect(warning, contains('could not be removed from Storage'));
      expect((await db.doc('reels/r1').get()).exists, isFalse);
    });
  });

  group('rules of the module', () {
    test('status, filters and duration', () {
      final active = ReelModel.fromMap('a', {'isActive': true, 'visible': true});
      final hidden = ReelModel.fromMap('h', {'isActive': false, 'visible': false});
      final unavailable = ReelModel.fromMap('u', {'isActive': true, 'visible': false});
      expect([active, hidden, unavailable].map(reelStatusOf),
          [ReelStatus.active, ReelStatus.hidden, ReelStatus.productUnavailable]);
      expect(ReelStatus.values.map((s) => s.label), ['Active', 'Hidden', 'Product unavailable']);
      expect([active, hidden, unavailable].where(ReelFilter.active.matches), [active, unavailable]);
      expect([active, hidden, unavailable].where(ReelFilter.hidden.matches), [hidden]);
      expect(formatReelDuration(23400), '0:23');
      expect(formatReelDuration(59600), '1:00');
      expect(formatReelDuration(125000), '2:05');
      expect(formatReelDuration(0), '0:00');
      expect(formatReelDuration(null), isNull);
      expect(isVertical916(1080 / 1920), isTrue);
      expect(isVertical916(720 / 1280), isTrue);
      expect(isVertical916(16 / 9), isFalse);
      expect(isVertical916(3 / 4), isFalse);
      expect(isVertical916(null), isFalse);
    });

    test('roles: super, ops and content — never finance or sellers', () {
      expect({for (final r in AdminRole.values) r: ReelsAccess.canManage(r)}, {
        AdminRole.superAdmin: true,
        AdminRole.ops: true,
        AdminRole.content: true,
        AdminRole.finance: false,
        AdminRole.seller: false,
      });
    });

    test('files: MP4 under 100 MB; posters JPEG / PNG / WebP under 10 MB', () {
      expect(reelVideoFileError('clip.mp4', 5 * 1024 * 1024), isNull);
      expect(reelVideoFileError('CLIP.MP4', 1), isNull);
      expect(reelVideoFileError('clip.mov', 100), 'Videos must be MP4 files (.mp4).');
      expect(reelVideoFileError('clip', 100), 'Videos must be MP4 files (.mp4).');
      expect(reelVideoFileError('clip.mp4', 0), 'The video file is empty.');
      expect(reelVideoFileError('clip.mp4', ReelFileRules.maxVideoBytes - 1), isNull);
      expect(reelVideoFileError('clip.mp4', ReelFileRules.maxVideoBytes), startsWith('Videos must be under 100 MB'));
      expect(reelPosterFileError('cover.png', 1000), isNull);
      expect(reelPosterFileError('cover.svg', 1000), 'Posters must be JPEG, PNG or WebP images.');
      expect(reelPosterFileError('cover.jpg', ReelFileRules.maxPosterBytes), startsWith('Posters must be under 10 MB'));
      expect(['a.jpg', 'a.JPEG', 'a.png', 'a.webp'].map(posterContentType),
          ['image/jpeg', 'image/jpeg', 'image/png', 'image/webp']);
      expect(ReelMediaPaths.video('abc'), 'reels/abc.mp4');
      expect(ReelMediaPaths.poster('abc'), 'reels/abc.jpg');
      expect(fileSizeLabel(2048), '2 KB');
      expect(fileSizeLabel(12 * 1024 * 1024 + 300000), '12.3 MB');
    });

    test('poster frame and size; the VM has no browser, so probing knows nothing', () async {
      expect(posterFrameSeconds(23.4), 0.5);
      expect(posterFrameSeconds(0.6), 0.3);
      expect(posterFrameSeconds(double.nan), 0.5);
      expect(posterFrameSeconds(double.infinity), 0.5);
      expect(posterFrameSeconds(null), 0.5);
      expect(posterSize(1080, 1920), (720, 1280));
      expect(posterSize(720, 1280), (720, 1280));
      expect(posterSize(480, 854), (480, 854), reason: 'never scaled up');
      expect(posterSize(3840, 2160), (720, 405));
      expect(const VideoProbe(width: 1080, height: 1920).aspectRatio, 0.5625);
      expect(const VideoProbe().aspectRatio, isNull);
      expect(await probeVideo(fakeMp4), isNull);
    });

    test('the stored reel round-trips through the app model', () async {
      await seedProduct(db, reelProduct('pen', 'Pen', giftFor: [GiftAudience.companies]), createdAt: DateTime(2026));
      await repo.save(reel('r2', productId: 'pen', caption: 'For the team'), isNew: true, adminUid: 'admin-1');
      final m = ReelModel.fromMap('r2', await doc('r2'));
      expect(m.toEditableMap(), reel('r2', productId: 'pen', caption: 'For the team').toEditableMap());
      expect(m.giftFor, [GiftAudience.companies]);
      expect(m.product?.title.en, 'Pen');
      expect(m.visible, isTrue);
    });
  });
}

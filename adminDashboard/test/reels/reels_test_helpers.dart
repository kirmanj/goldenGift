import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/app_constants.dart';
import 'package:golden_gift/models/localized_text.dart';
import 'package:golden_gift/models/product_model.dart';
import 'package:golden_gift/models/reel_model.dart';
import 'package:golden_gift_admin/core/web/video_probe.dart';
import 'package:golden_gift_admin/features/reels/data/reel_media.dart';
import 'package:golden_gift_admin/features/reels/data/reels_admin_repository.dart';

import '../products/products_test_helpers.dart' show seedProduct;

/// A real 1×1 PNG, so Image.memory previews decode in widget tests.
final tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Stand-in MP4 bytes (never decoded: the prober is faked too).
final fakeMp4 = Uint8List.fromList(List.generate(2048, (i) => i % 256));

/// Records uploads / deletes instead of talking to Firebase Storage.
class FakeReelMediaStore implements ReelMediaStore {
  final videos = <String, Uint8List>{};
  final posters = <String, (Uint8List, String)>{};
  final deleted = <String>[];
  final progress = <double>[];
  int uploads = 0;

  /// Thrown by the next video upload / delete when set.
  Object? videoError;
  Object? deleteError;

  /// While set, a video upload reports 50 % and waits for it.
  Completer<void>? holdVideo;

  @override
  Future<String> putVideo(String reelId, Uint8List bytes, {void Function(double fraction)? onProgress}) async {
    uploads++;
    final error = videoError;
    if (error != null) {
      videoError = null;
      throw error;
    }
    for (final f in [0.0, 0.5]) {
      progress.add(f);
      onProgress?.call(f);
    }
    await holdVideo?.future;
    progress.add(1);
    onProgress?.call(1);
    videos[reelId] = bytes;
    return 'https://storage.test/${ReelMediaPaths.video(reelId)}?v=$uploads';
  }

  @override
  Future<String> putPoster(String reelId, Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    uploads++;
    posters[reelId] = (bytes, contentType);
    return 'https://storage.test/${ReelMediaPaths.poster(reelId)}?v=$uploads';
  }

  @override
  Future<void> deleteFiles(String reelId) async {
    final error = deleteError;
    if (error != null) throw error;
    deleted.add(reelId);
  }
}

/// Overrides for the reel editor: fake Storage, a file picker answering from
/// [video] / [poster], and a prober answering [probe].
List<Override> reelOverrides(
  FakeReelMediaStore media, {
  PickedReelFile? video,
  PickedReelFile? poster,
  VideoProbe? probe,
  List<Uint8List>? probed,
}) =>
    [
      reelMediaStoreProvider.overrideWithValue(media),
      reelFilePickerProvider.overrideWithValue((kind) async => kind == ReelFileKind.video ? video : poster),
      reelVideoProberProvider.overrideWithValue((bytes) async {
        probed?.add(bytes);
        return probe;
      }),
    ];

/// What a 1080×1920, 23 s clip gives in the browser.
final verticalProbe = VideoProbe(poster: tinyPng, durationMs: 23400, width: 1080, height: 1920);

ProductModel reelProduct(
  String id,
  String title, {
  int price = 25000,
  int? compareAtPrice,
  bool active = true,
  List<String> categories = const ['mugs'],
  List<GiftAudience> giftFor = const [GiftAudience.men, GiftAudience.women],
  String storeId = 'golden-gift-home',
}) =>
    ProductModel(
      id: id,
      title: LocalizedText(title, ar: '$title ع'),
      storeId: storeId,
      price: price,
      compareAtPrice: compareAtPrice,
      isActive: active,
      categoryIds: categories,
      giftFor: giftFor,
      images: ['https://cdn.goldengift.test/$id.jpg'],
    );

Future<void> seedReelProducts(FirebaseFirestore db) async {
  await seedProduct(db, reelProduct('engraved-mug', 'Engraved Mug', compareAtPrice: 30000), createdAt: DateTime(2026, 10, 3));
  await seedProduct(db, reelProduct('walnut-frame', 'Walnut Frame', price: 60000, categories: ['frames']),
      createdAt: DateTime(2026, 10, 2));
  await seedProduct(db, reelProduct('old-pen', 'Old Pen', active: false, giftFor: [GiftAudience.companies]),
      createdAt: DateTime(2026, 10, 1));
}

/// Writes a reel the way the dashboard does, with an explicit `createdAt`.
Future<void> seedReel(
  FirebaseFirestore db,
  ReelModel reel, {
  ProductModel? product,
  required DateTime createdAt,
  String createdBy = 'admin-0',
}) =>
    db.doc('reels/${reel.id}').set({
      ...ReelsAdminRepository.reelData(reel, product),
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(createdAt),
    });

ReelModel reel(
  String id, {
  String productId = 'engraved-mug',
  bool active = true,
  String? caption,
  String? captionAr,
  int? durationMs = 23400,
  String? posterUrl,
}) =>
    ReelModel(
      id: id,
      productId: productId,
      videoUrl: 'https://storage.test/reels/$id.mp4',
      posterUrl: posterUrl ?? 'https://storage.test/reels/$id.jpg',
      durationMs: durationMs,
      aspectRatio: 9 / 16,
      caption: caption == null ? LocalizedText.empty : LocalizedText(caption, ar: captionAr),
      isActive: active,
    );

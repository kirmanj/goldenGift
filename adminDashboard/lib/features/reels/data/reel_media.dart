import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';

import '../../../core/web/video_probe.dart';

/// Upload limits of the Reels module (SRS §6.16, §6.17 Storage rules).
class ReelFileRules {
  ReelFileRules._();

  /// The Storage rules accept a `video/mp4` under 100 MB.
  static const maxVideoBytes = 100 * 1024 * 1024;

  /// Every image upload is under 10 MB.
  static const maxPosterBytes = 10 * 1024 * 1024;

  static const videoExtensions = ['mp4'];

  /// Raster images only — the Storage rules refuse SVG and others.
  static const posterExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  /// Recommendations shown in the editor (not enforced).
  static const recommendedMaxSeconds = 60;
  static const recommendedAspectRatio = 9 / 16;

  static const videoHint = 'MP4 (H.264), vertical 9:16, up to 60 s recommended. Under 100 MB.';
}

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Why a picked file can't be the reel's video; null = fine.
String? reelVideoFileError(String name, int size) {
  if (!ReelFileRules.videoExtensions.contains(_extensionOf(name))) return 'Videos must be MP4 files (.mp4).';
  if (size == 0) return 'The video file is empty.';
  if (size >= ReelFileRules.maxVideoBytes) return 'Videos must be under 100 MB (this one is ${_megabytes(size)} MB).';
  return null;
}

/// Why a picked file can't be the reel's poster; null = fine.
String? reelPosterFileError(String name, int size) {
  if (!ReelFileRules.posterExtensions.contains(_extensionOf(name))) return 'Posters must be JPEG, PNG or WebP images.';
  if (size == 0) return 'The image file is empty.';
  if (size >= ReelFileRules.maxPosterBytes) return 'Posters must be under 10 MB (this one is ${_megabytes(size)} MB).';
  return null;
}

/// Content type of a replacement poster (stored at `reels/{id}.jpg` whatever its format).
String posterContentType(String name) => switch (_extensionOf(name)) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

/// "12.3 MB" for the editor.
String fileSizeLabel(int bytes) =>
    bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${_megabytes(bytes)} MB';

/// A reel's objects in Storage (SRS §6.16): `reels/{id}.mp4` + `reels/{id}.jpg`.
class ReelMediaPaths {
  ReelMediaPaths._();

  static String video(String reelId) => '${FirestorePaths.reels}/$reelId.mp4';
  static String poster(String reelId) => '${FirestorePaths.reels}/$reelId.jpg';
}

/// Uploads / deletes a reel's video and poster. Injected through
/// [reelMediaStoreProvider] so tests fake Storage.
abstract class ReelMediaStore {
  /// Uploads the MP4 to [ReelMediaPaths.video] (`video/mp4`); [onProgress]
  /// gets 0…1. Returns the download URL.
  Future<String> putVideo(String reelId, Uint8List bytes, {void Function(double fraction)? onProgress});

  /// Uploads the poster to [ReelMediaPaths.poster]. Returns the download URL.
  Future<String> putPoster(String reelId, Uint8List bytes, {String contentType = 'image/jpeg'});

  /// Deletes both objects; objects that don't exist are ignored.
  Future<void> deleteFiles(String reelId);
}

class FirebaseReelMediaStore implements ReelMediaStore {
  FirebaseReelMediaStore(this._storage);
  final FirebaseStorage _storage;

  @override
  Future<String> putVideo(String reelId, Uint8List bytes, {void Function(double fraction)? onProgress}) async {
    final object = _storage.ref(ReelMediaPaths.video(reelId));
    final task = object.putData(bytes, SettableMetadata(contentType: 'video/mp4'));
    final progress = task.snapshotEvents.listen(
      (s) {
        if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
      },
      onError: (Object _) {}, // the task's own future reports the failure
    );
    try {
      await task;
    } finally {
      unawaited(progress.cancel());
    }
    onProgress?.call(1);
    return object.getDownloadURL();
  }

  @override
  Future<String> putPoster(String reelId, Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    final object = _storage.ref(ReelMediaPaths.poster(reelId));
    await object.putData(bytes, SettableMetadata(contentType: contentType));
    return object.getDownloadURL();
  }

  @override
  Future<void> deleteFiles(String reelId) async {
    for (final path in [ReelMediaPaths.video(reelId), ReelMediaPaths.poster(reelId)]) {
      try {
        await _storage.ref(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
  }
}

final reelMediaStoreProvider = Provider<ReelMediaStore>((ref) => FirebaseReelMediaStore(ref.watch(storageProvider)));

enum ReelFileKind { video, poster }

class PickedReelFile {
  const PickedReelFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;

  int get size => bytes.length;
}

/// Opens the browser's file chooser for a video or a poster image (tests override it).
final reelFilePickerProvider = Provider<Future<PickedReelFile?> Function(ReelFileKind kind)>((ref) => (kind) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: kind == ReelFileKind.video ? ReelFileRules.videoExtensions : ReelFileRules.posterExtensions,
        withData: true,
      );
      final file = result?.files.singleOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return null;
      return PickedReelFile(file.name, bytes);
    });

typedef VideoProber = Future<VideoProbe?> Function(Uint8List bytes);

/// Reads poster / duration / size of a picked video in the browser (tests override it).
final reelVideoProberProvider = Provider<VideoProber>((ref) => (bytes) => probeVideo(bytes));

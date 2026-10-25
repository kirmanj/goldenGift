import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/firebase_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/product_configuration.dart';

class PhotoTooLargeException implements Exception {
  const PhotoTooLargeException();
}

/// Customer photos for `photoUpload` option groups (SRS §5.9, §6.16, §8):
/// pick → crop (mobile) → compressed to ≤ 1600 px / 85 % → uploaded on Add to
/// Cart to `uploads/{uid}/{cartItemId}/{n}.jpg` with progress.
class PhotoService {
  PhotoService(this._storage, {ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  static const maxSide = 1600.0;
  static const quality = 85;
  static const maxBytes = 10 * 1024 * 1024;

  /// Null when the user cancels. Throws [PhotoTooLargeException] above 10 MB.
  Future<PickedPhoto?> pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: quality,
    );
    if (file == null) return null;
    var path = file.path;
    if (!kIsWeb) {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        maxWidth: maxSide.toInt(),
        maxHeight: maxSide.toInt(),
        compressQuality: quality,
        uiSettings: [
          AndroidUiSettings(
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: AppColors.textOnPrimary,
            activeControlsWidgetColor: AppColors.primary,
            lockAspectRatio: false,
          ),
          IOSUiSettings(aspectRatioLockEnabled: false),
        ],
      );
      if (cropped == null) return null;
      path = cropped.path;
      final bytes = await XFile(path).readAsBytes();
      if (bytes.length > maxBytes) throw const PhotoTooLargeException();
      return PickedPhoto(bytes, name: file.name);
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw const PhotoTooLargeException();
    return PickedPhoto(bytes, name: file.name);
  }

  /// Uploads every group's photos; [onProgress] reports 0..1 over all bytes.
  /// Returns download URLs per group id, in slot order.
  Future<Map<String, List<String>>> upload({
    required String uid,
    required String cartItemId,
    required Map<String, List<PickedPhoto>> photosByGroup,
    ValueChanged<double>? onProgress,
  }) async {
    final all = [
      for (final e in photosByGroup.entries)
        for (final p in e.value) (e.key, p),
    ];
    final total = all.fold<int>(0, (n, e) => n + e.$2.bytes.length);
    var done = 0;
    final urls = <String, List<String>>{};
    for (var i = 0; i < all.length; i++) {
      final (group, photo) = all[i];
      final ref = _storage.ref('uploads/$uid/$cartItemId/${i + 1}.jpg');
      final task = ref.putData(photo.bytes, SettableMetadata(contentType: 'image/jpeg'));
      final sub = task.snapshotEvents.listen((s) {
        if (total > 0) onProgress?.call((done + s.bytesTransferred) / total);
      });
      await task;
      await sub.cancel();
      done += photo.bytes.length;
      onProgress?.call(total == 0 ? 1 : done / total);
      urls.putIfAbsent(group, () => []).add(await ref.getDownloadURL());
    }
    return urls;
  }
}

final photoServiceProvider = Provider<PhotoService>((ref) => PhotoService(ref.watch(storageProvider)));

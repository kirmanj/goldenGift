import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/product_details/domain/product_configuration.dart';
import '../providers/firebase_providers.dart';

/// Uploads already-picked JPEGs (pick them with `photoServiceProvider.pick`)
/// to `{folder}/{n}.jpg` and returns their download URLs in order. Used by
/// special requests, partner applications and the gift-card designer.
class ImageUploadService {
  ImageUploadService(this._storage);
  final FirebaseStorage _storage;

  Future<List<String>> upload(String folder, List<PickedPhoto> photos, {ValueChanged<double>? onProgress}) async {
    final total = photos.fold<int>(0, (n, p) => n + p.bytes.length);
    var done = 0;
    final urls = <String>[];
    for (var i = 0; i < photos.length; i++) {
      final ref = _storage.ref('$folder/${i + 1}.jpg');
      final task = ref.putData(photos[i].bytes, SettableMetadata(contentType: 'image/jpeg'));
      final sub = task.snapshotEvents.listen((s) {
        if (total > 0) onProgress?.call((done + s.bytesTransferred) / total);
      });
      await task;
      await sub.cancel();
      done += photos[i].bytes.length;
      onProgress?.call(total == 0 ? 1 : done / total);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}

final imageUploadServiceProvider = Provider<ImageUploadService>((ref) => ImageUploadService(ref.watch(storageProvider)));

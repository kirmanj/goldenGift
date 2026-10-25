import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/firestore_paths.dart';
import 'firebase_providers.dart';

/// True while Firestore serves only cached data (SRS §4.8 "offline" chip).
///
/// Watches `app_settings/general` with metadata changes: a snapshot that is
/// still `isFromCache` a few seconds after the last change means the server is
/// unreachable. The grace period hides the normal cache-first startup.
final isOfflineProvider = StreamProvider<bool>((ref) {
  const grace = Duration(seconds: 3);
  final controller = StreamController<bool>();
  Timer? timer;
  var last = false;

  void emit(bool value) {
    if (value == last || controller.isClosed) return;
    last = value;
    controller.add(value);
  }

  final sub = ref
      .watch(firestoreProvider)
      .doc(FirestorePaths.settingsDoc('general'))
      .snapshots(includeMetadataChanges: true)
      .listen(
    (snap) {
      timer?.cancel();
      if (snap.metadata.isFromCache) {
        timer = Timer(grace, () => emit(true));
      } else {
        emit(false);
      }
    },
    onError: (_) => emit(true),
  );

  controller.add(false);
  ref.onDispose(() {
    timer?.cancel();
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

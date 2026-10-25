import 'dart:typed_data';

import 'video_probe_result.dart';

/// The Dart VM (tests) has no browser to read a video with: nothing is known,
/// so the editor saves the reel without a poster / duration / aspect ratio.
Future<VideoProbe?> probeVideo(Uint8List bytes, {String mimeType = 'video/mp4', Duration timeout = videoProbeTimeout}) async =>
    null;

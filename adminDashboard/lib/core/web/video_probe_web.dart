import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'video_probe_result.dart';

/// Loads [bytes] into a muted, detached `<video>` (object URL, metadata
/// preload), reads its duration and size, seeks to [posterFrameSeconds] and
/// draws that frame to a canvas → JPEG ([posterJpegQuality], ≤ [maxPosterWidth]
/// px wide).
///
/// Returns null when the browser can't read the video at all (e.g. a codec it
/// doesn't play) and a probe without a poster when only the frame capture
/// fails — never hangs longer than [timeout]. The object URL is always revoked.
Future<VideoProbe?> probeVideo(Uint8List bytes, {String mimeType = 'video/mp4', Duration timeout = videoProbeTimeout}) async {
  final deadline = DateTime.now().add(timeout);
  Duration left() {
    final d = deadline.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  final url = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType)));
  final video = web.document.createElement('video') as web.HTMLVideoElement;
  try {
    video
      ..muted = true
      ..preload = 'metadata'
      ..playsInline = true;
    final metadata = _nextEvent(video, 'loadedmetadata');
    video.src = url;
    await metadata.timeout(left());

    final width = video.videoWidth, height = video.videoHeight;
    final seconds = video.duration.toDouble();
    final durationMs = seconds.isFinite && seconds > 0 ? (seconds * 1000).round() : null;
    Uint8List? poster;
    if (width > 0 && height > 0) {
      try {
        final seeked = _nextEvent(video, 'seeked');
        video.currentTime = posterFrameSeconds(seconds);
        await seeked.timeout(left());
        poster = await _jpegFrame(video, width, height).timeout(left());
      } catch (_) {
        poster = null; // metadata is still useful without a poster
      }
    }
    return VideoProbe(
      poster: poster,
      durationMs: durationMs,
      width: width > 0 ? width : null,
      height: height > 0 ? height : null,
    );
  } catch (_) {
    return null;
  } finally {
    video
      ..removeAttribute('src')
      ..load(); // releases the decoder
    web.URL.revokeObjectURL(url);
  }
}

/// Completes on the video's next [type] event; fails on its `error` event.
Future<void> _nextEvent(web.HTMLVideoElement video, String type) {
  final done = Completer<void>();
  late final JSFunction onEvent;
  late final JSFunction onError;
  void stop() {
    video
      ..removeEventListener(type, onEvent)
      ..removeEventListener('error', onError);
  }

  onEvent = ((web.Event _) {
    stop();
    if (!done.isCompleted) done.complete();
  }).toJS;
  onError = ((web.Event _) {
    stop();
    if (!done.isCompleted) done.completeError(StateError('The browser could not read this video.'));
  }).toJS;
  video
    ..addEventListener(type, onEvent)
    ..addEventListener('error', onError);
  return done.future;
}

/// The video's current frame as JPEG bytes, scaled by [posterSize].
Future<Uint8List?> _jpegFrame(web.HTMLVideoElement video, int width, int height) async {
  final (w, h) = posterSize(width, height);
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
    ..width = w
    ..height = h;
  final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
  if (context == null) return null;
  context.drawImage(video, 0, 0, w, h);
  final blob = Completer<web.Blob?>();
  canvas.toBlob(((web.Blob? b) => blob.complete(b)).toJS, 'image/jpeg', posterJpegQuality.toJS);
  final jpeg = await blob.future;
  if (jpeg == null) return null;
  final buffer = await jpeg.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

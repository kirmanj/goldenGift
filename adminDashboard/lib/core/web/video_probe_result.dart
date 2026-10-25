import 'dart:math' as math;
import 'dart:typed_data';

/// What the browser read from a picked reel video (SRS §9 Reels): the poster
/// frame and the metadata stored on `reels/{id}` (`durationMs`, `aspectRatio`).
class VideoProbe {
  const VideoProbe({this.poster, this.durationMs, this.width, this.height});

  /// JPEG of the frame at [posterFrameSeconds], at most [maxPosterWidth] wide;
  /// null when the browser could not capture it.
  final Uint8List? poster;
  final int? durationMs;

  /// Displayed size of the video in pixels (null = unknown).
  final int? width;
  final int? height;

  /// Width / height (9:16 ≈ 0.5625); null when the size is unknown.
  double? get aspectRatio {
    final w = width, h = height;
    return w != null && h != null && w > 0 && h > 0 ? w / h : null;
  }
}

/// Gives up on a video the browser can't read instead of hanging the editor.
const videoProbeTimeout = Duration(seconds: 15);

/// Automatic posters are at most this wide (SRS §9 Reels).
const maxPosterWidth = 720;

/// JPEG quality of an automatic poster.
const posterJpegQuality = 0.85;

/// Frame time of the automatic poster: 0.5 s, or half of a shorter video.
double posterFrameSeconds(double? durationSeconds) {
  final d = durationSeconds;
  if (d == null || !d.isFinite || d <= 0) return 0.5;
  return math.min(0.5, d / 2);
}

/// The poster's pixel size: [width] × [height] scaled down to at most
/// [maxWidth] wide, keeping the aspect ratio (never scaled up).
(int, int) posterSize(int width, int height, {int maxWidth = maxPosterWidth}) {
  if (width <= maxWidth) return (width, height);
  return (maxWidth, math.max(1, (height * maxWidth / width).round()));
}

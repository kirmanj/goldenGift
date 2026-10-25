import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// A video_player platform for widget tests (there is no decoder in tests):
/// every player initializes at once as a 9:16, 15 s video — or fails, for a
/// URL in [failing] — and records what the app asked it to do.
///
/// Install with [FakeVideoPlayerPlatform.install] in a test or setUp (restored on tear-down).
class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({this.failing = const {}});

  final Set<String> failing;

  final _events = <int, StreamController<VideoEvent>>{};
  final urls = <int, String>{};
  final playing = <int>{};
  final volumes = <int, double>{};
  final disposed = <int>[];
  int _nextId = 0;

  static const size = Size(720, 1280);
  static const duration = Duration(seconds: 15);

  static FakeVideoPlayerPlatform install({Set<String> failing = const {}}) {
    final previous = VideoPlayerPlatform.instance;
    final fake = FakeVideoPlayerPlatform(failing: failing);
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    return fake;
  }

  /// URLs of the players currently playing.
  Set<String> get playingUrls => {for (final id in playing) urls[id]!};

  /// URLs of the players created and not disposed.
  Set<String> get liveUrls => {
        for (final e in urls.entries)
          if (!disposed.contains(e.key)) e.value,
      };

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async => _create(dataSource.uri ?? '');

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => _create(options.dataSource.uri ?? '');

  int _create(String url) {
    final id = _nextId++;
    urls[id] = url;
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    scheduleMicrotask(() {
      if (failing.contains(url)) {
        controller.addError(PlatformException(code: 'VideoError', message: 'cannot play $url'));
      } else {
        controller.add(VideoEvent(eventType: VideoEventType.initialized, duration: duration, size: size));
      }
    });
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing.remove(playerId);
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async => playing.add(playerId);

  @override
  Future<void> pause(int playerId) async => playing.remove(playerId);

  @override
  Future<void> setVolume(int playerId, double volume) async => volumes[playerId] = volume;

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox.expand();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

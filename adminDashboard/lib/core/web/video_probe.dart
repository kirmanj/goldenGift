// Reads a picked video in the browser (poster frame, duration, size) for the
// Reels editor (SRS §9 Reels). Tests run on the Dart VM, where package:web is
// unavailable, so the VM gets a stub that knows nothing.
export 'video_probe_result.dart';
export 'video_probe_stub.dart' if (dart.library.js_interop) 'video_probe_web.dart';

// Browser helpers for the dashboard (web only). Tests run on the Dart VM, where
// package:web is unavailable, so the VM gets a recording stub instead.
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';

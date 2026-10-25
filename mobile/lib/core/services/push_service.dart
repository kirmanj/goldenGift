import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/firestore_paths.dart';
import '../providers/firebase_providers.dart';
import '../router/app_router.dart';

/// FCM registration (SRS §4.5): the device token lives in
/// `users/{uid}.fcmTokens` while signed in; functions send order updates,
/// replies and broadcasts to it. Tapping a push opens its `data.route`.
/// Web push needs a service worker + VAPID key and is not enabled — web users
/// still get the in-app notification list.
class PushService {
  PushService(this._messagingFactory, this._db, this._openRoute);

  /// Resolved lazily inside the guarded calls: without a Firebase app (tests,
  /// misconfigured builds) push is simply off.
  final FirebaseMessaging Function() _messagingFactory;
  FirebaseMessaging get _messaging => _messagingFactory();
  final FirebaseFirestore _db;
  final void Function(String route) _openRoute;

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  String? _token;

  static bool get supported => !kIsWeb;

  Future<void> register(String uid) async {
    if (!supported) return;
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      _token = await _messaging.getToken();
      if (_token != null) await _save(uid, _token!);
      await _refreshSub?.cancel();
      _refreshSub = _messaging.onTokenRefresh.listen((t) {
        _token = t;
        _save(uid, t).catchError((Object _) {});
      });
      await _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_open);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      // No push is never fatal: the in-app list still shows everything.
      if (kDebugMode) debugPrint('push registration failed: $e');
    }
  }

  Future<void> unregister(String uid) async {
    if (!supported) return;
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    try {
      final token = _token ?? await _messaging.getToken();
      if (token == null) return;
      await _db.doc(FirestorePaths.userDoc(uid)).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      await _messaging.deleteToken();
    } catch (_) {
      // Signing out must not fail because of push cleanup.
    }
    _token = null;
  }

  Future<void> _save(String uid, String token) => _db.doc(FirestorePaths.userDoc(uid)).update({
        'fcmTokens': FieldValue.arrayUnion([token]),
      });

  void _open(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.startsWith('/')) _openRoute(route);
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(
      () => FirebaseMessaging.instance,
      ref.watch(firestoreProvider),
      (route) => ref.read(appRouterProvider).push(route),
    ));

/// Watched once by the main shell: registers the token when someone signs in.
final pushRegistrationProvider = Provider<void>((ref) {
  ref.listen(authStateProvider, (previous, next) {
    final uid = next.valueOrNull?.uid;
    if (uid != null && uid != previous?.valueOrNull?.uid) ref.read(pushServiceProvider).register(uid);
  }, fireImmediately: true);
});

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/providers/connectivity_provider.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/core/services/push_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_fakes.dart';

/// Overrides that let any screen (incl. the whole MainShell) run in widget
/// tests without Firebase: an empty in-memory Firestore, a signed-out (or
/// given) user, mock SharedPreferences, no-op analytics and no push registration.
Future<List<Override>> appTestOverrides({
  FakeFirebaseFirestore? firestore,
  User? user,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return appTestOverridesSync(await SharedPreferences.getInstance(), firestore: firestore, user: user);
}

/// Same, for synchronous widget builders: pass prefs created in setUp.
List<Override> appTestOverridesSync(SharedPreferences prefs, {FirebaseFirestore? firestore, User? user}) => [
      firestoreProvider.overrideWithValue(firestore ?? FakeFirebaseFirestore()),
      authStateProvider.overrideWith((ref) => Stream.value(user)),
      sharedPreferencesProvider.overrideWithValue(prefs),
      analyticsServiceProvider.overrideWithValue(FakeAnalytics()),
      isOfflineProvider.overrideWith((ref) => Stream.value(false)),
      pushRegistrationProvider.overrideWithValue(null),
    ];

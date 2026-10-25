import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/firebase_providers.dart';

/// Calls a Cloud Function by name and returns its `data` (europe-west1).
/// Repositories take this instead of FirebaseFunctions so tests can fake it;
/// errors are the plugin's FirebaseFunctionsException.
typedef CallableInvoker = Future<Object?> Function(String name, Map<String, dynamic> data);

final callableInvokerProvider = Provider<CallableInvoker>((ref) {
  final functions = ref.watch(functionsProvider);
  return (name, data) async => (await functions.httpsCallable(name).call<Object?>(data)).data;
});

/// The callable's map response (empty when it returned something else).
Map<String, dynamic> callableMap(Object? data) =>
    data is Map ? Map<String, dynamic>.from(data) : const <String, dynamic>{};

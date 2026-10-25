import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../models/user_model.dart';
import '../../data/datasources/user_repository.dart';

/// The signed-in customer's profile, live. `null` for guests and while the
/// document doesn't exist yet (between sign-in and profile creation).
final currentUserProfileProvider = StreamProvider<UserModel?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watch(user.uid);
});

/// True when someone is signed in (any provider).
final isSignedInProvider = Provider<bool>((ref) => ref.watch(authStateProvider).valueOrNull != null);

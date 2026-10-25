import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../models/user_model.dart';

/// `users/{uid}` reads and the customer's own writes (SRS §5.14, §6.1).
/// Server-owned fields are never written here — see UserModel.toProfileMap.
class UserRepository {
  UserRepository(this._db, this._storage, this._functions);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _db.doc(FirestorePaths.userDoc(uid));

  Stream<UserModel?> watch(String uid) => _doc(uid)
      .snapshots()
      .map((snap) => snap.exists ? UserModel.fromMap(uid, snap.data()!) : null);

  /// Server read: decides "new or returning user" right after sign-in, so a
  /// stale offline cache must not answer it.
  Future<UserModel?> fetch(String uid) async {
    final snap = await _doc(uid).get(const GetOptions(source: Source.server));
    return snap.exists ? UserModel.fromMap(uid, snap.data()!) : null;
  }

  /// First document after sign-up (SRS AUTH-3). `onUserCreate` then adds the
  /// wallet, the referral code and the server-owned defaults.
  Future<void> create(UserModel user) => _doc(user.uid).set({
        ...user.toCreateMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateProfile(UserModel user) => _doc(user.uid).update({
        ...user.toProfileMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateFields(String uid, Map<String, Object?> fields) =>
      _doc(uid).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  /// Uploads `users/{uid}/avatar.jpg` and returns its download URL.
  Future<String> uploadAvatar(String uid, Uint8List jpegBytes) async {
    final ref = _storage.ref('users/$uid/avatar.jpg');
    await ref.putData(jpegBytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// SRS AUTH-7 via the `deleteAccount` callable: anonymizes the profile,
  /// removes personal data and deletes the Auth user server-side.
  Future<void> deleteAccount() => _functions.httpsCallable('deleteAccount').call<void>();
}

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(
      ref.watch(firestoreProvider),
      ref.watch(storageProvider),
      ref.watch(functionsProvider),
    ));

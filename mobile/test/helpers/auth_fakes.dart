import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/services/analytics_service.dart';
import 'package:golden_gift/features/auth/data/datasources/auth_repository.dart';
import 'package:golden_gift/features/profile/data/datasources/user_repository.dart';
import 'package:golden_gift/models/user_model.dart';

/// Firebase-free fakes for auth / profile tests.

class FakeUserInfo extends Fake implements UserInfo {
  FakeUserInfo(this.providerId);
  @override
  final String providerId;
}

class FakeUser extends Fake implements User {
  FakeUser({
    this.uid = 'u1',
    this.phoneNumber,
    this.displayName,
    this.email,
    this.photoURL,
    List<String> providers = const ['phone'],
  }) : providerData = providers.map(FakeUserInfo.new).toList();

  @override
  final String uid;
  @override
  final String? phoneNumber;
  @override
  final String? displayName;
  @override
  final String? email;
  @override
  final String? photoURL;
  @override
  final List<UserInfo> providerData;
}

class FakeUserCredential extends Fake implements UserCredential {
  FakeUserCredential(this.user);
  @override
  final User? user;
}

/// Records every call so tests can assert that invalid input never reached Firebase.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user, this.signedInUser, this.sendError, this.confirmError});

  User? user;
  final User? signedInUser;
  AuthFailure? sendError;
  AuthFailure? confirmError;

  final sentTo = <String>[];
  final phoneChangeCodes = <String>[];
  final confirmedCodes = <String>[];
  final changedTo = <String>[];
  final _auth = StreamController<User?>.broadcast();

  @override
  User? get currentUser => user;

  @override
  Stream<User?> authStateChanges() async* {
    yield user;
    yield* _auth.stream;
  }

  @override
  Future<PhoneCodeSession> sendCode(String phoneE164, {bool forPhoneChange = false}) async {
    sentTo.add(phoneE164);
    if (forPhoneChange) phoneChangeCodes.add(phoneE164);
    if (sendError != null) throw sendError!;
    return PhoneCodeSession(phoneE164: phoneE164, forPhoneChange: forPhoneChange);
  }

  @override
  Future<UserCredential> confirmCode(PhoneCodeSession session, String smsCode) async {
    confirmedCodes.add(smsCode);
    if (confirmError != null) throw confirmError!;
    user = signedInUser ?? FakeUser(phoneNumber: session.phoneE164);
    return FakeUserCredential(user);
  }

  @override
  Future<void> changePhone(PhoneCodeSession session, String smsCode) async {
    confirmedCodes.add(smsCode);
    if (confirmError != null) throw confirmError!;
    changedTo.add(session.phoneE164);
  }

  @override
  Future<UserCredential?> signInWithGoogle() async => null;

  @override
  Future<UserCredential?> signInWithApple() async => null;

  @override
  Future<void> signOut() async => user = null;
}

/// A session as `sendCode` returns it.
PhoneCodeSession testSession(String phoneE164, {bool forPhoneChange = false}) =>
    PhoneCodeSession(phoneE164: phoneE164, forPhoneChange: forPhoneChange);

class FakeUserRepository implements UserRepository {
  FakeUserRepository({this.existing});

  UserModel? existing;
  Object? fetchError;
  final created = <UserModel>[];
  final fieldUpdates = <Map<String, Object?>>[];

  @override
  Future<UserModel?> fetch(String uid) async {
    if (fetchError != null) throw fetchError!;
    return existing;
  }

  @override
  Stream<UserModel?> watch(String uid) => Stream.value(existing);

  @override
  Future<void> create(UserModel user) async {
    created.add(user);
    existing = user;
  }

  @override
  Future<void> updateProfile(UserModel user) async => existing = user;

  @override
  Future<void> updateFields(String uid, Map<String, Object?> fields) async => fieldUpdates.add(fields);

  @override
  Future<String> uploadAvatar(String uid, Uint8List jpegBytes) async => 'https://example.com/a.jpg';

  @override
  Future<void> deleteAccount() async {}
}

class FakeAnalytics implements AnalyticsService {
  final events = <String, Map<String, Object>?>{};

  @override
  Future<void> log(String name, [Map<String, Object>? parameters]) async => events[name] = parameters;
}

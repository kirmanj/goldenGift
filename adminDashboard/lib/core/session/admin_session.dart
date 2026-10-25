import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:golden_gift/core/constants/firestore_paths.dart';
import 'package:golden_gift/core/providers/firebase_providers.dart';
import 'package:golden_gift/models/store_model.dart';

/// Admin roles (SRS §6.14 `admins/{uid}.role`).
enum AdminRole { superAdmin, ops, content, finance, seller }

AdminRole adminRoleFrom(Object? value) => switch (value) {
      'super' => AdminRole.superAdmin,
      'ops' => AdminRole.ops,
      'content' => AdminRole.content,
      'finance' => AdminRole.finance,
      'seller' => AdminRole.seller,
      _ => AdminRole.ops,
    };

/// Who is using the dashboard (SRS §9: email/password, admin claim required).
sealed class AdminAuthState {
  const AdminAuthState();
}

class AdminSignedOut extends AdminAuthState {
  const AdminSignedOut();
}

/// Signed in, but the account has no `admin` custom claim (or no admins doc).
class AdminNotAuthorized extends AdminAuthState {
  const AdminNotAuthorized(this.email);
  final String? email;
}

class AdminSession extends AdminAuthState {
  const AdminSession({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.permissions = const [],
    this.storeId,
  });

  final String uid;
  final String email;
  final String name;
  final AdminRole role;
  final List<String> permissions;

  /// Seller accounts (claim `seller == storeId`, Phase 8) see only their store.
  final String? storeId;

  bool get isSuper => role == AdminRole.superAdmin;

  /// A partner account limited to [storeId] (SRS §9 "Seller view").
  bool get isSeller => role == AdminRole.seller;
}

/// Reads the custom claims (force-refreshed, so a just-granted claim applies)
/// and `admins/{uid}`. Both are required: the claim is what security rules
/// check; the doc holds the name and role.
Future<AdminAuthState> resolveAdmin(User? user, FirebaseFirestore db) async {
  if (user == null) return const AdminSignedOut();
  final token = await user.getIdTokenResult(true);
  return resolveAdminClaims(
    uid: user.uid,
    email: user.email,
    displayName: user.displayName,
    claims: token.claims ?? const {},
    db: db,
  );
}

/// [resolveAdmin] after the token is read (testable without Firebase Auth).
///
/// Staff: claim `admin == true` + `admins/{uid}`. Partners (SRS §5.25, Phase 8):
/// `reviewPartner` grants claim `seller == storeId` (never `admin`, so the
/// security rules keep them to their store) and writes `admins/{uid}`
/// `{role: seller, storeId}`; the store id always comes from the claim. The
/// doc only adds the name, so a seller whose doc can't be read still gets in.
Future<AdminAuthState> resolveAdminClaims({
  required String uid,
  required String? email,
  String? displayName,
  required Map<String, dynamic> claims,
  required FirebaseFirestore db,
}) async {
  final sellerStore = claims['seller'];
  if (claims['admin'] != true) {
    if (sellerStore is! String || sellerStore.isEmpty) return AdminNotAuthorized(email);
    Map<String, dynamic>? data;
    try {
      data = (await db.doc('${FirestorePaths.admins}/$uid').get()).data();
    } catch (_) {
      data = null;
    }
    return AdminSession(
      uid: uid,
      email: email ?? data?['email'] as String? ?? '',
      name: data?['name'] as String? ?? displayName ?? email ?? 'Partner',
      role: AdminRole.seller,
      storeId: sellerStore,
    );
  }
  final doc = await db.doc('${FirestorePaths.admins}/$uid').get();
  if (!doc.exists) return AdminNotAuthorized(email);
  final data = doc.data()!;
  final role = adminRoleFrom(data['role']);
  return AdminSession(
    uid: uid,
    email: email ?? data['email'] as String? ?? '',
    name: data['name'] as String? ?? email ?? 'Admin',
    role: role,
    permissions: (data['permissions'] as List?)?.whereType<String>().toList() ?? const [],
    storeId: role == AdminRole.seller
        ? (sellerStore is String && sellerStore.isNotEmpty ? sellerStore : data['storeId'] as String?)
        : null,
  );
}

final adminAuthProvider = StreamProvider<AdminAuthState>((ref) {
  final db = ref.watch(firestoreProvider);
  return ref.watch(firebaseAuthProvider).idTokenChanges().asyncMap((user) => resolveAdmin(user, db));
});

/// The signed-in admin; throws if used outside the gated pages.
final adminSessionProvider = Provider<AdminSession?>((ref) {
  final state = ref.watch(adminAuthProvider).valueOrNull;
  return state is AdminSession ? state : null;
});

/// The signed-in seller's store (`stores/{storeId}`), null when the account
/// is not a seller or the store doc is missing (e.g. a rejected application).
/// AdminScaffold shows a pending / suspended page unless it is `active`.
final sellerStoreProvider = StreamProvider<StoreModel?>((ref) {
  final session = ref.watch(adminSessionProvider);
  final storeId = session?.role == AdminRole.seller ? session!.storeId : null;
  if (storeId == null || storeId.isEmpty) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .doc(FirestorePaths.storeDoc(storeId))
      .snapshots()
      .map((d) => d.exists ? StoreModel.fromMap(d.id, d.data()!) : null);
});

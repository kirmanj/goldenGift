import '../core/constants/app_constants.dart';
import '../core/utils/firestore_parse.dart';

/// `users/{uid}` (SRS §6.1).
///
/// The app writes the profile fields and `referralCodeEntered`; `referralCode`,
/// `referredBy`, `role`, `storeIds`, `isBlocked` and the order totals are
/// server-owned (set by `onUserCreate` / functions / admin — SRS AUTH-3, §6.17),
/// so [toProfileMap] never includes them.
class UserModel {
  const UserModel({
    required this.uid,
    required this.name,
    this.email,
    required this.phone,
    this.countryCode = AppConstants.defaultCountryCode,
    this.photoUrl,
    this.birthday,
    this.gender,
    this.city,
    this.locale = AppConstants.defaultLocale,
    this.role = UserRole.customer,
    this.storeIds = const [],
    this.referralCode,
    this.referralCodeEntered,
    this.referredBy,
    this.profileCompleted = false,
    this.fcmTokens = const [],
    this.notificationsEnabled = true,
    this.totalOrders = 0,
    this.totalSpent = 0,
    this.lastSeenAt,
    this.isBlocked = false,
    this.deviceId,
    this.isDeleted = false,
    this.createdAt,
  });

  final String uid;
  final String name;
  final String? email;

  /// National number without the country code.
  final String phone;
  final String countryCode;
  final String? photoUrl;
  final DateTime? birthday;
  final String? gender;

  /// City id from `app_settings/cities`.
  final String? city;
  final String locale;
  final UserRole role;
  final List<String> storeIds;
  final String? referralCode;
  final String? referralCodeEntered;
  final String? referredBy;
  final bool profileCompleted;
  final List<String> fcmTokens;
  final bool notificationsEnabled;
  final int totalOrders;
  final int totalSpent;
  final DateTime? lastSeenAt;
  final bool isBlocked;

  /// Random per-install id written at sign-up (same-device referral check).
  final String? deviceId;
  final bool isDeleted;
  final DateTime? createdAt;

  /// Google/Apple accounts may not have verified a phone yet (SRS AUTH-4).
  bool get hasPhone => phone.isNotEmpty;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// Profile is complete when name, email, birthday, gender and city are set (SRS §5.4 item 11).
  bool get computedProfileCompleted =>
      name.trim().isNotEmpty &&
      (email?.isNotEmpty ?? false) &&
      birthday != null &&
      (gender?.isNotEmpty ?? false) &&
      (city?.isNotEmpty ?? false);

  factory UserModel.fromMap(String uid, Map<String, dynamic> map) => UserModel(
        uid: uid,
        name: map['name'] as String? ?? '',
        email: FirestoreParse.stringOrNull(map['email']),
        phone: map['phone'] as String? ?? '',
        countryCode: map['countryCode'] as String? ?? AppConstants.defaultCountryCode,
        photoUrl: FirestoreParse.stringOrNull(map['photoUrl']),
        birthday: FirestoreParse.date(map['birthday']),
        gender: FirestoreParse.stringOrNull(map['gender']),
        city: FirestoreParse.stringOrNull(map['city']),
        locale: map['locale'] as String? ?? AppConstants.defaultLocale,
        role: FirestoreParse.enumValue(UserRole.values, map['role'], UserRole.customer),
        storeIds: FirestoreParse.stringList(map['storeIds']),
        referralCode: FirestoreParse.stringOrNull(map['referralCode']),
        referralCodeEntered: FirestoreParse.stringOrNull(map['referralCodeEntered']),
        referredBy: FirestoreParse.stringOrNull(map['referredBy']),
        profileCompleted: FirestoreParse.boolean(map['profileCompleted']),
        fcmTokens: FirestoreParse.stringList(map['fcmTokens']),
        notificationsEnabled: FirestoreParse.boolean(map['notificationsEnabled'], true),
        totalOrders: FirestoreParse.integer(map['totalOrders']),
        totalSpent: FirestoreParse.integer(map['totalSpent']),
        lastSeenAt: FirestoreParse.date(map['lastSeenAt']),
        isBlocked: FirestoreParse.boolean(map['isBlocked']),
        deviceId: FirestoreParse.stringOrNull(map['deviceId']),
        isDeleted: FirestoreParse.boolean(map['isDeleted']),
        createdAt: FirestoreParse.date(map['createdAt']),
      );

  /// The document the app creates after the first sign-in (SRS AUTH-3).
  /// Exactly the creation keys the production rules allow; `onUserCreate`
  /// adds the server-owned fields. Timestamps are set by the repository.
  Map<String, dynamic> toCreateMap() => {
        'name': name,
        'email': email,
        'phone': hasPhone ? phone : null,
        'countryCode': countryCode,
        'locale': locale,
        'referralCodeEntered': referralCodeEntered,
        'deviceId': deviceId,
        'photoUrl': photoUrl,
        'notificationsEnabled': notificationsEnabled,
        'profileCompleted': computedProfileCompleted,
      };

  /// Pass a value wrapped in [Optional] to set a nullable field (including to null).
  UserModel copyWith({
    String? name,
    Optional<String?>? email,
    String? phone,
    String? countryCode,
    Optional<String?>? photoUrl,
    Optional<DateTime?>? birthday,
    Optional<String?>? gender,
    Optional<String?>? city,
    String? locale,
    bool? notificationsEnabled,
  }) =>
      UserModel(
        uid: uid,
        name: name ?? this.name,
        email: email != null ? email.value : this.email,
        phone: phone ?? this.phone,
        countryCode: countryCode ?? this.countryCode,
        photoUrl: photoUrl != null ? photoUrl.value : this.photoUrl,
        birthday: birthday != null ? birthday.value : this.birthday,
        gender: gender != null ? gender.value : this.gender,
        city: city != null ? city.value : this.city,
        locale: locale ?? this.locale,
        role: role,
        storeIds: storeIds,
        referralCode: referralCode,
        referralCodeEntered: referralCodeEntered,
        referredBy: referredBy,
        profileCompleted: profileCompleted,
        fcmTokens: fcmTokens,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        totalOrders: totalOrders,
        totalSpent: totalSpent,
        lastSeenAt: lastSeenAt,
        isBlocked: isBlocked,
        deviceId: deviceId,
        isDeleted: isDeleted,
        createdAt: createdAt,
      );

  /// Fields the customer may write on their own document.
  Map<String, dynamic> toProfileMap() => {
        'name': name,
        'email': email,
        'phone': hasPhone ? phone : null,
        'countryCode': countryCode,
        'photoUrl': photoUrl,
        'birthday': birthday,
        'gender': gender,
        'city': city,
        'locale': locale,
        'notificationsEnabled': notificationsEnabled,
        'profileCompleted': computedProfileCompleted,
      };
}

/// Wraps a nullable value for `copyWith`, so "set to null" differs from "unchanged".
class Optional<T> {
  const Optional(this.value);
  final T value;
}

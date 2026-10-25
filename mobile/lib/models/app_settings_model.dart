import '../core/utils/firestore_parse.dart';
import 'localized_text.dart';

/// `app_settings/general` (SRS §6.14).
class GeneralSettings {
  const GeneralSettings({
    this.supportPhone = '',
    this.whatsapp = '',
    this.email = '',
    this.instagram = '',
    this.sameDayCutoff = '14:00',
    this.minOrder = 0,
    this.maintenanceMode = false,
    this.minAppVersionIos = '1.0.0',
    this.minAppVersionAndroid = '1.0.0',
    this.storeUrlIos = '',
    this.storeUrlAndroid = '',
    this.deliverySlots = DeliverySlot.defaults,
  });

  final String supportPhone;
  final String whatsapp;
  final String email;
  final String instagram;

  /// Local time "HH:mm"; orders after it can't ship today (SRS §5.11).
  final String sameDayCutoff;
  final int minOrder;
  final bool maintenanceMode;
  final String minAppVersionIos;
  final String minAppVersionAndroid;

  /// Store links for the force-update button (empty until the listing exists).
  final String storeUrlIos;
  final String storeUrlAndroid;

  /// Checkout time windows (SRS §5.11); defaults when the doc has none.
  final List<DeliverySlot> deliverySlots;

  factory GeneralSettings.fromMap(Map<String, dynamic> map) {
    final minVersion = FirestoreParse.map(map['minAppVersion']);
    final storeUrls = FirestoreParse.map(map['storeUrls']);
    return GeneralSettings(
      supportPhone: map['supportPhone'] as String? ?? '',
      whatsapp: map['whatsapp'] as String? ?? '',
      email: map['email'] as String? ?? '',
      instagram: map['instagram'] as String? ?? '',
      sameDayCutoff: map['sameDayCutoff'] as String? ?? '14:00',
      minOrder: FirestoreParse.integer(map['minOrder']),
      maintenanceMode: FirestoreParse.boolean(map['maintenanceMode']),
      minAppVersionIos: minVersion['ios'] as String? ?? '1.0.0',
      minAppVersionAndroid: minVersion['android'] as String? ?? '1.0.0',
      storeUrlIos: storeUrls['ios'] as String? ?? '',
      storeUrlAndroid: storeUrls['android'] as String? ?? '',
      deliverySlots: () {
        final slots = FirestoreParse.mapList(map['deliverySlots']).map(DeliverySlot.fromMap).toList();
        return slots.isEmpty ? DeliverySlot.defaults : slots;
      }(),
    );
  }

  Map<String, dynamic> toMap() => {
        'supportPhone': supportPhone,
        'whatsapp': whatsapp,
        'email': email,
        'instagram': instagram,
        'sameDayCutoff': sameDayCutoff,
        'minOrder': minOrder,
        'maintenanceMode': maintenanceMode,
        'minAppVersion': {'ios': minAppVersionIos, 'android': minAppVersionAndroid},
        'storeUrls': {'ios': storeUrlIos, 'android': storeUrlAndroid},
        'deliverySlots': deliverySlots.map((s) => s.toMap()).toList(),
      };
}

/// A delivery time window, local time "HH:mm" (SRS §5.11, §6.14).
class DeliverySlot {
  const DeliverySlot({required this.id, required this.label, required this.from, required this.to});

  final String id;
  final LocalizedText label;
  final String from;
  final String to;

  static const defaults = [
    DeliverySlot(id: 'morning', label: LocalizedText('Morning', ar: 'صباحًا', ku: 'بەیانی'), from: '10:00', to: '14:00'),
    DeliverySlot(id: 'afternoon', label: LocalizedText('Afternoon', ar: 'بعد الظهر', ku: 'دوانیوەڕۆ'), from: '14:00', to: '18:00'),
    DeliverySlot(id: 'evening', label: LocalizedText('Evening', ar: 'مساءً', ku: 'ئێوارە'), from: '18:00', to: '22:00'),
  ];

  factory DeliverySlot.fromMap(Map<String, dynamic> map) => DeliverySlot(
        id: map['id'] as String? ?? '',
        label: LocalizedText.fromMap(map, 'label'),
        from: map['from'] as String? ?? '00:00',
        to: map['to'] as String? ?? '23:59',
      );

  Map<String, dynamic> toMap() => {'id': id, ...label.toMap('label'), 'from': from, 'to': to};
}

/// One entry of `app_settings/cities.items` (SRS §4.3).
class CityModel {
  const CityModel({
    required this.id,
    required this.name,
    this.deliveryFee = 0,
    this.isActive = true,
  });

  final String id;
  final LocalizedText name;
  final int deliveryFee;
  final bool isActive;

  factory CityModel.fromMap(Map<String, dynamic> map) => CityModel(
        id: map['id'] as String? ?? '',
        name: LocalizedText.fromMap(map, 'name'),
        deliveryFee: FirestoreParse.integer(map['deliveryFee']),
        isActive: FirestoreParse.boolean(map['isActive'], true),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        ...name.toMap('name'),
        'deliveryFee': deliveryFee,
        'isActive': isActive,
      };

  /// Parses the whole `app_settings/cities` document.
  static List<CityModel> listFromDoc(Map<String, dynamic> doc) =>
      FirestoreParse.mapList(doc['items']).map(CityModel.fromMap).toList();
}

/// `app_settings/referral` (SRS §5.19).
class ReferralSettings {
  const ReferralSettings({
    this.joinBonus = 0,
    this.orderBonus = 0,
    this.maxReferralsPerMonth = 0,
    this.creditsExpiryDays = 0,
  });

  final int joinBonus;
  final int orderBonus;
  final int maxReferralsPerMonth;
  final int creditsExpiryDays;

  factory ReferralSettings.fromMap(Map<String, dynamic> map) => ReferralSettings(
        joinBonus: FirestoreParse.integer(map['joinBonus']),
        orderBonus: FirestoreParse.integer(map['orderBonus']),
        maxReferralsPerMonth: FirestoreParse.integer(map['maxReferralsPerMonth']),
        creditsExpiryDays: FirestoreParse.integer(map['creditsExpiryDays']),
      );

  Map<String, dynamic> toMap() => {
        'joinBonus': joinBonus,
        'orderBonus': orderBonus,
        'maxReferralsPerMonth': maxReferralsPerMonth,
        'creditsExpiryDays': creditsExpiryDays,
      };
}

/// `app_settings/payments` (SRS §6.14) — which payment methods are offered.
class PaymentSettings {
  const PaymentSettings({
    this.cashOnDelivery = true,
    this.wallet = true,
    this.card = false,
    this.fastPay = false,
    this.zainCash = false,
  });

  final bool cashOnDelivery;
  final bool wallet;
  final bool card;
  final bool fastPay;
  final bool zainCash;

  bool get anyOnlineGateway => card || fastPay || zainCash;

  factory PaymentSettings.fromMap(Map<String, dynamic> map) => PaymentSettings(
        cashOnDelivery: FirestoreParse.boolean(map['cashOnDelivery'], true),
        wallet: FirestoreParse.boolean(map['wallet'], true),
        card: FirestoreParse.boolean(map['card']),
        fastPay: FirestoreParse.boolean(map['fastPay']),
        zainCash: FirestoreParse.boolean(map['zainCash']),
      );

  Map<String, dynamic> toMap() => {
        'cashOnDelivery': cashOnDelivery,
        'wallet': wallet,
        'card': card,
        'fastPay': fastPay,
        'zainCash': zainCash,
      };
}

/// `app_settings/search` (SRS §6.14): Algolia for text search. The search key
/// is Algolia's public search-only key. Missing → Firestore keyword fallback.
class SearchSettings {
  const SearchSettings({this.algoliaAppId = '', this.algoliaSearchKey = '', this.indexName = 'products'});

  final String algoliaAppId;
  final String algoliaSearchKey;
  final String indexName;

  bool get isConfigured => algoliaAppId.isNotEmpty && algoliaSearchKey.isNotEmpty;

  factory SearchSettings.fromMap(Map<String, dynamic> map) => SearchSettings(
        algoliaAppId: map['algoliaAppId'] as String? ?? '',
        algoliaSearchKey: map['algoliaSearchKey'] as String? ?? '',
        indexName: (map['indexName'] as String?)?.isNotEmpty == true ? map['indexName'] as String : 'products',
      );

  Map<String, dynamic> toMap() => {
        'algoliaAppId': algoliaAppId,
        'algoliaSearchKey': algoliaSearchKey,
        'indexName': indexName,
      };
}

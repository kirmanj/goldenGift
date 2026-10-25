import '../core/utils/firestore_parse.dart';

/// `users/{uid}/addresses/{id}` (SRS §5.20, §6.1).
class AddressModel {
  const AddressModel({
    required this.id,
    required this.label,
    required this.name,
    required this.phone,
    required this.city,
    required this.area,
    required this.street,
    this.building = '',
    this.floor = '',
    this.notes = '',
    this.lat,
    this.lng,
    this.isDefault = false,
  });

  final String id;

  /// "Home", "Work", "Mum's house"…
  final String label;
  final String name;

  /// Recipient's phone in E.164, e.g. +9647501234567 (may differ from the
  /// account's). Older national-only values are read as Iraqi numbers.
  final String phone;

  /// City id from `app_settings/cities`.
  final String city;
  final String area;
  final String street;
  final String building;
  final String floor;
  final String notes;

  /// Map pin (Phase 9).
  final double? lat;
  final double? lng;
  final bool isDefault;

  factory AddressModel.fromMap(String id, Map<String, dynamic> map) => AddressModel(
        id: id,
        label: map['label'] as String? ?? '',
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        city: map['city'] as String? ?? '',
        area: map['area'] as String? ?? '',
        street: map['street'] as String? ?? '',
        building: map['building'] as String? ?? '',
        floor: map['floor'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        lat: map['lat'] is num ? (map['lat'] as num).toDouble() : null,
        lng: map['lng'] is num ? (map['lng'] as num).toDouble() : null,
        isDefault: FirestoreParse.boolean(map['isDefault']),
      );

  Map<String, dynamic> toMap() => {
        'label': label,
        'name': name,
        'phone': phone,
        'city': city,
        'area': area,
        'street': street,
        'building': building,
        'floor': floor,
        'notes': notes,
        'lat': lat,
        'lng': lng,
        'isDefault': isDefault,
      };

  AddressModel copyWith({String? id, bool? isDefault}) => AddressModel(
        id: id ?? this.id,
        label: label,
        name: name,
        phone: phone,
        city: city,
        area: area,
        street: street,
        building: building,
        floor: floor,
        notes: notes,
        lat: lat,
        lng: lng,
        isDefault: isDefault ?? this.isDefault,
      );

  /// "Street, Building, Floor · Area" — the city is shown separately (localized).
  String get oneLine => [street, building, floor].where((p) => p.trim().isNotEmpty).join(', ') +
      (area.trim().isEmpty ? '' : ' · $area');
}

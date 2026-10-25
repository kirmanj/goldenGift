import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings_model.dart';
import '../constants/firestore_paths.dart';
import 'firebase_providers.dart';

/// Live `app_settings/*` documents (SRS §6.14). Each falls back to model
/// defaults when the document is missing, so a fresh project still runs.
Stream<Map<String, dynamic>> _settingsDoc(FirebaseFirestore db, String id) => db
    .doc(FirestorePaths.settingsDoc(id))
    .snapshots()
    .map((snap) => snap.data() ?? const <String, dynamic>{});

final generalSettingsProvider = StreamProvider<GeneralSettings>((ref) =>
    _settingsDoc(ref.watch(firestoreProvider), 'general').map(GeneralSettings.fromMap));

final citiesProvider = StreamProvider<List<CityModel>>((ref) =>
    _settingsDoc(ref.watch(firestoreProvider), 'cities').map(CityModel.listFromDoc));

/// Only cities that currently accept deliveries.
final activeCitiesProvider = Provider<AsyncValue<List<CityModel>>>((ref) => ref
    .watch(citiesProvider)
    .whenData((cities) => cities.where((c) => c.isActive).toList()));

final referralSettingsProvider = StreamProvider<ReferralSettings>((ref) =>
    _settingsDoc(ref.watch(firestoreProvider), 'referral').map(ReferralSettings.fromMap));

final paymentSettingsProvider = StreamProvider<PaymentSettings>((ref) =>
    _settingsDoc(ref.watch(firestoreProvider), 'payments').map(PaymentSettings.fromMap));

final searchSettingsProvider = StreamProvider<SearchSettings>((ref) =>
    _settingsDoc(ref.watch(firestoreProvider), 'search').map(SearchSettings.fromMap));

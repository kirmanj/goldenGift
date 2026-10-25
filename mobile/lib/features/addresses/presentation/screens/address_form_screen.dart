import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/country_codes.dart';
import '../../../../core/providers/app_settings_providers.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/l10n.dart';
import '../../../../models/address_model.dart';
import '../../../auth/presentation/widgets/auth_messages.dart';
import '../../../auth/presentation/widgets/phone_field.dart';
import '../../../orders/presentation/widgets/order_section.dart';
import '../../../profile/presentation/providers/profile_providers.dart';
import '../../../profile/presentation/widgets/profile_pickers.dart';
import '../../data/address_repository.dart';
import '../providers/address_map_providers.dart';
import '../widgets/address_card.dart';
import '../widgets/address_map_pin_field.dart';
import 'address_map_picker_screen.dart';

/// Add / edit an address (SRS §5.20). Save pops with the saved
/// [AddressModel]. With maps enabled ([mapsEnabledProvider]) the customer can
/// also pin the door on a map (lat / lng, Phase 9).
class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, this.addressId});

  /// null = new address.
  final String? addressId;

  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

enum _Field { label, name, phone, city, area, street }

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _cityText = TextEditingController();
  final _area = TextEditingController();
  final _street = TextEditingController();
  final _building = TextEditingController();
  final _floor = TextEditingController();
  final _notes = TextEditingController();
  CountryCode _country = CountryCodes.iraq;
  String _cityId = '';
  double? _lat;
  double? _lng;
  AddressModel? _existing;
  bool _loaded = false;
  bool _saving = false;
  Map<_Field, String?> _errors = const {};

  bool get _isEdit => widget.addressId != null && widget.addressId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loaded = !_isEdit;
  }

  @override
  void dispose() {
    for (final c in [_label, _name, _phone, _cityText, _area, _street, _building, _floor, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(AddressModel a) {
    _existing = a;
    _label.text = a.label;
    _name.text = a.name;
    final (country, national) = splitAddressPhone(a.phone);
    _country = country;
    _phone.text = national;
    _cityId = a.city;
    _area.text = a.area;
    _street.text = a.street;
    _building.text = a.building;
    _floor.text = a.floor;
    _notes.text = a.notes;
    _lat = a.lat;
    _lng = a.lng;
    _loaded = true;
  }

  Future<void> _pickCity() async {
    final city = await showCityPickerSheet(context, selectedId: _cityId.isEmpty ? null : _cityId);
    if (city == null || !mounted) return;
    setState(() {
      _cityId = city.id;
      _errors = {..._errors, _Field.city: null};
    });
  }

  Future<void> _pickOnMap() async {
    final current = _lat == null || _lng == null ? null : (lat: _lat!, lng: _lng!);
    final pin = await showAddressMapPicker(context, initial: current);
    if (pin == null || !mounted) return;
    setState(() {
      _lat = pin.lat;
      _lng = pin.lng;
    });
  }

  Map<_Field, String?> _validate(AppLocalizations l10n) {
    String? required(TextEditingController c) => c.text.trim().isEmpty ? l10n.errorRequired : null;
    return {
      _Field.label: required(_label),
      _Field.name: l10n.validation(Validators.name(_name.text)),
      _Field.phone: l10n.validation(Validators.phone(_phone.text, _country)),
      _Field.city: _cityId.isEmpty ? l10n.errorRequired : null,
      _Field.area: required(_area),
      _Field.street: required(_street),
    };
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final errors = _validate(l10n);
    setState(() => _errors = errors);
    if (errors.values.any((e) => e != null)) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(addressRepositoryProvider).save(
            uid,
            AddressModel(
              id: _existing?.id ?? '',
              label: _label.text.trim(),
              name: _name.text.trim(),
              phone: addressPhoneValue(_phone.text, _country),
              city: _cityId,
              area: _area.text.trim(),
              street: _street.text.trim(),
              building: _building.text.trim(),
              floor: _floor.text.trim(),
              notes: _notes.text.trim(),
              lat: _lat,
              lng: _lng,
              isDefault: _existing?.isDefault ?? false,
            ),
          );
      if (mounted) context.pop(saved);
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final signedIn = ref.watch(isSignedInProvider);
    final title = _isEdit ? l10n.editAddress : l10n.addAddress;

    Widget body;
    if (!signedIn) {
      body = const GuestSignInCard(icon: Icons.location_on_rounded);
    } else if (!_loaded) {
      final addresses = ref.watch(addressesProvider);
      final found = addresses.valueOrNull?.where((a) => a.id == widget.addressId).firstOrNull;
      if (found != null) {
        _prefill(found);
        body = _form(context, l10n);
      } else if (addresses.isLoading) {
        body = const SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: SkeletonLoader.list(count: 4),
        );
      } else {
        body = CenteredScroll(child: ErrorState(onRetry: () => ref.invalidate(addressesProvider)));
      }
    } else {
      body = _form(context, l10n);
    }

    return Scaffold(
      backgroundColor: AppColors.bg(context),
      appBar: GGAppBar(title: title),
      body: body,
    );
  }

  Widget _form(BuildContext context, AppLocalizations l10n) {
    final cities = ref.watch(citiesProvider).valueOrNull ?? const [];
    final cityName = _cityId.isEmpty ? '' : cityDisplayName(context, cities, _cityId);
    if (_cityText.text != cityName) _cityText.text = cityName;
    const gap = SizedBox(height: AppSpacing.md);
    final bottom = math.max(AppSpacing.xl, MediaQuery.paddingOf(context).bottom + AppSpacing.md);
    void clear(_Field f) {
      if (_errors[f] != null) setState(() => _errors = {..._errors, f: null});
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(AppSpacing.screenHorizontal, AppSpacing.sm, AppSpacing.screenHorizontal, bottom),
      children: [
        GGInput(
          key: const ValueKey('address-label'),
          label: l10n.addressLabel,
          controller: _label,
          errorText: _errors[_Field.label],
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => clear(_Field.label),
        ),
        gap,
        GGInput(
          key: const ValueKey('address-name'),
          label: l10n.recipientName,
          controller: _name,
          errorText: _errors[_Field.name],
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          onChanged: (_) => clear(_Field.name),
        ),
        gap,
        KeyedSubtree(
          key: const ValueKey('address-phone'),
          child: PhoneField(
            controller: _phone,
            country: _country,
            errorText: _errors[_Field.phone],
            onCountryChanged: (c) => setState(() {
              _country = c;
              _errors = {..._errors, _Field.phone: null};
            }),
          ),
        ),
        gap,
        GGInput(
          key: const ValueKey('address-city'),
          label: l10n.city,
          hint: l10n.selectCity,
          controller: _cityText,
          readOnly: true,
          onTap: _pickCity,
          errorText: _errors[_Field.city],
          suffix: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.gold(context)),
        ),
        gap,
        GGInput(
          key: const ValueKey('address-area'),
          label: l10n.area,
          controller: _area,
          errorText: _errors[_Field.area],
          onChanged: (_) => clear(_Field.area),
        ),
        gap,
        GGInput(
          key: const ValueKey('address-street'),
          label: l10n.street,
          controller: _street,
          errorText: _errors[_Field.street],
          autofillHints: const [AutofillHints.streetAddressLine1],
          onChanged: (_) => clear(_Field.street),
        ),
        gap,
        GGInput(key: const ValueKey('address-building'), label: l10n.building, controller: _building),
        gap,
        GGInput(key: const ValueKey('address-floor'), label: l10n.floor, controller: _floor),
        gap,
        GGInput(
          key: const ValueKey('address-notes'),
          label: l10n.addressNotes,
          controller: _notes,
          multiline: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 300,
        ),
        if (ref.watch(mapsEnabledProvider)) ...[
          gap,
          AddressMapPinField(
            pin: _lat == null || _lng == null ? null : (lat: _lat!, lng: _lng!),
            onPick: _pickOnMap,
            onRemove: () => setState(() {
              _lat = null;
              _lng = null;
            }),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          key: const ValueKey('address-save'),
          label: l10n.save,
          isLoading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

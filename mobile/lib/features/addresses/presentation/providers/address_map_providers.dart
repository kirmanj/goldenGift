import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_env.dart';
import '../widgets/google_address_map.dart';

/// A map position (WGS84).
typedef GeoPin = ({double lat, double lng});

/// Address map pin on/off (SRS §5.20, Phase 9): needs a Google Maps key, so
/// it follows `--dart-define=MAPS_ENABLED=true` (never on web). Tests
/// override it.
final mapsEnabledProvider = Provider<bool>((ref) => AppEnv.mapsEnabled);

/// Builds the interactive map under the fixed centre pin; reports the
/// camera centre as it moves. Tests swap in a fake (no platform view).
typedef AddressMapBuilder = Widget Function(
  BuildContext context, {
  required GeoPin initial,
  required ValueChanged<GeoPin> onCenterChanged,
});

final addressMapBuilderProvider = Provider<AddressMapBuilder>(
  (ref) => (context, {required initial, required onCenterChanged}) =>
      GoogleAddressMap(initial: initial, onCenterChanged: onCenterChanged),
);

/// Where the map opens without a pin: central Erbil.
const GeoPin defaultMapCenter = (lat: 36.1911, lng: 44.0092);

/// "36.19110, 44.00920" — shown under "Location pinned".
String formatGeoPin(GeoPin pin) => '${pin.lat.toStringAsFixed(5)}, ${pin.lng.toStringAsFixed(5)}';

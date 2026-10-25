import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/address_map_providers.dart';

/// The Google map behind the address pin picker (SRS §5.20). The pin itself
/// is a fixed overlay in the picker; this only reports the camera centre.
class GoogleAddressMap extends StatelessWidget {
  const GoogleAddressMap({super.key, required this.initial, required this.onCenterChanged});

  final GeoPin initial;
  final ValueChanged<GeoPin> onCenterChanged;

  /// Muted night style so the map matches gold-on-black.
  static const _darkStyle = '[{"elementType":"geometry","stylers":[{"color":"#1a1a1c"}]},'
      '{"elementType":"labels.text.fill","stylers":[{"color":"#b0ada3"}]},'
      '{"elementType":"labels.text.stroke","stylers":[{"color":"#0e0e0f"}]},'
      '{"featureType":"road","elementType":"geometry","stylers":[{"color":"#343438"}]},'
      '{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e0e0f"}]},'
      '{"featureType":"poi","stylers":[{"visibility":"off"}]}]';

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: LatLng(initial.lat, initial.lng), zoom: 16),
      onCameraMove: (position) => onCenterChanged((lat: position.target.latitude, lng: position.target.longitude)),
      style: AppColors.isDark(context) ? _darkStyle : null,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: true,
    );
  }
}

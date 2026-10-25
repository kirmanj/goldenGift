import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Platform seams for the Profile area (SRS §5.13, §5.14). Each one is a
/// provider so widget tests can replace it without plugins.

/// Changing the phone goes through the `sendOtp` / `changePhone` functions
/// (OTPIQ), so it works on every platform. Kept as a seam for tests.
final phoneChangeSupportedProvider = Provider<bool>((ref) => true);

/// "1.0.0 (1)" for Settings ▸ version.
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.buildNumber.isEmpty ? info.version : '${info.version} (${info.buildNumber})';
});

/// Opens a web page outside the app (privacy policy, terms). Returns false
/// when nothing could handle the link.
typedef ExternalLinkOpener = Future<bool> Function(Uri uri);

final externalLinkOpenerProvider = Provider<ExternalLinkOpener>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Public pages linked from Settings (SRS §8 Privacy).
class ProfileLinks {
  ProfileLinks._();
  static final privacyPolicy = Uri.parse('https://goldengift.app/privacy');
  static final termsOfService = Uri.parse('https://goldengift.app/terms');
}

/// Largest avatar we upload (SRS §8: photo uploads ≤ 10 MB).
const maxAvatarBytes = 10 * 1024 * 1024;

/// Picks a profile photo, already downscaled to 512 px. Returns null when the
/// user closes the picker.
abstract class AvatarPicker {
  Future<Uint8List?> pick(ImageSource source);
}

class ImagePickerAvatarPicker implements AvatarPicker {
  ImagePickerAvatarPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    return file?.readAsBytes();
  }
}

final avatarPickerProvider = Provider<AvatarPicker>((ref) => ImagePickerAvatarPicker());

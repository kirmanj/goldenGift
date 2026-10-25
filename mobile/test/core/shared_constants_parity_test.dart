import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CLAUDE.md: enums and Firestore paths are defined twice (mobile + admin)
/// and must NOT diverge. These tests fail the build when they do.
/// (functions/test also checks its TypeScript copies against the mobile files.)
void main() {
  const mobileConstants = 'lib/core/constants/app_constants.dart';
  const adminConstants = '../adminDashboard/lib/core/constants/admin_constants.dart';
  const mobilePaths = 'lib/core/constants/firestore_paths.dart';
  const adminPaths = '../adminDashboard/lib/core/constants/firestore_paths.dart';

  String stripComments(String src) =>
      src.replaceAll(RegExp(r'//[^\n]*'), '').replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  Map<String, List<String>> enums(String path) {
    final src = stripComments(File(path).readAsStringSync());
    return {
      for (final m in RegExp(r'enum\s+(\w+)\s*\{([^}]*)\}').allMatches(src))
        m.group(1)!: m
            .group(2)!
            .split(';')
            .first
            .split(',')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
    };
  }

  Map<String, String> paths(String path) {
    final src = File(path).readAsStringSync();
    return {
      for (final m in RegExp(r"static const String (\w+) = '([^']*)';").allMatches(src))
        m.group(1)!: m.group(2)!,
    };
  }

  test('the dashboard re-exports the app enums and paths (one definition)', () {
    expect(File(adminConstants).readAsStringSync(),
        contains("export 'package:golden_gift/core/constants/app_constants.dart'"));
    expect(File(adminPaths).readAsStringSync(),
        contains("export 'package:golden_gift/core/constants/firestore_paths.dart'"));
    expect(File('../adminDashboard/pubspec.yaml').readAsStringSync(), contains('path: ../mobile'));
  });

  test('Firestore paths are well-formed and unique', () {
    final mobile = paths(mobilePaths);
    expect(mobile, isNotEmpty);
    final values = mobile.values.toList();
    expect(values.toSet().length, values.length, reason: 'two constants share a path');
  });

  test('stored enum values match SRS §6.15 spellings', () {
    final mobile = enums(mobileConstants);
    expect(mobile['OrderStatus'], [
      'pending', 'confirmed', 'preparing', 'readyForDelivery', 'outForDelivery',
      'delivered', 'cancelledByBuyer', 'cancelledBySeller', 'returned', 'refunded',
    ]);
    expect(mobile['OptionType'], [
      'imageVariant', 'textVariant', 'colorSwatch', 'text', 'longText', 'date', 'photoUpload', 'quantity',
    ]);
  });
}

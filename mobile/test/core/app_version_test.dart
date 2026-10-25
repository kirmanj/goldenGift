import 'package:flutter_test/flutter_test.dart';
import 'package:golden_gift/core/utils/app_version.dart';

void main() {
  test('lower versions are below the minimum', () {
    expect(AppVersion.isBelow('1.0.0', '1.0.1'), isTrue);
    expect(AppVersion.isBelow('1.9.9', '2.0.0'), isTrue);
    expect(AppVersion.isBelow('1.2', '1.2.1'), isTrue);
  });

  test('equal or higher versions pass', () {
    expect(AppVersion.isBelow('1.0.0', '1.0.0'), isFalse);
    expect(AppVersion.isBelow('1.10.0', '1.9.0'), isFalse);
    expect(AppVersion.isBelow('2.0.0+7', '1.9.9'), isFalse);
    expect(AppVersion.isBelow('1.2.0', '1.2'), isFalse);
  });

  test('build suffixes are ignored', () {
    expect(AppVersion.isBelow('1.2.0+3', '1.2.0'), isFalse);
    expect(AppVersion.isBelow('1.2.0-beta', '1.2.1'), isTrue);
  });

  test('a broken minimum never blocks the app', () {
    expect(AppVersion.isBelow('1.0.0', ''), isFalse);
    expect(AppVersion.isBelow('1.0.0', 'abc'), isFalse);
    expect(AppVersion.isBelow('1.0.0', '1.0.0.0'), isFalse);
  });
}

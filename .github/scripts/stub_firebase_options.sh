#!/usr/bin/env bash
# CI only: lib/firebase_options.dart is git-ignored (generated locally by
# `flutterfire configure`). Analyze and unit tests just need the symbols, so
# write a stub with dummy values. Never used for a real build.
#
# usage: stub_firebase_options.sh <flutter app dir>
set -euo pipefail

target="$1/lib/firebase_options.dart"
if [[ -f "$target" ]]; then
  echo "$target exists, leaving it alone"
  exit 0
fi

cat > "$target" <<'DART'
// CI stub — see .github/scripts/stub_firebase_options.sh
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: 'ci-stub',
        appId: '1:000000000000:web:0000000000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'goldengift-iq',
      );
}
DART
echo "wrote stub $target"

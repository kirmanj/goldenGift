#!/usr/bin/env bash
# Release CI only: writes the git-ignored Firebase config files of a Flutter app
# from base64 repository secrets (docs/RELEASE.md, "Secrets"). Fails when one is
# missing — a release is never built with the stub of stub_firebase_options.sh.
#
# usage: write_firebase_config.sh <flutter app dir> <part>...
#   dart     lib/firebase_options.dart               ← $FIREBASE_OPTIONS_DART_B64
#   android  android/app/google-services.json        ← $GOOGLE_SERVICES_JSON_B64
#   ios      ios/Runner/GoogleService-Info.plist     ← $GOOGLE_SERVICE_INFO_PLIST_B64
#
# Make a secret value from a working local checkout:  base64 -i <file> | pbcopy
set -euo pipefail

app="$1"
shift

decode() {
  local var="$1" target="$2"
  local value="${!var:-}"
  if [[ -z "$value" ]]; then
    echo "::error::Secret $var is not set — see docs/RELEASE.md (Secrets)."
    exit 1
  fi
  mkdir -p "$(dirname "$target")"
  printf '%s' "$value" | tr -d ' \r\n' | base64 --decode > "$target"
  if ! grep -q 'goldengift-iq' "$target"; then
    echo "::error::$var does not decode to a goldengift-iq config file ($target)."
    exit 1
  fi
  echo "wrote $target"
}

for part in "$@"; do
  case "$part" in
    dart)
      decode FIREBASE_OPTIONS_DART_B64 "$app/lib/firebase_options.dart"
      grep -q 'class DefaultFirebaseOptions' "$app/lib/firebase_options.dart" ||
        { echo "::error::FIREBASE_OPTIONS_DART_B64 is not a firebase_options.dart"; exit 1; }
      ;;
    android)
      decode GOOGLE_SERVICES_JSON_B64 "$app/android/app/google-services.json"
      python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$app/android/app/google-services.json" ||
        { echo "::error::GOOGLE_SERVICES_JSON_B64 is not valid JSON"; exit 1; }
      ;;
    ios)
      decode GOOGLE_SERVICE_INFO_PLIST_B64 "$app/ios/Runner/GoogleService-Info.plist"
      if command -v plutil > /dev/null; then plutil -lint "$app/ios/Runner/GoogleService-Info.plist"; fi
      ;;
    *)
      echo "::error::unknown part '$part' (dart | android | ios)"
      exit 1
      ;;
  esac
done

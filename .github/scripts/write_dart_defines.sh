#!/usr/bin/env bash
# Release CI: writes the JSON file passed to `flutter build … --dart-define-from-file`
# (switches read in mobile/lib/core/config/app_env.dart). Only non-empty values
# are written, so a missing secret / variable simply leaves the feature off.
#
#   MAPS_ENABLED=true        → MAPS_ENABLED (address map pin; mobile only — the
#                              workflow also hands the platform key to the build)
#   RECAPTCHA_SITE_KEY=…     → RECAPTCHA_SITE_KEY (App Check on the web builds)
#   DART_DEFINES_JSON='{…}'  → merged first (optional extra defines, JSON object)
#
# usage: write_dart_defines.sh <out.json>
set -euo pipefail

python3 - "$1" <<'PY'
import json
import os
import sys

defines = {}
extra = os.environ.get("DART_DEFINES_JSON", "").strip()
if extra:
    data = json.loads(extra)
    if not isinstance(data, dict):
        sys.exit("DART_DEFINES_JSON must be a JSON object")
    defines.update({str(k): str(v) for k, v in data.items()})

if os.environ.get("MAPS_ENABLED", "").strip().lower() == "true":
    defines["MAPS_ENABLED"] = "true"

site_key = os.environ.get("RECAPTCHA_SITE_KEY", "").strip()
if site_key:
    defines["RECAPTCHA_SITE_KEY"] = site_key

for forbidden in ("USE_EMULATOR", "EMULATOR_HOST"):
    if forbidden in defines:
        sys.exit(f"{forbidden} must never be set for a release build")

with open(sys.argv[1], "w", encoding="utf-8") as out:
    json.dump(defines, out)
print("dart-defines:", ", ".join(sorted(defines)) or "(none)")
PY

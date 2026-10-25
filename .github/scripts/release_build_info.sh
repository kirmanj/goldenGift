#!/usr/bin/env bash
# Release CI: version name + build number for a store build (docs/RELEASE.md,
# "Versioning"). Writes `version_name` and `build_number` to $GITHUB_OUTPUT.
#
#   version name  = pubspec.yaml `version:` without `+build`
#   build number  = $BUILD_NUMBER_OVERRIDE (workflow input), else
#                   $BUILD_NUMBER_OFFSET (repository variable, default 0) + $RUN_NUMBER
#
# On a tag push the tag must match the pubspec version: v1.2.0 (or v1.2.0-rc1)
# for `version: 1.2.0+…` — otherwise the build stops before anything is built.
#
# usage: release_build_info.sh <pubspec.yaml>
set -euo pipefail

pubspec="$1"
version="$(sed -n 's/^version:[[:space:]]*//p' "$pubspec" | head -n 1 | tr -d '[:space:]')"
name="${version%%+*}"
if [[ ! "$name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::$pubspec version '$version' is not MAJOR.MINOR.PATCH(+BUILD)"
  exit 1
fi

override="${BUILD_NUMBER_OVERRIDE:-}"
if [[ -n "$override" ]]; then
  [[ "$override" =~ ^[1-9][0-9]*$ ]] || { echo "::error::build number '$override' is not a positive integer"; exit 1; }
  build="$override"
else
  offset="${BUILD_NUMBER_OFFSET:-0}"
  [[ -z "$offset" ]] && offset=0
  [[ "$offset" =~ ^[0-9]+$ ]] || { echo "::error::BUILD_NUMBER_OFFSET '$offset' is not an integer"; exit 1; }
  build=$((offset + ${RUN_NUMBER:?RUN_NUMBER is required}))
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  tag="${GITHUB_REF_NAME#v}"
  if [[ "${tag%%-*}" != "$name" ]]; then
    echo "::error::tag ${GITHUB_REF_NAME} does not match pubspec version $name — bump mobile/pubspec.yaml or re-tag."
    exit 1
  fi
fi

echo "Golden Gift $name ($build)"
{
  echo "version_name=$name"
  echo "build_number=$build"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

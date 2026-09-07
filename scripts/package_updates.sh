#!/usr/bin/env bash
# Prepare local, signed release assets. This script never uploads or publishes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${XFLOW_BUILD_DIR:-$ROOT_DIR/.build-xflow}"
SPARKLE_TOOLS="$BUILD_DIR/artifacts/sparkle/Sparkle/bin"
ACCOUNT="com.distantg.xflow.updates"
for arch in arm64 x86_64; do
  case "$arch" in arm64) folder="Apple Silicon";; x86_64) folder="Intel";; esac
  app="$ROOT_DIR/dist/$folder/Mosaic.app"
  plist="$app/Contents/Info.plist"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
  expected_feed="https://raw.githubusercontent.com/distantg/xFlow/main/updates/$arch/appcast.xml"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == 'com.distantg.xflow' ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" == "$expected_feed" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" == "$("$SPARKLE_TOOLS/generate_keys" --account "$ACCOUNT" -p)" ]]
  codesign --verify --deep --strict "$app"
  output="$ROOT_DIR/dist/updates/$arch"
  mkdir -p "$output"
  archive="$output/Mosaic-$version-$build-$arch.zip"
  if [[ -e "$archive" ]]; then
    echo "Release archive already exists: $archive. Use a new build number or move the old staging output aside." >&2
    exit 2
  fi
  ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
  cp "$ROOT_DIR/Resources/UpdateReleaseNotes.html" "${archive%.zip}.html"
  "$SPARKLE_TOOLS/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/distantg/xFlow/releases/download/v$version/" \
    --link 'https://github.com/distantg/xFlow/releases' "$output"
  # Sign the feed as well as its enclosure. Do not edit it after signing.
  "$SPARKLE_TOOLS/sign_update" --account "$ACCOUNT" "$output/appcast.xml"
done
echo "Prepared dist/updates/{arm64,x86_64}. Nothing has been published."

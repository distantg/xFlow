#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="xFlow"
BIN_NAME="XFlow"
BUNDLE_ID="${XFLOW_BUNDLE_ID:-com.distantg.xflow}"
TARGET_ARCH="${XFLOW_ARCH:-arm64}"
case "$TARGET_ARCH" in
  arm64)
    ARCH_FOLDER="Apple Silicon"
    ;;
  x86_64)
    ARCH_FOLDER="Intel"
    ;;
  *)
    echo "Unsupported architecture: $TARGET_ARCH" >&2
    exit 2
    ;;
esac
APP_DIR_NAME="${XFLOW_APP_DIR_NAME:-${ARCH_FOLDER}/${APP_NAME}.app}"
APP_DIR="$ROOT_DIR/dist/${APP_DIR_NAME}"
BUILD_DIR="${XFLOW_BUILD_DIR:-$ROOT_DIR/.build-xflow}"
BIN_PATH="$BUILD_DIR/${TARGET_ARCH}-apple-macosx/release/${BIN_NAME}"
APP_ICON_PNG="$ROOT_DIR/AppIcon.png"
BASE_ENTITLEMENTS_FILE="$ROOT_DIR/Config/xFlow.entitlements"
CONTAINER_MIGRATION_FILE="$ROOT_DIR/Resources/container-migration.plist"
CODESIGN_IDENTITY="${XFLOW_CODESIGN_IDENTITY:-"-"}"
APS_ENVIRONMENT="${XFLOW_APS_ENVIRONMENT:-development}"

if [[ ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  echo "XFLOW_BUNDLE_ID must be a valid reverse-DNS bundle identifier." >&2
  exit 2
fi
for required_file in "$BASE_ENTITLEMENTS_FILE" "$CONTAINER_MIGRATION_FILE"; do
  if [[ ! -f "$required_file" || -L "$required_file" ]]; then
    echo "Required packaging file is missing or unsafe: $required_file" >&2
    exit 2
  fi
done

if [[ "$APP_DIR_NAME" == /* || "$APP_DIR_NAME" == *".."* || "$APP_DIR_NAME" == *$'\n'* || "$APP_DIR_NAME" == *$'\r'* ]]; then
  echo "XFLOW_APP_DIR_NAME must stay inside dist and cannot contain traversal components." >&2
  exit 2
fi
case "$APP_DIR_NAME" in
  "$APP_NAME.app")
    APP_PARENT=""
    ;;
  */"$APP_NAME.app")
    APP_PARENT="${APP_DIR_NAME%/$APP_NAME.app}"
    if [[ "$APP_PARENT" == */* ]]; then
      echo "XFLOW_APP_DIR_NAME may contain at most one output folder." >&2
      exit 2
    fi
    ;;
  *)
    echo "XFLOW_APP_DIR_NAME must end with $APP_NAME.app." >&2
    exit 2
    ;;
esac
if [[ -L "$ROOT_DIR/dist" || ( -n "$APP_PARENT" && -L "$ROOT_DIR/dist/$APP_PARENT" ) ]]; then
  echo "Refusing to package through a symbolic-link output directory." >&2
  exit 2
fi
if [[ "$APS_ENVIRONMENT" != "development" && "$APS_ENVIRONMENT" != "production" ]]; then
  echo "XFLOW_APS_ENVIRONMENT must be development or production." >&2
  exit 2
fi

cd "$ROOT_DIR"

swift build -c release -j 1 --arch "$TARGET_ARCH" --scratch-path "$BUILD_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.0</string>
    <key>CFBundleVersion</key>
    <string>6</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.social-networking</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
strip -S "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [[ -f "$APP_ICON_PNG" ]] && sips -g pixelWidth -g pixelHeight "$APP_ICON_PNG" >/dev/null 2>&1; then
  ICONSET_DIR="$ROOT_DIR/dist/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$APP_ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  cp "$APP_ICON_PNG" "$APP_DIR/Contents/Resources/AppIcon.png"
else
  echo "No valid AppIcon.png found at $APP_ICON_PNG (skipping custom icon)."
fi

cp "$CONTAINER_MIGRATION_FILE" "$APP_DIR/Contents/Resources/container-migration.plist"

xattr -cr "$APP_DIR" 2>/dev/null || true

ENTITLEMENTS_FILE="$BASE_ENTITLEMENTS_FILE"
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
  ENTITLEMENTS_FILE="$ROOT_DIR/dist/xFlow.entitlements"
  cp "$BASE_ENTITLEMENTS_FILE" "$ENTITLEMENTS_FILE"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.developer.aps-environment string $APS_ENVIRONMENT" \
    "$ENTITLEMENTS_FILE"
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --entitlements "$ENTITLEMENTS_FILE" \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Created: $APP_DIR"

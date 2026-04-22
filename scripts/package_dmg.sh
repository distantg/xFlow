#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="xFlow"
TARGET_ARCH="${XFLOW_ARCH:-arm64}"

case "$TARGET_ARCH" in
  arm64)
    ARCH_FOLDER="Apple Silicon"
    ARCH_SLUG="AppleSilicon"
    ARCH_LABEL="Apple Silicon"
    ;;
  x86_64)
    ARCH_FOLDER="Intel"
    ARCH_SLUG="Intel"
    ARCH_LABEL="Intel"
    ;;
  *)
    ARCH_FOLDER="$TARGET_ARCH"
    ARCH_SLUG="$TARGET_ARCH"
    ARCH_LABEL="$TARGET_ARCH"
    ;;
esac

APP_DIR="$ROOT_DIR/dist/${ARCH_FOLDER}/${APP_NAME}.app"
STAGING_DIR="$ROOT_DIR/dist/dmg-${ARCH_SLUG}"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_PNG="$BACKGROUND_DIR/background.png"
INSTRUCTIONS_FILE="$STAGING_DIR/Click here for installation instructions.txt"
RW_DMG="$ROOT_DIR/dist/${APP_NAME}-${ARCH_SLUG}.rw.dmg"
FINAL_DMG="$ROOT_DIR/dist/${APP_NAME}-${ARCH_SLUG}.dmg"
VOLUME_NAME="${APP_NAME} ${ARCH_LABEL}"

cd "$ROOT_DIR"

XFLOW_ARCH="$TARGET_ARCH" "$ROOT_DIR/scripts/package_app.sh"

rm -rf "$STAGING_DIR" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$BACKGROUND_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$INSTRUCTIONS_FILE" <<'TEXT'
xFlow installation instructions

1. Open the downloaded .dmg file.
2. Drag xFlow.app into the Applications shortcut.
3. Open your Applications folder.
4. Double-click xFlow.app.

Because xFlow is currently distributed without Apple notarization, macOS may show this warning:

"Apple could not verify “xFlow” is free of malware that may harm your Mac or compromise your privacy."

If you see that warning, do this:

1. Open Apple menu > System Settings.
2. Click Privacy & Security in the sidebar.
3. Scroll down to the Security section.
4. Click Open Anyway for xFlow.
5. Enter your Mac login password if prompted.
6. Click OK.

xFlow should open after that.

Important: the Open Anyway button is only available for about one hour after you first try to open the app. If you do not see it, try opening xFlow.app again, then return to Privacy & Security.

Why this happens:

xFlow is not notarized because it is currently distributed without an Apple Developer account. macOS shows this warning for non-notarized apps. This does not mean the app is malware, but you should only install apps from sources you trust.
TEXT

BACKGROUND_SCRIPT="$(mktemp /tmp/xflow-dmg-background.XXXXXX.swift)"
cat > "$BACKGROUND_SCRIPT" <<'SWIFT'
import AppKit

let outputPath = CommandLine.arguments[1]
let archLabel = CommandLine.arguments.dropFirst(2).first ?? "Mac"
let size = NSSize(width: 660, height: 400)
let image = NSImage(size: size)

image.lockFocus()

let bounds = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1.0).setFill()
bounds.fill()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.95),
    NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.93, alpha: 0.95)
])
gradient?.draw(in: bounds, angle: 315)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 28, weight: .bold),
    .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    .paragraphStyle: titleStyle
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.26, alpha: 1),
    .paragraphStyle: titleStyle
]

"Install xFlow".draw(in: NSRect(x: 0, y: 324, width: size.width, height: 36), withAttributes: titleAttributes)
"Drag xFlow.app into Applications".draw(in: NSRect(x: 0, y: 294, width: size.width, height: 24), withAttributes: subtitleAttributes)

func roundedPanel(_ rect: NSRect) {
    let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
    path.fill()
    NSColor(calibratedWhite: 1.0, alpha: 0.85).setStroke()
    path.lineWidth = 1.5
    path.stroke()
}

roundedPanel(NSRect(x: 94, y: 180, width: 150, height: 116))
roundedPanel(NSRect(x: 416, y: 180, width: 150, height: 116))

let iconStyle = NSMutableParagraphStyle()
iconStyle.alignment = .center

let arrowAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 64, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 0.52),
    .paragraphStyle: iconStyle
]
"→".draw(in: NSRect(x: 270, y: 208, width: 120, height: 76), withAttributes: arrowAttributes)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Could not render DMG background")
}

try png.write(to: URL(fileURLWithPath: outputPath))
SWIFT

swift "$BACKGROUND_SCRIPT" "$BACKGROUND_PNG" "$ARCH_LABEL"
rm -f "$BACKGROUND_SCRIPT"

hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOLUME_NAME" -fs HFS+ -format UDRW "$RW_DMG" >/dev/null

MOUNT_DIR="$(mktemp -d /tmp/xflow-dmg-mount.XXXXXX)"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" >/dev/null

osascript >/dev/null <<APPLESCRIPT
tell application "Finder"
    set dmgFolder to POSIX file "$MOUNT_DIR" as alias
    set backgroundImage to POSIX file "$MOUNT_DIR/.background/background.png" as alias
    open dmgFolder
    set dmgWindow to container window of dmgFolder
    set current view of dmgWindow to icon view
    set toolbar visible of dmgWindow to false
    set statusbar visible of dmgWindow to false
    set bounds of dmgWindow to {100, 100, 760, 500}
    set arrangement of icon view options of dmgWindow to not arranged
    set icon size of icon view options of dmgWindow to 88
    set background picture of icon view options of dmgWindow to backgroundImage
    set position of item "xFlow.app" of dmgFolder to {170, 170}
    set position of item "Applications" of dmgFolder to {492, 170}
    set position of item "Click here for installation instructions.txt" of dmgFolder to {330, 236}
    close dmgWindow
    open dmgFolder
    update dmgFolder without registering applications
    delay 1
end tell
APPLESCRIPT

bless --folder "$MOUNT_DIR" --openfolder "$MOUNT_DIR" >/dev/null 2>&1 || true

hdiutil detach "$MOUNT_DIR" >/dev/null
rmdir "$MOUNT_DIR"

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"

echo "Created: $FINAL_DMG"

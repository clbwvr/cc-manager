#!/usr/bin/env bash
# Build cc-manager and install it as a .app bundle in ~/Applications.
# Re-run whenever you change the source to update the installed app.

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="cc-manager"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
BUNDLE_ID="com.calebweaver.ccmanager"

echo "Building (release)..."
swift build -c release

BIN_PATH=".build/release/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Build did not produce $BIN_PATH" >&2
    exit 1
fi

echo "Installing to $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Generate .icns icon from our Swift drawing script.
ICON_SRC=".build/AppIcon.png"
ICONSET=".build/AppIcon.iconset"
ICNS="$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Generating app icon..."
swift tools/make_icon.swift "$ICON_SRC" >/dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
cp "$ICON_SRC" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ICNS"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>Claude Conversations</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Conversations</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>cc-manager needs to control iTerm2 to open Claude Code sessions.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS doesn't complain about an unsigned app launch.
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Installed: $APP_DIR"
echo "Launch with: open \"$APP_DIR\"  (or Spotlight: Claude Conversations)"

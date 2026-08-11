#!/bin/bash
# Build caliper and launch it as a minimal .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$ROOT/.build/Caliper.app"

echo "› building"
swift build --package-path "$ROOT" -c debug

echo "› bundling $BUNDLE"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$ROOT/.build/debug/caliper" "$BUNDLE/Contents/MacOS/caliper"
cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Caliper</string>
  <key>CFBundleDisplayName</key><string>Caliper</string>
  <key>CFBundleExecutable</key><string>caliper</string>
  <key>CFBundleIdentifier</key><string>dev.gustaf.caliper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.0.1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

mkdir -p "$BUNDLE/Contents/Resources"
cp "$ROOT/icon/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"

pkill -x caliper 2>/dev/null || true
open -n "$BUNDLE"

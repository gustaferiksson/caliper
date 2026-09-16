#!/bin/bash
# Assemble .build/Caliper.app from an already-built executable.
# Usage: [VERSION=1.2.3] [BUILD=7] ./bundle.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-debug}"
VERSION="${VERSION:-0.0.1}"
BUILD="${BUILD:-1}"
BUNDLE="$ROOT/.build/Caliper.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ROOT/.build/$CONFIG/caliper" "$BUNDLE/Contents/MacOS/caliper"
cp "$ROOT/icon/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
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
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict>
</plist>
PLIST

echo "› bundled $BUNDLE"

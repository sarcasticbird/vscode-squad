#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodeSquad"
BUILD_DIR="$SCRIPT_DIR/.build/debug"
APP_BUNDLE="$SCRIPT_DIR/.build/${APP_NAME}.app"

swift build

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$SCRIPT_DIR/$APP_NAME/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

codesign -s - --force --deep "$APP_BUNDLE"

# Reset TCC so the new binary hash gets a fresh grant
tccutil reset Accessibility com.cdolan.codesquad 2>/dev/null || true

echo "Built $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"

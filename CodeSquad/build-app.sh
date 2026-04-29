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

ASSETS_DIR="$SCRIPT_DIR/$APP_NAME/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    xcrun actool "$ASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$APP_BUNDLE/Contents/Resources/AssetCatalog.plist" \
        > /dev/null 2>&1
fi

codesign -s - --force --deep "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
echo "Run with: open $APP_BUNDLE"

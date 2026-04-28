#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_BUNDLE="$PROJECT_DIR/.build/CodeSquad.app"
BINARY="$PROJECT_DIR/.build/debug/CodeSquad"
ENTITLEMENTS="$PROJECT_DIR/CodeSquad/CodeSquad.entitlements"
CERT_NAME="CodeSquad Dev"
BUNDLE_ID="com.cdolan.codesquad"

cd "$PROJECT_DIR"

echo "==> Building..."
swift build 2>&1

echo "==> Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/CodeSquad"
cp "$PROJECT_DIR/CodeSquad/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

ASSETS_DIR="$PROJECT_DIR/CodeSquad/Assets.xcassets"
if [ -d "$ASSETS_DIR" ]; then
    echo "==> Compiling asset catalog..."
    xcrun actool "$ASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$APP_BUNDLE/Contents/Resources/AssetCatalog.plist" \
        > /dev/null 2>&1
fi

if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "==> Signing with '$CERT_NAME' certificate..."
    codesign --force --sign "$CERT_NAME" \
        --identifier "$BUNDLE_ID" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        "$APP_BUNDLE"
    echo "==> Signed. AX permissions will persist across rebuilds."
else
    echo "==> No '$CERT_NAME' certificate found. Using ad-hoc signing."
    echo "    AX permissions will reset on each rebuild."
    echo ""
    echo "    To fix this, run:  $(dirname "$0")/create-cert.sh"
    echo ""
    codesign --force --sign - \
        --identifier "$BUNDLE_ID" \
        --entitlements "$ENTITLEMENTS" \
        "$APP_BUNDLE"
fi

echo "==> Done: $APP_BUNDLE"

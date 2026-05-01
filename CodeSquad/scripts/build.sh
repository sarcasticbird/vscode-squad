#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

BUILD_CONFIG="${BUILD_CONFIG:-debug}"
APP_BUNDLE="$PROJECT_DIR/.build/CodeSquad.app"
BINARY="$PROJECT_DIR/.build/$BUILD_CONFIG/CodeSquad"
ENTITLEMENTS="$PROJECT_DIR/CodeSquad/CodeSquad.entitlements"
CERT_NAME="CodeSquad Dev"
BUNDLE_ID="com.codesquad.app"

cd "$PROJECT_DIR"

echo "==> Building ($BUILD_CONFIG)..."
swift build -c "$BUILD_CONFIG" 2>&1

echo "==> Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/CodeSquad"
cp "$PROJECT_DIR/CodeSquad/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# --- App Icon: three-tier fallback ---
ASSETS_DIR="$PROJECT_DIR/CodeSquad/Assets.xcassets"
ICON_SOURCE="$SCRIPT_DIR/icon_source.png"

if [ -d "$ASSETS_DIR" ] && xcrun --find actool > /dev/null 2>&1; then
    echo "==> Compiling asset catalog (actool)..."
    xcrun actool "$ASSETS_DIR" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$APP_BUNDLE/Contents/Resources/AssetCatalog.plist"
elif [ -f "$ICON_SOURCE" ] && command -v iconutil > /dev/null 2>&1 && command -v sips > /dev/null 2>&1; then
    echo "==> Generating app icon (iconutil fallback)..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"

    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" > /dev/null 2>&1
    done
    for size in 32 64 256 512 1024; do
        half=$((size / 2))
        sips -z $size $size "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${half}x${half}@2x.png" > /dev/null 2>&1
    done

    iconutil --convert icns "$ICONSET_DIR" --output "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_DIR")"
    echo "==> App icon generated."
else
    echo "==> Skipping app icon (no actool or iconutil+sips available)"
fi

# --- Codesign ---
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

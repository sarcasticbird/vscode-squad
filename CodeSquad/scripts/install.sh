#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="CodeSquad"
BUNDLE_ID="com.cdolan.codesquad"
APP_BUNDLE="$PROJECT_ROOT/.build/${APP_NAME}.app"
INSTALL_DIR="/Applications"
INSTALLED_APP="$INSTALL_DIR/${APP_NAME}.app"

echo "Installing ${APP_NAME}..."

# Stop existing instance
if pgrep -x "$APP_NAME" > /dev/null 2>&1; then
    echo "Stopping running ${APP_NAME}..."
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Remove old installation
if [ -d "$INSTALLED_APP" ]; then
    echo "Removing old installation..."
    rm -rf "$INSTALLED_APP"
fi

# Build (reuses scripts/build.sh for compilation + signing)
echo "Building ${APP_NAME}..."
"$SCRIPT_DIR/build.sh"

# Install to /Applications
echo "==> Installing to ${INSTALL_DIR}..."
cp -R "$APP_BUNDLE" "$INSTALLED_APP"

# Clear quarantine so Gatekeeper doesn't block unsigned app
xattr -cr "$INSTALLED_APP" 2>/dev/null || true

# Register with Launch Services
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_APP"

# Launch
echo "==> Launching ${APP_NAME}..."
open "$INSTALLED_APP"

echo ""
echo -e "${GREEN}${APP_NAME} installed successfully!${NC}"
echo -e "${YELLOW}Grant Accessibility permission when prompted.${NC}"
echo "  System Settings → Privacy & Security → Accessibility → enable ${APP_NAME}"

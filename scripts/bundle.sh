#!/usr/bin/env bash
#
# Builds ClaudeMeter.app from the SwiftPM release binary.
#
#   ./scripts/bundle.sh                     # ad-hoc signature
#   SIGN_IDENTITY="ClaudeMeter Dev" ./scripts/bundle.sh
#
# An ad-hoc signature changes on every rebuild, so macOS re-asks for keychain
# access each time. Pass SIGN_IDENTITY with a self-signed code-signing
# certificate to get a stable identity and a single prompt. See README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClaudeMeter"
APP="build/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> swift build -c release"
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
[ -x "$BINARY" ] || { echo "error: ${BINARY} not found" >&2; exit 1; }

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

cp "$BINARY" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
else
  echo "    (no Resources/AppIcon.icns — bundling without an icon)"
fi

echo "==> codesign (identity: ${SIGN_IDENTITY})"
codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict "$APP" && echo "    signature verifies"

echo
echo "Built ${APP} ($(du -sh "$APP" | cut -f1))"
echo "Install with:  cp -R \"${APP}\" /Applications/"

#!/bin/bash
# Builds the ScreenRecApp product and assembles + signs dist/ScreenRec.app.
#
# The signing identity comes from Scripts/devsign.sh (stable → TCC grants survive
# rebuilds). Run from anywhere; paths resolve relative to the repo root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="ScreenRec"          # bundle + binary name inside Contents/MacOS
PRODUCT="ScreenRecApp"        # SPM product name (.build/release/ScreenRecApp)
APP="dist/${APP_NAME}.app"
CONTENTS="${APP}/Contents"

echo "▸ Building ${PRODUCT} (release)…"
swift build -c release --product "$PRODUCT"

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp ".build/release/${PRODUCT}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "Sources/ScreenRecApp/Resources/Info.plist" "${CONTENTS}/Info.plist"
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "▸ Signing…"
IDENTITY="$(Scripts/devsign.sh)"   # prints the identity name on stdout; instructions on stderr
codesign --force --sign "$IDENTITY" "$APP"

echo "▸ Verifying signature…"
codesign --verify --strict "$APP"

# Gatekeeper assessment will fail until the app is notarized (Developer ID + notarytool,
# deferred to M6). That's expected for a self-signed dev build — report, don't fail.
if ! spctl -a -t exec "$APP" 2>/dev/null; then
  echo "  (spctl: not notarized — expected pre-M6, not a build failure)"
fi

echo "✓ Built ${APP} signed with '${IDENTITY}'"

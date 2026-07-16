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

# One source of truth for the version. Fail loudly rather than ship the plist's placeholder.
if [ ! -f VERSION ]; then
  echo "✗ VERSION file missing — refusing to build a bundle with an unstamped version" >&2
  exit 1
fi
VERSION="$(tr -d '[:space:]' < VERSION)"
if [ -z "$VERSION" ]; then
  echo "✗ VERSION file is empty" >&2
  exit 1
fi

ICON="Sources/ScreenRecApp/Resources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
  echo "✗ ${ICON} missing — run Scripts/makeicns.sh" >&2
  exit 1
fi

echo "▸ Assembling ${APP} (version ${VERSION})…"
rm -rf "$APP"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"
cp ".build/release/${PRODUCT}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "$ICON" "${CONTENTS}/Resources/AppIcon.icns"
cp "Sources/ScreenRecApp/Resources/Info.plist" "${CONTENTS}/Info.plist"

# Stamp the version. PlistBuddy sets the keys by value rather than editing text, so a VERSION
# containing sed-special characters (/ & \) can't corrupt the plist or truncate it mid-write.
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleShortVersionString ${VERSION}" "${CONTENTS}/Info.plist"
"$PB" -c "Set :CFBundleVersion ${VERSION}" "${CONTENTS}/Info.plist"
# Read the value back and confirm it landed: a token rename or a PlistBuddy miss must fail the
# build, never ship the literal placeholder as the version (notarization would reject it later).
STAMPED="$("$PB" -c "Print :CFBundleShortVersionString" "${CONTENTS}/Info.plist")"
if [ "$STAMPED" != "$VERSION" ]; then
  echo "✗ version stamp failed: plist reads '${STAMPED}', expected '${VERSION}'" >&2
  exit 1
fi
printf 'APPL????' > "${CONTENTS}/PkgInfo"

echo "▸ Signing…"
IDENTITY="$(Scripts/devsign.sh)"   # prints the identity name on stdout; instructions on stderr
# NOT signed with Scripts/entitlements.plist: AMFI refuses to launch a self-signed app carrying
# the restricted time-sensitive entitlement (POSIX 153 spawn failure). It needs a provisioning
# profile — Developer ID territory, M6-T4. The plist waits there.
codesign --force --sign "$IDENTITY" "$APP"

echo "▸ Verifying signature…"
codesign --verify --strict "$APP"

# Gatekeeper assessment will fail until the app is notarized (Developer ID + notarytool,
# deferred to M6). That's expected for a self-signed dev build — report, don't fail.
if ! spctl -a -t exec "$APP" 2>/dev/null; then
  echo "  (spctl: not notarized — expected pre-M6, not a build failure)"
fi

echo "✓ Built ${APP} signed with '${IDENTITY}'"

#!/bin/bash
# Builds Sources/ScreenRecApp/Resources/AppIcon.icns from the code-drawn master.
# Run when the icon design changes; the .icns is checked in so a normal build doesn't need it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# One temp dir for everything, so cleanup is a single rm and nothing orphans. (`mktemp -t
# foo).png` would append `.png` to a name mktemp already created, leaving the original behind.)
WORK="$(mktemp -d -t screenrec-icon)"
MASTER="${WORK}/master.png"
ICONSET="${WORK}/AppIcon.iconset"
OUT="Sources/ScreenRecApp/Resources/AppIcon.icns"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Rendering master…"
swift tools/makeicon.swift "$MASTER" >/dev/null

echo "▸ Building iconset…"
mkdir -p "$ICONSET"
# The slot names iconutil requires; each maps a pixel size to a @1x/@2x role.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$MASTER" --out "${ICONSET}/icon_$2.png" >/dev/null
done

echo "▸ Running iconutil…"
iconutil --convert icns --output "$OUT" "$ICONSET"
echo "✓ Wrote $OUT ($(du -h "$OUT" | cut -f1))"

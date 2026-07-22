#!/usr/bin/env bash
#
# Cut a release (M13-T5). The version bump is YOUR semver decision (ADR-013) — bump `VERSION` and
# `CoreInfo.version` and commit `release: vX.Y.Z` first. This script then verifies that release is
# consistent, runs the full gate (stricter than the pre-push hook — it also signs the bundle),
# tags `vX.Y.Z`, and (on confirm) pushes main + the tag.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[90m'; Z=$'\033[0m'; else G=; R=; Y=; D=; Z=; fi
ok()  { printf '%s✓%s %s\n' "$G" "$Z" "$1"; }
die() { printf '%s✗ %s%s\n' "$R" "$1" "$Z" >&2; exit 1; }

log=$(mktemp -t screenrec-release)
trap 'rm -f "$log"' EXIT
# step "<label>" <command…> — run quietly; ✓ on success, dump the tail and abort on failure.
step() {
  local label=$1; shift
  if "$@" >"$log" 2>&1; then ok "$label"; else
    printf '%s✗ %s%s\n\n' "$R" "$label" "$Z" >&2; tail -40 "$log" >&2; exit 1
  fi
}

# --- consistency checks (fail fast, before the slow gate) ---
[ -z "$(git status --porcelain)" ] || die "working tree is dirty — commit or stash first"
ok "clean working tree"

VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$VERSION" ] || die "VERSION is empty"
ok "VERSION = $VERSION"

# The pin test's check, caught here before we tag a version-mismatched release.
grep -q "\"$VERSION\"" Sources/RecorderCore/CoreInfo.swift \
  || die "CoreInfo.version != VERSION ($VERSION) — bump both in the release commit"
ok "CoreInfo.version matches VERSION"

TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then die "tag $TAG already exists"; fi
ok "tag $TAG is free"

# --- the release gate (build · test · encode · release-build · bundle-sign) ---
printf '%s▸ release gate…%s\n' "$D" "$Z"
step "swift build"          swift build
step "swift test"           swift test
step "encode: Exporter"     env SCREENREC_HW_ENCODE_TESTS=1 swift test --filter ExporterTests
step "encode: Trimmer"      env SCREENREC_HW_ENCODE_TESTS=1 swift test --filter TrimmerTests
step "encode: GifExporter"  env SCREENREC_HW_ENCODE_TESTS=1 swift test --filter GifExporterTests
step "swift build -c release"  swift build -c release
step "bundle + sign"        ./Scripts/bundle.sh

# --- tag, then push on confirm ---
git tag "$TAG" || die "could not create tag $TAG"
ok "tagged $TAG"

printf '%sPush %s to origin (main + tag)?%s [y/N] ' "$Y" "$TAG" "$Z"
read -r reply || reply=""
case "$reply" in
  y|Y)
    # Branch + tag in one push so the pre-push hook's gate runs once, not twice.
    step "push main + $TAG" git push origin main "$TAG"
    ok "pushed — release $TAG is live"
    ;;
  *)
    printf 'Not pushed. When ready:  git push origin main && git push origin %s\n' "$TAG"
    ;;
esac

#!/usr/bin/env bash
#
# Cut a release (M13-T5). The version bump is YOUR semver decision (ADR-013) — bump `VERSION` and
# `CoreInfo.version` and commit `release: vX.Y.Z` first. This script then verifies that release is
# consistent, runs the full gate (stricter than the pre-push hook — it also signs the bundle),
# tags `vX.Y.Z`, pushes main + the tag, and publishes the signed bundle as a GitHub release asset.
#
# ⚠️ Run it in the BACKGROUND: a foreground timeout SIGTERMs it mid-encode. With no terminal it
# pushes without asking — `--no-push` opts out (M22-T5).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

NO_PUSH=
for arg in "$@"; do
  case "$arg" in
    --no-push) NO_PUSH=1 ;;
    *) printf 'usage: release.sh [--no-push]\n' >&2; exit 64 ;;
  esac
done

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[90m'; Z=$'\033[0m'; else G=; R=; Y=; D=; Z=; fi
ok()   { printf '%s✓%s %s\n' "$G" "$Z" "$1"; }
warn() { printf '%s! %s%s\n' "$Y" "$1" "$Z" >&2; }
die()  { printf '%s✗ %s%s\n' "$R" "$1" "$Z" >&2; exit 1; }

log=$(mktemp -t screenrec-release)
trap 'rm -f "$log"' EXIT
# step "<label>" <command…> — run quietly; ✓ on success, dump the tail and abort on failure.
step() {
  local label=$1; shift
  if "$@" >"$log" 2>&1; then ok "$label"; else
    printf '%s✗ %s%s\n\n' "$R" "$label" "$Z" >&2; tail -40 "$log" >&2; exit 1
  fi
}

# The `## <version>` section of CHANGELOG.md, without its heading. Defined up here because the
# consistency checks use it, long before the notes are assembled.
changelog_section() {
  awk -v heading="## $VERSION" '
    $0 == heading { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' CHANGELOG.md
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

# The notes are CHANGELOG.md's now, with no `git log` left to fall back on, so a missing section
# would publish a release that says nothing. Checked before anything is tagged, pushed or uploaded.
[ -n "$(changelog_section | tr -d '[:space:]')" ] \
  || die "CHANGELOG.md has no '## $VERSION' section — write the release notes first"
ok "CHANGELOG.md has notes for $VERSION"

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
step "encode: VideoFrameReader" env SCREENREC_HW_ENCODE_TESTS=1 swift test --filter VideoFrameReaderTests
step "swift build -c release"  swift build -c release
step "bundle + sign"        ./Scripts/bundle.sh

# --- the release notes: how to get past Gatekeeper, then what changed ---
# The install note is not decoration: this build is signed by us and deliberately NOT notarized
# (ADR-014), so a *downloaded* zip is quarantined and macOS 15 refuses it — without these steps
# the download is a trap.
#
# What changed comes from CHANGELOG.md, never from `git log`: commit subjects are the per-task audit
# trail and read as one — task IDs, `docs:` bookkeeping, internal nouns (M32-T5). Anyone who wants the
# commits has them on the tag, one click away.
release_notes() {
  cat <<'NOTES'
## Install

1. Unzip and move **ScreenRec.app** to `/Applications`.
2. macOS will refuse to open it the first time — this build is signed by its author, not notarized
   by Apple. Open **System Settings › Privacy & Security**, find the ScreenRec message and choose
   **Open Anyway** (macOS 15 removed the old Control-click shortcut).
3. Grant Screen Recording and Microphone when asked.

## What's new
NOTES
  changelog_section
}

# --- the downloadable build (M22-T6) ---
# ⚠️ `ditto`, never `zip -r`: it preserves the bundle's symlinks and extended attributes, and a
# mangled bundle fails `codesign --verify` — the signature is what the TCC grants key to (M0-T3).
# Never fatal: main and the tag are already pushed by the time this runs, so a failed upload must
# not report the release as failed. It says how to finish by hand instead.
publish_release() {
  local zip="dist/ScreenRec-$VERSION.zip"
  rm -f "$zip"
  if ! ditto -c -k --sequesterRsrc --keepParent dist/ScreenRec.app "$zip" >"$log" 2>&1; then
    warn "could not zip the bundle — $TAG has no download"; return
  fi
  ok "zipped $(basename "$zip") ($(du -h "$zip" | cut -f1 | tr -d ' \t'))"

  local notes; notes=$(mktemp -t screenrec-notes)
  release_notes >"$notes"
  if gh release create "$TAG" --title "ScreenRec $VERSION" --notes-file "$notes" "$zip" >"$log" 2>&1
  then
    ok "github release $TAG"
    printf '%s  %s%s\n' "$D" "$(tail -1 "$log")" "$Z"
  else
    tail -5 "$log" >&2
    warn "release not created — rerun: gh release create $TAG --title \"ScreenRec $VERSION\" --generate-notes $zip"
  fi
  rm -f "$notes"
}

# --- tag, then push ---
git tag "$TAG" || die "could not create tag $TAG"
ok "tagged $TAG"

if [ -n "$NO_PUSH" ]; then
  reply=n
elif [ ! -t 0 ]; then
  # The background run this script asks for: `read` sees EOF and used to answer N, so every cut
  # "succeeded" with main and the tag still local (M22-T5).
  printf '%sno terminal — pushing (--no-push to stop)%s\n' "$D" "$Z"
  reply=y
else
  printf '%sPush %s to origin (main + tag)?%s [y/N] ' "$Y" "$TAG" "$Z"
  read -r reply || reply=""
fi

case "$reply" in
  y|Y)
    # Branch + tag in one push so the pre-push hook's gate runs once, not twice.
    step "push main + $TAG" git push origin main "$TAG"
    ok "pushed — release $TAG is live"
    publish_release
    ;;
  *)
    printf 'Not pushed. When ready:  git push origin main && git push origin %s\n' "$TAG"
    ;;
esac

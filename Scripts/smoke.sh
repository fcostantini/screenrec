#!/usr/bin/env bash
#
# Live-pipeline smoke (M13-T5): record 3 s via the CLI and assert the file has video + ≥1 audio at
# ~3 s. Needs the dev box's Screen Recording + Microphone TCC grants — it catches capture→write
# regressions that `swift test` can't (the unit suite never touches ScreenCaptureKit). Run on
# demand, and before a release.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; D=$'\033[90m'; Z=$'\033[0m'; else G=; R=; D=; Z=; fi

printf '%s▸ building the CLI…%s\n' "$D" "$Z"
swift build -c release >/dev/null 2>&1 || { printf '%s✗ build failed%s\n' "$R" "$Z" >&2; exit 1; }

out="$(mktemp -d)/smoke.mov"
trap 'rm -f "$out"' EXIT

printf '%s▸ recording 3 s via the CLI…%s\n' "$D" "$Z"
if ! .build/release/screenrec-cli record --duration 3 "$out" >/dev/null 2>&1; then
  printf '%s✗ the CLI recording failed — is Screen Recording granted?%s\n' "$R" "$Z" >&2; exit 1
fi

probe="$(swift tools/probe.swift "$out" 2>&1)"
video=$(printf '%s\n' "$probe" | grep -cE 'track [0-9]+: video')
audio=$(printf '%s\n' "$probe" | grep -cE 'track [0-9]+: audio')
duration=$(printf '%s\n' "$probe" | sed -n 's/^duration: \([0-9.]*\)s.*/\1/p' | head -1)

fail=0
if [ "$video" -ge 1 ]; then printf '%s✓%s %s video track\n' "$G" "$Z" "$video"
else printf '%s✗ no video track%s\n' "$R" "$Z"; fail=1; fi

if [ "$audio" -ge 2 ]; then printf '%s✓%s %s audio tracks (system + mic)\n' "$G" "$Z" "$audio"
elif [ "$audio" -eq 1 ]; then printf '%s✓%s 1 audio track %s(no mic — is one connected?)%s\n' "$G" "$Z" "$D" "$Z"
else printf '%s✗ no audio track%s\n' "$R" "$Z"; fail=1; fi

if [ -n "$duration" ] && awk "BEGIN{exit !($duration >= 2.5 && $duration <= 3.5)}"; then
  printf '%s✓%s duration %ss (within 2.5–3.5)\n' "$G" "$Z" "$duration"
else
  printf '%s✗ duration %ss out of range%s\n' "$R" "${duration:-?}" "$Z"; fail=1
fi

if [ "$fail" -eq 0 ]; then printf '%ssmoke passed.%s\n' "$G" "$Z"
else printf '%ssmoke FAILED.%s\n' "$R" "$Z" >&2; exit 1; fi

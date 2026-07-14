#!/usr/bin/env bash
# beepflash.sh — emit a periodic A/V sync marker: a short audible click plus a bright
# full-screen white flash, fired together. Used by the 30-min drift test (docs/04 §3.5):
# run it alongside a `record`, then scrub in QuickTime — the beep (system-audio track) and
# the flash (video track) must still line up at minute 30 as well as they do at minute 0.
#
# Usage: tools/beepflash.sh [--interval SECONDS] [--count N]
#   --interval  seconds between markers (default 300 = 5 min)
#   --count     stop after N markers (default: run until Ctrl-C)
#
# The first marker fires immediately (a minute-0 reference), then every --interval seconds.
set -euo pipefail

interval=300
count=-1
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) interval="$2"; shift 2 ;;
    --count) count="$2"; shift 2 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
done

sound=/System/Library/Sounds/Ping.aiff

# Compile the full-screen flasher once; a fresh process per flash keeps it self-cleaning
# (the window vanishes when the process exits).
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/flash.swift" <<'SWIFT'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
guard let screen = NSScreen.main else { exit(1) }
let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                      backing: .buffered, defer: false)
window.level = .screenSaver          // above everything, so it's unmistakable in the capture
window.backgroundColor = .white
window.isOpaque = true
window.ignoresMouseEvents = true
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
RunLoop.current.run(until: Date().addingTimeInterval(0.15))
SWIFT
swiftc -O "$work/flash.swift" -o "$work/flash"

marker() {
  afplay "$sound" &     # audible click…
  "$work/flash"         # …and a ~150 ms full-screen flash, together
  wait
}

echo "beepflash: marker every ${interval}s (Ctrl-C to stop)"
marker
echo "  ✦ marker 0 (t≈0)"
n=0
while [ "$count" -lt 0 ] || [ "$n" -lt $((count - 1)) ]; do
  sleep "$interval"
  marker
  n=$((n + 1))
  echo "  ✦ marker $n"
done

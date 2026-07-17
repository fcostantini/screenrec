# 00 — Product Brief

## One-liner

A native macOS menu-bar screen recorder that captures **screen video + system audio +
microphone** in high quality, with a **separate microphone track** for post-editing,
**crash-proof long recordings**, **pause/resume**, and **instant replay** ("save the last
N seconds") — no virtual audio drivers, no subscription, no Electron.

## Why this exists

The Tier-1 proof of concept (`~/code/screenrec-poc`) validated that ScreenCaptureKit on
macOS 15 captures all three sources natively. But `SCRecordingOutput` (the Tier-1
shortcut) has hard limits we now remove by owning the writing pipeline:

| Tier-1 limitation | Tier-2 answer |
|---|---|
| System audio + mic mixed into ONE track | Separate tracks in one `.mov` via own `AVAssetWriter` |
| No bitrate/quality control (Apple's bloated defaults) | Tuned HEVC bitrate, quality presets |
| No pause/resume | Timestamp-offset pause implementation |
| No instant replay possible | VideoToolbox ring buffer + global hotkey |
| CLI with terminal-attributed permissions | Signed `.app` bundle with its own TCC identity |
| No HDR (SCRecordingOutput incompatible) | Possible later (stretch) |

Market context (from research, 2026-07): users' loudest complaints about existing tools
are business models (Screen Studio $108/yr subscription, Loom 720p free cap) and Electron
jank (Loom, dormant Kap) — not capture capability. Free OSS competition (QuickRecorder,
Azayaka) is capable but utilitarian. Reliability (mic sync, crash-safe long recordings)
and instant replay are the differentiators.

## Target user

Ourselves first (franco.costantini@heyglide.com, macOS 15.6.1, Apple Silicon, AirPods +
built-in mic, 4112×2570 display). Design decisions default to "power user recording
demos, bug reports, and meetings" — not streamers, not video editors.

## Goals (v1)

1. **Record** the full screen (later: window/app) with system audio + mic to a single
   `.mov`, mic on its own track, at quality ≥ Tier-1 PoC with files ~2–4× smaller.
2. **Survive anything**: SIGKILL/power loss mid-recording loses ≤ 10 seconds.
3. **Pause/resume** mid-recording with monotonic timestamps and perfect A/V sync.
4. **Instant replay**: hotkey saves the last N (default 60) seconds to disk in < 1 s
   without interrupting the ring buffer.
5. **Menu-bar app** with permissions onboarding, display/mic pickers, quality presets.
6. CPU budget: < 15% of one performance core while recording at 60 fps (hardware encode
   does the heavy lifting; this is mostly bookkeeping overhead).

## Non-goals (v1)

- Editing of any kind (trim, zoom, cursor effects). Cursor-as-data recording is designed
  for but not implemented (see ADR-008).
- Webcam capture/overlay. (Architecture leaves room: it would be a 4th source.)
- Streaming, sharing, cloud anything.
- App Store distribution / sandboxing (see ADR-006). Windows. macOS < 15 (see ADR-001).
- Echo cancellation (document "use headphones"; see 02-technical-reference §8).

## Success criteria / acceptance for v1

(Adjudicated by M6-T1's acceptance run, 2026-07-16/17 — evidence in STATUS.md.)

- [ ] 2-hour recording on battery: no dropped-frame visible stutter, in-sync audio at the
      2 h mark (clap test §4 of 04-testing), file playable after `kill -9` at 1:59.
      *Satisfied by M6-T2's soak — one run counts for both (Franco, 2026-07-16).*
- [x] Output for typical desktop work meaningfully smaller than Tier-1 at "Balanced",
      full Retina — met: ≈5.7 Mbps over a 30-min active-screen real-usage run vs Tier-1's
      ~34 Mbps (≈6×; goal 1's 2–4× exceeded). *Amended from "≤ 1.5 GB/hour" 2026-07-17
      (Franco): absolute size is not a v1 concern; the ratio to Tier-1 is the bar. The
      measured 2.59 GB/h at Balanced stands on record in STATUS.md.*
- [x] Instant replay clip saved while a manual recording is NOT running, in < 1 s,
      containing the last 60 s ± 1 keyframe interval, with audio. *Measured 2026-07-16:
      0.30 s signal→file, 60.55 s window, keyframe start, both audio tracks.*
- [x] ~~Fresh macOS user account: onboarding flow yields working recording in < 2 minutes
      without reading docs.~~ **Waived** (Franco, 2026-07-16 — not run; G4 §5.1's
      walkthrough proved the flow works, untimed).
- [x] ~~QuickTime, IINA, Premiere, and DaVinci Resolve all open the files; NLEs show the
      mic as an independent track.~~ **Waived** (Franco, 2026-07-16 — only QuickTime is
      installed here; not run).

## Naming

Working title: **screenrec**. Bundle ID `dev.fcostantini.screenrec.app`. Rename is a
find-and-replace away; don't bikeshed it before v1 works.

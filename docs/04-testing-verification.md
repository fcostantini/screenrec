# 04 — Testing & Verification

How we know each milestone is actually done. Agents: run the relevant section as the
milestone's exit gate and paste results into STATUS.md. `tools/probe.swift` is the file
inspector (tracks, codecs, dimensions, duration): `swift tools/probe.swift <file.mov>`.

Environment notes for agents:
- The dev terminal already holds Screen Recording + Microphone TCC grants; CLI capture
  runs work from Claude Code Bash. GUI/TCC-onboarding tests (§5) need the human.
- stdout of CLI runs is unbuffered by design; capture-based tests take real seconds.
- Never write test recordings to Desktop/Documents/Downloads (TCC — 02 §2). Use the
  session scratchpad or `~/Movies`, and clean up after.

## §1 — G0: Scaffolding

```sh
swift build && swift test && Scripts/bundle.sh
codesign -dv dist/ScreenRec.app 2>&1 | grep -E 'Identifier|Signature'
```
Pass: all green; identifier `dev.fcostantini.screenrec.app`; same signing identity on
two consecutive builds (`codesign -dv` TeamIdentifier/designated requirement identical).

## §2 — G1: Capture engine

```sh
.build/release/screenrec-cli probe-stream --duration 5
```
Pass criteria:
- Buffer counts: video > 0 (move the mouse during the run — frame-on-change!),
  system audio ≈ 5 s × ~43 buffers/s, mic > 0.
- Mic format description printed; record it in STATUS.md (sample rate/channels vary by
  device — AirPods vs built-in).
- PTS deltas positive and sane (no zero/negative video deltas).
- Run twice: once AirPods, once `--mic BuiltInMicrophoneDevice`.

## §3 — G2: MovieRecorder (the big one)

1. **Track layout**: record 5 s with mic → probe shows `hvc1` video at full pixel res +
   TWO `aac` audio tracks. Open in QuickTime (human: both audible; NLE sees 2 tracks).
2. **Kill test (required)**: start 30 s recording in background, `kill -9` at ~6 s,
   probe the file. Pass: readable, duration ≥ 5 s (10 s fragment interval ⇒ worst-case
   loss ≤ 10 s; typical sub-second like the PoC). This gate is non-negotiable.
3. **Sync clap test (human)**: record while playing a video with a hard cut AND
   clapping near the mic; scrub in QuickTime: video event, system-audio event, and mic
   clap align within ~2 frames at start AND end of a 2-min recording.
4. **Static-screen duration**: record 15 s where the last 10 s nothing moves. Pass:
   file duration 15 s ± 0.5 s (tail-frame patch working), not ~5 s.
5. **Drift test**: 30-min recording with periodic audible/visible events (e.g. a
   script that beeps + flashes every 5 min — write `tools/beepflash.sh`). Pass: sync at
   minute 30 as good as at minute 0; video/audio track durations within 100 ms.
6. **Quality/size calibration** (M2-T6): busy-content comparison table vs Tier-1 in
   STATUS.md; Balanced ≤ half of Tier-1 size at comparable subjective quality.

## §4 — G3: Pause & robustness

1. **Pause math**: scripted: record 10 s → pause 5 s → resume 10 s → stop (CLI
   supports timed pause for tests: `--script rec10,pause5,rec10`). Pass: duration
   20 s ± 0.2 s; clap-sync across the seam; monotonic PTS (probe warns otherwise).
2. **Mic disappears**: kill AirPods mid-recording. Pass: clean stop, playable file,
   event message names the cause.
3. **Display sleep/lock** (human): close lid mid-recording. Pass: playable file to
   that point.
4. **Disk guard**: run with `--test-disk-floor <huge>` to trip the monitor. Pass:
   clean stop + message.

## §5 — G4: App & onboarding (human-driven)

1. Fresh macOS user account: launch app → onboarding → grants → first recording
   in < 2 min without docs. App (not terminal) listed in System Settings panes.
2. Rebuild app (`Scripts/bundle.sh`), relaunch: grants persist (stable identity).
3. Menu flows: start/pause/stop from menu; icon states; notification on stop opens
   Finder at the file.
4. Settings: change output dir to Desktop WITHOUT granting → immediate friendly error
   at selection (preflight), not at record time.

## §6 — G5: Instant replay

1. `replay-arm --seconds 60` for 3 min: ring occupancy stabilizes at ~60 s; RSS plateau
   ≲ 200 MB (`footprint` or Activity Monitor); CPU < 10% average (`top -pid`).
2. `replay-save` timing: `time` from hotkey/command to file-exists < 1 s. Probe: hvc1 +
   2 AAC; duration 60 + ≤ 1 s; content is genuinely the LAST minute (human check:
   on-screen clock visible in recording).
3. Save twice rapidly: second either coalesced or queued; no crash, no torn file.
4. Simultaneity: manual recording running + replay armed + save → both files correct.
5. Arm for 30 min: memory flat (no ring leak), then save still < 1 s.

## §7 — G6: Soak

2-hour recording on battery, mixed real usage, AirPods mic, replay armed:
- File plays end to end; §3.3 sync check at 0:00, 1:00, 2:00.
- No thermal runaway; battery drain noted in STATUS.md.
- `kill -9` a second 2-h run at ~1:59 → playable.

## Unit-test targets (run in every gate via `swift test`)

- `MovieRecorder` synthetic-buffer integration test (M2-T2): writes a real file from
  generated CVPixelBuffers + PCM silence, no ScreenCaptureKit involved — the writer is
  verifiable on any machine, no TCC needed.
- `TimestampRebaser`: epoch, pre-epoch drop, pause accumulation, monotonic enforcement.
- `RingBuffer`: eviction by duration, keyframe search, snapshot-during-append (thread
  sanitizer run: `swift test --sanitize=thread` at least once per milestone).
- `BitrateModel`: preset math, pixel-count edge cases.
- `OutputLocation`: naming, collision (two files same second), preflight failure paths.

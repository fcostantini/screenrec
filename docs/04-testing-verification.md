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

## Automated gate — pre-push hook (M13-T1)

`Scripts/hooks/pre-push` runs the dev loop automatically before every `git push` and blocks it
on any failure: `swift build` · `swift test` · the **hardware-encode tests** a default `swift test`
skips (`SCREENREC_HW_ENCODE_TESTS=1 swift test --filter {Exporter,Trimmer,GifExporter}Tests`, one
suite per invocation so they don't oversubscribe VideoToolbox — 02 field notes) · `swift build -c
release`. Install once per clone: `git config core.hooksPath Scripts/hooks`. Signing (`bundle.sh`)
is left to the release path; bypass with `git push --no-verify`. This is the standing regression
gate — the milestone §-gates below stay the source of truth for feature/behaviour verification.
**Future (public-repo only):** a GitHub Actions macOS job running the same four steps (minus signing —
no identity in CI) as an unbypassable backstop; skipped now because a private repo bills macOS
runner minutes at a 10× multiplier for no added authority when Franco is the sole committer.

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
- Run twice: once with the default mic (AirPods when connected — device-dependent),
  once with `--mic BuiltInMicrophoneDevice`.

## §3 — G2: MovieRecorder (the big one)

1. **Track layout**: record 5 s with mic → probe shows `hvc1` video at full pixel res +
   TWO `aac` audio tracks. Open in QuickTime (human: both audible; NLE sees 2 tracks).
2. **Kill test (required)**: start 30 s recording in background, `kill -9` at ~6 s,
   probe the file. Pass: readable, duration ≥ 5 s (10 s fragment interval ⇒ worst-case
   loss ≤ 10 s; typical sub-second like the PoC). This gate is non-negotiable.
   Since M6-T7 the in-progress/killed file is `….mov.partial` (rename to `.mov` before
   probing — that IS the recovery path; probe judges by extension and refuses `.partial`).
3. **Sync clap test (human)**: record while playing a video with a hard cut AND
   clapping near the mic; scrub in QuickTime: video event, system-audio event, and mic
   clap align within ~2 frames at start AND end of a 2-min recording.
4. **Static-screen duration**: record 15 s where the last 10 s nothing moves — redirect
   the CLI's stdout to a file, or its own progress ticker keeps repainting the screen
   and nothing is ever static. Pass: file duration 15 s ± 0.5 s (tail-frame patch
   working), not ~5 s.
5. **Drift test**: 30-min recording with periodic audible/visible events via
   `tools/beepflash.sh` (delivered in M2-T6). Pass: sync at minute 30 as good as at
   minute 0; per-track durations (probe, extended in M2-T4) within 100 ms.
6. **Quality/size calibration** (M2-T6): busy-content comparison table vs Tier-1 in
   STATUS.md; Balanced ≤ half of Tier-1 size at comparable subjective quality.

## §4 — G3: Pause & robustness

1. **Pause math**: scripted: record 10 s → pause 5 s → resume 10 s → stop (CLI
   supports timed pause for tests: `--script rec10,pause5,rec10`). Pass: duration
   20 s ± 0.2 s; clap-sync across the seam; monotonic PTS (probe warns otherwise).
2. **Mic disappears** (human — device action): record with AirPods, then put them in the
   case mid-recording. Pass (ADR-012): recording **CONTINUES** — video + system audio run to
   the intended end, a `microphoneLost` event names the cause, the file is playable, and the
   mic track ends at the disconnect (probe: mic track shorter than video). NOT a stop. The
   original wording here ("clean stop") assumed a built-in-mic takeover that does not happen
   — see 02 §4. Run 2026-07-15 against the pre-M3-T6 build recorded the loss correctly in the
   file (mic 22.6 s vs video 59.9 s) but emitted no event; the event is what M3-T6 adds.
3. **Display sleep/lock**: Pass: playable file to that point + a sensible reason.
   ✅ 2026-07-15. Two ways in, both landing on `-3815` → `finished(.displayDisconnected)`:
   - **Display sleep — now HEADLESS**, no human needed: run a capture and fire
     `pmset displaysleepnow` mid-recording (`( sleep 4; pmset displaysleepnow ) &` before a
     foreground `record`), then `caffeinate -u -t 3` to wake. → playable 3.3 s file.
   - **Lid close (system sleep)** (human): playable 11.2 s file finalized on wake.
   - **Monitor unplug: N/A on this hardware** (built-in display only). Re-run if an external
     display ever exists; it may reveal a code other than -3815 (02 §7).
4. **Disk guard**: the volume must fall below the floor **during** the take — a guard that only
   trips on a disk already too full at Start passed this criterion for four milestones (M19-T1).
   - **The evidence**: a 4 GB APFS disk image, the **real 2 GB floor and no test hook**, a
     recording writing into it, and ~2 GiB of `dd` ballast landing mid-take. Pass:
     `finished (diskAlmostFull)` within a poll or two of the crossing + a playable file.
   - `--test-disk-floor <huge>` stays as a smoke check of the stop path (it trips on the first
     poll), but it is **not** evidence that the guard can see a disk filling. Neither is any test
     using the injected probe: the freeze lived in the real one.

## §5 — G4: App & onboarding (human-driven)

1. Fresh macOS user account: launch app → onboarding → grants → first recording
   in < 2 min without docs. App (not terminal) listed in System Settings panes.
2. Rebuild app (`Scripts/bundle.sh`), relaunch: grants persist (stable identity).
3. Menu flows: start/pause/stop from menu; icon states; notification on stop opens
   Finder at the file.
4. Settings: change output dir to Desktop WITHOUT granting → immediate friendly error
   at selection (preflight), not at record time.

**Capability self-test (M16-T6)** — the same judgement as `Scripts/smoke.sh`, from the UI:
onboarding's `Run a test` records 5 s into scratch, reports per-source outcomes and deletes the file.
`CaptureSelfTest.verdict` is pure, so every partial-pass case is unit-tested; the live legs are
mic-None, muted, and a normal run.

## §6 — G5: Instant replay

1. `replay-arm --seconds 60` for 3 min: ring occupancy stabilizes at ~60 s; CPU < 10%
   average (cumulative cpu-time / wall-time, not spot samples). Memory: ring payload ≈
   Balanced bitrate × (window + 2 s slack) — ~145 MB busy at 4112×2570 — so the RSS
   plateau bound is **≲ 400 MB busy** (AMENDED 2026-07-16, Franco: replay keeps Balanced
   parity with recordings, no dedicated cap; the original ≲ 200 MB assumed ~10 Mbps).
   ⚠️ Task-level RSS attribution of VT/CM buffer memory varies run-to-run on identical
   binaries (02 §9 / STATUS field notes) — **flatness over minutes 5→30 is the leak
   check; the absolute number is advisory.** VT `DataRateLimits` on the replay session
   remains the lever if the uncapped ring ever matters (we drive VT directly).
   **The formula ships as `ReplayFootprint` (M16-T2) — it is what the UI quotes, and its tests
   restate this line, so changing one means changing both.**
2. Save timing: with `replay-arm` running, `kill -USR1 $PID`, then poll for the output
   file — signal-to-file-exists < 1 s. Probe: hvc1 + 2 AAC; duration 60 + ≤ 1 s; starts
   on a keyframe; content is genuinely the LAST minute (human check: on-screen clock
   visible in recording).
3. Two rapid SIGUSR1s: second coalesced or queued; no crash, no torn file.
4. Simultaneity: manual recording running + replay armed + save → both files correct.
5. Arm for 30 min: memory flat (no ring leak), then save still < 1 s.

## §7 — G6: Soak

2-hour recording on battery, mixed real usage, AirPods mic, replay armed:
- File plays end to end; §3.3 sync check at 0:00, 1:00, 2:00.
- No thermal runaway; battery drain noted in STATUS.md.
- `kill -9` a second long run near its end → playable. *Amended from "2-h run at ~1:59"
  to a 1-h run at ~0:59 (Franco, 2026-07-17): the kill mechanics are proven at 6 s (G2
  §3.2); this leg tests salvage at fragment-count/file-size scale, and 1 h buys most of
  that scale at half the wall-clock.*

## Unit-test targets (run in every gate via `swift test`)

- `MovieRecorder` synthetic-buffer integration test (M2-T2): writes a real file from
  generated CVPixelBuffers + PCM silence, no ScreenCaptureKit involved — the writer is
  verifiable on any machine, no TCC needed.
- `TimestampRebaser`: epoch, pre-epoch drop, pause accumulation, monotonic enforcement.
- `RingBuffer`: eviction by duration, keyframe search, snapshot-during-append (thread
  sanitizer run: `swift test --sanitize=thread` at least once per milestone).
- `BitrateModel`: preset math, pixel-count edge cases.
- `OutputLocation`: naming, collision (two files same second), preflight failure paths.

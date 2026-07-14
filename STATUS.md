# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short; details go to Field notes / History.

## Now

- **Current milestone:** M3 — pause/resume + robustness. M2 COMPLETE, G2 PASSED (5/5).
- **M3-T1 DONE** — pause/resume wired end-to-end: `MovieRecorder.pause()/resume()` drive the
  (already unit-tested) `TimestampRebaser`; `CaptureEngine` owns the paused state + emits
  `.paused`/`.resumed`; `RecordingSession` coordinates (recorder freezes the timeline first,
  then the engine publishes the event). CLI `record` gains `--script rec10,pause5,rec10`
  (unattended) and interactive `p`/`r`/Return keys. G3 §4.1 pause-math leg PASSED (see gate
  table). **Cross-seam clap-sync is human → Needs Franco.**
- **Next task:** **M3-T2** — mic format-change detection → clean stop emitting
  `finished(url:reason:.microphoneChanged)` (docs/02 §4, ADR-007). Unit test injects a
  format-changed buffer; live AirPods-off run is human (§4.2).
- **Now done:** M2-T1..T6 + M3-T1. `record` is a full CLI (real 3-track capture, presets,
  explicit path, progress ticker, pause/resume, scripted timeline).
  KEY ENV FACT: foreground Bash captures WORK (TCC held); backgrounded/detached ones lose the
  grant. Keep capture commands foreground. Reference binary: `~/code/screenrec-poc`.

## M2-T6 calibration comparison (6 s, `tools/busyscene.swift`, --no-mic, 4112×2570)

| Source | Size | ~Mbps | vs Tier-1 |
|--------|------|-------|-----------|
| efficient | 12.0 MB | 16.8 | ~50% |
| balanced  | 11.8 MB | 16.5 | ~49% |
| high      | 16.1 MB | 22.5 | ~67% |
| Tier-1 (PoC, SCRecordingOutput) | 24.2 MB | 33.8 | 100% |

Balanced/Tier-1 over 3 rounds: **48.8% / 51% / 50% → ≈50%** (≈2× more efficient — target met, at
the line). Notes: (1) **efficient ≈ balanced on busy content** — `AVVideoAverageBitRateKey` is a
soft target the real-time HW HEVC encoder loosely respects; it floors at ~16 Mbps for this scene
and won't crush quality to hit efficient's 4.76 Mbps cap. On LIGHT content presets DO order
(M2-T5 mouse-mover: 4.28<4.96<5.25 MB). (2) Constants left UNCHANGED — they produce the intended
targets; further gains need HARD data-rate limits (VideoToolbox `DataRateLimits`, not exposed via
AVAssetWriter's AverageBitRate) — candidate M6 refinement. (3) Scene = generated, not a QuickTime
video (deterministic, reproducible).
- **Blockers:** none — the M1-T4 finding (mic 24k/48k mono vs system 48k stereo) is the
  key input to M2's two-separate-audio-tracks design (confirmed working in M2-T2).

## Needs Franco (human-only items)

- [x] DONE 2026-07-14: Franco granted the Claude Code runtime ("2.1.209") Screen
      Recording AND Microphone, so capture tests (engine-smoke/record/probe) run directly
      via the agent's shell. Both applied immediately, no restart. If Claude Code's
      identity changes, the grants may need re-doing.

- [x] M0-T2 prerequisite DONE (2026-07-14): self-signed Code Signing identity
      "screenrec-dev" created in login keychain and trusted for codeSign policy
      (`security add-trusted-cert -r trustRoot -p codeSign`). Verified: signs and
      passes `codesign --verify --strict`. devsign.sh should find and use this
      identity; it must NOT try to create a new one.
- [ ] First GUI TCC grants for the .app once M4 begins (grant + relaunch dance).
- [ ] **G3 §4.1 cross-seam A/V sync (human)** — record `--script rec10,pause5,rec10` with mic
      while clapping near the pause seam; scrub QuickTime that video/system/mic realign within
      ~2 frames across the resume seam. (Automated duration + monotonic legs already PASS.)
- [x] **M2-T6 subjective quality check** — DONE 2026-07-14: Franco compared Balanced vs High on
      real busy content and confirmed "balanced looks pretty good". Balanced quality is
      acceptable at ~2× the efficiency of Tier-1 → BitrateModel constants CONFIRMED, no change.
      M2-T6 fully complete.
- [ ] **G2 human legs** (when we run G2): sync-clap A/V test (§3.3), 30-min drift test (§3.5,
      `record` + `tools/beepflash.sh` running alongside; scrub QuickTime for sync at 0 vs 30 min).
- (gates marked "(human)" in docs/04 accumulate here as milestones close)

## Gate status

| Gate | Status | Evidence |
|------|--------|----------|
| G0   | ✅ passed 2026-07-14 | build+test(23)+bundle green; Identifier=dev.fcostantini.screenrec.app, Authority=screenrec-dev, designated requirement stable across rebuilds |
| M1   | ✅ complete 2026-07-14 | all 5 tasks done; capture engine + router + probe + sleep guard, 41 tests |
| G1   | ✅ passed 2026-07-14 | probe-stream: all 3 sources flowing. video 4112×2570 420v (PTS Δ 0.008–0.09s, frame-on-change); system audio 48kHz/2ch/32-bit (Δ 0.02s); mic native format device-dependent — AirPods 24kHz/1ch, built-in 48kHz/1ch (both differ from system audio → separate tracks required, M2) |
| G2   | ✅ passed 2026-07-14 | §3.1 tracks hvc1+2×aac ✅; §3.2 kill-9 ✅ (kill@6s→5.04s playable AFTER fragment fix 10s→1s — 10s was unparseable if killed <10s); §3.3 sync-clap ✅ (Franco); §3.4 static-tail ✅ (14s static→14.4s @7.9fps, tail patch holds); §3.5 30-min drift ✅ (Franco ran real 30-min record + beepflash; per-track dur match 50ms; flash↔beep offset constant ~−67ms±10 from min 5→29 = no drift) |
| G3   | 🟡 §4.1 passed | §4.1 pause-math: scripted `rec10,pause5,rec10` (--no-mic). Calm box → 4 runs 19.86–19.98s, all ∈ [19.8,20.2], tracks match ≤40ms. Loaded box (post code-review workflow, load ~2.6) → mean 20.05s over 8 runs (25s wall→20s file ⇒ 5s pause exactly removed), 5/8 strictly in-window; the 3 outliers are load jitter (audio starvation stretches the video tail; a load-delayed resume frame), NOT pause-math error. All runs probe monotonic-clean. §4.2 mic-disappears / §4.3 sleep-lock / §4.4 disk-guard await M3-T2..T4. Cross-seam clap-sync = human. |
| G4   | ⬜ not run | — |
| G5   | ⬜ not run | — |
| G6   | ⬜ not run | — |

## Field notes (append; things learned that docs don't cover yet)

- 2026-07-14 (M3-T1 pause/resume): wiring + a timing lesson for future gate runs.
  - **Pause anchor = newest raw PTS across all tracks**, not the last video frame. The rebaser
    removes `resumeFrameRaw − pauseAnchor`; anchoring on the last *video* frame (which can be
    stale on a static screen) would over-remove. System audio flows continuously (~43/s) so
    the cross-track max stays within a buffer of real "now". `MovieRecorder.latestRawPTS`.
  - **Resume re-anchors on the next COMPLETE video frame** (docs/02 §5, for A/V sync). So the
    pause-math precision depends on a frame arriving promptly after resume — i.e. on the screen
    changing. With normal desktop activity (ticker repainting, cursor) frames flow at tens of
    fps and the resume frame lands within ~1 frame; on a truly static screen the resume frame
    can lag up to ~1 s and shorten the file. The gate must run with screen motion present.
  - **`--script` sleeps use a tight-tolerance ContinuousClock sleep, not `Task.sleep`.** Default
    `Task.sleep` grants the scheduler generous wake-up slack; under the capture's CPU load the
    two 10 s record segments overshot ~0.2–0.3 s total, pushing the file to ~20.25 s (just over
    the ±0.2 s gate). A 2 ms tolerance recentres warm runs on ~20.0 s (±0.05).
  - **First scripted run in a batch is a cold-start outlier** (saw both 20.46 s high and 19.04 s
    low). The SCK capture-start / first-frame path warms up after one run; warm runs then
    cluster tightly (19.86–20.03 across ~9 runs). Same cold-start caveat as the G2 §3.5 flasher.
    Gate protocol: do one warm-up capture, then measure on a CALM system. DO NOT drive the
    record segments off `recordedDuration` to "nail" 20 s — that would make the file 20 s *by
    construction* and stop the duration check from proving the pause was removed (the 25 s-wall→
    20 s-file delta is the whole point). Keep wall-clock sleeps. The `--script` first segment IS
    anchored to the first frame (waits for `recordedDuration` to leave NaN) so SCK startup
    latency doesn't shorten the file — that's a *measurement* anchor, the segments stay wall-timed.
  - **Under heavy background load the gate spread widens** (saw 19.2–20.85 with load ~2.6 right
    after the 17-agent code-review workflow), but the MEAN stays ~20.05 (math is exact). The
    high outliers are *audio starvation*: near stop, under load, system-audio delivery lags and
    the video tail-frame patch extends video ~0.5–0.9 s past where audio ended → total tracks
    the longer video. Not pause-specific (tail-patch × load; G2 §3.5's 30-min run matched tracks
    ≤50 ms under normal load). Measure §4.1 on a calm box.
  - **`.paused`/`.resumed` events are gated on the timeline actually toggling** (high-effort
    /code-review finding): `TimestampRebaser.pause/resume` now return whether they took effect,
    `MovieRecorder` propagates it, and `RecordingSession` emits the engine event only when true.
    Pausing in the startup window (engine `.running` but before the first frame / rebaser epoch)
    is a no-op and no longer emits a pause that didn't happen. Also fixed: interactive stop
    regressed to "only bare Return" — restored to "any non-p/r line stops"; `--duration` timer
    now uses the same `preciseSleep`.

- 2026-07-14 (G2 §3.5 drift): the 30-min A/V-sync check is fully automatable given a
  beepflash recording. Method (reusable for the M6 §7 soak sync check): find each flash via
  **AVAssetReader sequential decode** of the video track in a time window + sparse-pixel
  brightness (NOT AVAssetImageGenerator random-access — it decodes from a keyframe per seek,
  ~100× slower); find each beep via AVAssetReader LPCM peak amplitude in the same window;
  compare flash-time − beep-time across markers. Result: constant ~−67 ms offset (fixed
  pipeline latency), no drift over 30 min. GOTCHAS: (a) the flasher's FIRST invocation is a
  cold-start → first marker's flash renders ~400 ms late; use markers 2+ for sync. (b) beepflash
  markers are ~287 s apart (285 s sleep + ~2 s per marker), so estimated marker times drift
  ~12 s by 30 min — center the search on observed flash times, not the nominal interval.

- 2026-07-14 (M2-T6): calibration + tools. Big practical unlocks for future capture work:
  - **Foreground Bash captures WORK** (agent runtime holds the TCC grant); backgrounded/
    detached commands lose it and fail "permission needed". Keep capture commands foreground
    and short-ish (a 28 s 4-way calibration loop stayed foreground; a `swift tools/probe.swift`
    COMPILE inside a command can push it over the auto-background threshold — pre-compile).
  - **I can drive a full-screen scene myself**: a `.screenSaver`-level `NSWindow` from a
    swiftc-compiled CLI renders on the display and IS captured (verified via frame brightness:
    a white flash reads 1.00 vs 0.22 baseline). `tools/busyscene.swift` (animated scene) and
    `tools/beepflash.sh` (sync markers) both use this.
  - **AVVideoAverageBitRateKey is a SOFT cap in real-time HEVC.** The HW encoder floors at the
    content's "natural" bitrate and won't crush quality to hit a low target — so presets barely
    separate on busy content (efficient≈balanced) and Balanced can't be pushed below ~50% of
    Tier-1 on complex scenes. Hard control needs VideoToolbox `DataRateLimits` (a VTCompression
    path), not AVAssetWriter — note for M6 if stronger preset differentiation is wanted.
  - Comparison table + numbers are in the "M2-T6 calibration comparison" section above.

- 2026-07-14 (human-verified): Franco ran `record` in his OWN terminal (not the agent
  runtime) and it worked perfectly — real capture, plays back, produced file good. Confirms
  the record pipeline works for a real user outside the agent's TCC grant, and the documented
  first-run permission dance holds. NOT a formal G2 pass (kill-9 / sync-clap / static-tail /
  drift still unrun), but de-risks G2 §3.1 track layout.

- 2026-07-14 (M2-T5): full `record` CLI UX. Notes:
  - **Progress ticker** = `\r  ⏺ MM:SS  <size>` every 0.5 s to stdout, guarding
    `recordedDuration.seconds` with `.isFinite` (the recorder returns `.invalid`/NaN before
    the first frame — docs/02 §10). `RecordingSession.recordedDuration` exposes it.
  - **Positional `[path]`**: an existing directory → auto-named inside; else an exact output
    file (O_EXCL-reserved via `OutputLocation.reserveExact`, refuses to overwrite).
  - **Return-to-stop** only when `isatty(STDIN_FILENO)` — a piped/automated run must NOT be
    stopped by stdin EOF, so the reader is skipped there (`--duration` bounds those).
  - **Preset size ordering IS testable live** with generated motion: a background mouse-mover
    (`CGWarpMouseCursorPosition` in a loop — no Accessibility grant needed) gives enough
    consistent frame change that efficient<balanced<high holds. Ambient static screen won't.
  - **Backgrounded/detached Bash commands lose the Screen Recording TCC grant** → capture
    fails "permission needed". Run capture tests in the FOREGROUND. (The failure did confirm
    the placeholder cleanup: a failed record leaves no 0-byte litter.)
  - Review fix: keeping the O_EXCL placeholder (M2-T4 TOCTOU) leaked a 0-byte file on failure
    paths and blocked exact-path retry; `MovieRecorder` now removes it on cancel / no-frames.

- 2026-07-14 (M2-T4): `record` does real 3-track capture. Design + gotchas future agents need:
  - **MovieRecorder self-configures from buffers.** It's now a `SampleConsumer`; the video
    input is built lazily from the FIRST frame's format (dimensions), like the mic input from
    the first mic buffer. This removed all pixel-dimension plumbing (the CLI can't resolve the
    display size without capturing) — the recorder just needs fps + preset + mic on/off. Every
    buffer is rebased via `TimestampRebaser` and retimed with
    `CMSampleBufferCreateCopyWithNewTiming` before append, so the file is zero-based & monotonic.
  - **`RecordingSession`** (new, RecorderCore/Recording) composes engine+recorder and emits the
    unified event stream incl. `finished` — the CLI and (later) the app share it.
  - **Probe monotonic check must use DTS, not PTS.** HEVC B-frames make PRESENTATION timestamps
    legitimately non-monotonic in storage order (probe saw "61/122 out of order" — all false).
    DTS (decode order) is the real invariant. Also: encoders emit a benign equal-timestamp edit
    at the very start (priming) and an invalid (nan-PTS) trailing packet — flag only STRICTLY
    backward steps and skip non-numeric stamps, or the probe cries wolf on clean files.
  - **Synthetic-buffer tests can't verify the tail-frame patch's extension.** `expectsMedia
    DataInRealTime = true` (required so SCK callbacks never block) makes the writer DROP buffers
    fed faster than real time; a burst-fed test drops most frames so durations are unreliable.
    The tail-patch code runs in the live path; its EXTENSION behavior is a G2 §3.4 (static
    screen) gate item. Don't add synthetic duration-assert tests for it.
  - **OutputLocation.reserveRecordingURL** closes the TOCTOU by `O_EXCL`-creating each
    candidate name and KEEPING the placeholder (holds the name); `MovieRecorder.beginWriting`
    removes it in the same synchronous breath as `startWriting()` creates the real file
    (`AVAssetWriter` init is fine with a pre-existing file but `startWriting` fails on one —
    verified), so the name is free for microseconds, not the whole startup window.

- 2026-07-14 (M2-T4 review): high-effort /code-review found real bugs; all fixed this task:
  - **Mic-never-arrives no longer discards the recording.** A selected-but-silent mic used to
    block `startWriting` forever (whole capture lost). Now `MovieRecorder` gives the mic a
    0.75 s grace past the first video frame, then proceeds WITHOUT the mic track. (M3-T2 can
    refine — e.g. surface a "mic unavailable" event.)
  - **TOCTOU actually closed** — the first pass deleted the placeholder before returning,
    reopening the race; now the placeholder is held until the writer (see above).
  - **`--duration` capped at 86400 s** — `UInt64(seconds * 1e9)` trapped on huge values.
  - **CLI mic resolution made pure + deduped** (dry-run and capture share one resolver).
  - **probe monotonic check now single-pass** across all tracks (was one full file pass per
    track — slow on the 30-min gate files).
  - Left as-is (low value): the lazy video input can't throw a precise `cannotAddInput(.screen)`
    at init like the old eager path — a bad first-frame format would fail late with
    `noFramesWritten`. SCK always delivers a valid video format on this hardware.

- 2026-07-14 (M2-T2): MovieRecorder skeleton lands (3-track .mov, HEVC + 2×AAC).
  TWO things worth carrying forward:
  (1) **AAC bitrate must snap to the encoder's applicable set.** Apple's AAC encoder
      accepts only a discrete bitrate set that shrinks with the format — 24 kHz mono
      (AirPods!) tops out at 64 kbps: `[16,20,24,28,32,40,48,56,64]k`. Requesting the
      nominal 160 kbps → `AVAssetWriter` fails at finish with -11861 / OSStatus -12651
      "encoding parameters not supported." `MovieRecorder.supportedAACBitRate` now queries
      `AVAudioConverter.applicableEncodeBitRates` and picks the highest ≤ target. This is
      exactly the AirPods 24 kHz mono case from G1 — the docs/02 §4 "~160 kbps" is a target,
      not a literal. (docs/02 §4 could note the discrete-set constraint.)
  (2) **OPEN for M2-T4/M3-T2 — mic-enabled recording is hostage to the mic.** Because the
      mic input is built lazily from the first mic buffer and inputs can't be added after
      `startWriting()`, the writer defers `startWriting` until that first mic buffer. If a
      mic is selected but never produces a usable buffer (silent/failed device, or a first
      buffer with no ASBD), `startWriting` never fires, ALL video is dropped, and `finish()`
      throws `noFramesWritten` — the whole screen recording is lost over a mic glitch. M2-T4
      (readiness/robustness) or M3-T2 (mic handling) must add a fallback: e.g. after a short
      grace period with no mic buffer, start writing video+system without the mic track.
  Also: `MovieRecorder` needs the resolved PIXEL dimensions (not in CaptureConfiguration —
  the engine computes them at start). M2-T4 must pass the engine's resolved width/height +
  the clamped fps into the recorder.

- 2026-07-14 (M1-T4): probe-stream confirms all three sources flow through the router.
  KEY M2 INPUT — the mic's native format is device-dependent and differs from system
  audio: AirPods = 24000 Hz/1ch/32-bit float, built-in = 48000 Hz/1ch/32-bit, system
  audio = 48000 Hz/2ch/32-bit. Empirical proof the mic needs its own AVAssetWriterInput
  (can't share the system-audio input — DTS finding now confirmed live). Screen frames
  arrive as 4112×2570 `420v` (bi-planar YUV 4:2:0, NOT compressed — HEVC encode happens
  in the writer). Mic capture required Franco to grant Claude Code Microphone TCC.
- 2026-07-14 (M1-T2 review): xhigh code-review of the capture engine found real
  concurrency/robustness bugs — all fixed: (a) stop() during start()'s suspension was
  silently lost → added a state machine (idle/starting/running/terminated) + stopRequested
  honored on resume; (b) fail()/didStopWithError could both emit → single termination
  authority (failToStart/terminate, state-guarded; handler hops to the actor); (c) engine-
  smoke reported streamError / no-frame as OK → now requires .started + clean stop;
  (d) --duration nan/inf/neg trapped → validated; (e) unvalidated frameRateCap → clamped
  [1,240]; (f) raw TCC error → mapped to permissionGuidance (tested); per-instance sample
  queues; early-exit smoke on failure. Accepted as-is: startDecision.denied is defensive/
  unreachable in prod; minor guidance-string duplication with Permissions.swift.
- 2026-07-14 (M0 holistic review + M1-T1): Holistic M0 review passed from a fully clean
  state (`rm -rf .build dist` → build/test(23)/release/bundle all green; devsign
  idempotent; designated requirement stable across fresh rebuilds; CLI works). M0 is
  genuinely complete. M1-T1: CaptureConfiguration + QualityPreset/DisplaySelection/
  MicrophoneSelection value types + pixel math, 29 tests. CLI now parses presets via
  QualityPreset (placeholder array removed).
- 2026-07-14 (M0-T5): CLI dry-run + list-mics work. TWO things to watch in M1:
  (1) `CGPreflightScreenCaptureAccess()` returns false ("not determined") for the
  freshly-built Tier-2 CLI even though this terminal records fine via the Tier-1 PoC —
  TCC screen-recording grants attach to the responsible binary's code identity, so the
  new binary may need its own grant, or preflight is just conservative. M1-T2's
  engine-smoke will settle whether capture actually works from the terminal or needs a
  grant. (2) Desktop preflight now reports OK because this terminal currently CAN write
  there (the write-probe tests reality) — so the old "Desktop always fails" is
  environment-specific, not universal; ~/Movies default still stands as the no-grant-
  needed choice.
- 2026-07-14 (M0-T4): Permissions.swift + OutputLocation.swift in RecorderCore, 23
  tests green. Ran /code-review (xhigh workflow) on the diff; fixed 5 of 6 findings:
  preflight now probes WRITE access (opendir only proved read/execute) and distinguishes
  a missing folder from a permission denial; mic resolution rejects a stale/unplugged
  preferred ID and an empty default; timestamp/resolvedFileName made internal.
  **Deferred to M2 (open item):** newRecordingURL collision resolution is check-then-act
  (TOCTOU) — two recordings started in the same clock second could resolve to the same
  name. Real fix = the writer creating the file with `O_EXCL` and retrying the suffix on
  EEXIST. Low risk now (manual recording is single-instance; replay uses a "Replay"
  prefix). MovieRecorder (M2-T2/T4) MUST use exclusive create — add to that task's work.
- 2026-07-14 (M0-T3): bundle.sh assembles/signs dist/ScreenRec.app. Verified:
  Identifier=dev.fcostantini.screenrec.app, Authority=screenrec-dev; designated
  requirement byte-identical across two rebuilds (`identifier "…" and certificate leaf
  = H"62a8ac…"`) → TCC grants will survive rebuilds; `open` launches the LSUIElement
  app, process stays alive, quits cleanly. `spctl -a -t exec` fails (not notarized) —
  expected pre-M6, script reports it without failing. Info.plist lives at
  Sources/ScreenRecApp/Resources/Info.plist and is `exclude`d in Package.swift so SPM
  ignores it.
- 2026-07-14 (M0-T1): Command Line Tools have NO XCTest — `import XCTest` fails to
  compile. Swift Testing (`import Testing`) works and is now the mandated framework
  (docs/02 §10 updated). Verify evidence: `swift build` links all 3 targets;
  `swift test` → "1 test passed"; CLI prints skeleton banner with RecorderCore 0.1.0.

- 2026-07-13 (planning session): Tier-1 PoC (~/code/screenrec-poc) empirically verified:
  SCRecordingOutput survives kill -9 with sub-second loss; nil microphoneCaptureDeviceID
  throws "invalid parameter" on 15.6; Desktop output dir fails the same way when the
  terminal lacks the Files & Folders grant; recordedDuration is NaN pre-first-frame.
  All encoded in docs/02.

## History

- 2026-07-14 — docs/06-ui-spec.md added (menu states, notification copy, onboarding,
  contractual UserDefaults keys). Independent-agent audit of all milestones/tasks run;
  fixes applied across docs/01–06 (EngineEvent surface defined in 01, replay-save
  trigger = SIGUSR1/stdin on replay-arm, record subcommand lifecycle reconciled, probe
  extensions assigned to M2-T4, unrunnable Verify steps fixed or marked human). See
  git log for the diff.

- 2026-07-13 — Research + Tier-1 PoC completed in ~/code/screenrec-poc. Tier-2 planning
  docs authored (docs/00–05, CLAUDE.md, this file). No Tier-2 code exists yet.

# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short; details go to Field notes / History.

## Now

- **Current milestone:** M2 — MovieRecorder, the real writer (M1 complete, G1 passed)
- **Next task:** M2-T1 (`BitrateModel` + tests: 02 §3 presets — pixels×fps×BPP with the
  HEVC discount; monotone efficient<balanced<high). Then M2-T2 is the writer skeleton.
- **Blockers:** none — the M1-T4 finding (mic 24k/48k mono vs system 48k stereo) is the
  key input to M2's two-separate-audio-tracks design.

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
- (gates marked "(human)" in docs/04 accumulate here as milestones close)

## Gate status

| Gate | Status | Evidence |
|------|--------|----------|
| G0   | ✅ passed 2026-07-14 | build+test(23)+bundle green; Identifier=dev.fcostantini.screenrec.app, Authority=screenrec-dev, designated requirement stable across rebuilds |
| M1   | ✅ complete 2026-07-14 | all 5 tasks done; capture engine + router + probe + sleep guard, 41 tests |
| G1   | ✅ passed 2026-07-14 | probe-stream: all 3 sources flowing. video 4112×2570 420v (PTS Δ 0.008–0.09s, frame-on-change); system audio 48kHz/2ch/32-bit (Δ 0.02s); mic native format device-dependent — AirPods 24kHz/1ch, built-in 48kHz/1ch (both differ from system audio → separate tracks required, M2) |
| G2   | ⬜ not run | — |
| G3   | ⬜ not run | — |
| G4   | ⬜ not run | — |
| G5   | ⬜ not run | — |
| G6   | ⬜ not run | — |

## Field notes (append; things learned that docs don't cover yet)

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

# 03 — Milestones & Task Breakdown

Order is dependency-driven; do not reorder without updating STATUS.md and this file.
Task IDs (M2-T3) are stable — reference them in commits ("M2-T3: rebase audio PTS").
Every milestone ends with its **gate**: the acceptance checks in 04-testing that must
pass before starting the next milestone. Check boxes here as tasks complete.

Additionally, every task carries its own **Verify:** step, runnable immediately after
implementing that task alone. A task is NOT done (and must not be ticked) until its
Verify passes; paste non-trivial Verify output into STATUS.md. Verify steps marked
**(human)** go to STATUS.md → "Needs Franco" instead of blocking the next task.

Task completion order is: implement → Verify passes → **quality pass over the diff**
(see CLAUDE.md "Quality pass" — architecture, Swift practice, concurrency, cleanliness,
scope) → re-Verify if the pass changed code → tick box → commit.

Estimates assume one focused agent session ≈ half a day of human-equivalent work.

---

## M0 — Scaffolding & prerequisites (est. 1 session)

Goal: `swift build` + `swift test` green; stable signing; CLI skeleton runs.

- [x] M0-T1 `Package.swift`: targets `RecorderCore` (library), `screenrec-cli`
      (executable), `ScreenRecApp` (executable), `RecorderCoreTests`. Platform
      `.macOS(.v15)`, `swiftLanguageMode(.v5)`, zero external dependencies.
      **Verify:** `swift build && swift test` green (one placeholder test). ✅ 2026-07-14
      — note: tests MUST use Swift Testing, not XCTest (02 §10).
- [x] M0-T2 `Scripts/devsign.sh`: locate a valid codesigning identity — prefer
      "screenrec-dev" (already created & trusted 2026-07-14, see STATUS.md), else any
      "Apple Development"; print it; NEVER create certs itself (print manual Keychain
      instructions if none found). Idempotent.
      **Verify:** run twice → identical identity hash both times; exits nonzero with
      instructions when given `--pretend-missing`. ✅ 2026-07-14
- [x] M0-T3 `Scripts/bundle.sh`: SPM release build → assemble `dist/ScreenRec.app`:
      `Contents/MacOS/ScreenRec` = the `ScreenRecApp` product binary;
      `Contents/Info.plist` copied from `Sources/ScreenRecApp/Resources/Info.plist`
      (create it in this task: bundle id `dev.fcostantini.screenrec.app`,
      NSMicrophoneUsageDescription, LSUIElement=true); `Contents/PkgInfo` = `APPL????`
      → `codesign --force --sign "$(Scripts/devsign.sh)"`. (`spctl -a -v` failure is
      OK pre-notarization.)
      **Verify:** `codesign -dvv dist/ScreenRec.app 2>&1` shows the Identifier and
      Authority "screenrec-dev"; two consecutive bundle.sh runs → byte-identical output
      from `codesign -d -r- dist/ScreenRec.app 2>&1` (designated requirement = TCC
      stability); `open dist/ScreenRec.app` launches without crash. ✅ 2026-07-14
- [x] M0-T4 Port from PoC into `RecorderCore/Support` + `Capture`: `Permissions.swift`
      (preflights incl. ⚠️ output-dir lesson, 02 §2; owns default-mic resolution:
      `resolvedMicrophoneID()` returns an explicit uniqueID or a human reason — the
      ⚠️ nil-mic-ID lesson lives HERE; CaptureConfiguration only ever stores an
      already-explicit ID), `OutputLocation.swift` (naming + ` 2`/` 3` collision policy,
      02 §6). Design both so decision logic is pure/injectable.
      **Verify:** `swift test` — OutputLocation naming/collision/preflight-failure
      cases; Permissions decision table with injected TCC/device states. ✅ 2026-07-14
- [x] M0-T5 CLI skeleton: `screenrec-cli record --duration N` prints config it WOULD
      use (no capture yet); `--list-mics`; unbuffered stdout (02 §10).
      **Verify:** `--list-mics` lists real devices; dry-run `record` prints resolved
      config (incl. explicit mic ID, output path preflight result); output intact
      when piped to a file (buffering test). ✅ 2026-07-14 (subcommands `record` /
      `list-mics`; `AudioInputs` helper added to RecorderCore for device enumeration)
- [x] M0-T6 CI-less verification loop documented in CLAUDE.md ("Dev loop"): the ordered
      build/test/release/bundle sequence an agent runs after every change (canonical home
      is the always-read contract, not the volatile STATUS.md).
      **Verify:** execute the documented loop verbatim top to bottom; it passes.
      ✅ 2026-07-14 (all four steps green)

**Gate G0**: 04-testing §1 (build/test/bundle/sign all green; app launches, shows in
menu bar as placeholder or CLI prints config).

---

## M1 — Capture engine (est. 1–2 sessions)

Goal: RecorderCore starts an SCStream and delivers all three sample types to pluggable
consumers. No writing yet.

- [x] M1-T1 `CaptureConfiguration`: display selection (default main), mic device
      (stores the explicit ID resolved by Permissions/M0-T4 — 02 §1), fps cap, quality
      preset enum. Pixel math from contentRect × pointPixelScale.
      **Verify:** unit tests with mocked rect/scale (e.g. 2056×1285 @2× → 4112×2570);
      preset/fps defaults. ✅ 2026-07-14 (29 tests; CLI now uses the QualityPreset enum)
- [x] M1-T2 `CaptureEngine` actor: build filter + SCStreamConfiguration (02 §1 values),
      start/stop, delegate for `didStopWithError`, `EngineEvent` AsyncStream (the enum
      defined in docs/01 — implement it exactly). Includes a `screenrec-cli
      engine-smoke [--duration N]` subcommand (default 2 s), its own verification
      instrument.
      **Verify:** `engine-smoke` → prints `started` then `stopped(userStopped)`,
      exit 0. Denied-permission path = unit test with injected Permissions state
      (NEVER revoke live: `tccutil reset ScreenCapture` would destroy this terminal's
      own grant and block all capture testing — 02 §2). ✅ 2026-07-14 (started →
      stopped(userStopped), exit 0; 4 injected-state start-decision tests)
- [x] M1-T3 `SampleRouter`: three serial queues; consumer protocol
      `SampleConsumer { func consume(_ buffer: CMSampleBuffer, type: SourceType) }`;
      attach/detach under lock; frame-status filtering for video (02 §1).
      **Verify:** unit tests with synthetic CMSampleBuffers — two consumers both
      receive; detach mid-stream safe under `swift test --sanitize=thread`. ✅ 2026-07-14
      (4 router tests pass under TSan; .started now via a StartedDetector consumer; the
      per-output serial queues live on CaptureEngine from M1-T2)
- [x] M1-T4 CLI: `screenrec-cli probe-stream --duration 5 [--mic <uniqueID>]` — counts
      buffers per type, prints format descriptions (esp. mic native format — we need to
      SEE it), min/max PTS deltas. This is our instrumentation for everything after.
      **Verify:** run 04-testing §2 in full; the default-mic AirPods leg needs the
      device connected **(human/device present)**; paste output + mic format into
      STATUS.md. ✅ 2026-07-14 (all 3 streams flowing; mic native format varies by
      device — see STATUS)
- [x] M1-T5 `SleepGuard` (02 §7) wired to engine start/stop.
      **Verify:** during `engine-smoke --duration 10`, `pmset -g assertions` shows
      PreventUserIdleSystemSleep held by our process; released after exit. ✅ 2026-07-14
      (pid …(screenrec-cli) held "Recording the screen"; released after exit)

**Gate G1**: 04-testing §2 (probe-stream shows all three types flowing, PTS sane,
mic format captured and documented in STATUS.md).

---

## M2 — MovieRecorder: the real writer (est. 2–3 sessions, the heart of Tier 2)

Goal: three-track `.mov` with tuned HEVC, crash-safe, from the CLI.

- [x] M2-T1 `BitrateModel` (02 §3 presets).
      **Verify:** unit tests — preset math, pixel-count edge cases, monotone ordering
      Efficient < Balanced < High at fixed resolution. ✅ 2026-07-14 (9 tests; reference
      figures ~5/~19 Mbps, ratios, fps/pixel proportionality, zero-dim guard)
- [x] M2-T2 `MovieRecorder` skeleton: writer + 3 inputs (video HEVC from preset; system
      AAC; mic input built lazily from first mic buffer's format — 02 §4),
      `expectsMediaDataInRealTime`, fragment interval 10 s (02 §5).
      **Verify:** WITHOUT ScreenCaptureKit — a `swift test` integration test feeds 2 s
      of synthetic buffers (solid-color CVPixelBuffers + PCM silence in two different
      audio formats) → `finishWriting` to a temp path → the test itself asserts track
      count/codecs/duration via AVAsset (hvc1 + two aac, 2 ± 0.1 s); run tools/probe on
      the temp file once as a human-readable cross-check. Proves the writer
      independently of capture. ✅ 2026-07-14 (3 tests; probe: 2.00s, hvc1 640x360 +
      aac 48k/2ch + aac 24k/1ch. AAC bitrate must snap to the encoder's applicable set —
      see STATUS field note.)
- [x] M2-T3 `TimestampRebaser`: epoch at first complete video frame, drop
      pre-epoch audio, monotonic enforcement, pause offset accounting (pause used in M3
      but build the math now).
      **Verify:** pure unit tests — epoch rebase, pre-epoch drop, cumulative pause
      offsets, out-of-order rejection. ✅ 2026-07-14 (9 tests; pure value type, no AVF/clock)
- [x] M2-T4 Wire as SampleConsumer; readiness handling = drop + count (report dropped
      frames at stop). Stop path: tail-frame patch (02 §5), `markAsFinished` ×3,
      `finishWriting`, emit `finished(url:reason:droppedFrames:)` (docs/01). The
      existing `record` subcommand (a dry-run since M0-T5) now performs real capture;
      the old behavior moves behind `--dry-run`. Also extend `tools/probe.swift` with
      per-track durations and a monotonic-PTS warning — 04 §3.5 and §4.1 depend on
      those probe features. Close the OutputLocation TOCTOU (M0-T4 field note): create
      the output file exclusively (AVAssetWriter errors if it exists) and bump the ` 2`
      suffix on collision so two same-second recordings can't overwrite each other.
      **Verify:** `screenrec-cli record --duration 5` → probe: 3 tracks at full pixel
      res, duration 5 ± 0.5 s, per-track durations shown, reported dropped-frames = 0
      on an idle machine; `record --dry-run` still prints config without capturing.
      ✅ 2026-07-14 (live: hvc1 4112×2570 + aac 48k/2ch + aac 24k/1ch AirPods, dur 4.87s,
      dropped 0, probe monotonic-clean. RecordingSession composes engine+recorder; probe
      now checks DTS monotonicity + per-track durations. Tail-patch extension behavior
      deferred to G2 §3.4 — synthetic bursts can't exercise it, real-time encoder drops.)
- [x] M2-T5 CLI: full `record [--duration N] [--preset X] [--no-mic] [path]`
      — parity with the Tier-1 PoC UX (progress ticker with NaN guard!). Preset
      literals: `efficient` | `balanced` | `high` (02 §3).
      **Verify:** matrix — `--no-mic` → exactly 2 tracks; each preset → file sizes
      strictly ordered; explicit path honored; ticker never prints NaN (pipe run).
      ✅ 2026-07-14 (live: no-mic→2 tracks; sizes efficient 4.28<balanced 4.96<high 5.25 MB;
      exact path + positional dir honored; ticker 0 NaN piped. Return-to-stop on a TTY;
      +failure-path placeholder cleanup, 65 tests.)
- [x] M2-T6 Quality calibration: record the same 30 s busy scene at each preset +
      Tier-1 (~/code/screenrec-poc binary) for comparison; adjust BitrateModel
      constants. Repeatable scene: loop one fixed local video file fullscreen in
      QuickTime for all runs; record the exact file used in STATUS.md. Also deliver
      `tools/beepflash.sh` (beep + full-screen flash every 5 min; used by 04 §3.5's
      drift test).
      **Verify:** comparison table (size + notes) in STATUS.md; Balanced ≤ 50% of
      Tier-1 size. Subjective quality check **(human)**.
      ✅ 2026-07-14 (comparison table + findings in STATUS. Balanced ≈ 49–51% of Tier-1
      (~2× more efficient) — at the target line. Used a generated scene `tools/busyscene.swift`
      instead of a QuickTime video (deterministic, no external file). Constants UNCHANGED —
      the encoder's soft AverageBitRate cap floors output, so they can't do better here.
      `tools/beepflash.sh` delivered + flash verified visible. Subjective quality → Needs Franco.)

**Gate G2**: 04-testing §3 (tracks probe: hvc1 + 2×AAC; kill -9 test playable; sync
clap test; static-screen duration test; 30-min drift test).

---

## M3 — Pause/resume + robustness (est. 1–2 sessions)

- [x] M3-T1 Pause/resume through CaptureEngine → TimestampRebaser; resume waits for
      next complete video frame. CLI: interactive `p`/`r` keys in `record`, plus
      scripted mode `--script rec10,pause5,rec10` for unattended verification.
      **Verify:** 04-testing §4.1 — scripted run yields 20 s ± 0.2 s file, monotonic
      PTS. Cross-seam A/V sync check **(human)**.
      ✅ 2026-07-14 (calm box: 4 runs 19.86–19.98s, all ∈ [19.8, 20.2], tracks ≤40 ms;
      loaded box: mean 20.05s/8 runs, 5/8 in-window, outliers = load jitter not math. All
      monotonic-clean. First run in a batch swings wide (cold SCK path) — warm up before
      measuring; measure on a calm system. Cross-seam clap-sync → Needs Franco.)
- [x] M3-T2 Mic format-change detection → clean stop emitting
      `finished(url:reason:.microphoneChanged)` (docs/01 event surface; 02 §4,
      ADR-007).
      **Verify:** unit test injects a format-changed buffer → clean-stop path taken.
      Live AirPods-off run per §4.2 **(human present for the device action)**;
      afterwards agent confirms playable file + causal message.
      ✅ 2026-07-15 (unit test: injected format-B mic buffer fires the one-shot handler
      exactly once; live regression: 4s stable-mic record finishes `userStopped` with a
      clean 3-track file, no false-positive. Live AirPods-die run → Needs Franco.)
- [x] M3-T3 Disk-space monitor → clean stop at <2 GB (02 §7), `--test-disk-floor N`
      flag to trip it deterministically.
      **Verify:** §4.4 — run with floor above current free space → clean stop, message
      names disk space, file playable.
      ✅ 2026-07-15. `DiskSpaceMonitor` (Support/) watches free space on the output volume;
      `RecordingSession` owns and polls it (the engine has no idea where the file lives) and
      calls the M3-T2 seam `engine.stop(reason: .diskAlmostFull)`. §4.4 PASSED:
      `--test-disk-floor 500000` (GB) vs 676 GiB free → `✓ finished (diskAlmostFull)`, file
      **playable** (2.25 s). Negative side verified on a real non-boot volume: a 4 GB HFS+ image
      records the full 8 s and finishes `userStopped`. 9 unit tests (injected probe: fires once /
      not above / not *at* the floor / not when unreadable; plus the pure two-key reconciliation
      incl. the external-volume case). The poll waits for `recordedDuration` to leave NaN before
      guarding — stopping pre-first-frame yields `.failed`, not a playable file, and a wall-clock
      delay only narrows that race rather than removing it.
      ⚠️ /code-review caught a shipper: `volumeAvailableCapacityForImportantUsage` reads **0 on
      every non-boot volume**, so the guard killed every external-drive recording at ~2 s —
      invisible to both the gate and the unit test, which only ever touched the boot volume.
      See 02 §7 + STATUS field notes.
- [x] M3-T4 Display-change / sleep handling end-to-end (unplug display, close lid):
      always a playable file + correct event. Document observed behaviors in 02.
      **Also fix (found 2026-07-15, see STATUS):** a display asleep AT START is misreported as
      a permission failure — preflight says *granted* while `SCShareableContent` returns 0
      displays, and `startDecision` maps any zero-display result to `permissionGuidance`. Gate
      that wording on the preflight actually disagreeing; otherwise report "no displays
      available — the screen may be asleep, locked, or disconnected". 02 §1's "empty results =
      permission missing" is incomplete and needs the same correction, and
      `CaptureEngineTests.failsWhenNoDisplaysAvailable` encodes the conflation today.
      **Verify:** §4.3 **(human)** — both scenarios end in probe-clean files; observed
      SCK error codes recorded in docs/02 field additions.
      ✅ 2026-07-15. **Display-gone is `SCStreamErrorNoCaptureSource` (-3815)** — measured, not
      guessed, via `pmset displaysleepnow` mid-recording (which turns out to be a headless lever
      for this leg). `endReason(forStreamError:)` maps it → `finished(.displayDisconnected)` +
      playable file (verified live, 3.33 s); unmapped SCK errors now carry their raw code, which
      is how -3815 was identified at all. This finally wires up `EndReason.displayDisconnected`,
      declared-but-dead since M1. ⚠️ SCK collapses sleep/lock/unplug into that one code, so
      `.systemSleep` stays unreachable — no distinction faked (02 §7).
      **Locked-screen bug FIXED and verified live**: zero displays no longer implies "grant
      permission" — with the preflight reporting *granted*, we now say "No displays are
      available — the screen may be asleep, locked, or disconnected". Repro needs lock **AND**
      display-off (neither alone; truth table in 02 §1). Failure path leaves no 0-byte litter.
      **Still human (→ Needs Franco):** lid-close (system sleep, distinct from display sleep) and
      physical monitor unplug — both remain unobserved.
- [x] M3-T5 Stall watchdog logging (02 §7; input-idle via
      `CGEventSource.secondsSinceLastEventType` — not NSEvent), clock injectable.
      **Verify:** unit test with injected clock — 30 s of no video buffers fires
      exactly one log line; buffer arrival resets it.
      ✅ 2026-07-15. `StallWatchdog` (Capture/) is a router consumer; the engine polls it and
      logs via `os.Logger` (subsystem `dev.fcostantini.screenrec` — see 02 §7 for how to READ
      it; it does NOT reach stdout). Diagnostic only, no auto-restart. 8 unit tests with injected
      clock AND injected idle probe: fires once per episode; **silent when the user is idle**
      (the central case — frame-on-change makes a static screen legitimately silent); silent
      before the timeout / while frames flow / before the first frame ever arrives; re-arms so a
      second episode is reported (a stall can pass, unlike a mic disconnect); only `.screen`
      counts as proof-of-life (audio flows through a video stall and would mask it); and reports
      the measured silence, not the constant. A real stall can't be forced — SCK must genuinely
      wedge — so M6-T2's soak is where this would ever actually fire.
      Also **extracted the shared `pollingTask(every:)`** here per the rule-of-three deferral
      from M3-T3: mic-loss, disk-floor and stall were three verbatim copies of the same loop,
      each having re-learned the same cancellation/handle-retention lessons.
- [x] M3-T6 **Mic-loss watchdog** (02 §4, ADR-012). A lost mic device stops delivering
      rather than handing over (proved by §4.2, 2026-07-15), so M3-T2's format compare can
      never fire for it: detect *starvation* instead — mic was delivering, then nothing for
      N s while recording and not paused ⇒ emit `microphoneLost` (docs/01) exactly once.
      Recording CONTINUES (ADR-012); the mic track just ends. Clock injectable; do not fire
      while paused (buffers are dropped by design) or when no mic was ever selected.
      **Verify:** unit tests with an injected clock — buffers→silence fires exactly one
      event; no event while buffers flow, while paused, or with `--no-mic`. CLI prints the
      loss. Live AirPods-case run per §4.2 **(human)**; agent then confirms the file is
      playable with the mic track ending at the disconnect.
      ✅ 2026-07-15. Unit: 5 tests, injected clock, zero real time (fires once; not before the
      timeout; not while delivering; not when never delivered; only `.microphone` counts).
      **Live §4.2 PASSED** (Franco): AirPods cased at ~22 s of a 60 s run → CLI printed
      `⚠️ microphone disconnected — still recording` at ~25 s (≈3.2 s latency = the designed
      3 s timeout + ≤1 s poll), recording ran to the end, `finished (userStopped)`, file
      playable, mic track ends at 21.82 s vs video 59.83 s. Also verified: a 5 s scripted pause
      (> the 3 s timeout) does NOT false-fire, which proves SCK keeps delivering mic buffers
      while paused — so pause needs no handling here.
- [x] M3-T7 **SPIKE (time-boxed): can SCK re-point a live stream's mic?** The load-bearing
      unknown behind ever recovering mic audio after a disconnect. Two legs, staged — only run
      leg 2 if leg 1 survives:
      1. **Headless**: mid-capture, call `SCStream.updateConfiguration` with a *different*
         `microphoneCaptureDeviceID` (swap built-in ↔ AirPods by ID — no physical action, but
         both devices must be present) and see whether `.microphone` buffers switch to the new
         device's format.
      2. **Physical (human)**: the harder case — re-point at a device that *died and came back*
         (reconnect creates a NEW CoreAudio device object even when the uniqueID string is
         stable, which is the leading theory for why passive reconnect delivers nothing).
      Prior is now **low**: SCK doesn't resume even the same pinned device when it returns
      (02 §4), suggesting the mic path is torn down for good — but an explicit API call is not
      passive re-attach, so it's worth 30 minutes to stop guessing.
      Costing note: leg 2 is the *cheap* feature. A reconnecting device returns at the **same
      format**, so it needs no resampling — it drops straight into the existing mic input.
      Only switching to a *different* device needs the fixed-format/resampled input (ADR-012).
      **Verify:** the finding is recorded in 02 §4 + STATUS either way. Yes ⇒ reopen ADR-012
      with a re-attach proposal (reconnect-recovery first, it's cheaper). No ⇒ ADR-012's
      notify-and-continue is final for v1 and the resampling question closes with it.
      ✅ 2026-07-15 — ran to 6 experiments (`mic-swap-spike`, 5 modes). The one rule: **SCK binds
      the mic once at `startCapture` and never re-resolves**, named or nil. Re-point works to a
      device alive throughout, never to one that died (and `updateConfiguration` returns OK while
      doing nothing). Poisoning is per-stream, so a rebuilt mic-only stream recovers anything —
      two streams verified to coexist. nil is accepted (02 §1's "nil throws" is STALE) but
      resolves-once, so it is not a fallback mechanism. Full table + both routes in 02 §4.
      ADR-012 revisited: recovery is possible but **deferred post-v1** — decision unchanged.

**Gate G3**: 04-testing §4 (pause math: 10 s rec / 5 s pause / 10 s rec ⇒ 20 s ± 0.2 s
file, A/V in sync across the seam; all three robustness scenarios end in playable files).

---

## M4 — Menu-bar app (est. 2 sessions)

Goal: ScreenRec.app is the daily driver; CLI demoted to debugging.
UI layout, states, notification copy, and onboarding flow are specified in
**docs/06-ui-spec.md** — build to that spec; don't improvise structure or copy.

- [x] M4-T1 `MenuBarExtra` app shell, LSUIElement, status icon states (idle/recording
      pulse/paused), AppState consuming EngineEvents on MainActor. `AppState` + view
      models live in a NEW library target `AppCore` (depends on RecorderCore; no
      AppKit/SwiftUI imports) so they're unit-testable — SwiftUI views stay in the
      `ScreenRecApp` executable.
      **Verify:** `open dist/ScreenRec.app` → icon appears, no Dock icon; AppCore unit
      tests map each EngineEvent to the right icon state. Visual check **(human)**.
      DONE 2026-07-15: all three icon states captured via `screencapture` (idle template
      outline, red pulse, amber half-circle); `lsappinfo` reports `ApplicationType=UIElement`
      (no Dock icon); 11 AppCore tests (108 total). docs/06's 4th state (replay-armed badge)
      deferred to M4-T2, which brings the toggle that can set it.
- [x] M4-T2 Menu: Start/Stop/Pause, display picker (NSScreen list), mic picker
      (AVCaptureDevice list + "None"), preset picker, "Open Recordings Folder",
      recent files, inline rows (last 5 — docs/06 item 10 wins over "submenu" here; Franco
      confirmed 2026-07-15).
      **Verify:** menu-driven 5 s recording **(human — menus can't be clicked
      headlessly; first run also needs the app's own TCC grant)**; the agent's share:
      probe the produced file (3 tracks, sane duration) and check the recent-files
      logic via AppCore unit test against a fixture directory.
      DONE 2026-07-15. **No longer human**: `tools/menudriver.swift` + the Accessibility grant
      drove the whole flow (open → Start → 5 s → Stop & Save) headlessly → playable 6.38 s file,
      probed. **2 tracks, not 3** — mic was `None`, which is correct for that config; the 3-track
      probe moves to M4-T3 (below), because a mic needs Microphone TCC and *only the app can
      request it* (that pane has no "+"). Franco granted the app Screen Recording by hand.
      Instant-replay toggle deferred — first to M4-T4, then (Franco, 2026-07-15) to **M5**, with
      the feature it claims to arm. It had moved three times; the ruling is that it belongs to M5.
- [x] M4-T3 Onboarding: permission status view; request buttons; explains the
      restart-after-grant dance (02 §2); blocks record until green.
      DONE 2026-07-15. Window opens itself at launch when blocked (verified frontmost), and from
      the menu header always (Franco: a disabled header stranded the optional Notifications row).
      ⚠️ **Two spec bugs found while building, both fixed and both amended into docs/06**: a
      `Grant…`-only row is dead after any decline (macOS prompts once, ever — 02 §2), and
      auto-appearing ≠ being reachable. **The M3-T4 question is SETTLED** (see below) — no code
      change; `startDecision` was right. **M4-T2's 3-track probe closed**: menu-driven recording
      with a mic → `hvc1 4112×2570 + aac 48k/2ch + aac 48k/1ch`, 7.36 s, playable.
      **Inherits M4-T2's 3-track probe:** picking a mic in M4-T2 is an unrecoverable dead-end
      (Start greys out; the Microphone pane has no "+", so only a `requestAccess` call can grant
      it — verified 2026-07-15). Once the Grant… button exists, run a menu-driven recording with
      a mic selected and probe for 3 tracks. That closes M4-T2's one open leg.
      **SETTLED 2026-07-15 — it throws.** An ungranted process throws `-3801`
      (`SCStreamError.userDeclined`); it never enumerates zero. Measured on *both* paths
      (not-determined → prompt → decline; and denied → instant throw) — and without the fresh
      account the note called mandatory: **TCC keys on code identity, not on the user**, so a
      throwaway bundle with a different bundle ID is a never-granted subject on this account
      (recipe in 02 §1). `startDecision` was right all along and is unchanged; M3-T4's
      locked-screen fix stands. The fresh-account walkthrough is still owed for G4's <2-minute
      UX check — but it is no longer load-bearing for this question.
      **Verify:** unit tests render view model for every permission-state combination;
      fresh-account walkthrough per 04-testing §5.1 **(human)**.
- [ ] M4-T4 Settings window (SwiftUI Form, UserDefaults): output dir (with preflight on
      choose — 02 §2), preset, fps.
      ⚠️ **DESCOPED 2026-07-15 (Franco)**: replay duration + hotkey recorder move to **M5**, and
      launch-at-login to **M6** — see docs/06's Settings amendment. The principle: don't ship
      controls for a feature that doesn't exist, and don't register a login item pointing at
      `dist/`, which `bundle.sh` deletes on every build. So T4 writes exactly three keys:
      `outputDirectory`, `qualityPreset`, `fpsCap`.
      UserDefaults key names are still contractual — use exactly the table in docs/06
      "Settings window"; the names are fixed even where the writing task moved.
      **Verify:** change each setting, quit, relaunch → `defaults read
      dev.fcostantini.screenrec.app` shows the documented keys with persisted values and UI
      reflects them; choosing unreadable dir → immediate friendly error (§5.4).
      DONE 2026-07-15: verified headlessly — Quality→High via the menu → `qualityPreset = high`
      in `defaults read` → quit → relaunch → menu returns on `✓ High`. All three keys land under
      exactly the documented names. ⚠️ **G4 §5.4 (choose Desktop → friendly error at selection)
      is NOT yet run** — it needs the NSOpenPanel driven, and `menudriver` can't; the preflight
      behind it is M0-T4's and unit-tested. Owed to G4.
      **Verify:** change each setting, quit, relaunch → `defaults read
      dev.fcostantini.screenrec.app` shows the documented keys with persisted values
      and UI reflects them; choosing unreadable dir → immediate friendly error (§5.4).
- [x] M4-T5 Notifications (UserNotifications): recording ended + reason; click →
      reveal in Finder. Notification authorization is requested per docs/06 onboarding
      (optional row, non-blocking). Debug hook: the app accepts launch argument
      `--print-delivered-notifications` (prints `UNUserNotificationCenter` delivered
      list to stdout and exits).
      **Verify:** stop a recording, relaunch with the debug argument → the finish
      notification is in the delivered list with docs/06 copy; click behavior
      **(human)**.
      DONE 2026-07-15, verified headlessly: menu-driven 5 s recording → Stop & Save → relaunch
      with `--print-delivered-notifications` → `Recording saved · 00:00:05 / Recording 2026-07-15
      at 19.06.29.mov`. ⚠️ **docs/06's copy table didn't cover what the engine emits** — four
      amendments there: `streamError` had no copy, mic-loss had none though ADR-012 promises one,
      `failed` had none (the table assumes a playable file), and `Mac went to sleep` was copy for
      an unreachable state (M3-T4). **Still owed to a human:** whether a banner appears, and
      click-to-reveal. **Fail-stop copy is unit-tested but never delivered live** — the app has no
      `--test-disk-floor`, so provoking one needs a patch; G4 §5.3 covers it.
- [x] M4-T6 Bundle polish: app icon (placeholder ok, iconutil-built .icns),
      `bundle.sh` produces the final artifact, version stamping.
      **Verify:** Info.plist version matches a `VERSION` file; icon renders in Finder;
      `codesign --verify --strict` passes on the final bundle.
      DONE 2026-07-16, all three green: `defaults read …/Info.plist CFBundleShortVersionString`
      == `VERSION` (0.1.0); `NSWorkspace.icon(forFile:)` resolves the display+dot icon from the
      assembled bundle (screenshot in the task artifact); `codesign --verify --strict` passes.
      Icon (candidate C — Franco chose) is code-drawn (`tools/makeicon.swift`) → `.icns` via
      `Scripts/makeicns.sh`, checked in. `VERSION` is the single source; `bundle.sh` stamps the
      `__VERSION__` placeholders and fails loudly if VERSION or the icon is missing. **M4 is now
      code-complete.**

**Gate G4**: 04-testing §5 (fresh-account onboarding < 2 min; menu flows; app-identity
TCC grants — app appears by name in System Settings, grants survive rebuild).

---

## M5 — Instant replay (est. 2–3 sessions)

- [x] M5-T1 `RingBuffer` (generic, duration-bounded, lock-guarded).
      **Verify:** unit tests — eviction by duration, keyframe search, snapshot during
      concurrent append; clean under `swift test --sanitize=thread`.
      DONE 2026-07-16: `Sources/RecorderCore/Replay/RingBuffer.swift` — generic
      `RingBuffer<Element>` over `(element, pts, isKeyframe)`; eviction from the head while span >
      `capacity + 2 s slack`; keyframe-aligned `clip(seconds:)` starting at the tightest keyframe
      ≤ `newest − N` (+ a pure `clipStartIndex` the M5-T4 muxer will reuse). NSLock-guarded; kept
      `internal` until M5-T2 needs it cross-module. 7 tests (eviction boundary, keyframe selection
      incl. both empty cases, direct `clipStartIndex`, and a concurrent append/snapshot/clip run) —
      **clean under `--sanitize=thread`**. /code-review (medium) applied: precompute the eviction
      limit off the hot path; document the non-decreasing-pts precondition (ADR-005 no-B-frames
      guarantees it). `ReplayBuffer` protocol (ADR-005) deferred to when T2/T4 give it a consumer.
- [x] M5-T2 `ReplayEncoder`: VTCompressionSession per 02 §9; consume `.screen` via
      SampleRouter; keyframe flag extraction; ring append. CLI `replay-arm --seconds 60`
      boots the engine with ONLY the replay consumer attached (no MovieRecorder) and
      prints ring occupancy/memory every 2 s.
      **Verify:** 3-min `replay-arm` run — occupancy climbs then plateaus at ~60 s;
      keyframes counted ≈ 1/s; RSS stable (§6.1 short form).
      DONE 2026-07-16: `Sources/RecorderCore/Replay/ReplayEncoder.swift` (session lazily
      sized from the first frame, Balanced bitrate via BitrateModel, one-shot `onFailure`
      mirroring `onWriteFailure`) + CLI `replay-arm [--seconds N] [--duration N]`.
      3-min live run (final code): occupancy 0 → pinned 62.0 s (60 + 2 slack), keyframes
      62–63 ≈ 1/s, ring bytes flat ~141 MB, RSS ≪ 200 MB (but attribution varies run to
      run — field note; M5-T6's 30-min audit decides drift). 6 headless VT tests (no TCC
      needed), TSan-clean. /code-review high applied (async session bring-up off the SCK
      queue, failure routed through `stop(reason:)`, init validation, shared test fixture).
- [x] M5-T3 Audio rings (PCM copies of `.audio` + `.microphone`).
      **Verify:** `replay-arm` occupancy printout includes both audio rings; PCM byte
      counts match duration × format math; rings stay duration-aligned with video ring.
      DONE 2026-07-16: `ReplayAudioRing` (deep PCM copies — never retain SCK's own buffers;
      ASBD latch that clears + re-latches on a format change, so replay self-heals across
      codec flips; planar-aware byte math). `replay-arm` gains
      `--mic/--no-mic` + per-ring format lines + triplet ticker. 2-min live verify: system
      22.7 MB @ 62.0 s == 62 × 375 KB/s exactly; mic (AirPods, 24 k/1ch) 5.7 MB ✓; all three
      spans pinned at 62.0 s. **SCK system audio is planar Float32** — the live run caught
      `CMSampleBufferGetTotalSampleSize` returning 0 and a 2× rate error the interleaved-only
      fixtures couldn't see (field note). 200 tests, TSan-clean.
- [x] M5-T4 `ReplayMuxer`: snapshot → keyframe trim → rebase → passthrough video +
      AAC audio → file. Coalesce concurrent saves. CLI trigger (the ring lives inside
      the running `replay-arm` process — there is NO separate `replay-save`
      subcommand): `replay-arm` saves a clip on SIGUSR1 or on `s` + Return on stdin;
      document both in `--help`. The app path (M5-T5) uses the hotkey instead.
      **Verify:** 04-testing §6.2 + §6.3 — `kill -USR1 <pid>` → file exists < 1 s
      later; probe: hvc1 + 2 aac, duration N + ≤ 1 s, starts on keyframe; two rapid
      signals → one clean file, no crash. "Genuinely the last minute" content check
      **(human)** — ✅ PASSED 2026-07-16 (Franco).
      DONE 2026-07-16: §6.2 ✅ signal→file-exists 0.08 s external / 0.29 s to finalized;
      probe hvc1 4112×2570 + 2 aac, 60.56 s (60 + ≤1). §6.3 ✅ two rapid SIGUSR1s → one
      coalesced, 2 clean files total. `s`+Return verified through a pty. The clip window
      anchors at the newest pts across ALL rings and the last frame is tail-patched to
      the clip end (docs/02 §5's accounting) so a static screen still yields the true
      last N seconds. `--output` added; drains in-flight saves before exit. 207 tests
      (incl. real-HEVC end-to-end mux, static-tail + fully-stale-window), TSan-clean.
      /code-review presented → Franco approved batch. Owed **(human)**: "genuinely the
      last minute" content check.
- [x] M5-T5 App integration: "Arm instant replay" toggle (persists), hotkey ⌥⌘R via
      Carbon (02 §9), menu item + notification on save.
      DONE 2026-07-16: `ReplayController` (AppCore) owns the armed pipeline — its own
      CaptureEngine when idle, the recording's stream while one runs (docs/01's shared-stream
      design; buffer resets at record start/stop, Franco-approved semantics), auto-restart
      through display sleep. Toggle + Save Replay Now + armed info row in the menu; Instant
      Replay Settings section (buffer 30/60/120 + shortcut recorder, ⌥/⌃ required); armed dot
      badge on all icon states; docs/06's two replay notifications + two amendments (mic-lost
      while armed, shortcut unavailable). Keys `replayArmed`/`replaySeconds`/`replayHotkey`
      persisted + validated. §6.4 ✅ headless (recording 35.99 s + mid-recording replay 32.29 s,
      both probe-clean, one stream); armed state survives relaunch; buffer survives menu-open
      re-homing (regression-tested). 222 tests. /code-review: 10 confirmed findings presented
      → approved batch applied (re-home wipe, launch permission gate, hotkey failure surfacing,
      system-shortcut hijack, mid-recording buffer change, stale-mic retry loop, and more).
      **(human) ✅ 2026-07-16 (Franco):** ⌥⌘R from another app works (banner renders with the
      mirroring/sharing toggle on); "the UI looks great".
      **Inherits from M4-T4 (Franco, 2026-07-15):** the replay Settings rows (buffer length
      30/60/120, hotkey recorder) and the status-icon's replay-armed badge, plus the keys they
      write — `replayArmed`, `replaySeconds`, `replayHotkey` (names contractual, docs/06). They
      were going to ship in M4-T4 for this task to read later; the ruling is that nothing about
      replay appears in the UI until the ring buffer behind it exists. **So M5-T5 both writes and
      reads them — there is no cross-milestone contract left to get wrong, only a spelling to
      match docs/06.**
      **Verify:** §6.4 — manual recording + armed replay + save simultaneously → both
      files probe-clean. Hotkey fires while another app is frontmost **(human)**.
- [x] M5-T6 Memory/CPU audit: 30-min armed session.
      **Verify:** §6.1/§6.5 — RSS plateau (≲ 400 MB busy, amended — see 04 §6.1), CPU < 10%
      avg, save still < 1 s at minute 30; numbers into STATUS.md.
      DONE 2026-07-16, two legs. **Burst (busyscene, 4.5 min max load):** CPU 7.2% avg
      (cumulative), RSS flat 201–202 MB (+1 MB). **Main (30.2 min armed, Franco's real
      usage, AirPods pick):** CPU 4.7% avg (spot max 7.2%), RSS 195–279 MB (median 216;
      drift min5→end **+7 MB** — no leak), saves at min-1 (Franco's ⌥⌘R) and min-30 both
      probe-clean 60.6 s; min-30 save wrote in 0.17 s (birth→mtime), ≈0.6 s end-to-end
      after subtracting the menudriver rig's measured 0.87 s (raw rig-inclusive: 1.53 s;
      T4's 0.08 s signal→file external measurement corroborates). Bitrate ruling (Franco):
      **(b) no replay cap — Balanced parity**; 04 §6.1 + 02 §9 amended, VT DataRateLimits
      recorded as the ready lever.

**Gate G5**: 04-testing §6 (clip saved < 1 s, contains last N ± 1 s with audio; works
while a manual recording runs; memory flat over 30 min).

---

## M6 — Ship-quality pass (est. 1–2 sessions)

- [x] M6-T1 Full acceptance run: every item in 00-product-brief "Success criteria".
- [x] M6-T2 The 2-hour soak test (04-testing §7) on battery **(human — physical
      unplug)**. Kill leg amended to 1 h (Franco, 2026-07-17).
- [x] M6-T3 Error-message audit: force each failure path; every message says what
      happened AND what to do.
- [x] M6-T5 Launch at login (`SMAppService`, key `launchAtLogin` — docs/06). **Moved here from
      M4-T4 (Franco, 2026-07-15):** `SMAppService.mainApp` registers a login item pointing at the
      bundle's *current path*, and until the app has a permanent address that path is
      `dist/ScreenRec.app` — a build directory `bundle.sh` deletes on every run. Registering it
      earlier aims a login item at a folder that stops existing. It belongs with M6-T4's
      installability work, not before it.
      **Verify:** toggle on → `SMAppService.mainApp.status == .enabled`; log out/in → the app is
      running **(human)**; toggle off → the login item is gone.
- [ ] M6-T4 Optional (**DEFERRED 2026-07-20** — Franco: revisit when actually sharing the app;
      see STATUS). Developer ID + notarization for distribution
      beyond this machine; `--h264-downscale` compat mode; HDR spike (ADR stretch).
      **Mic recovery after device loss GRADUATED to its own milestone M8** (2026-07-20): the
      decision is made (Route 2), the PTS-coherence gate is spike-verified (both phases), and it's
      post-v1 by ADR-012 — so it's no longer a T4 "decide then" item.
- [x] M6-T5 README for the repo: build, sign, install, use. Update all docs to
      match reality; close out STATUS.md v1 section.

- [x] M6-T6 Replay-window resize preserves the buffer (Franco, 2026-07-17; plan approved).
      Grow retains contents and fills to the new length; shrink evicts eagerly (eviction
      must not wait for an append — a static screen's video ring stops appending);
      quality/fps keep the rebuild path. `RingBuffer.setCapacity`, encoder/audio-ring
      forwarding, `ReplayController.windowChanged` (no teardown, muxer recreated per the
      `setOutputDirectory` pattern), AppState routes the `replaySeconds` didSet.
      **Verify:** unit (grow-retains / shrink-evicts / didSet routing via the
      `ReplayControlling` seam) + in-process live capture: arm own-stream → 40 s → grow →
      immediate save ≈ pre-change span; fill → shrink → save ≈ new window.
- [x] M6-T7 Safeguard the in-progress recording file (Franco's pick 2026-07-17: options
      1+3 from the 2-h-soak trash incident). (1) vnode event source on the writer's fd:
      file moved out of the output folder → surface it immediately (menu-header warning;
      notification — banners may be suppressed while armed, the menu is the reliable
      surface) and/or rename back; file *unlinked* (Trash emptied) → fail-stop on the
      spot with a clear reason instead of writing into a doomed fd. (3) in-progress file
      named `….mov.partial`, renamed at finalize — keeps crash-salvage visible in the
      folder. **Verify:** unit + live: mv the file mid-recording → warning fires, stop
      still yields the complete file at the restored path; simulate unlink → clean
      fail-stop; kill -9 mid-recording → `.partial` present and playable after rename.
- [x] M6-T8 Arm/disarm replay while recording (Franco, 2026-07-17). The state layer already
      supports it (`syncReplayArming`'s `session != nil` branch attaches to the live
      stream); the recording-state menu just never rendered the toggle — docs/06's
      recording menu predates armed replay. Show the arm toggle + Save Replay Now row in
      the recording menu; amend docs/06.
      **Verify:** menudriver mid-recording: arm → badge + Save row appear, save produces a
      clip, recording unharmed (probe both); disarm mid-recording → recording continues.

- [x] M6-T9 Armed state survives relaunch (from the M6-T2 leg-2 finding; also reproduced
      on a *graceful* quit→relaunch 2026-07-17 — the SCK stream-reap race is a coin flip
      on any quick restart, roughly 1-in-3 across the day's cycles, not kill-specific). Arm-time
      stream failure at launch currently hits the pipeline-failure bucket → permanent
      self-disarm + `replayArmed=0`, though the condition is transient (SCK still reaping
      the dead process's stream — re-arm by hand worked seconds later). Fix: launch/arm
      stream failures join the 5 s retry bucket (armed is a standing intent, ADR-style);
      self-disarm stays for genuine pipeline failures. **Verify:** unit (failure routing) +
      live: kill -9 the armed app → relaunch → armed badge back without human help;
      display-sleep retry regression stays green.

- [x] M6-T10 Open-menu rebuild corrupts rows (Franco, 2026-07-17; replay-clip evidence at
      00:11 of his capture — highlight parked on the disabled "Sources locked" row, its
      label displaced, persisting across ticks while the cursor sat on Settings…).
      Cause: `refreshWhileOpen` → `refreshProgress()` reassigns `elapsedSeconds`/
      `recordedBytes` at 1 Hz → @Observable publishes → SwiftUI rebuilds every AppKit row
      of the OPEN menu; the hover/highlight machinery garbles rows across the swap.
      Fix directions, in order: (1) free win — assign progress values only on real change
      (the M4-T3 @Observable lesson; the idle menu stops rebuilding entirely since its
      values sit at 0); (2) recording menu: stable row identity (`.id`) so SwiftUI updates
      the header Text in place instead of rebuilding siblings; (3) if the bridge still
      glitches, measure and decide (slower tick vs docs/06 header-fidelity trade).
      **Verify:** screen-record the open menu across ≥5 ticks while hovering each row —
      measured, not eyeballed (M4-T1 rule); idle menu provably rebuild-free (no publish
      without change).

- [x] M6-T11 Mic list goes stale in a long-running app (Franco, 2026-07-17: AirPods
      connected + actively captured by armed replay, yet absent from the Microphone picker
      across multiple fresh menu opens; checkmark on None). Measured: a fresh process's
      `AVCaptureDevice.DiscoverySession` lists them, the running app's doesn't — while the
      same process's `AVCaptureDevice(uniqueID:)` lookup (the capture-side resolver) finds
      them, which is why the replay had his voice. The filtered DiscoverySession list is
      the stale layer. Fix: enumerate via CoreAudio HAL (`kAudioHardwarePropertyDevices` +
      input-stream check — live per call, probe-verified, UIDs identical to what SCK
      binds), keeping `AudioInputDevice` as the seam. **Verify:** unit (CoreAudio
      enumeration shape) + live: connect/disconnect AirPods with the app running →
      the picker reflects it on the next menu open, both directions.

- [x] M6-T12 Discard an ongoing recording (Franco, 2026-07-17). Today every start lands a
      file (Stop & Save finalizes; quit-mid-recording finalizes; T7 even recovers a
      force-quit `.partial`) — no "throw this take away." Add a **subordinate, confirmed**
      Discard action to the recording menu (below Stop & Save, not adjacent-and-equal —
      it's the one irreversible button; an accidental hit must not sit under Stop's muscle
      memory). Seam exists: `RecordingSession` gains `discard()` → stop the engine, route to
      `MovieRecorder.cancel()` (writer teardown + file removal, already used on failure
      paths) instead of `finish()`; the `.partial` name makes the half-file trivial to drop.
      Confirmation alert like the quit-mid-recording one. **Decide at build:** does an
      intentional discard-by-force-quit want T7 recovery suppressed, or is recovery-on-crash
      the right default (explicit Discard is the clean path; recovery is for the *un*intended
      exit — probably leave it). **Verify:** menudriver discard mid-recording → no file in
      ~/Movies (no `.mov`, no `.partial`), recording ended, app back to Ready; Stop & Save
      unaffected.

- [x] M6-T13 Automatic (system default) microphone option (Franco, 2026-07-20, from M6-T11
      dogfooding). Today the mic pick is a specific device or `None`; a connecting device never
      overrides an explicit pick (picked-device-or-nothing, `resolvedMicrophone()`) — pick built-in,
      connect AirPods, built-in stays. Add an **opt-in** `MicrophoneSelection.automatic` that
      resolves the current system-default input at record/arm start (flip on the resolver's existing
      `fallingBackToDefault`, which `Permissions.resolvedMicrophoneID` already supports). Picker
      gains an "Automatic (System Default)" row above the device list; persist as a distinct value
      (not a device ID); the recording menu's active-mic line already names the resolved device so
      the menu still doesn't lie. **Scope: resolved AT START only** — SCK binds the mic once (02 §4),
      so a live armed/recording stream does NOT hot-switch to a device connected mid-session; that
      live takeover is the M6-T4 mic-recovery rebuild, not this task. **Verify:** unit (automatic →
      resolves default; → None when no default) + live: pick Automatic, connect AirPods, start
      recording → mic track is AirPods; with a specific device picked, connecting AirPods does not
      change the pick.

**Gate G6** = v1 done.

---

## M7 — Per-app capture (post-v1; requested by Franco 2026-07-17)

Record a single application instead of the whole screen — recording AND armed replay.
`SCContentFilter(display:including:)` filters video and system audio per-app; frames stay
display-sized, so BitrateModel/timing are untouched, and a `content` case on
`CaptureConfiguration` reaches replay for free (both paths build from the same seam;
shared-stream mode rides the recording's filter). **Window-level capture is explicitly NOT
this milestone** — independent-window streams and live resize are a different, harder
feature; do not bundle.

- [x] M7-T1 Core: `CaptureConfiguration.content` (`.display(id)` / `.app(bundleID)`),
      filter construction, CLI `record --app <bundle-id>`. Rulings to make here: the
      end-reason for "target app quit mid-recording" (the display-gone precedent, 02 §7),
      and StallWatchdog scoping (user-active ⇒ frames-expected is false under an app
      filter — the idle cross-check must not cry wolf).
      **Verify:** CLI capture of one app while another app animates on screen → the other
      app appears in NO frame; system audio contains only the target's audio; app-quit
      mid-run → clean `finished(reason:)`, playable file.
- [x] M7-T2 App: source picker in the menu (Entire Screen / running apps — dynamic list,
      refreshed on open; the M5-T5 `refreshSources` re-home suppression applies), settings
      persistence, sources-locked-while-recording behavior, armed replay follows the pick.
      **Verify:** menudriver-driven app-scoped recording + mid-recording replay save, both
      probe clean and both contain only the target app.

- [x] M7-T3 CLI parity (added post-G7, Franco 2026-07-20): `replay-arm --app <bundle-id>` —
      the record precedent's flag on the replay harness; app-quit ends the armed stream (no
      CLI auto-retry, deliberately — the retry loop is the GUI ReplayController's).
      **Verify:** arm app-scoped → USR1 save → clip probes clean + frames contain only the
      target; quit the app while armed → `stopped (appQuit)`; whole-screen regression run.

**Gate G7**: an app-scoped recording and an app-scoped armed-replay save, each verified
content-clean (no bystander app visible, no bystander audio), app-quit handled, plus a
no-regression pass of G5 §6.4 (simultaneity) under an app filter. (T3 is post-gate parity
polish; G7 closed on T1+T2.)

---

## M8 — Mic recovery after device loss (post-v1; graduated from M6-T4 2026-07-20)

Recover the **microphone** after a mid-capture device loss — for both recording and armed replay —
instead of the mic track ending permanently (today's ADR-012 notify-and-continue). Deferred from v1
by ADR-012, so it's post-v1 by design; it lands here, not in M6 (M6 is v1 ship-quality). **Armed
replay is the priority scenario** — it runs all day, AirPods case/reconnect constantly, and
MEASURED 2026-07-20 that a reconnect does NOT restore the mic today (the armed stream binds it once;
only a manual re-arm recovers it, which wipes nothing but requires noticing).

**The approach is Route 2 (rebuild a mic-only 2nd `SCStream`), and it is already de-risked** — the
PTS-coherence gate passed both phases (docs/02 §4 · STATUS field notes 2026-07-20): two `SCStream`s
share a coherent host clock (drift ≈ 0), and an end-to-end two-stream recording stays synced
(constant ~16 ms offset, no drift). The working reference is `screenrec-cli mic-swap-spike
--two-streams / --two-streams-pts / --two-streams-record` (the two-stream setup + the mux). **NOT
this milestone:** the re-point-to-a-live-device route (one-way, can't handle reconnect — ADR-012);
the video / system-audio / replay-buffer are never disturbed (that's the whole point vs the rejected
auto-re-arm, which wiped the last minutes of buffer). Constraint reminder: SCK binds the mic once at
`startCapture` (02 §4) and the mic input's format is welded to the first buffer (M3-T2 / ADR-007) —
hence T1 is a hard prerequisite for T2.

- [x] M8-T1 **Fixed-format resampled mic input** (prerequisite). Normalize any incoming mic buffer
      (any ASBD — AirPods 24 kHz, built-in 48 kHz, …) into ONE fixed writer-input format, so a mic
      buffer from a *rebuilt* stream (a different device/rate) can append to the same track without
      the M3-T2 format-change corruption. Insert an `AVAudioConverter` resample stage in the mic
      path, PTS preserved (host-clock in → host-clock out, sample-accurate, no drift).
      **Seams:** `MovieRecorder`'s lazy mic input (today welded to the first buffer — becomes a fixed
      target); `AudioFormatIdentity` (Support/); `ReplayAudioRing` (today re-latches on format change,
      M5-T3 — instead resamples). **Decisions (pre-made):** target = 48 kHz mono; the resampler is a
      shared `ResampledMicInput` seam used by BOTH recorder and replay ring (so they can't disagree);
      M3-T2's same-device fail-stop is retired for the mic path (the resampler absorbs a codec flip
      now — amend ADR-007's mic-format note). **Verify:** unit — a 24 kHz and a 48 kHz mono buffer
      both emerge as the fixed target with correct sample counts/durations and monotonic PTS (fixture
      on each side of the rate); live — a mid-stream device change keeps the mic track valid/playable.

- [x] M8-T2 **Reconnect watchdog + mic-only stream rebuild.** When the picked mic (or, under
      Automatic, the current system default) returns after a loss, build a fresh mic-only `SCStream`
      and splice its buffers through T1's fixed-format input against the shared epoch, so the mic
      track / replay ring resumes (a silent gap over the loss→reconnect window is expected). Wire into
      BOTH `RecordingSession` and `ReplayController` (armed replay first). **Seams:** the spike's
      `spikeConfiguration(micID:)` + `RecordingSink` (the `--two-streams-record` reference);
      `MicrophoneWatchdog` (M3-T6) already fires the LOSS; a CoreAudio HAL device-list listener
      (`AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDevices` — the M6-T11 API) for the
      RETURN; `AppState.microphoneResolution` / `MicrophonePreference` (M6-T13) picks which device to
      rebind; `SampleRouter`/`MovieRecorder.consume` for the splice. **Decisions (pre-made):** honor
      the pick (a specific pick rebinds that device on return; Automatic rebinds the current default);
      the replay buffer (video + system audio) is NEVER reset — only the mic-only stream is rebuilt
      underneath; recovery is best-effort (device never returns ⇒ today's ADR-012 outcome). **Verify:**
      live — arm replay, case the mic, reconnect → the mic RESUMES in the buffer with no re-arm (probe
      a saved clip: mic track present after the reconnect) and A/V sync holds (§3.5 drift); same for an
      active recording; no-regression on a stable-mic capture.

**Gate G8**: (1) armed replay — case the mic mid-armed → reconnect → mic auto-recovers into the
buffer (saved clip's mic resumes, no re-arm), video+system-audio buffer uninterrupted, A/V sync holds
(§3.5); (2) recording — mic dies mid-recording → reconnect → mic track resumes, file playable, sync
holds; (3) no regression — a stable-mic recording/replay is unaffected and G2 §3.5 drift still passes.

## M9 — Post-review polish & debt (post-v1; from the 2026-07-21 product review)

Two buckets from the review, done first because they clear the deck before M10 adds new code.
**Quality-of-life** (T1–T4): four small, independent, daily-use fixes — none touch the sample path.
**Debt** (T5–T7): the concentrated maintainability items. Feature tasks bump MINOR (ADR-013); the
feedback fixes and debt are PATCH/`refactor:` — Franco's call per commit. One task at a time.

### Quality-of-life

- [x] M9-T1 **Notify when a recording starts without its mic.** `AppState.resolvedMicrophone()`
      records screen-only and sets `lastFailure` when the picked device is absent (or Automatic
      resolves to nothing) but never posts — so a mic'd take set up and walked away from goes
      silently mic-less, while a *mid*-recording loss does notify (`.microphoneLost`). Post an
      outcome-first notice at start (ADR-007). **Seams:** a new pure
      `RecordingNotifications.recordingStartedWithoutMicrophone(...)` factory (keeps copy
      unit-testable, like every sibling); `AppState.start()` fires it via the injected `notifier`
      after `resolvedMicrophone()` returns `.noDevice`; distinguish specific-pick vs Automatic
      wording as `lastFailure` already does. **Verify:** unit — the factory's copy for both cases;
      the fold — a start with an absent pick posts exactly one notification (fake notifier).
- [x] M9-T2 **In-app confirmation for a saved replay (banner-independent).** macOS suppresses
      banners whenever the display is captured — i.e. whenever replay is armed — so "Replay saved",
      the headline confirmation, renders only in Notification Center's list, never as a banner
      (docs/06 §Notifications, measured). Give the save a signal that doesn't route through
      UserNotifications: a **"Last replay: `<name>` · `N`s" row at the top of the menu** (idle and
      recording), from a new `AppState.lastReplay` summary set in `saveReplay`'s success branch.
      Add one line of discoverability near the Arm control (a Settings caption naming the System
      Settings toggle — copy only, "name the fix not the API"). Optional stretch: a brief menu-bar
      label flash (label is outside the `.menu` bridge — see M9-T3). Keep the existing notification
      too. **Verify:** menudriver — arm → save → the menu shows the last-replay row with name +
      duration; disarm clears it. Unit — the summary formats name + rounded seconds.
- [x] M9-T3 **Live elapsed clock in the menu-bar label.** The in-menu clock is frozen-at-open by the
      `.menu` bridge (M6-T10, correct). The `MenuBarExtra` *label* is NOT bridged — it already
      redraws frame-by-frame to animate the pulse (`PulsingRecordingIcon`, StatusIconView). Render a
      monospaced `HH:MM:SS` next to the icon while recording, off the same timer, so elapsed time is
      always visible without opening the menu. **Seams:** a recording-start `Date` exposed by
      `AppState` (`.started` fold), read by the label; extend `PulsingRecordingIcon`/`StatusIconView`
      to draw the string; a Settings toggle to hide it (menu-bar width / on-screen-share privacy);
      paused freezes it amber. Reduce Motion stills the pulse but the clock still advances.
      **Verify:** screenshot the label across ≥3 one-second ticks and assert the string advances —
      MEASURE, don't eyeball (M4-T1 rule); Settings-off shows no string.
- [x] M9-T4 **Global start/stop recording shortcut.** Only replay-save has a global hotkey today;
      start/stop needs the menu-bar icon, unreachable in a full-screen app or presentation. Add an
      optional global Start/Stop shortcut. **Seams:** `HotkeyCenter` is hardcoded to one hotkey
      (`id: 1`, single `hotKeyRef`) — generalize to N hotkeys keyed by id; a new `recordHotkey`
      setting + `HotkeyRecorderButton` in Settings; the handler toggles `start()`/`stop()` gated on
      `readiness`. **Rulings:** behavior in the `isSessionActive`-but-not-yet-recording window; a
      blocked start fires the readiness notification (never a silent no-op); default combo or ship
      unset. **Verify:** unit — the generalized `HotkeyCenter` registers/unregisters two independent
      hotkeys without clobbering; the toggle picks start vs stop off session state. Live (human) —
      the combo starts and stops from another frontmost app.

### Debt

- [x] M9-T5 **Retire `MicSwapSpike.swift` (822 LOC).** Every leg's purpose is recorded (M3-T7 in
      02 §4, the M6-T4 decision in ADR-012, M8 shipped). It ships in the CLI binary, duplicates
      RecorderCore internals it can't reach (`isCompleteSpikeVideoFrame`, the audio-capture
      contract), and has two undocumented modes. **Decision:** delete outright (the M8 G8 live gates
      are the standing regression), or trim to the one `--record-repoint` leg as a documented
      harness — recommendation: delete, rationale to STATUS field notes not a code comment.
      **Verify:** build/test green; CLI help no longer advertises removed modes; other subcommands
      unaffected.
- [x] M9-T6 **Allocation-free `SampleRouter.route`.** `Array(consumers.values)` runs on the SCK
      capture queue ~140×/s, against docs/01's "handlers allocation-light" rule. Hold an immutable
      `[any SampleConsumer]` snapshot rebuilt only on `attach`/`detach` (rare); `route` reads the
      reference under the lock and delivers outside it, no per-buffer allocation. **Verify:**
      `SampleRouterTests` green; add a concurrent attach/detach-during-routing test; TSan clean.
- [x] M9-T7 **Split `AppState` — extracted `PermissionsModel`.** The permission/onboarding cluster
      (`onboardingRows`, `refreshOnboarding`, the request/relaunch/readiness surface, `notificationState`,
      `hasAskedForScreenRecording`, `screenWasGrantedAtLaunch`) moved to a `@Observable`
      `PermissionsModel` that AppState owns and forwards to; it needs one input, `microphoneRequired`,
      supplied from the mic pick. Behavior-preserving (315 tests, +2 `PermissionsModelTests`; forwarders
      keep the view/CLI surface, so no existing test changed). AppState 962 → 917.
      **The source-picker split was deliberately NOT done (Franco, 2026-07-21) — and is not deferred.**
      On close reading the picks (`selectedDisplayID`/`selectedAppBundleID`/`microphonePreference` +
      `quality`/`frameRateCap`) are *intrinsically* coupled to `persist()` and
      `replayConfigurationChanged()` via non-uniform `didSet`s (display reconfigures replay but doesn't
      persist; the others do; `isRehomingSources` batches). They ARE the capture config that drives
      persistence and replay — extracting them adds a callback layer over intrinsic coupling rather than
      separating a concern, for negative clarity value. Left in AppState on purpose. Do not re-attempt
      without a genuinely better seam. (The optional `RecordingSessionTests` pairing also dropped.)

### Feature (Franco's ask, 2026-07-21)

- [x] M9-T8 **Replay buffer length as a slider (small floor → 15 min, seconds granularity).** Replace
      the Settings Picker (30 / 60 / 120 s) with a slider from a small non-zero floor (~5 s) to 15 min,
      seconds granularity. **RAM/disk cost explicitly accepted (Franco) — no memory cap**; the ring is a
      live in-RAM buffer that scales with the window (≈2.6 GB resident at 15 min / Balanced), and that's
      fine. **Seams:** `Settings.allowedReplaySeconds` (the fixed list) → a `replaySecondsRange`
      (`5...900`); load **clamps** into the range instead of list-membership (garbage still falls back to
      60); `SettingsView` Picker → `Slider` with a live `M:SS` value label; `windowChanged` already
      resizes the armed ring in place (M6-T6), so a live drag grows/shrinks the buffer — **apply on
      drag-end** (a `Slider(onEditingChanged:)`), not per-tick, or every intermediate value rebuilds.
      **Rulings:** the floor value; the value-label format (`M:SS`); commit-on-release vs live. docs/06
      updated (`replaySeconds` key type is now a range; the Instant Replay settings line); the
      SettingsTests pinning 30/60/120 rewritten to the clamp/fallback rules. **Verify:** unit — load
      clamps an out-of-range value into `[floor, 900]`, round-trips an arbitrary in-range value (e.g.
      137 s), garbage falls back to 60; the value-label formats; a change while armed fires
      `windowChanged`. Live — set an odd length (e.g. 3:20), arm, save → clip ≈ that length. MINOR bump.

**Gate G9**: the four QoL verifies pass (mic-less start posts once; a saved replay shows an in-app
confirmation while armed; the menu-bar clock advances live, measured; the global shortcut starts and
stops from another app), and after the debt tasks build + full test + release build + `bundle.sh` +
TSan are all green with a menudriver smoke (start → stop → arm → save) showing no regression. T8 (the
replay slider) is an additional feature with its own verify above — not a G9 blocker.

---

## M10 — Share export & basic editing (post-v1; from the 2026-07-21 review)

The first **export stage** in the codebase, then the two cheapest "basic-editing" features that reuse
its read side. Order matters: T1 builds the `AVAssetReader` read/transcode side that T3 (GIF) and T4
(trim) both lean on. The XL Metal "studio" render stage (auto-zoom, backgrounds) stays parked — this
milestone is the trim/format side only, held deliberately (ADR-015). Capture default is never changed
(still HEVC `.mov`, ADR-004); everything here is export/derive.

- [x] M10-T1 **Transcode-to-MP4 core + CLI.** A messaging/web-friendly export: read an existing
      `.mov` and write H.264 High + AAC `.mp4`, `yuv420p`, `+faststart` — motivated by the manual
      ffmpeg-to-WhatsApp step done today (ADR-016; ADR-004 already named H.264 export demand-driven).
      **Seams:** a new `Exporter` (Export/ or Recording/) over `AVAssetReader`/writer (or
      `AVAssetExportSession`), zero-dep (ADR-010); CLI `export --to-mp4 <in> [<out>]` as the headless
      verify surface (ADR-011). **Decisions:** "share" quality + a size ceiling (not archival);
      downmix to one audio track for `.mp4` (messaging apps expect it) — flag it. **Verify:** CLI
      export of a 3-track test `.mov` → `probe` shows h264 + aac in `.mp4`, plays; WhatsApp
      constraints hold (yuv420p, faststart).
- [x] M10-T2 **Export app wiring.** A **Share… / Export as MP4** action on a recent recording and a
      saved replay (menu row and/or the replay-saved confirmation), off the main path, with a
      progress + completion signal reusing M9-T2's in-app confirmation pattern; reveal on done.
      **Verify:** menudriver — export a recent file → the `.mp4` appears in the output folder, probes
      clean; a failure surfaces per the copy rules.
- [x] M10-T3 **GIF export from a clip (esp. the replay ring).** A replay clip → animated GIF straight
      into a bug-report thread — the framing no competitor has. **Seams:** the M10-T1 frame read →
      `ImageIO` animated-GIF destination (`kUTTypeGIF`) with palette reduction and an fps/scale cap;
      zero-dep (ImageIO is system, ADR-010). Offer on a saved replay and a recent recording (a "Save
      as GIF" action). **Verify:** a looping GIF from a test clip, size bounded by the caps, opens in
      Preview/browser.
- [x] M10-T3 follow-up **GIF settings (Franco's ask, 2026-07-22).** The T3 caps were fixed defaults;
      a **GIF** section in Settings (fps 12/15/20/24 · width 320/480/640/800 · max length 10/15/30/60 s,
      snap-on-load) now steers `Save as GIF`, and the CLI gained `--fps/--width/--seconds` flags.
      **Verify:** settings round-trip + snap unit tests; `settingsdriver` shot shows the section; a
      persisted width 640 → real app `Save as GIF` → a 640-wide GIF.
- [x] M10-T4 **Lossless trim (in/out, passthrough).** Trim a `.mov` to `[in, out]` without
      re-encoding, reusing `ReplayMuxer`'s snapshot→keyframe-trim→passthrough approach, so "clip the
      useful 20 s before sharing" costs no quality. **Seams:** generalize the muxer's trim or a
      sibling `Trimmer` sharing the keyframe logic; a spare in/out UI (first editing surface — docs/06
      amendment). **Rulings:** the in-point snaps to a keyframe (passthrough can only cut there — snap
      and state it); keep the original, write a new file. Softens the brief's "no editing" non-goal
      deliberately, on the trim/format side, not auto-zoom/render (ADR-015). **Verify:** `probe` shows
      no re-encode (same codec/params), correct trimmed duration ±1 keyframe, playable; original
      untouched.

**Gate G10 ✅ PASSED (2026-07-22)**: an `.mp4`, a GIF, and a losslessly-trimmed clip all produced
from a real recording/replay via the app, each playable and correct (h264/aac/faststart; GIF loops
within caps; trim is passthrough, duration correct, original intact); the capture default is
unchanged and the "no render stage / no studio" line (ADR-015) is documented and held. **M10 (T1–T4
+ the GIF-settings follow-up) COMPLETE.** Evidence: M10-T1..T4 verifies (STATUS) — MP4 export
(h264 High/yuv420p/1920×1200/faststart, live), GIF (480×300 looping, live), lossless trim (hvc1
preserved, exact 6.00s, original intact, live); the Trim window rendered live (AVPlayerView).

## M11 — Region capture (post-M10; Franco's ask, 2026-07-22)

A **third capture mode**: record an arbitrary rectangle of a display, not just the whole screen
(M0–M6) or a chosen app's windows (M7). It slots into the existing `ContentSelection` enum
(`.display` / `.app` → add `.region`), so the recording, replay and shared-stream paths all inherit
it from one place — the M7 shape exactly. **Independent** of M7–M10; builds only on M2 (recording),
M4 (menu) and M5 (replay). The capture default is unchanged (still whole-screen HEVC `.mov`,
ADR-004); region is opt-in.

**Mechanism (SCK):** `SCContentFilter(display:excludingWindows:[])` for the display, plus
`SCStreamConfiguration.sourceRect` = the region (display-relative **points** — 02 §1's
points-vs-pixels rule bites here) and `width`/`height` = the region's **pixel** size (points ×
displayScale, snapped **even** for the encoder). `destinationRect` maps the region to the full
output frame. The region is a fixed *screen* rectangle — it captures whatever is under it; it does
**not** follow a window (that's `.app`).

- [x] M11-T1 **Region capture core + CLI.** Add `.region(display:, rect:)` to `ContentSelection`;
      `CaptureEngine` builds the display filter + `sourceRect` and sizes the output to the region
      (even pixels). Resolve at start: an off-screen/empty/zero-area rect, or a vanished display,
      **fails loud** (the M7 `.app`-gone precedent — never a silent whole-screen fallback). No
      StallWatchdog concerns beyond the display path's. CLI `record --region <x>,<y>,<w>,<h>` and
      `replay-arm --region …` (the headless verify surface, ADR-011), coordinates in display points.
      **Rulings to nail (T1's platform-facts §, like M7-T1's 02 §1a):** the sourceRect coordinate
      space and origin (top-left vs bottom-left), Retina scaling to output pixels, even-dimension
      snap, and behaviour when the rect straddles the display edge (clamp). **Verify:** a
      region-scoped recording's frames contain **only** the rectangle's content (a bystander window
      outside it is absent from every checked frame — the M7-T1 method); dimensions match the
      snapped region; system audio still whole-machine (audio has no region). One display only —
      cross-display region is out of scope (SCK `sourceRect` is per-display).
- [x] M11-T2 **Region selection overlay + menu wiring.** The interesting part: a **drag-to-select
      overlay** (⌘⇧4-style) — a borderless, translucent, full-screen `NSWindow` per display, crosshair
      cursor, a live `w×h` readout, click-drag to draw the rect, Return/second-click confirms, Escape
      cancels. On confirm the rect (screen points) → `ContentSelection.region`, set as the Source.
      The **Source ▸** picker (M7-T2) gains a **`Select Region…`** row; once picked, a checkmarked
      `Region <w>×<h>` row shows the current selection (re-pick via `Select Region…` again). Recording
      and armed replay follow the pick (M7-T2's shared-stream rebuild); the recording menu shows
      `Recording region <w>×<h>`. **Decisions to confirm (Franco):** (a) **persist** the last region
      (display + rect) like the app pick, re-selectable — or select fresh each time? (b) a picked
      region on a **secondary display** — support in T2, or defer? (c) **no live on-screen boundary**
      while recording (SCK draws none; the user set it) — out of scope, or wanted? **Verify:**
      menudriver + the overlay (AX-drivable? — a taste/tooling call, may need a new driver) or a
      seeded rect: `Select Region…` → draw → record → the `.mp4`/frames show only the region; the
      overlay's Escape cancels cleanly; a mid-recording source-lock (M7) still holds.

**Gate G11**: a region-selected recording **and** an armed replay both capture exactly the chosen
rectangle (content outside it absent), at the correct even dimensions, playable; the selection
overlay draws, reports `w×h`, confirms and cancels; the pick survives per the (a) ruling; failure
paths (vanished display, empty rect) fail loud with actionable copy. The whole-screen and per-app
modes are unaffected (one `ContentSelection`, three cases).

**Non-goals (M11):** cross-display / multi-monitor single region; a region that follows a window
(that's `.app`); freeform/non-rectangular selection; a live recording-boundary overlay; auto-zoom or
any render stage (ADR-015 still holds).

## M12 — Share & Surface (post-M11; from the v1.6.0 review, 2026-07-22)

screenrec is excellent at *capture*; the value chain after "record" is thin, and the menu hides what
it will do. M12 **closes the capture→share loop** and **makes the menu tell the truth at a glance.**
Everything here is zero-dep AppKit + menu/notification wiring — **no capture-path changes.** Builds only
on shipped work (M4 menu, M9-T2 receipts, M10 export, M11 region). The three capture modes, replay,
export and trim are untouched.

- [x] M12-T1 **Share · Copy · Quick Look on recordings and exports.** Add three actions to every
      recording and export row: **Share…** (`NSSharingServicePicker` — AirDrop/Messages/Mail), **Copy**
      (`NSPasteboard`, writing the file so it pastes into Slack/Finder), and **Quick Look**
      (`QLPreviewPanel`, spacebar). AppKit, so it lives in ScreenRecApp and is injected into AppState
      like the other AppKit seams (`beginRegionSelection`/`appDisplayName` precedent) — AppCore stays
      framework-free. This is the demo/bug-report share step (ADR-016's sibling), turning "reveal → drag"
      into one action. **Verify:** each action works on a real `.mov` and on an exported `.mp4`/`.gif`;
      Copy pastes into a target app; Quick Look previews.
- [x] M12-T2 **Exports become first-class.** Include `.mp4`/`.gif` in the recent-recordings scan (or a
      separate **Recent exports** grouping), **persist `lastExport`** across relaunch (small receipt
      store), and add **Rename…** + **Move to Trash** to the per-file submenu. Today exports are
      Finder-only and the receipt is in-memory (lost on relaunch, overwritten by the next). **Verify:**
      export a GIF → it appears in recents/exports and survives relaunch; rename and trash work; the
      source is never touched by rename/trash of a derived export.
- [x] M12-T3 **The menu tells the truth at a glance.** Inline the current selection in the
      **Source/Microphone/Quality** submenu *titles* (`Source: Region 820×512`, `Microphone: None`,
      `Quality: Balanced` — the `.menu` bridge keeps title text); **advertise the opt-in start/stop
      hotkey** on the Start/Stop rows when `recordHotkey != nil` (like the replay row); keep **`Start
      Recording` the first actionable row** — move the export/replay receipts below it and auto-expire a
      stale export receipt. **Verify:** `menudriver dump` shows the values in the titles + the hotkey
      suffix; a stale receipt no longer squats above Start.
- [x] M12-T4 **Region entry is coherent and honest.** Move **`Select Region…` inside `Source ▸`**
      (under the region tag) so all three capture modes are entered from one place; add a **main-display-
      only hint** to the overlay when multiple displays are present; show **`pt · px`** in the overlay
      badge (a power user framing exactly 1920×1080 needs the pixel size). *(Actual secondary-display
      region capture stays the deferred M11 follow-up — this is the regrouping + honesty, not multi-
      display capture.)* **Verify:** the menu enters region from inside `Source ▸`; the overlay hints on
      a multi-display setup (or the hint condition is unit-covered); the badge shows both units.
- [x] M12-T5 **Surface armed replay's banner suppression.** While replay is armed the screen is
      captured, so macOS hides **every app's** notification banners — invisible, cross-app, and
      misattributed. Add a **one-time alert on first arm** ("While armed, macOS hides notification
      banners from every app — Slack, Messages, and others…"), a **persistent dimmed menu row** under the
      Arm toggle, and a line in onboarding's Notifications copy. **Verify:** the first-arm alert fires
      once (persisted "seen" flag); the row renders while armed and clears on disarm.
- [x] M12-T6 **Keyboard-first QoL: global Pause/Resume + optional count-in.** An **opt-in global
      Pause/Resume shortcut** (the demo companion to ⌥⌘S — the menu is itself captured, so mid-demo
      pause must not require opening it; `HotkeyCenter` already keys N hotkeys), and an **optional 3-2-1
      count-in** before recording (Settings toggle, off by default — a beat to switch to the target
      window). **Verify:** the hotkey pauses/resumes a live recording from another app; the count-in
      overlay shows and delays start by its duration.

**Gate G12**: a recording can be **shared, copied, and Quick-Looked without opening Finder**; the menu
shows source/mic/quality/hotkey **at a glance**; a first-time arm **warns about banner suppression**;
region is entered from one place and states its main-display limit; exports appear in-app and survive
relaunch. No capture-path regression — record / per-app / region / replay / export / trim all unchanged
(the M11/M10/M8/M7 gates still pass).

**Non-goals (M12):** multi-display *region capture* (deferred M11 follow-up); any render/compositing
stage (ADR-015); webcam (ADR-017); cloud/upload sharing (the Share sheet uses the OS's own services —
no screenrec-hosted anything).

## M13 — Hardening (post-M11; from the v1.6.0 review, 2026-07-22)

Reliability is genuinely delivered, but it rests on **manual (no-CI) discipline**, has **one OS-quit
finalize gap**, and the safety-critical `RecordingSession` finalize tree is **untested**. M13 shores up
the net you can't see. Mostly process + two small reliability fixes; **no user-facing features.** Can
run before or after M12 — independent.

- [x] M13-T1 **CI / pre-push gate.** A GitHub Actions macOS job (or a local `git` pre-push hook while
      the repo stays private) running `swift build && swift test && swift build -c release`, **plus an
      isolated step running the gated hardware-encode tests** (`SCREENREC_HW_ENCODE_TESTS=1 swift test
      --filter ExporterTests` etc.) so MP4 losslessness/faststart, GIF, and trim-passthrough are asserted
      automatically — not only via manual CLI. No signing in CI (no identity); the unit suite needs no
      SCK/TCC, so it runs anywhere. **Verify:** the workflow/hook runs green locally; a deliberately-
      broken test fails it; the gated step actually exercises a real encode.
- [x] M13-T2 **Graceful finalize on OS-initiated quit.** `AppDelegate.applicationShouldTerminate` →
      `.terminateLater`, finalize an in-progress recording via `stopAndWaitForFinalize()`, then
      `reply(toApplicationShouldTerminate: true)` — so logout/shutdown/`⌘Q`-from-a-window finalize
      cleanly instead of falling to `.partial` crash-recovery. Closes the one hole in the crash-safe
      story (the graceful path is currently wired only to the menu Quit). **Verify (live):** start a
      recording, trigger a non-menu quit (`⌘Q` from the Settings window, or `osascript -e 'quit app'`);
      confirm a clean finalized file, not a recovered partial.
- [x] M13-T3 **Extract + test `RecordingSession`'s finalize fate-matrix.** Pull the 6-way file-fate
      branch (discard / start-failure / deleted / stranded / write-never-began / normal-finish) out of
      the inline `Task` closure into a pure `finalize(startFailure:endReason:) -> EngineEvent` over the
      existing fields/boxes, and **unit-test each branch** — closing the top complexity hotspot AND the
      safety-critical test gap (the M9-T7-dropped `RecordingSessionTests` pairing). **Verify:** new unit
      tests cover all six branches; full dev loop green; live record/discard/`kill -9` behavior
      unchanged.
- [x] M13-T4 **Two small reliability notices.** (1) **Notify on a mic-grace silent drop** — extend
      M9-T1's "started without a microphone" to the case where a *resolved* device misses
      `MovieRecorder`'s 0.75 s first-buffer grace (a plausible Bluetooth handshake), which today yields a
      silent mic-less take. (2) **Guard the region `.main` display resolution** so a multi-monitor
      `displays.first` fallback can't silently crop a region against the wrong display — fail loud
      instead. **Verify:** unit tests for both; the mic-grace copy is reviewed against the M6-T3 bar.
- [x] M13-T5 **`release.sh` + `smoke.sh` + doc refresh.** `Scripts/release.sh` (assert clean tree, read
      `VERSION`, run the 4-step loop, `git tag v$VERSION`, a README-vs-`VERSION` consistency check,
      remind to push); `Scripts/smoke.sh` (`screenrec-cli record --duration 3` + `probe` asserting 3
      tracks / ~3 s) for the dev box, which holds TCC — the only cheap catch for live-pipeline
      regressions. Refresh **README** (stale "v1.0.0 / M0–M6"; add region/export/trim to "Use") and
      **docs/01**'s file tree (predates the AppCore model split; mislocates `Hotkey`). **Verify:**
      `release.sh` dry-run; `smoke.sh` green on the dev box; README/docs current.

**Gate G13**: `swift test` (+ the gated encode step) runs in CI/pre-push and **fails on a deliberate
regression**; an OS-initiated quit **finalizes cleanly** (not a recovered partial); the
`RecordingSession` finalize branches are **unit-covered**; the mic-grace + region-display notices land;
`release.sh`/`smoke.sh` exist and pass; README + docs/01 are current.

**Non-goals (M13):** notarization / Developer ID (ADR-014); external CI services, matrix/Docker builds,
coverage gates (enterprise overkill at this audience); auto-restart of a wedged stream (stall watchdog
stays diagnostic-only, documented v1 policy).

## M14 — Cleanup (post-M13; from the v1.6.0 review, 2026-07-22)

Pure refactors, **no behavior change** — sharpen the biggest files once M12/M13 land. (The
`RecordingSession` finalize extraction lands in M13-T3, not here.) The layering and concurrency model
are load-bearing strengths and stay untouched.

- [x] M14-T1 **Extract `ExportModel` from `AppState` (1068 LOC).** Move the export cluster
      (`exportInProgress`, `lastExport`, the three inject-closures, `performExport`, the trim target)
      into an `@Observable ExportModel` that AppState owns and forwards to — mirroring `PermissionsModel`
      (M9-T7). ~60 near-zero-coupling lines (it never touches `session`/`replay`/capture-config), and it
      sharpens `ExportWiringTests`'s target. **Do NOT** extract the source-picker/capture-config or
      recording-lifecycle clusters — intrinsically coupled to persist+replay, deliberately kept (M9-T7
      ruling). **Verify:** full dev loop green; the export tests narrow; behavior unchanged.
- [x] M14-T2 **De-duplicate the AVAssetWriter drain pump + first-error box.** `ReplayMuxer` and
      `Exporter` hand-roll the same `requestMediaDataWhenReady` + done-flag + `DispatchGroup` +
      first-error pump (the comments call it "the ReplayMuxer idiom"), each with an identical
      `@unchecked Sendable` first-error latch. Extract one `FirstError` box + one `drain(...)` helper into
      `RecorderCore/Support`, used by both — one place to get "leave the group exactly once even if the
      writer dies" right. **Verify:** full dev loop green **including** the gated encode tests; behavior
      unchanged.
- [x] M14-T3 **Small hygiene: file-size helper · dead event · one doc line.** Add
      `OutputLocation.currentFileSize(for:)` (partial-first) and call it from AppState + the CLI (kills an
      avoidable cross-module dup); **retire `EngineEvent.fileProgress`** — declared and threaded through
      ~4 switches but never emitted (AppState polls instead); add one line to `SampleRouter`'s doc that
      `detach()` is **not** a hard callback barrier (a consumer can get one late `consume` after detach —
      safe today, an implicit contract). **Verify:** full dev loop green; the CLI + app still report the
      growing file size.

**Gate G14**: all three refactors land with **no behavior change** (full dev loop green incl. the gated
encode step); `AppState` is smaller; the drain logic lives in one place; no dead event arms remain in
the `EngineEvent` switches.

**Non-goals (M14):** any behavior change; extracting the source-picker/recording clusters (M9-T7 ruling
stands); touching the concurrency model or the seam design (the review's "don't regress" list).

## M15 — Gate & Debt (post-M14; from the 2026-07-24 review, findings A1–A6)

**Do this first.** M15 is the M9/M13 pattern again: clear the deck before new features land. The
headline is that **`swift test` — step 2 of the CLAUDE.md dev loop — is not reliably green**, and
with no CI it is the only automated check the project has. A gate that fails for environmental
reasons doesn't get fixed, it gets bypassed. Everything else here is accumulated debt the review
surfaced. **No user-facing features → PATCH (ADR-013).** Nothing touches the sample path, the
layering or the seam design.

- [x] M15-T1 **Make `swift test` deterministic again.** Measured 2026-07-24 on a clean tree at
      v1.7.1, three consecutive runs, no source changes: **run 1 aborted** (`Precondition failed:
      encoder session never became ready`, `SyntheticBuffers.swift:24` — a `precondition` in a shared
      helper, so the process dies and the other 424 tests never report); **runs 2 and 3 failed** with
      4–6 issues after burning 120 s timeouts, all in `ReplayEncoderTests`/`ReplayMuxerTests`, one
      carrying `VT error -12912` (encoder malfunction / resource exhaustion). The mechanism is already
      in the field notes (2026-07-21): swift-testing parallelises suites, several hold a live
      `VTCompressionSession`, Apple Silicon allows only a handful. **The mitigation was only ever
      applied to the three env-gated encode suites** — the pre-push hook runs each with `--filter`,
      one at a time, and says so in a comment — while the two always-on VT suites still run
      concurrently with everything else and carry no `.serialized` trait.
      **Seams:** `Tests/RecorderCoreTests/{ReplayEncoder,ReplayMuxer}Tests.swift`,
      `SyntheticBuffers.swift`, `Scripts/hooks/pre-push`, `Scripts/release.sh`, and docs/04's
      "Automated gate" section + CLAUDE.md/README's dev loop if the promised command changes.
      **RESOLVED — `@Suite(.serialized)` on both VT suites, plus `Issue.record` in place of the
      `precondition`. Option (a) (gating them behind `SCREENREC_HW_ENCODE_TESTS=1`) was NOT needed, so
      replay coverage stays in the default loop.** Measured: baseline **8/10 runs failed**; serialising
      the two suites → **0/20 failed, slowest 3 s** (evidence table in STATUS.md).
      **⚠️ Two premises in the paragraph above were wrong, and the measurement is what corrected them:**
      **(1)** the `precondition` is *not* the common failure — forced to fire 13× it proves the run now
      reports instead of aborting, but in 10 real runs it never fired once, and removing it alone left
      the rate unchanged (7/10). It is a robustness fix, not the cure. **(2)** The ~120 s is *not* a
      previous run's abort poisoning the next one; it is spent **inside** each test, and those tests
      then mostly **pass** at ~122 s. Root cause is plainly the concurrent session count: 14 tests can
      hold a live `VTCompressionSession` (`ReplayMuxerTests` 8/8, `ReplayEncoderTests` 6/7), and
      `VTCompressionSessionCreate` **blocks rather than fails** once the hardware pool is exhausted.
      `ReplayEncoder.deinit` already invalidates, so nothing leaks and **production was never
      affected** — this was purely a test-harness concurrency bug. (Killing the leaked
      `VTEncoderXPCService` processes does *not* heal it: the 14-way race re-exhausts a fresh service
      immediately.) **Verify (as run):** 20 consecutive `swift test`, 0 failures, none over 10 s —
      against a 10-run baseline of 8 failures at ~123 s each; the readiness path deliberately provoked
      (wait budget → 0) recording 13 issues with **0 aborts and all 425 tests still reporting**, which
      also serves as the deliberately-broken-test check; the three gated encode suites green in
      isolation; full dev loop green.
- **M15-T2 — DECLINED, not deferred (Franco, 2026-07-24).** *Was: collapse the settings mirror — 17
      `Settings` fields, 17 mirrored stored properties on `AppState`, and a `persist()` rebuilding the
      struct from 17 arguments, into one `private var settings: Settings` behind computed forwarders.*
      **Closed "won't do" (the ADR-014 / M9-T7 pattern) — do not re-attempt without a new ruling.** Two
      findings from the planning pass killed it:
      **(1) The bug it claimed to prevent barely exists.** The review said a forgotten preference
      silently stops persisting. It doesn't: `Settings` uses the **memberwise** initialiser and
      `persist()` passes all 17 arguments, so a new field **breaks the build**. The only silent case is
      a field declared *with a default value*, which gains a memberwise default and lets `persist()`
      keep compiling — one declaration style, not the general case. So the justification was only ever
      size and single-source-of-truth.
      **(2) It conflicts with `@Observable`, unavoidably.** The macro tracks **stored** properties, so
      today's 17 are tracked individually — writing `gifFPS` notifies only `gifFPS` readers. Backing
      them with one stored `settings` makes every getter read that one property, so **any** preference
      write notifies **every** preference reader: granularity 17 → 1. On a codebase where M6-T10 makes
      spurious publishes actively harmful (a publish rebuilds the open menu's AppKit rows and garbles
      hover) and which is full of assign-only-on-change guards written for exactly that reason, that is
      a deliberate loosening of a load-bearing mechanism. The `PermissionsModel`/`ExportModel`
      precedent does **not** transfer: those keep granularity because they are `let` references to
      `@Observable` **classes** whose properties are each tracked; a `Settings` **struct** has no such
      tracking. Backing it with a `SettingsModel` class would preserve granularity and **not do the
      task** — the 17 properties merely move to another file and `persist()` still assembles a
      `Settings` — which is the "layer over intrinsic coupling for negative clarity value" shape M9-T7
      already rejected. Hand-rolling `@ObservationIgnored` + `access`/`withMutation` 17 times was
      considered and is strictly more code than today.
      **Ruling: ~70 lines is not worth loosening the observation graph.** `AppState` keeps its 17
      properties and its 15-line `persist()`. If the mirror ever needs revisiting, the trigger is a
      *new* reason (e.g. a language-mode move that changes observation semantics), not this one.
- [x] M15-T3 **Exports defend themselves like recordings do.** Recordings get `.partial` + an O_EXCL
      reservation + a vnode sentinel + a launch recovery sweep. MP4/GIF/trim exports write straight
      to the final path, so a quit or crash mid-export leaves a **truncated file at a real name** —
      and since M12-T2 it then appears in **Recent Exports** as a first-class, shareable file with a
      receipt, rename and trash. This was assessed and accepted (field note 2026-07-21 ②) on the
      grounds that an export is a derived, re-doable copy — sound *at the time*, but **M12-T2 shipped
      the surface that exposes it afterwards**, so the trade is worth re-deciding rather than
      inheriting. **Seams:** `Exporter`/`GifExporter`/`Trimmer` write to a `.partial` sibling and
      rename on success — `OutputLocation.partialURL(for:)`/`finalizePartial(_:)` already exist and
      the recents scan already ignores `.partial`. **Rulings:** does the launch sweep adopt orphaned
      export partials too (a truncated `.mp4` is *not* playable the way a fragmented `.mov` is — so
      probably **delete**, not recover); and does `applicationShouldTerminate` await an in-flight
      export alongside M13-T2's recording finalize, or just let the partial be swept? **Verify:**
      kill the app mid-export → no stray file in Recent Exports, and the next launch is clean; a
      normal export still lands at the same final name; the source is untouched in both cases.
      **RESOLVED. Premise confirmed by A/B measurement**, not assumed: `kill -9` mid-export **before**
      the change left a torn `Take.mp4` **at the real name**; **after**, only `Take.mp4.partial`, with
      nothing at the final name. Two design changes from the plan:
      **(1) The discipline went into the three exporters, not `ExportModel.performExport`.** The funnel
      looked like the one-place win, but `performExport`'s injected spies deliberately never touch the
      filesystem ("the wiring is tested on a fake"), so a rename there made 5+ pure wiring tests fail
      and would have forced them to create real files. Putting it at each exporter's public entry point
      keeps those tests untouched, puts the knowledge where the writing happens — and **closes the CLI
      gap the plan had written off as acceptable.**
      **(2) The sweep is three-way, not two.** "Recover `.mov`, delete the rest" would have deleted the
      CLI's extension-less exact-path partials (`take1.partial`), which `finalizePartial` explicitly
      supports. Since deletion is irreversible: recover `.mov` **and extension-less**, delete only
      known export extensions, and **leave anything unrecognized alone** rather than destroy it.
      `OutputLocation.exportExtensions` is now the single list both the sweep and `RecentRecordings`
      read, so they can't drift. **Verified:** 429 tests (+4); all three gated encode suites green
      through the new path; live CLI mp4 + gif + trim all landing at their final names; the A/B kill
      test above. ⚠️ AVFoundation also leaves its own `<name>.sb-<hex>` temp on a hard kill — invisible
      to the menu, not swept (field note).
- [x] M15-T4 **Stale comments, dead enum cases, one duplicated helper.** Four doc drifts, each one
      measurement out of date: **(1)** `MovieRecorder.makeMicrophoneInput` claims it matches "the
      device-native sample rate/channel count read from its first buffer" — since M8-T1 every mic
      buffer is normalised to a fixed 48 kHz mono format, and the same class's `consume` comment 200
      lines above says so correctly; **(2)** `Settings.replaySeconds` still says "docs/06 offers 30,
      60 or 120" (M9-T8 made it a 5…900 range); **(3)** `AppState.replaySeconds` carries the same
      stale sentence; **(4)** docs/06 still lists `microphone changed` as a fail-stop cause, which
      ADR-007's M8-T1 amendment made unreachable. Also retire or explicitly justify
      `EndReason.microphoneChanged` and `.systemSleep` — both declared-but-unreachable, the same
      category as the dead `fileProgress` M14-T3 removed — and lift the duplicated two-line
      `isSameFile` (`AppState` + `ExportModel`, a known-defensible M14-T1 nit) into one `URL`
      extension in AppCore. **Rulings:** whether the two dead `EndReason` cases go (a public-API
      ripple through the CLI's `describe` and the notification `cause` switch) or stay declared with
      a sharper comment — M14-T3's precedent says go. **Verify:** full dev loop green; the
      exhaustiveness checker confirms no arm was missed; `grep` shows one `isSameFile`.
      **DONE — both cases deleted.** `EndReason` is now `userStopped`/`displayDisconnected`/`appQuit`/
      `diskAlmostFull`/`streamError`, rippling through the CLI's `describe`, the notification `cause`
      switch, two test fixtures and docs 01/02/05/06. `isSameFile` is one `URL` extension
      (`FileIdentity.swift`) — deliberately still distinct from `Exporter.sameFile`, which resolves
      symlinks and file identity; the AppCore one answers "does this receipt point at that row" and must
      keep working once the file is gone. **A fifth drift surfaced while fixing the fourth:** docs/06's
      fail-stop cause list was wrong in *both* directions — it named `microphone changed` (unreachable
      since M8-T1) **and** omitted `the recorded app quit` (added by M7). It now matches the `cause`
      switch exactly. **429 tests unchanged; full dev loop green; CLI verified by hand.**
- [x] M15-T5 **Rotate STATUS.md and the milestones doc.** `STATUS.md` is 2,619 lines / 236 KB —
      larger than any source file by a wide margin — and CLAUDE.md mandates it as the entry point for
      every session. Its own contract says "keep Now brutally short", and Now *is* short; the problem
      is ~950 lines of newest-first session log sitting between it and the structured sections. The
      **field notes are the most valuable artefact in the repo** (measured platform behaviour
      available nowhere else) and they are currently buried 1,400 lines deep in an append-only log.
      `docs/03-milestones.md` has the same shape at 1,109 lines with M0–M11 all closed.
      **Seams:** promote field notes to their own `docs/07-field-notes.md` (and point CLAUDE.md's
      reading order at it); rotate closed-milestone session logs into `docs/history/`; keep
      `STATUS.md` to ~250 lines — Now, Needs Franco, the gate table, and pointers. Nothing is lost:
      git holds the history and the parts worth re-reading get findable. **Rulings:** whether closed
      milestones' task text also rotates out of 03 or stays as the audit trail (recommend: stays —
      the tick boxes *are* the record; only the session log moves). **Verify:** every doc reference
      in CLAUDE.md resolves; STATUS.md ≤ ~250 lines; a cold read of CLAUDE.md → STATUS.md → the
      current task still answers "what do I do now" without opening a history file.
      **DONE. STATUS.md 2,769 → 237 lines.** Field notes → **`docs/07-field-notes.md`** (1,236 lines)
      and promoted to **#4 in CLAUDE.md's reading order** — they were the most valuable artefact in the
      repo and the least findable. Closed session logs, the v1 status write-up and the M2-T6 calibration
      table → **`docs/history/2026-07-sessions.md`** (1,320 lines), explicitly unmaintained. STATUS.md
      keeps Now (today's entries + the current release), Needs Franco, the gate table, and a pointer
      table. **Rotation verified lossless**: every original non-blank line accounted for in the three
      files bar the two headings deliberately rewritten. CLAUDE.md's five "STATUS.md field notes"
      references and README's doc map now point at the new homes, and the session-end checklist gained a
      standing instruction to re-rotate past ~250 lines so this doesn't silently regrow.
      **Ruling taken as recommended:** closed milestones' task text stays in docs/03 — the tick boxes
      are the audit trail; only the session log moved.

**Gate G15**: `swift test` runs green **20 times in a row** with no run over 10 s (the evidence table
in STATUS.md — the original "five times" bar was too weak against an intermittent failure, corrected
at T1); a killed mid-export leaves nothing behind; no stale comment or dead enum arm remains;
STATUS.md is back under ~250 lines and the reading order still works cold. No behaviour change
reaches the user (PATCH). *(T2 is closed "won't do" and is not part of this gate.)*

**Non-goals (M15):** any user-facing feature (that's M16+); a GitHub Actions runner (docs/04's
public-repo-only note stands); re-opening the M9-T7 source-picker ruling; touching the sample path.

## M16 — Honest State (post-M15; from the 2026-07-24 review, findings B1–B4, B8, B9)

The review's central thesis. screenrec is scrupulously honest about failures it has **modelled** — a
mic that disappears gets a watchdog, a rescue stream and four notifications — and silent about states
it hasn't. M16 extends ADR-007 from *"never a broken file"* to *"never a lying state"*: what arming
costs you, whether audio is actually arriving, and which build you're running. Every task is small;
what makes it a milestone rather than a list is the single thesis. Zero-dep throughout (ADR-010);
**no capture-path redesign** — T3 adds one flag to an existing config, T4/T5 read buffers that already
flow past a consumer. Earns a **MINOR** (ADR-013).

- [x] M16-T1 **Every stream's sleep assertion says what it is actually doing.** `CaptureEngine.start()`
      took a `SleepGuard` assertion reading *"Recording the screen"* for **every** stream, and
      `ReplayController` starts a full `CaptureEngine` for its armed stream — so a merely-armed Mac
      reported a recording that wasn't happening. Measured 2026-07-27 on the running 1.7.1: `pmset -g`
      listed `ScreenRec` under "sleep prevented by" with no `.partial` anywhere on disk.
      **The task as filed proposed making the assertion conditional on a recording, so an armed Mac
      would idle-sleep. Measurement killed that premise before any code was written:** any SCK stream
      capturing audio *also* carries a `PreventUserIdleSystemSleep` held by `coreaudiod` on behalf of
      `/usr/libexec/replayd` — present with the mic off too, so the system-audio tap alone does it —
      and released only at stream teardown. Dropping `SleepGuard` would have bought honesty and no
      sleep; only an idle stand-down (tear the armed stream down after N idle minutes) would have
      delivered sleep, at the cost of the buffer being there when you reach for it.
      **RULING (Franco, 2026-07-27): arming is MEANT to keep the Mac awake — keep the assertion, fix
      the reason, state the cost in the UI (ADR-018).** The stand-down alternative was declined with it.
      **As built:** `CaptureEngine.Purpose` (`.recording` / `.replayBuffer` / `.diagnostic`) is a
      required init argument on every engine, and its `assertionReason` is the only place the strings
      live. **Verify (as run):** all four CLI entry points live, snapshotting `pmset -g assertions` 6 s
      in — `record` → `"Recording the screen"`, `replay-arm` → `"Instant replay is armed"`,
      `probe-stream` and `engine-smoke` → `"Capturing the screen"`, and no assertion surviving any
      exit; 430 tests (+1: the purpose→reason mapping, including that no two purposes share a string);
      full dev loop green. The sleep/wake leg the original task called for is moot under the ruling.
- [x] M16-T2 **Armed replay states its cost.** Two captions, one number. The Settings slider (M9-T8)
      runs to 15 minutes with the RAM cost "explicitly accepted" but shows only `M:SS` — at Balanced
      / 60 fps a 15-minute ring is ≈2.6 GB resident, and the slider is the exact moment the user is
      making that trade. **Seams:** a pure `Settings`/`BitrateModel` helper turning (seconds, quality,
      fps, capture pixel size) into an estimated ring footprint — `BitrateModel` already has the
      math and docs/04 §6.1 already states the formula (bitrate × (window + 2 s slack), plus the two
      PCM rings); a caption under the slider; and the armed menu row gaining the same figure
      (`Armed · 60 s · ≈180 MB`) beside the existing banner-suppression line. **ADR-018 sends the
      second cost here too:** arming holds the Mac awake deliberately, so the Settings caption says
      so in the user's words (`… · keeps your Mac awake`) — T1 fixed what `pmset` reports, this is
      where the person choosing the setting finds out.
      **As built:** `ReplayFootprint` (RecorderCore, beside `BitrateModel`) is the estimator;
      `RingBuffer`'s 2 s slack became `ReplayWindow.slackSeconds` so the ring and the estimate can't
      drift. **Quality is deliberately NOT an input — `ReplayEncoder` hardcodes `.balanced` (docs/04
      §6.1's 2026-07-16 amendment), so the preset doesn't change the ring**; billing a High user for
      1.6× would have been the obvious bug. The mic counts only when `presentMicrophonePreference`
      says a device will actually be captured (an away pick attaches no ring). Pixel size arrives
      through `DisplayOption` (`pointSize` + `pointPixelScale` from `NSScreen`, the no-AppKit seam
      that already existed) and goes through `CaptureConfiguration.pixelDimensions`; a region is
      billed for its own rect, an app-scoped pick for the display (02 §1a). No geometry ⇒ the figure
      is withheld, never guessed. Copy: `A 4:30 buffer holds about 800 MB in memory. While armed,
      ScreenRec keeps your Mac awake.` / menu `4:30 buffer · ≈800 MB · Mac stays awake` (Franco
      picked the full-sentence variant, 2026-07-27); rounded to two significant figures so an
      estimate doesn't read as a measurement.
      **Verify (as run):** 442 tests (+12) — the estimator restated against docs/04 §6.1's formula
      across 5 s/60 s/5 min/15 min × 30/60 fps × mic on/off, the region case, the withheld-figure
      case, and the phrase table; then **live on the deployed build**: `menudriver dump` shows
      `4:30 buffer · ≈800 MB · Mac stays awake` (before/after dumps recorded), and a Settings
      screenshot shows the caption under the slider carrying Franco's real 4:30 → 800 MB. Full dev
      loop green. ⚠️ **Slider-drag tracking is proven by unit test, not on screen** — driving the
      live slider would have restarted his armed ring, and `settingsdriver` can only shoot/toggle. **Rulings:** the menu
      row must **stamp at open, never tick** (M6-T10 — a publish rebuilds the open menu's AppKit rows
      and garbles hover). **Verify:** unit — the estimator against the docs/04 §6.1 formula at three
      window lengths and both fps caps; `menudriver dump` shows the figure in the armed row;
      `settingsdriver` shows the caption tracking the slider.
- [x] M16-T3 **System audio becomes optional.** `ShareableContent.applyAudioCapture` sets
      `capturesAudio = true` unconditionally. The mic has None / Automatic / device; **system audio
      has no control anywhere in the product** — not the menu, not Settings, not the CLI. So there is
      no way to record screen + mic without also capturing whatever is playing: music, a call's other
      side, the soundtrack of the video you are narrating over. For the stated use cases (demos, bug
      reports, meetings) "just my voice over the screen" is routine, and today the answer is to mute
      the Mac. **Seams:** one `Bool` on `CaptureConfiguration` → `applyAudioCapture`; a persisted key
      (docs/06's contractual table); one menu row; a CLI `--no-system-audio` flag mirroring
      `--no-mic`; `MovieRecorder` must not add the system-audio input when it's off (it is currently
      built eagerly in `init`, unlike the two lazy inputs — that's the one real code change).
      **Rulings:** **(a)** ADR-004 names "two AAC audio tracks" a product requirement — a
      system-audio-off recording has one, so this needs an ADR amendment, not a silent contradiction;
      **(b)** where the control lives (a `System Audio ▸` submenu beside `Microphone ▸`, or a row
      inside it) — note B10/M18-T3 is trying to *shorten* the menu; **(c)** what an all-off recording
      does (silent video is legitimate — allow it). **Verify:** CLI record with `--no-system-audio`
      → `probe` shows video + mic only, no empty second track; the pick round-trips; a normal record
      still shows three tracks (no regression against G2 §3.1).
      **Rulings (Franco, 2026-07-27):** (a) **ADR-019** written, amending ADR-004 — "never mixed"
      survives, "always two tracks" does not; (b) a **checkmark row** `Capture System Audio`, not a
      submenu — a boolean doesn't earn one, and M18-T3 is cutting rows; (c) an all-off recording is
      legitimate **and says so first**: one dimmed row `This recording will have no audio`, shown
      only in that configuration.
      **As built:** one `Bool` on `CaptureConfiguration` → `applyAudioCapture(systemAudio:…)`;
      `MovieRecorder.systemAudioInput` became optional (the eager non-optional `let` was the one real
      code change the task predicted — an input that never receives a buffer still writes an empty
      AAC track); `capturesSystemAudio` persisted **absent ⇒ on** via the `showsMenuBarTimer` idiom;
      `--no-system-audio` on `record` and `replay-arm`. **The mic-rescue stream keeps
      `systemAudio: true`** — it adds only the microphone output so nothing reads it, and M8-T2's
      rescue can't be re-proven without a device that physically leaves and returns.
      **The replay path needed no change:** `ReplayMuxer.makeAACInput` already returns nil for an
      empty ring, so a silent system ring yields a clip with no system track.
      **Verify (as run):** 449 tests (+7); live `probe` of three recordings — control **3 tracks**
      (2ch system + 1ch mic), `--no-system-audio` → **video + 1ch mic, no empty track**, both off →
      **video only, playable**; an armed save with system audio off → clip with a mic track and no
      system track (system ring measured 0.0 s / 0.0 MB throughout); dev loop green. **Bonus, and it
      closes M16-T1's loop:** with all audio off SCK opens **no audio tap** — assertion count 3 → 3
      (all off) vs 3 → 4 (system audio on), so that is the only configuration where an armed Mac
      could idle-sleep. ⚠️ **Known, unfixed by ruling:** with no audio at all, `ReplayMuxer` loses the
      continuous clock it anchors saves on — a still screen can yield a stale clip (field note).
- [x] M16-T4 **Notice when audio is arriving but silent.** The product defends hard against a mic
      *disappearing* and not at all against the far more common failure: a mic connected and
      delivering buffers that are **silent** — hardware mute switch, wrong input selected, gain at
      zero, a conferencing app holding the device. You find out an hour later and the take is
      unrecoverable. This is precisely the outcome ADR-007 forbids ("no outcome: recording silently
      broken") and the one instance the design currently misses. **Seams:** `MicrophoneWatchdog`
      already inspects mic buffers on a timer from the router, so a peak-amplitude read is a few
      lines on a path that already exists — extend it (or add a sibling consumer) with a
      silence-duration threshold, and emit a new `EngineEvent` folded like `microphoneLost`
      (**recording continues** — this is a notice, never a fail-stop, ADR-012's shape). Copy follows
      the outcome-first rule: `Still recording · microphone is silent`. Same treatment for system
      audio if the sibling is cheap. **Rulings:** the threshold and the amplitude floor (a genuinely
      quiet room is not a muted mic — pick numbers by measuring, and prefer late-and-right to
      early-and-wrong); whether it fires once or re-arms if sound returns (recommend: paired
      lost/recovered notices, the M8-T2 shape); whether `.none` and a deliberately silent screen
      recording are excluded (yes). **Verify:** unit — the pure silence decision over synthetic PCM
      (silent, quiet-room, speech) at the chosen threshold; live — record with the mic muted at the
      hardware switch → exactly one notice, recording continues, file playable with a (silent) mic
      track; unmute → the recovered notice.
      **RULINGS (Franco, 2026-07-27):** **−90 dBFS sustained 10 s**; **paired** silent/audible
      notices; **microphone only** — silent system audio is the normal state, and saying so would
      train the user to ignore the notice.
      **Thresholds MEASURED, not picked** (full table in docs/07): a muted device delivers **exact
      digital zeros**, while the same quiet room reads **−65.5 dBFS median on AirPods (quietest
      window −78.9)** and **−42.7 on the built-in** — a 23 dB spread that makes eyeballing a floor
      impossible. −90 sits ~11 dB below the quietest real window. ⚠️ **SCK delivers ~1 s of exact
      zeros while a Bluetooth route spins up**, which is why the decision judges a *run*, never a
      buffer — and why no separate start grace was needed (the 10 s run subsumes it, a simplification
      from the plan).
      **As built:** `MicrophoneSilenceWatchdog`, a sibling of `MicrophoneWatchdog` on the router path
      (that one asks whether buffers arrive, this whether they carry anything); thresholds on a public
      `MicrophoneSilence` seam because the notice copy quotes the duration; `.microphoneSilent` /
      `.microphoneAudible` folded like `microphoneLost` (recording continues, ADR-012). **Armed replay
      gets the pair too** — a clip saved with a dead mic is the same failure.
      **Verify (as run):** 456 tests (+13), including every measured level as a must-not-fire case;
      live — muted record → **exactly one** notice at ~10 s, recording ran to completion, file
      playable with a full-length (silent) mic track; **unmute mid-recording → the paired recovery
      notice**; control run with a live mic → **neither notice**. Input volume restored after every
      leg. Dev loop green.
- [x] M16-T5 **Input level in the menu-bar label.** T4 tells you after 30 seconds; this tells you
      before you start. **⚠️ An in-menu level meter is not implementable** — M6-T10 established that
      any publish rebuilds an open `.menu` MenuBarExtra's AppKit rows and garbles hover, which is the
      same constraint that froze the in-menu clock. The **status-item label is not bridged** (M9-T3
      proved it: it already redraws frame-by-frame for the pulse and carries a live ticking clock),
      so that is the ADR-consistent home. **Seams:** a small level indicator drawn beside the M9-T3
      clock in `StatusIconView`, off the same timer, fed by a lightweight peak-level consumer on the
      router (shared with T4's watchdog — one read, two uses); opt-out beside `showsMenuBarTimer`;
      Reduce Motion stills any animation but the level still updates. **Rulings:** does it show while
      merely *armed* (replay has a mic too) or only while recording; menu-bar width is scarce, so
      three or four discrete segments probably beat a continuous bar. **Verify:** screenshot the
      label across ≥3 ticks with audio playing and assert the drawn level changes — **MEASURE, don't
      eyeball** (the M4-T1 rule); the opt-out shows nothing.
- [x] M16-T6 **Onboarding proves capability, and names the build.** *(Review findings B4 + B9 — B4
      was missing from the review artifact's bundle table; Franco caught it, it belongs here beside
      T4/T5.)* The setup checklist goes green when **TCC says yes**. It never proves the thing that
      actually matters: that a recording comes out with picture *and* both audio tracks, from the
      devices the user thinks are selected. Permission granted and capture working are different
      claims, and the gap between them is where every T4 failure lives — a first-time user's first
      real take is currently their first test. Separately, **nothing in the app displays its own
      version**: `CoreInfo.version` exists, `bundle.sh` stamps the plist, `release.sh` pins them and a
      test guards the pin, but the menu, Settings and onboarding are all silent — and ADR-014's whole
      distribution model is handing a signed `.app` to people directly, who then have no way to
      answer "am I on the build with the fix?". **Seams:** a *Run a 5-second test* button on the
      onboarding window that records, probes and reports `✓ screen · ✓ system audio · ✓ microphone
      (<resolved device name>)`, then deletes the file — this is exactly what `Scripts/smoke.sh`
      already does from the CLI, so it is a UI over trusted machinery, and the probe logic wants to
      live in RecorderCore where both surfaces can reach it. Version: one line in the Settings footer
      or under the onboarding checklist, read from `CoreInfo.version`. **Rulings:** where the test
      writes (scratch, never the output folder); what a *partial* pass says (mic silent → route
      straight to T4's copy, don't invent a second vocabulary); whether it is offered again from the
      menu after setup (recommend: yes, it is a diagnostic, not a rite). **Verify:** run it with the
      mic set to None → reports screen + system audio and says why the mic line is absent, without
      calling it a failure; run it muted → the mic line reflects T4's silence check; no file survives;
      the version string matches `VERSION`.

**Gate G16**: no stream misreports itself to the system — `pmset -g assertions` never shows a recording
while merely armed — and the armed cost (RAM, and the Mac staying awake) is stated where the user picks
the setting (ADR-018 replaced this criterion's original "an armed Mac idle-sleeps"); a recording can be made with system audio
off (`probe`: no empty track) and with it on (no regression); a muted mic produces exactly one
outcome-first notice while the recording continues; the menu-bar label shows a level that measurably
tracks real audio; the setup window can prove a working capture end-to-end and names the build. Every
capture mode (whole screen / app / region), replay, export and trim unchanged — M7/M8/M10/M11/M12
gates still pass.

**Non-goals (M16):** echo cancellation (ADR-009 still parked); any render/compositing stage
(ADR-015); webcam (ADR-017); auto-restart of a wedged stream (the stall watchdog stays
diagnostic-only); a level meter *inside* the menu (blocked by M6-T10 — see T5).

## M17 — Window capture (post-M16; from the 2026-07-24 review, finding B5)

The last missing scoping mode, and the only one that **follows its subject**. Source offers the whole
screen (M0–M6), one *app* — all of its windows (M7) — or a fixed *region* (M11). "Record just this
window" is the most common scoping request there is: one Chrome window, not all of Chrome; one
terminal, not every terminal. It also solves what region cannot — the capture tracks the window as it
moves and resizes, so a demo doesn't have to be framed and then frozen in place. Architecturally it is
**M11's shape exactly**: a fourth `ContentSelection` case, so recording, replay and the shared-stream
path all inherit it from one place. The capture default is unchanged (ADR-004); window is opt-in.
Earns a **MINOR**.

**Mechanism (SCK):** `SCContentFilter(desktopIndependentWindow:)` — window-only capture, output sized
to the window rather than the display. Unlike `.app` (which composites an app's windows onto a
display filter) this filter has no display to fall back on, so its failure modes are its own.

- [x] M17-T1 **Window capture core + CLI, and the platform facts.** Add `.window(id:)` to
      `ContentSelection`; `CaptureEngine` resolves it against `SCShareableContent.windows` and builds
      the desktop-independent filter. A vanished/closed window **fails loud** (the M7 `.app`-gone and
      M11 region precedents — never a silent whole-screen fallback), and a window that closes
      *mid-recording* should end the session the way `AppTerminationWatch` ends an app-scoped one.
      CLI `record --window <id>` + `replay-arm --window <id>` + a `list-windows` subcommand (the
      headless verify surface, ADR-011). **Rulings to nail — measure and write them into 02 as a new
      §1c, the way M7-T1 and M11-T1 did:** (a) does the output resize when the user resizes the
      window mid-recording, or does SCK letterbox into a fixed size (this decides whether we pin
      `width`/`height` at start — a mid-stream dimension change is exactly what the writer's welded
      video input cannot take); (b) what a **minimised** or fully-occluded window delivers (frames?
      nothing? does the stall watchdog need the `.app` exemption?); (c) whether system audio is
      scoped to the window's app the way `.app` scopes it (02 §1a), or stays whole-machine; (d)
      whether the window's shadow/titlebar is included. **Verify:** a window-scoped recording's
      frames contain **only** that window — a bystander window of the *same app* overlapping it is
      absent from every checked frame (the M7-T1/M11-T1 method, which is the point: this is what
      `.app` cannot do); dimensions match; closing the window mid-recording finalises a playable file
      with a sensible reason.
- [x] M17-T2 **Window picker in `Source ▸`, and the persistence question.** The Source submenu (M7-T2,
      regrouped M12-T4) gains the running windows. **The hard part is identity:** an app pick persists
      by bundle ID and survives the app being closed (the mic rule); an `SCWindow.windowID` is **not
      stable across a relaunch of the owning app**, so a persisted window pick can go stale in a way
      no existing pick can. **Rulings (settle before building):** (a) does a window pick **persist at
      all**, or is it select-fresh-each-time — and if it persists, is it by `(bundleID, title)`
      re-resolution at start, accepting that a title change loses it? (b) how the menu lists windows
      without becoming unreadable — grouped under their app, titles truncated, and how many; (c) what
      the checkmark says when the picked window is gone (the `(not running)` precedent). **Note the
      tension with M18-T3**, which is trying to *shorten* the menu — coordinate the two.
      **Verify:** `menudriver dump` shows the windows grouped and the checkmark on the pick; pick →
      record → only that window; quit and relaunch the owning app → the pick behaves exactly as
      ruling (a) says, and a start against a gone window fails loud.

**Gate G17**: a window-scoped recording **and** an armed replay both capture exactly the chosen
window — including against a same-app bystander, which per-app capture cannot exclude — at correct
dimensions, playable; mid-recording resize and close both behave as T1's measured rulings say;
the pick's persistence matches ruling (a) and never silently falls back to another source. Whole-screen,
per-app and region modes are unaffected (one `ContentSelection`, four cases).

**Non-goals (M17):** multiple windows in one capture; a window pick that follows an app across
relaunches by anything cleverer than ruling (a); cross-display windows beyond whatever T1 measures;
any render stage (ADR-015).

## M18 — Editing & Menu polish (post-M17; from the 2026-07-24 review, findings B6, B7, B10–B12)

The derive-a-file paths work but don't say what they will actually produce, and the menu has grown a
row per feature since M10. Nothing here is structural — it is the accumulated "last 10%" of surfaces
that already ship. Earns a **MINOR** for T1/T2 (real new capability); the rest is polish that could
ride the same bump.

- [x] M18-T1 **Trim tells the truth, and can be exact.** ⚠️ **The filed premise was false and the
      measurement killed it (2026-07-27):** a passthrough trim does **not** cut early. The export
      writes an edit list, so playback starts exactly at the in-point — measured byte-identical to
      the source frame there, in AVFoundation and ffmpeg alike. What is true: the file **keeps** the
      frames back to the previous sync sample, hidden (`ffprobe -ignore_editlist 1` → 13.56 s inside
      a 10.00 s clip, decoding 3.43 s before the in-point). docs/02 §6a has the mechanism. So the
      task became: state the hidden lead-in where the range is chosen, and offer a mode whose file
      holds only the kept range. **Rulings (Franco, 2026-07-27):** (a) ship the re-encode mode, named
      for what it does — the clip will contain only the kept range — not for a precision the trim
      already has; (b) the window says `Starts exactly at 1:01 · keeps 3.4 s before it inside the
      file`, and says nothing when the in-point is already a keyframe. **As built:** `KeyframeIndex`
      (the `AVSampleCursor` lookup + the pure sentence), `TrimMode.lossless/.precise` on `Trimmer`,
      `--precise` on the CLI, and the window's lead-in line, Re-encode checkbox,
      <kbd>I</kbd>/<kbd>O</kbd> shortcuts and Play range. ⚠️ **`AVAssetExportPresetHEVCHighestQuality`
      alone does not re-encode an HEVC source** (byte-identical passthrough) — `.precise` forces it
      with an `AVVideoComposition`, and a unit test fails without that line. **Verified:** both modes'
      first frame is the requested second (lossless byte-identical, precise 41.8 dB vs 30.8 dB
      against a second earlier); lossless stores a lead-in and precise stores none (edit-list
      segments); the re-encode preserves 4112×2570, hvc1 and both audio tracks (ADR-004); the
      original is byte-identical after both.
- [x] M18-T2 **MP4 export gets the options GIF already has.** `Export as MP4` was hardcoded to 1920
      wide / 6 Mbps / H.264 High while `Save as GIF` got three pickers. **Rulings (Franco,
      2026-07-27):** (a) a **Settings section** mirroring GIF, not a `Share ▸` submenu — M18-T3 is
      cutting menu rows; (b) the ceiling row names what it will really produce, `Largest
      (3686 × 2304)`; (c) bitrate **rises with the output's pixel count** from 6 Mbps at 1920×1200 and never
      falls below it, no second picker — today's default export is unchanged and no smaller output
      gets softer.
      ⚠️ **The measurement that bounded it:** docs/02 §3's "AVAssetWriter's H.264 path caps at
      4096×2304" is **false** — the writer encodes 4112×2570 fine, but at **Level 6.0**, which most
      phone decoders refuse. 4096×2304 is exactly **Level 5.2's** frame size, so the ceiling is a
      compatibility one and there is **no honest "Original"** for a 4112×2570 recording. 02 §3
      corrected. **Verified:** 508 tests (+6) incl. round-trip/snap and the settings→config wiring;
      four CLI exports measured — 1280×800 L3.2 / 1920×1200 L5.0 / 2560×1600 L5.0 / 3686×2304 L5.2,
      all yuv420p + faststart, bitrate at or above the 6 Mbps reference, up to 19.6; and a persisted `Largest` pick driven
      through the real Settings picker → menu export → **3686 × 2304, High, Level 5.2** (setting
      restored to 1920 afterwards).
- [x] M18-T3 **The menu earns its rows back.** The idle menu measured **20 rows with three
      recordings and no exports, and 32 at worst** (5 recents + 3 exports + the `Recent Exports`
      label + both receipts + the failure and no-audio rows) — the file browser was two thirds of it.
      **Rulings (Franco, 2026-07-27):** (a) the export and replay receipts **stay** under Start —
      they exist for the minute after an export, already self-expire, and burying them is exactly
      wrong then; (b) rows read **`<name> — 23:04 · 5.5 GB`**, the name exactly as on disk (docs/06).
      **As built:** one **`Recordings ▸`** submenu holding `Open Folder — ~/Movies`, the recents and
      the Recent Exports group → **17 rows today, 23 at worst**. The leading-space indent hack and
      its accessibility labels are gone: inside a submenu the nesting is real. Row details are read
      **off the open and cached by modification date** (M6-T10); measured 1–8 ms per file, and the
      657 MB file was the *fastest* of three (a header read, not a scan). ⚠️ **`URL` caches resource
      values per instance** and the menu holds its URLs across opens — the cache check clears them
      first, or a re-recorded file keeps a stale size forever (caught by the test, not by review).
      **Verified live on the deployed build:** `menudriver dump` before/after → **20 → 17** rows
      (the 9-row worst case → 23); every action still present, the only diffs being three live window
      titles that changed between dumps and the deliberate `Open Recordings Folder` → `Open Folder`
      rename; menu open **0.57–0.60 s** against a **0.57–0.59 s** baseline (5 runs each, same
      harness); rows rendered their details on the *first* open (`Replay … .mov — 4:30 · 656,9 MB`);
      and the rewired folder row opened `~/Movies` in Finder. 513 tests (+5).

- [x] M18-T4 **Four small honesties.** **Rulings (Franco, 2026-07-28):** a `Stop After ▸` menu
      submenu (not Settings — a standing preference that ends every take is a footgun); the disk
      figure only when it's news; a vanished row says so *and* drops itself. Wall-clock bound kept
      over recorded-time (the menu states an absolute `Stops at`).
      **(1)** <kbd>Esc</kbd> cancels the count-in. The overlay is click-through and never key, so no
      key event can reach it and a global monitor would need a TCC grant this product has never
      required — measured instead that a **bare-Esc Carbon hotkey registers and fires** in an
      accessory app, not frontmost (02 §9's mechanism), registered only while the count runs since
      it swallows Esc system-wide. **(2)** `Stop After` (Off/5/15/30/60) stops via the shipped
      `.userStopped` path, and the recording menu states `Stops at 2:35 PM` — absolute, never
      ticking (M6-T10), locale-formatted. **(3)** `Room for about 40 min at High` under Start, below
      a 2-hour threshold. ⚠️ **Review caught it over-promising by the whole 2 GiB fail-stop
      reserve** — 4 GiB free would have said 30 min for a take that stops at 15; it now subtracts
      the reserve and says `Not enough room to record` when there is none. **(4)** Every file action
      is built through one `fileButton` that checks first, so an unguarded one can't be written;
      the export receipt is existence-checked at menu open, not only at launch, and the replay
      receipt is cleared too (it was the one row nothing else dropped).
      **Verified live on the deployed build:** Esc cancelled twice in a row with no file written and
      Start immediately reusable; `Stop After: 5 min` persisted and a take begun at 09:30 read
      `Stops at 9:35`; a 3 GB volume read **2 min** (11 before the reserve fix) and **`Not enough
      room`** at 1.2 GiB free; a row whose file was deleted under an open menu dropped itself on
      click. 525 tests (+11). ⚠️ Two harness lessons: `defaults write` stores an untyped value as a
      **string**, which the first loader silently rejected (fixed to read like its siblings), and a
      first attempt at the Esc leg raced its own `swift` compile so the key landed before the count.

- [x] M18-T5 **A region pick can be adjusted.** **Rulings (Franco, 2026-07-28):** the drag snaps
      **magnetically** within ~6 pt and the badge says `· snapped` (a modifier-held snap only helps
      people who know it exists, and this is for the ones missing 1920×1080 by four pixels); the
      standard sizes are **1920×1080, 1280×720, 3840×2160, 1080×1080**, compared in pixels.
      **Two premises measured before building, both cheap:** the SCK↔view coordinate flip is **its
      own inverse**, so seeding the overlay is the shipped function applied twice — no new geometry;
      and the overlay is **already a key window with a live `keyDown`**, so arrows are a new `case`,
      not a new mechanism. **As built:** `present(seededWith:)` draws the stored pick (only when it
      belongs to this display and still fits — a stale rect starts empty rather than off-screen),
      arrows nudge 1 pt / ⇧ 10, ⌥+arrows resize from the far edge, all clamped to the display and to
      M11-T1's floor; the pure arithmetic lives beside `sckRect`/`badgeText` in `RegionSelection`.
      Keys never snap, so a deliberately odd size stays reachable.
      **Verified live on the deployed build:** the overlay re-opened with the previous rectangle
      drawn (`800 × 500 pt · 1600 × 1000 px`); two ⇧→ moved it 100 → **120** with the size untouched;
      ⌥⇧→ and ⌥⇧↑ gave **810 × 510** (the persisted SCK `y` moving 100 → 90 is right — it is the top
      edge, and the rect grew upward); Esc discarded an adjustment; a 956 × 543 drag snapped to
      **`960 × 540 pt · 1920 × 1080 px · snapped`**; and the adjusted region recorded **1620 × 1020
      px**, so M11's gate is unaffected. 530 tests (+5). ⚠️ The first deploy of this task was
      **stale despite reporting success** — the badge lacked its new suffix until a second
      `swift build -c release` + `bundle.sh` + `ditto`; re-run the leg, don't assume the deploy took.

- [x] M18-T6 **The Settings window is too tall to fit.** (Franco flagged it when M18-T2's MP4
      section pushed the window past the screen.) **Measured on the running app: 420 × 1137 pt
      against 1260 pt of usable screen — 90%**, and as one `Form` with `.fixedSize()` it had no
      ceiling; on a 13-inch Air it would run ~200 pt off the bottom with no scroll view to save it.
      **Rulings (Franco, 2026-07-28):** four tabs, and the version stays in General (the default
      tab). **As built:** four `Form`s behind a segmented control — **General** (folder, launch at
      login, the two menu-bar toggles, the version) · **Recording** (quality, frame rate, count-in,
      the two global shortcuts) · **Instant Replay** (unchanged) · **Sharing** (MP4 + GIF). The split
      isn't alphabetical: Recording collects what changes what a take *is*.
      ⚠️ **`TabView` was the wrong mechanism and only a screenshot said so** — at this width SwiftUI
      collapsed all four toolbar tabs into a `»` overflow menu, hiding three pages behind a chevron
      (Franco saw it before I did). A `Picker(.segmented)` over a `Page` enum can't collapse.
      **Verified live, per tab:** General 292 pt · Recording 289 · Instant Replay 372 · **Sharing 437**
      (the tallest), every row present and in its intended tab, and a picker driven on Sharing
      round-tripped (`gifFPS` 15 → 20 → 15). **1137 → 437 pt, 90% → 35% of the usable screen.**
      530 tests unchanged — layout only: no binding, key or `AppState` property moved.

**Gate G18** ⚠️ **first criterion amended 2026-07-28 (M18-T1's measurement):** a lossless trim was
never cutting early — the export writes an edit list and playback starts exactly at the in-point —
so "states the cut point it will actually make" was written on a false premise. The criterion is now
**a trim states what it keeps that you didn't ask for, and a re-encoding trim's file holds only the
kept range**. The rest stands: an MP4 export honours a chosen size; the idle menu is materially
shorter with every action still reachable and no slower to open; the count-in is cancellable; a
region pick can be adjusted rather than redrawn. No capture-path change anywhere in the milestone.

**Non-goals (M18):** a timeline editor, multi-clip, or anything needing the render/compositing stage
(ADR-015 — trim and transcode only); frame-accurate scrubbing UI; re-opening the `.menu` MenuBarExtra
for styling the bridge won't carry (docs/06 "Menu text styling").

## M19 — The disk tells the truth (from the 2026-07-28 review, findings A1, P2, P3, P4)

The 2 GB fail-stop floor **has never been able to see the disk filling** (A1, measured), nothing ever
prunes `~/Movies` where one take is 5.5 GB, and a picked window's title is written to preferences in
plaintext. Everything here is about the app being straight with you regarding disk and privacy.
**PATCH** (ADR-013): with T2/T3 closed "won't do" the milestone adds no user-facing capability —
a safety fix, clearer picker labels, and a preference that stops being written.

- [x] M19-T1 **The disk guard can see the disk filling.** ✅ 2026-07-28 — `availableBytes(
      forVolumeAtPath:)` builds its `URL` per poll, so no caller can hold one; `AppState`'s room
      figure routes through it too (ruling C). Live A/B at the real 2 GB floor: 60 s
      `userStopped` before → `diskAlmostFull` at 15.3 s + playable 14.89 s file after (docs/07).
      **Ruling A: the hook stays, demoted** — 04 §4.4 now rests on the falling-volume leg.
- [x] ~~M19-T2 **The recordings folder has a ceiling.**~~ — **CLOSED "won't do" 2026-07-28
      (Franco): the app does not delete the user's files.** The plan artifact
      (`claude.ai/code/artifact/1fb4f5fa-a182-485f-a929-ef11730eed67`) proposed a GB cap swept after
      finalize, Trash-only, restricted to ScreenRec's own file names — that restriction came from
      inventorying the real `~/Movies`, which holds **two clips Franco made himself and they are the
      oldest files in it**, so the obvious "trash the oldest `.mov`s" would have taken those first.
      Ruled out at the plan gate anyway: an unattended deleter is not something this product wants,
      whatever its safety rules. Cleaning up stays the user's job in Finder. Don't re-file it without
      a new reason; the 5.5-GB-per-take fact is unchanged and is stated by M18-T4's "Room for about
      N" row.
- [x] ~~M19-T3 **Delete the original when the export lands.**~~ — **CLOSED "won't do" 2026-07-28
      (Franco)**, with M19-T2 and for the same reason: the app deleting a recording is out, whether
      it is a background policy or a per-export offer. An export leaves its source alone.
- [x] M19-T4 **MP4 sizes named by destination, not by pixels.** ✅ 2026-07-28 — each row states what
      a minute weighs (`1920 px · ≈46 MB per minute`), which is what decides between picks that all
      play anywhere; **`1280 px` was dropped**, measured to weigh 1% *more* than 1920 for 2.25×
      fewer pixels (the M18-T2 rate floor). Live: the deployed picker reads the new row and a menu
      export landed at **45.1 MB/min** against its promised ≈46. Destination words were ruled out —
      they promise an acceptance that clip length governs (docs/07, docs/06).
- [x] M19-T5 **A window pick stops storing its title.** ✅ 2026-07-28 — `WindowSelection` is
      identity only (`id` + `bundleID`); the plist entry has exactly those two keys, and a legacy
      `title` is ignored on load and erased by the next save. A gone pick reads **`Firefox
      (closed)`** in both the row and the `Source:` header (rulings A + B), since without the
      marker it would read like an app-scoped pick. 🔴 **The probe found a live bug too:** the menu
      tags rows with the selection, so a *retitled* window stopped matching its own row and lost its
      checkmark — dropping the field fixes it. Live: pick → plist `{bundleID, id}` only, folder
      renamed → `✓ Finder — T5-after` still marked, window closed → `✓ Finder (closed)` + Start
      failed loud.


**Gate G19** (amended 2026-07-28, T2/T3 closed "won't do"): a recording running on a volume that
fills **during the take** stops itself with `diskAlmostFull` and leaves a playable file (not just
one that started below the floor); no window title appears in the preferences plist; the MP4 picker
names what its sizes are for.

## M20 — Marks — **CLOSED "won't do" 2026-07-28 (Franco)**

🔴 **The feature is discarded, and the reason is a measurement worth keeping.** Marks were only
useful if they reached the Trim window (Franco: "markers are good to have mostly for trimming the
recording"), and every route to getting them there costs more than the feature returns:

- **A chapter track written live (option a)** — implemented, then rejected. It works in isolation:
  a fragmented `.mov` with a text track associated `chapterList` finalizes cleanly, and QuickTime
  and ffmpeg both read the chapters back. 🔴 **But it silently disables fragmentation.**
  `AVAssetWriter` emits a fragment only when *every* input has data up to the boundary, so a text
  track fed once per mark — or never — starves it. **Measured mid-write, which is the only state a
  crash sees: no track → 3 fragments · track never marked → 0 · track + one mark → 0.** End to end
  through the app: two takes, same build, same `kill -9`, marks off recovered as a **playable
  10.99 s file** and marks on was **unreadable** ("moov atom not found"). That is the exact loss
  ADR-007 exists to prevent, on a path where a 40-minute take is at stake.
- **Movie metadata written at finalize** — impossible: `AVAssetWriter.setMetadata` throws once
  writing has started ("Cannot call method when status is 1"), so it must be fixed before the first
  frame, when no marks exist.
- **A sidecar `.json` (option b)** — works and is crash-safe, **rejected by Franco**: a companion
  file beside every recording isn't worth it, and it orphans on any Finder move or rename.
- **Post-hoc atom surgery** on the finished file — hand-rolled MP4 rewriting on the user's only
  copy of a multi-GB take. Not entertained.

**M20-T1 (the ⌥⌘M shortcut) shipped and was then reverted** — without persistence it left nothing
behind, and this repo doesn't keep scaffolding. The measurements live in `docs/07`; the
fragment-starvation one is a trap for **anything** that ever adds a track to `MovieRecorder`.

- [x] ~~M20-T1 **Mark the moment.**~~ — built, shipped, reverted with the milestone.
- [x] ~~M20-T2 **Marks survive the file.**~~ — the task that killed the feature; see above.
- [x] ~~M20-T3 **The Trim window seeks between marks.**~~ — nothing to seek between.

**Gate G20**: n/a — closed unbuilt.

## M21 — One step from "it happened" to "here it is" (from the 2026-07-28 review, P1, P5, F2, F3)

The app has every piece of the sharing workflow and none of the joins: trim writes a `.mov`, export
writes an `.mp4` from it, and the intermediate is the file nobody wants — while the ffmpeg recipe
this replaced did both in one command. **MINOR.**

- [x] M21-T1 **Trim exports directly.** ✅ 2026-07-29 — the Trim window's **Export as MP4** writes the
      chosen range straight to a shareable `.mp4`, no intermediate `.mov`; `Trim & Save` keeps Return
      (ADR-015), output is `<take> trimmed.mp4`. **562 tests.**
      The range rides **`AVAssetReader.timeRange`**, not `AVAssetExportSession` — the export must stay
      a reader/writer pipeline for its one mixed AAC track, size fit and faststart.
      **Measured, and it settled the design:** a ranged read clips exactly at the in-point (first PTS
      30.000 with the preceding keyframe 1.900 s back, audio the same), so no retiming and none of the
      lossless trim's lead-in caveat. Verified on a clip that burns its timestamp into every frame —
      first frame reads `27.30 s`, PSNR 52.4 dB there vs 8.8 dB at the keyframe (a real recording
      scored ~38 dB against every candidate, so it could not have failed).
      🔴 A fast export can strand `AVAssetWriter`'s `.sb-` temp (1 in 5 runs) — swept after finalize,
      since "no intermediate file" is the point (docs/07).
- [x] M21-T2 **Stop &amp; Share** — shipped as **`Stop & Copy MP4`**. ✅ 2026-07-29 — one row stops the
      take, exports at the Settings size and leaves the `.mp4` on the pasteboard; one notice, not two.
      **566 tests.**
      **Rulings:** *not* "Stop & Share" (`Share…` means the macOS share sheet everywhere else here);
      beside `Stop & Save`, which keeps ⌥⌘R; disabled while an export runs, under the `Exporting …`
      row that says why (M17-T2); no length limit, but the row states the cost.
      **Verified live:** 2.0 s from press to a pasteboard `.mp4` (avc1 1920×1200 + one AAC, 15.47 s),
      the `.mov` master untouched.
      🔴 The live leg caught the cost estimate lying — `≈11 MB` quoted, 2.2 MB written, because the
      rate budget over-quotes a quiet screen ~5× (docs/07). The row says **`up to`** now.
- [x] M21-T3 **Name the take.** ✅ 2026-07-29 — an opt-in prompt (Settings → Recording, off by
      default) the moment a take stops, feeding M12-T2's `rename`. **570 tests.**
      **Rulings:** the prompt, not a Settings prefix (a prefix groups, it can't say what *this* take
      was); off by default; Esc, Cancel, a blank or unchanged name all keep the date name.
      **Two orderings carry it:** *after* teardown, so a dialog left open can't delay re-arming
      replay; *before* the share export, so `Stop & Copy MP4` copies the **named** `.mp4`.
      🔴 The quality pass caught the second one broken — the share path looked the take up by its
      pre-rename URL and would have exported nothing. `lastRecording` (named `lastFinishedRecording`
      until M24-T3) records where it landed.
      **Verified live:** named → `Bug-1204 repro.mov` with the recents row agreeing; Esc → the date
      name kept; named + Stop & Copy MP4 → both files, receipt and pasteboard carrying the name.
- [x] M21-T4 **Leave an app's audio out** — shipped as **`Source ▸ Everything Except ▸`**.
      ✅ 2026-07-30 — the whole screen minus one app, `Entire Screen except Slack` with a dimmed
      `Slack won't be seen or heard` row. **576 tests.**
      ⚠️ **The premise moved under measurement** (docs/02 §1a-ii): SCK's exclusion is not audio-only —
      it removes the app's picture too — and it cannot touch an app with nothing on screen, which is
      the background-music case this task was filed for. Shipped as what it is; the audio-only route
      (Core Audio process taps) is parked as its own future milestone.
      **Verified twice:** raw SCK −9.1 → **−∞ dBFS** (buffers still flowing, so silent not stalled),
      the app's window present in one frame and absent in the other; then the shipped path,
      `record --exclude-app` → −∞ dBFS against a −8.3 dBFS control, and the same menu-driven.
      🔴 **The honesty path is measured, not assumed:** with the app minimised the take ran, the menu
      read *"The app to leave out wasn't on screen — nothing was excluded."*, and the file's system
      audio came back at −9.0 dBFS. A new `EngineEvent.excludedAppUnavailable` carries it — degraded,
      never silent (ADR-007). An excluded app quitting mid-take is a non-event, so no
      `AppTerminationWatch`: the `.app` precedent doesn't transfer.
      ⚠️ The mic still hears an excluded app through the speakers (−35.2 dBFS while system audio was
      −∞) — docs/07.

**Gate G21** ✅ **PASSED 2026-07-30** (evidence in STATUS): a recording goes from Stop to a
pasteboard-ready `.mp4` in one action, with no intermediate file left behind; a named take carries
that name through file, recents row and receipt; an excluded app's audio is measurably absent while
the rest of the system's audio is present.

## M22 — Structure (from the 2026-07-28 review, findings A2, A3, A4, A6)

No user-visible change: the milestone that keeps the next four cheap. **PATCH** (ADR-013).

- [x] M22-T1 **`AppState` sheds its sources.** ✅ 2026-07-28 — `SourcesModel` (288 lines,
      `@Observable` **class** per M15-T2) owns the lists, the four picks, `sourceChoice`, the
      missing-pick rows, the labels and the pick's geometry; `AppState` forwards, so **557 tests
      passed untouched** and the deployed menu dumped identical (the only diff was a live Slack
      window retitling itself). Persistence and the armed-stream rebuild come back through two
      injected closures — the display pick fires only the rebuild, since it isn't persisted.
      **1,568 → 1,391 lines (11%), not the ~1,290 I predicted** — the forwarding surface costs more
      than estimated; the win is the seam, not the number. Live: a menu-driven recording is
      4112×2570 hvc1 + 2 audio tracks. ⚠️ **The `// MARK: - Sources` section was mis-filed** —
      quality, frame rate, both menu-bar toggles, GIF/MP4 and Stop-After all lived under it and are
      *settings*; they stayed, under a new `// MARK: - Settings`. `regionLabel` moved with the model
      (3 call sites renamed). **Ruling A: the microphone stayed** — its presentation is entangled
      with the session's live mic events, so it belongs to T2's question.
- [x] M22-T2 **`AppState` sheds the session.** ✅ 2026-07-28 — `SessionModel` (187 lines) owns the
      capture handle, the counters, the clock, the `active*` facts and the fold; **the actions
      stayed**, because `start()` needs the count-in, permissions, the output location and replay,
      and moving that would relocate the tangle rather than cut it. **557 tests passed untouched**;
      1,391 → **1,288 lines**. **Ruling A: `lastFailure` stays on `AppState`** — it is set before
      any session exists (M17-T2) — and the fold reports through a `reportFailure(message,
      outlivesSession:)` closure, so the policy stays where the state is. **Ruling B:**
      `activeMicrophoneName` moved and `resolvedMicrophone()` now *returns* the name, since it runs
      before a session exists; the mic **pick** stayed. 🔴 **Two guards silently inverted** when
      `session` stopped being optional (`session == nil` on a non-optional, and `session != nil ||
      isReplayArmed`) — the suite caught both, which is exactly what "tests pass untouched" is for.
      **Live:** menu dump identical, and a Start → Pause → Resume → Stop cycle froze the clock at
      `00:00:06` across three seconds, resumed to `00:00:10`, and wrote an 11.90 s 3-track file.
- [x] M22-T3 **Six units get a test that names them.** ✅ 2026-07-28 — six suites, **557 tests
      (+17)**, each verified by **breaking its unit and watching the test fail**: `WriterDrain`
      (never leave the group → the deadlock, caught by a bounded `wait`), `SampleTiming` (drop the
      duration override), `PCMSampleBuffer` (ignore `fill`'s failure), `Polling` (swallow
      cancellation), `MediaFile` (never read a duration), `VideoFrameReader` (drop the fps gate).
      🔴 **The mutation pass earned its keep on `Polling`:** the first version of that test *passed*
      against broken code — swallowing cancellation costs exactly one extra tick and the assertion
      tolerated one. Rewritten to check a window shorter than the interval (docs/07).
      `VideoFrameReader`'s subsample test needs the encoder, so it is gated and **added to both the
      pre-push hook and `release.sh`** — a gated test nothing runs is not a test.
- [x] M22-T4 **One timecode, one hotkey registry.** ✅ 2026-07-28 — `Timecode.cutPoint` (floored,
      a point you can cut at) · `.clock` (`HH:MM:SS`, truncated, NaN-safe) · `.length` (rounded, a
      finished thing's label) in `RecorderCore/Support`, replacing five renderers with three
      roundings across two modules; the rounding lives in the **name**, since a style parameter
      invites a default and a default is how the next caller picks the wrong rule. `HotkeyID: UInt32`
      now types `setHotkey`, so the four ids can't collide — **duplicate raw values don't compile**,
      which is the guarantee. ⚠️ **Correction to the entry below: the `In 0:05` / `0:04` bug was
      already fixed** by M18-T1 (both surfaces call the same renderer); what remained was the
      condition (M20's mark list would have been the sixth caller, before that milestone closed). **Verify:** 540 tests, the 14
      pinned strings moved to `TimecodeTests` unchanged, and the deployed menu dumps **byte-identical**
      before/after (90 rows; the only diff was a live Slack window retitling between dumps).
- [x] M22-T5 **`release.sh` can push.** ✅ 2026-07-28 — **no terminal ⇒ push**, announced in the
      output, with `--no-push` to opt out; an interactive run keeps its `[y/N]` prompt unchanged.
      A `--push` flag was rejected: same failure mode as today, since you have to remember it.
      Verified five ways through the shipped block (no-TTY, no-TTY + `--no-push`, pty + `y`, pty +
      `n`, pty + Return, plus a bad flag → usage/64).
- [x] M22-T6 **A tag carries a downloadable build.** ✅ 2026-07-28 — `publish_release` zips the
      signed bundle with `ditto` and creates the GitHub release; a `gh` failure **warns** with the
      re-run command instead of failing a cut whose irreversible half (main + tag) is already
      pushed. Notes lead with the three-step Gatekeeper install, then `git log` for the range.
      **Verified against the real `v1.10.1`** by sourcing the shipped functions:
      `ScreenRec-1.10.1.zip` (992,374 B) attached, downloaded back, quarantined, and after
      `ditto -x -k` the app **inherits the quarantine** and still reads **`valid on disk` ·
      `satisfies its Designated Requirement`** (`spctl` rejects it, `origin=screenrec-dev` — exactly
      what the install note is for).


**Gate G22**: `AppState` is materially smaller with the menu dump unchanged; the six units are named
by tests that can fail; one timecode type serves every surface; a background release pushes without
a human and leaves a downloadable, still-signed build behind it. No behaviour change anywhere — the
whole suite passes untouched at every step.

## M23 — The write path tells the truth (from the 2026-07-30 review)

The recorder never checks whether its writes land, exports never check whether they fit, and work in
flight is invisible from the menu bar. M16's thesis — the state stops lying — applied to the three
places it hasn't been. **PATCH** (ADR-013): no new capability, unless T3's signal turns into a real
affordance.

- [x] M23-T1 **The writer says when it fails.** `MovieRecorder.append` discards
      `input.append(retimed)`'s `Bool`, and nothing watches `writer.status` during a session — the
      poll checks free space, not the writer. Once an `AVAssetWriter` goes `.failed` every append
      no-ops silently and the icon, the clock and the byte counter all keep claiming a recording; the
      user learns at Stop, which on a long take is up to forty minutes late. This is M19-T1's shape:
      a mechanism that cannot see the thing it exists to catch. **Seams:** the discarded result at
      `MovieRecorder.swift:235`; `EndReason` already carries the fail-stop vocabulary the disk guard
      uses (ADR-007: a fail-stop is a success with a cause); `ReplayMuxer` line 277 discards the same
      call and takes the same rule. ⚠️ `isReadyForMoreMediaData` is checked *before* the append, so a
      `false` return here is a real failure, not backpressure. **Rulings:** a new `EndReason` case
      (`.writeFailed`) versus reusing `.streamError`; and whether one refused append ends the session
      or it confirms against `writer.status` first. **Verify:** a *real* failure, M19-T1's standard —
      a volume that goes away mid-take, not a mock — leaving `finished(<cause>)` and a playable file
      holding everything written up to the failure; plus a unit test over the decision.
- [x] M23-T2 **An export checks that it fits, and quitting says what's in flight.** A recording stops
      itself at the 2 GB floor; an export has no check at all and writes ≈46 MB/min (the Size
      picker's own figure), so a 40-minute take is ~1.8 GB and a full disk surfaces as "check the
      output folder is writable" — the wrong sentence. Separately `applicationShouldTerminate` waits
      for a *recording* to finalize but not for an export: quit during one and the task dies with the
      process. Nothing is corrupted (the `.partial` discipline holds) but the work is gone silently,
      and with Stop & Copy MP4 the clipboard simply never arrives. **Seams:**
      `DiskSpaceMonitor.availableBytes` + `ExportConfiguration.bytesPerMinute` (the estimate already
      exists and is honest about being a ceiling); `ExportModel.performExport`'s one entry point;
      `AppDelegate.applicationShouldTerminate`. **Rulings:** refuse-before-start versus stop-midway
      (a recording can't know its length, an export can, so refusing up front is the honest shape);
      and what quit does — wait, warn, or cancel and say so. **Verify:** a small volume + a long
      export → refused before writing, with the reason naming the disk; quit mid-export → the chosen
      behaviour, observed.
- [x] M23-T3 **Work in flight is visible without opening the menu.** `StatusIcon` has three states —
      idle, recording, paused — so a multi-minute export is invisible; the menu's `Exporting …` row
      is stamped at open and never updates (the `.menu` bridge, M6-T10). And because banners are
      suppressed while replay is armed (M9-T2), **stopping a recording while armed is completely
      silent**: no banner, no receipt row, no flash — while a replay *save* gets all three.
      **Seams:** `StatusIconView` already composites the clock and the level meter into the icon
      image, so a fourth state is a drawing change, not an architecture one; `replaySavedFlash` is
      the badge shape; `exportInProgress` is the state to read. **Rulings:** a fourth icon state
      versus a small badge; whether a finished take flashes always or only when banners are
      suppressed. **Verify:** pixel-diff the rendered states (M16-T5's method), and the armed-then-stop
      case observed live.
- [x] M23-T4 **`SessionModel` and `ExportModel` get tests that name them.** The two models M22
      extracted are the two units nothing tests by name — exercised only through `AppState`, which is
      how "557 tests passed untouched" was achieved and is a real property worth keeping, but M22-T3's
      own standard was a test per unit that can fail. **Seams:** both are `@Observable` `@MainActor`
      classes with injected closures; no capture hardware needed. **Verify:** the M22-T3 standard —
      break each unit, watch its test fail (the fold's clock/icon transitions; the one-at-a-time
      guard and receipt policy).
- [x] M23-T5 **Collapse `AppState`'s forwarding layer.** ✅ Done 2026-07-30: **130 → 95 public
      members, 1,420 → 1,355 lines**, verified to M22's bar. ⚠️ **The follow-on extractions named
      below were measured and the figures here are wrong** — replay is **143** lines in `AppState`,
      not 360; the self-test **35**, not 188. 178 total, not 548, and extracting replay would inject
      a larger surface than it moves (docs/07). Not done, and not worth filing again on these
      numbers. *Optional, and last.* M22 cut `AppState`
      1,572 → 1,288 keeping 18 forwarding properties so no view or test had to move; one feature
      milestone put it back to **1,382 / 127 public members**, because every feature now pays twice —
      once in the sub-model, once in the forward. The scaffolding did its job. **Seams:** the
      sub-models are already `public`, so views can read `state.sources.selectedDisplayID` directly;
      the change is mechanical and the compiler finds every site. The replay cluster (360 lines in
      `AppState` on top of a 354-line `ReplayController`) and the self-test (188) are the next
      extractions if this is worth continuing. **Rulings:** whether to do it at all now, or leave it
      until a feature milestone touches those files anyway. **Verify:** tests and the deployed menu
      dump unchanged — M22's own bar.

**Gate G23** — ✅ **PASSED 2026-07-30** (evidence in STATUS.md's gate table): a recording that cannot
be written stops itself with a stated cause and keeps what it wrote; an export that cannot fit refuses
before it starts and names the disk; an export in flight is visible without opening the menu, and a
take that stops while replay is armed is never silent; both extracted models have tests that fail when
their logic is broken.

## M24 — Finish the share loop (from the 2026-07-30 review)

M21 made "it happened → here it is" one action from the menu. It is still not one action from the
keyboard, and the window whose whole job is producing a shareable clip is the one place that won't
hand it to you. **MINOR.**

- [x] M24-T1 **The Trim window hands you the clip.** `Export as MP4` writes the ranged `.mp4` and
      leaves you to find it: back to the menu, into the receipt row, `Copy`. Stop & Copy MP4 already
      proves the ending. **Seams:** `ExportModel.exportAndCopy` and `ExportRange` both exist — this is
      the two of them meeting; `TrimView`'s button row. **Rulings taken** (Franco, 2026-07-31): one
      button, renamed **`Export & Copy`**, over an `Export` / `Export & Copy` pair — the row has
      39.5 pt of slack and a fourth button needs ~112 pt (docs/07), and the title names the copy
      because the clipboard is taken either way; and the notice is M21-T2's **`Copied — ⌘V to paste`**
      reused, one notice rather than a receipt plus a copy. **Verify:** live — set a range, one press,
      ⌘V pastes the clip.
- [x] M24-T2 **Stop and copy from the keyboard.** The start/stop shortcut stops *and saves* a `.mov`,
      so the keyboard path stops one step short of the thing you wanted; the menu is still required
      for the last move. **Seams:** `HotkeyID` has been a typed registry since M22-T4, so a second id
      is cheap; `AppState.stopAndShare()` is the action. **Rulings taken** (Franco, 2026-07-31): a
      **setting on the existing shortcut**, not a second combo — `When it stops: Save · Save and
      copy`, backed by `stopHotkeyCopies`, so **no new `HotkeyID` was needed**. `Save and copy` keeps
      the `.mov` too (ADR-004), so there is nothing to trade per-take; it costs no Settings height
      while the shortcut is off; and the menu's shortcut column moves to whichever Stop row the
      ending selects, so one combo with two meanings still can't lie. With an export already running
      it **still stops and saves**, then says so — stopping is the combo's primary contract, and a
      hotkey can't grey itself out (M17-T2's lesson). **Verify:** fired from another app; the file
      lands on the clipboard and one notice is posted.
- [x] M24-T3 **The take you just made is one click away.** A replay save gets a top-level receipt row
      *and* a menu-bar flash; the recording you just stopped gets neither — it is two levels down
      under `Recordings ▸`, identified by timestamp. **Seams:** `lastReplay`'s row and
      `replaySavedFlash` are the shapes to mirror; `RecentRecordings` already refreshes on finalize.
      **Rulings taken** (Franco, 2026-07-31): the receipt is **in memory only**, expiring at menu
      open on the export receipt's own one-hour clock (an export's receipt is persisted because it is
      that file's only pointer — a take already lives in `Recordings ▸`, so its row is prominence, not
      access), and it appears after **every** stop, not only when banners are suppressed. The flash
      ruling was **already answered by M23-T3** (`stopNeedsFlash`: armed only) and was left alone. **Verify:** stop with replay armed → the row
      and the flash both appear; clicking reveals the file.
- [x] M24-T4 **Find the moment without scrubbing blind.** The Trim window offers a 480×300 player,
      Set In/Set Out and nothing else: no filmstrip, no waveform, no frame stepping. docs/06 calls the
      window "spare by design" and that is right — but ←/→ and thumbnails are *navigation*, not
      editing, and finding 20 seconds in a 3-minute take is the step that costs the most. **Seams:**
      `VideoFrameReader` already extracts frames off the main thread; `AVPlayer.step(byCount:)` is the
      stepping primitive. **Rulings taken** (Franco, 2026-07-31): **16 thumbnails**
      (785 ms measured; 24 costs 1.8 s and is past the size a screen recording reads at), and
      **←/→ step one frame, ⇧←/⇧→ a second** — the strip covers travel, so the keys buy exactness.
      ⚠️ **Both stated seams were wrong.** `VideoFrameReader` reads sequentially from zero and cannot
      build a strip (`AVAssetImageGenerator` does); and `step(byCount:)` is on `AVPlayerItem`, not
      `AVPlayer`, *and* assumes a cadence frame-on-change capture doesn't have — measured, one step
      moved 0.25 s and landed 25 ms off any real frame, so stepping walks the sample table instead.
      ⚠️ **The budget's real driver is keyframe spacing, not take length**, so a 40-minute take costs
      what a two-minute one does at the same count (docs/07). **Verify:** measure strip build time on a
      long take; a step lands on the adjacent PTS (`probe`), not "looks right".
- [x] M24-T5 **An `.mp4` stays an `.mp4`.** `Trimmer.trimmedSibling` hard-codes `.mov`, so trimming
      the `.mp4` you just made for Slack hands back the container you were converting away from. The
      per-file submenu is generic too: it offers `Export as MP4` on an `.mp4` and `Save as GIF` on a
      GIF, quietly re-encoding something already encoded. **Seams:** `trimmedSibling`;
      `AVAssetExportSession.export(to:as:)` writes either container; `MenuView.fileActions`.
      **Rulings taken** (Franco, 2026-07-31): **hide** them, not disable — on a GIF they were never choices (AVFoundation can't read one: `isReadable false`, no tracks, duration `-1`, yet an export session is still *created*, which is why it never failed at the menu), and M18-T3 shortened this menu rather than annotating it. Also fixed, beyond the filed text: the `… trimmed trimmed` stutter found live in M24-T1. ⚠️ **The `.mov` was a hard-code and its comment was wrong** — passthrough reports `mpeg-4` among its supported types (docs/07). **Verify:** trim
      an `.mp4` → an `.mp4` out, probe clean; the submenu on an export no longer offers to re-derive it.

**Gate G24** — ✅ **PASSED 2026-07-31** (evidence in STATUS.md's gate table): from a finished take, a
chosen range reaches the clipboard in one action without the mouse; the take you just recorded is
actionable from the top of the menu; the Trim window can find a moment without blind scrubbing; and
deriving from an export never silently re-encodes it. ⚠️ **Criterion 1 failed on the first run** —
`Export & Copy` had no key equivalent, so the last press needed a click; ⌘↩ was added and it was
re-run. The keyboard criteria are human-only: `LSUIElement` plus synthetic input cannot confer
activation (docs/07).

## M25 — Swift 6 language mode (debt; encoded from the parked list 2026-07-31)

docs/01's concurrency rules — sample-path code uses locks not actors, never block an SCK callback
queue, no unbounded buffer retention — are held in agents' heads and checked by review. Swift 6 makes
the compiler check a real subset of them. **First, because it protects what follows:** M27 adds a
second audio clock into `SampleRouter`, the most concurrency-dense work on this list, and M22 set the
precedent of pulling the protective milestone ahead of the one it protects. **PATCH** — nothing here
is user-facing. ⚠️ **The bump is deliberately deferred (Franco, 2026-07-31): no v1.12.1.** With no
user-facing change there is nothing to download, so M25 rides into **M26's cut** instead. Do not
"correct" this by tagging a patch release after the fact. `Package.swift` is already tools-version 6.0 with every target pinned to v5, so this
is a per-target flip, not a migration.

- [x] M25-T1 **`RecorderCore` compiles in v6.** **7 distinct sites, measured 2026-07-31:** the
      `SCShareableContent.forCapture()` hop (`CaptureEngine.swift:125`); two static non-`Sendable`
      globals — `ByteCountFormatter` (`ApproximateBytes.swift:20`) and `AVAudioFormat`
      (`ResampledMicInput.swift:20`); and four non-`Sendable` captures in the export plans
      (`Exporter.swift:233`, `Exporter.swift:411`, `GifExporter.swift:84`,
      `FilmstripThumbnails.swift:58`). **Rulings:** per site, whether the fix is
      `nonisolated(unsafe)` (defensible for an immutable, thread-safe formatter), a real isolation
      change, or a redesign — "make the error go away" is the failure mode here, and a blanket
      `@unchecked Sendable` would buy the flip while spending the point of it. **Verify:** the target
      at v6, dev loop green, **no behaviour change**, plus one real capture — the sample path is what
      this protects.
      ✅ **Done 2026-07-31 — and the 7 was a floor.** Fixing the first batch revealed **5 more**
      (1 in `MicrophoneRescue`, 4 `SCStream` sites in `CaptureEngine`): **12 sites, 8 edits**. The
      compiler stops after the first batch, so each fix unblocks the next wave (docs/07).
      **Rulings taken** (Franco, 2026-07-31): `@preconcurrency import ScreenCaptureKit` in
      `CaptureEngine` — SCK carries no `Sendable` annotations at all, so this is one true statement
      rather than escape hatches scattered through the capture path, and **our own types stay
      checked**. `nonisolated(unsafe)` for the three confined export workers and the immutable
      `AVAudioFormat`; **not** for `ByteCountFormatter`, which is built per call instead because its
      thread-safety is undocumented. `Exporter:411` was a genuine over-capture and got a real fix;
      `MicrophoneRescue` took `sending`, which needs no import concession. **No test was edited** —
      that was the claim, and it held (660 green).
- [x] M25-T2 **`AppCore` compiles in v6.** **At least 5 distinct sites** — ⚠️ a floor, not a total:
      T1's measured 7 became 12 as each fix unblocked the next wave. Clustered on the replay-save
      completion closure (`AppState.swift:641–647`) capturing non-`Sendable` state across a callback.
      **Seams:** `ReplayController`'s completion; `AppState`'s `@MainActor` isolation. **Verify:** as
      T1.
      ✅ **Done 2026-07-31 — and it was 5 mechanical lines with two structural surprises.** The
      cluster is a **double `[weak self]`** (outer closure *and* inner `Task`), which defeats Swift
      6's implicit-self rebinding; both captures were kept — the inner one stops the Task extending
      `AppState`'s lifetime across the hop — and made explicit. 🔴 **`AppCore` cannot flip without
      `AppCoreTests`:** v6 mangles `@MainActor` into closure-property types, so the v5 test target
      fails to *link* (`symbol(s) not found`, reported as a bare `error: fatalError`). 🔴 That flip
      then breaks **`@Test(arguments:)` on a `@MainActor` suite** — five declarations — fixed with
      `nonisolated` on the shared `endReasons` fixture. **Ruling (Franco, 2026-07-31): the test edit
      is fine** — it is an isolation keyword, changing no assertion and no fixture value, and T3
      would have needed it regardless. ⚠️ So M25-T1's "no test edited" property **does not carry
      forward**, by necessity rather than choice. Verified live: a real replay save rendered
      `Replay saved · 27 s`, which is exactly the closure that changed.
- [x] M25-T3 **The rest, and the escape hatch goes.** `ScreenRecApp`, `screenrec-cli` and
      `RecorderCoreTests` are **unmeasured** (`AppCoreTests` flipped with `AppCore` in T2, of
      necessity — see above) — `swift build` stops at the first failing target, so they have
      never been compiled at v6 at all. Measure, fix, then **delete `.swiftLanguageMode(.v5)` from
      `Package.swift` entirely**, so a later target cannot be added at v5 silently. **Verify:** no
      `.v5` remains anywhere; dev loop green; a deployed build records, replays and exports.

**Gate G25** — ✅ **PASSED 2026-07-31** (evidence in STATUS.md's gate table). ⚠️ **Criterion amended 2026-07-31 (Franco), before being run.** As filed it required
*no `.v5` left in `Package.swift`*. One remains, deliberately: `RecorderCoreTests`, whose conversion
would rewrite three bounded waits that exist so a stuck drain fails rather than hangs (docs/07). The
gate now reads: **every target that ships builds and tests in Swift 6** — `RecorderCore`, `AppCore`,
`ScreenRecApp`, `screenrec-cli` and `AppCoreTests` — **the single remaining `.v5` is documented in
`Package.swift` as a decision**, and a real recording, replay and export still work. The point is
unchanged: nothing changed except who checks the rules. ⚠️ Recorded here rather than quietly passed
against a criterion that moved.

## M26 — Crop on export (from the parked list; **ADR-015 amended**, Franco 2026-07-31)

Franco crops recordings by hand today. The recipe exists because `cropdetect` fails on letterboxed
stream captures: the bars are **luma 62–66**, not black, so a black-threshold detector finds none.
Region capture does not help — it crops what you record yourself, not a window that arrives
letterboxed. **MINOR.**

**Ruling (Franco, 2026-07-31): crop is in scope.** ADR-015 admits "trim and format export" and rules
out the render/compositing stage; crop sat between them, and this decides it. The reasoning: the
export path **already scales every frame**, so a source rectangle is an argument to work that happens
anyway — not a new pipeline. ADR-015's line does not move: composite, animate, auto-zoom and padded
backgrounds all stay out. Amendment recorded in docs/05.

- [x] M26-T1 **The exporter takes a source rect.** **Seams:** `Exporter.exportToMP4`'s existing
      `fittedSize` scaling and its `AVVideoComposition`; `ExportConfiguration`, where the width cap
      already lives; `screenrec-cli export --to-mp4`, so this half is verifiable headlessly.
      **Rulings:** whether the rect is source **pixels** or a normalised **fraction** — a fraction
      survives a source of a different size, pixels are what a person reads off `probe`; and whether
      the Size cap then applies to the *cropped* rect (it must, or the picker's "≈46 MB per minute"
      starts lying). **Verify:** CLI crop → `probe` shows the cropped dimensions and the aspect
      follows; the source is untouched; `mdls` confirms the container is unchanged (M24-T5).
      ✅ **Done 2026-07-31. Rulings taken (Franco): source pixels, and the cap measures the crop.**
      🔴 **The seam named above does not exist:** the MP4 path has no `AVVideoComposition` — it
      declares a smaller size on the writer input and the *encoder* scales. The composition is
      `VideoFrameReader`'s (the GIF path), and it carries: `420v` accepted, one frame per source
      frame, top-left origin, crop+fit in one transform (all measured before implementing, docs/07).
      **A crop composites; an uncropped export reads exactly the code it always did.** Three smaller
      calls: an out-of-bounds crop is **refused, not clamped** (`ExportError.cropOutOfBounds`); crop
      dimensions round **down** to even so the fit never upscales; and a cropped export keeps today's
      file naming, with a " cropped" suffix left to T2. **664 tests** (+4 pure, +1 gated encode).
      Verified on a real 4112×2570 take: crop → `avc1` 1600×1000; crop + `--width 1280` →
      **1280×782**, the *crop's* aspect; an out-of-bounds crop refused with **no `.mp4`, no
      `.partial`, no `.sb-`**; the uncropped control still 1920×1200; `public.mpeg-4`; source md5
      unchanged. **The pixels are the rect asked for** — 0.36% differ from the same rect cut out of a
      source frame (tolerance 6) against **29.86% at delta 255** for the bottom-left reading, the
      control without which a plausible-looking wrong crop would have passed.
- [x] M26-T2 **A crop rectangle in the Trim window.** The window already has the player, the range
      and the export button, and since M24-T1 `Export & Copy` already carries a range — the rect
      rides the same way. **Seams:** `TrimView`'s player overlay (the filmstrip's `SpatialTapGesture`
      is the drag precedent); `ExportRange`'s shape. **Rulings:** drag-to-draw, numeric fields, or
      both; whether a crop persists between opens (the range does not); and what the caption
      promises, since M16-T2's rule is that a figure you cannot compute yet is omitted, not guessed.
      **Verify:** live — crop, export, and the file matches what the window said it would produce.
      ✅ **Built 2026-07-31; the live leg is Franco's** (an agent cannot drag inside this app —
      docs/07). **Rulings taken:** drag to draw with a live read-out and `Reset`, no numeric fields;
      **no persistence** between opens; the caption quotes the **cropped** size live; and
      **`Trim & Save` is disabled while a crop is set** and says why — a trim is an
      `AVAssetExportSession` and has no crop, so the button could only ignore one. ⚠️ **Crop had to be
      a mode:** `AVPlayerView`'s inline transport controls sit under any always-on overlay, so the
      toggle is off by default and the window is unchanged until it is asked for; while cropping, the
      playhead still moves by ←/→, ⇧←/⇧→ and the filmstrip. **The risky part is pure and tested:**
      `CropGeometry` maps a drag inside a letterboxed preview to source pixels — **6 tests**
      including a round-trip and the drag-in-any-direction case — because that is where an
      off-by-a-scale-factor bug would live. The crop is held **in source pixels** and converted back
      for drawing, never the reverse. `crop:` is threaded through `AppState.exportAndCopy` →
      `ExportModel` → `Exporter`, and into `mp4Bytes` so M23-T2's disk guard weighs the **cropped**
      size instead of refusing a cropped export that fits. **671 tests.** `VERSION` → **1.13.0**,
      carrying M25's deferred patch.
      ✅ **Live leg PASSED (Franco, 2026-07-31), which is the only way this task could be verified.**
      Two real takes off a 4112 × 2570 source: `avc1` **1920 × 812**, and then **57.21 s of 129.11 s
      at 1920 × 1030** — a range and a crop in one encode. Both heights follow the *crop's* aspect,
      not the source's (an uncropped export of that take is 1920 × 1200), so the cap measured the
      crop. **The caption matched the file — confirmed by Franco**, which is the criterion the task
      was filed on. Source untouched, `public.mpeg-4`, faststart intact, no `.partial`/`.sb-`.
- [x] M26-T3 **Find the bars without being told.** This is why it is a milestone and not a one-liner.
      **Seams:** `VideoFrameReader` decodes frames off the main thread already, and M24-T4 measured
      what frame extraction costs (keyframe spacing × count, not take length) — sample a handful and
      look for constant-luma bands rather than black ones. **Rulings:** how many frames, and what
      counts as "constant" at luma 62–66; whether a detected crop auto-applies or is merely offered.
      **Verify:** measured against a real letterboxed capture — the detected rect matches the
      hand-cropped one to within a pixel or two, **and a non-letterboxed take detects nothing** (the
      negative control, without which a detector that always fires looks like it works).
      ⚠️ **Needs a letterboxed sample from Franco** — there is none in the repo, and the task is
      calibration against real bars.
      ✅ **Done 2026-07-31, against a synthetic letterbox (Franco's call).** ⚠️ **Measured first, and
      the premise was wrong twice.** ① **The "luma 62–66" test would have missed its own fixture:**
      bars encoded at luma 64 decode to **73.0**, so the detector tests *flatness and edge-anchoring*
      and never the level. ② **The tolerance is 24, not the 16 the plan proposed:** at 6 the run stops
      6 px short (HEVC ringing at the bar boundary), at 16 the five sampled frames disagree by up to
      4 px — which the conservative combine inherits — and **at 24 every frame lands on the boundary
      exactly**, while no negative fires below 32. **Rulings:** 5 frames, combined by the **smallest**
      bar any of them shows (a dark scene reads like a bar, so one misleading frame can only
      under-crop, never eat content); the crop is **offered, not applied** — a `Find bars` button
      fills in the crop you already have, and says `No bars found.` rather than appearing to do
      nothing. **679 tests** (+6 pure, frames built in memory). **Verified end to end on the release
      binary:** `export --to-mp4 --crop detect` on a 1600 × 1200 letterboxed fixture landed
      **1600 × 900 at 0,150 — the true rect, to the pixel** — while three negatives (a synthetic
      no-bars clip and **two of Franco's real screen recordings**) all reported no bars.
      ✅ **Calibrated against a real letterboxed capture 2026-08-03** — recorded headlessly by the CLI
      while Franco held a video fullscreen (a 16:9 video on a 16:10 display bars itself). 🔴 **It broke
      the detector twice, in ways a synthetic fixture structurally could not** (docs/07): a
      **watermark inside the bottom bar** (spread 190, but only 1.6% of pixels moved) forced the line
      test to become the fraction within ±tolerance of the line's **median**; and **2–10 px uniform
      edge runs on ordinary recordings** forced a **16 px minimum bar**, without which every
      un-letterboxed take gets shaved. ⚠️ The old negative fixture was invalid — `testsrc2`'s
      constant-colour bands *are* pillars. **Result on the real thing: 512/512 pillars against a true
      513/512, top bar 128 against a predicted 128.5**, four real negatives silent, **681 tests**.

- [x] M26-T4 **A precise trim can crop too** (Franco's ask, 2026-07-31: *"why can't we trim and crop
      at the same time?"*). The answer split in two: `Export & Copy` **already** does both in one pass
      (that is what `range:` + `crop:` are), and a **lossless** trim never can — it copies encoded
      frames, a crop must decode them. But **precise** mode already re-encodes through an
      `AVVideoComposition`, so a crop rides the composition it was building anyway, and hands back
      what the MP4 export cannot: the source's **codec and scale, with both audio tracks separate**
      (ADR-004). **Seams:** `Trimmer.makeSession(.precise)`; `CropComposition`, extracted from
      M26-T1's exporter so one transform serves both paths. **Verify:** CLI — headless, unlike T2.
      ✅ **Done 2026-07-31.** `TrimError.cropNeedsReencode` refuses lossless + crop **before the asset
      opens**; the window disables `Trim & Save` unless `Re-encode` is ticked and says why.
      🔴 **The measurement that shaped it:** an `AVAssetExportSession` **honours** the composition's
      `frameDuration`, unlike the reader path (M26-T1) which ignores it. A hand-built composition
      resampled a 19.4 fps variable-rate capture to a constant 60 and cost **2.9× the bytes** (2.23 MB
      → 781 KB for the identical crop). The fix is to derive the composition from
      `videoComposition(withPropertiesOf:)` — it carries `sourceTrackIDForFrameTiming` — and override
      only `renderSize` and `instructions` (docs/07). **673 tests.** Verified through the CLI:
      `--crop` without `--precise` refused with nothing written; with it, **hvc1 1600 × 1000, both
      audio tracks, 4.00 s**, container still `com.apple.quicktime-movie`, and the pixels are the rect
      asked for (**0.72%** differ at tolerance 6, against **30.13% at delta 255** for the bottom-left
      reading).

**Gate G26** — ✅ **PASSED 2026-08-03** (evidence in STATUS.md's gate table). The criterion as filed:
an export can be cropped from the Trim window and from the CLI; the output's dimensions
are what the UI promised and the Size cap still applies to them; the original is untouched; and a
letterboxed capture's bars are found without anyone typing a rectangle.

## M27 — Audio-only per-app exclusion, via Core Audio process taps (the honest answer to F3)

`Everything Except ▸ <app>` is a **content** filter. Measured (docs/02 §1a-ii): the excluded app's
audio goes to **−∞ dBFS** — and **its windows leave the frame with it**, because SCK has no
audio-scoped exclusion. 🔴 **And the case worth having is the one the API cannot reach at all:**
minimise an app and it vanishes from `SCShareableContent.applications`, so it cannot be excluded —
while its audio still lands at **full level (−9.1 dBFS, measured)**. Background music is exactly that
shape. The route is `AudioHardwareCreateProcessTap` + `CATapDescription(excludeProcesses:)`
(macOS 14.2+): **a second system-audio source, not a filter change.** **MINOR.**

- [x] M27-T1 **Measure before designing anything else.** M21's lesson, already recorded in this file:
      three of its four tasks were filed on a premise measurement moved. Answer, with numbers in
      docs/07: does a process tap capture system audio minus a chosen process, **including a
      windowless one**? What format and clock does the aggregate device present? What happens when
      the excluded process quits mid-take, or was never running? What does it cost against ADR-019's
      current path? **Verify:** a spike and a field note — **every task below is shaped by this, so
      none of them should be detailed further until it lands.**
- [x] M27-T2 **The tap as a second system-audio source.** **Seams:** `SampleRouter` (the one place
      consumers attach), `TimestampRebaser` (a tap has its own clock — this is the alignment risk),
      `CaptureConfiguration`. **Rulings:** whether the tap *replaces* SCK's audio whenever an
      exclusion is set or runs beside it; and what a mid-take tap failure does — ADR-012's shape
      (keep recording, say so) is the precedent, and a silent drop to no audio is the outcome to
      design against.
      **Re-specified 2026-08-03 against T1's measurements** (the milestone deferred this until the
      spike landed):
      ✅ **Narrower than filed.** The tap presents **48 kHz, 2 ch, 32-bit float — byte-identical to
      SCK's own system audio** — so no converter, no resampler, and no format negotiation. Tap and
      SCK **run together without conflict**, measured. What survives of the "alignment risk" is
      **epoch** alignment only: the tap counts in its own `mSampleTime`, so it needs the same
      `TimestampRebaser` treatment SCK's sources get, not new machinery.
      🔴 **The ruling now has an obvious answer: the tap REPLACES SCK's audio when an exclusion is
      set.** Running both would double every sound in the file, since the tap is a global mixdown of
      the same output the SCK tap already carries. So the choice is which single system-audio source
      is attached, decided at `CaptureConfiguration` time.
      ⚠️ **The 512-frame callback (~10.7 ms) is not SCK's 960-frame, 20 ms cadence.** Same rate, twice
      the callback rate — check the writer's pacing assumptions rather than assuming they carry.
      **Cost is not a consideration:** ~0.4% of one core, 27.6 MB.
      ✅ **Done 2026-08-03.** `SystemAudioTap` (RecorderCore/Capture) turns the tap into
      `CMSampleBuffer`s through `PCMSampleBuffer` — its third caller, not a new mechanism — stamped on
      the **host clock** so `TimestampRebaser` needs no special case, and routed as `.systemAudio`.
      **No consumer changed**: the writer, the replay ring and the meter never learn the difference.
      `screenrec-cli record --mute-app <bundle-id>` is the verify surface. **681 tests.**
      **Measured:** silencing QuickTime by bundle ID dropped its tone **−18.5 → −102.4 dBFS** while
      the rest of the mix held at −18.1; the no-exclusion control kept both paths intact and an
      ordinary take still lands **3 tracks** (hvc1 + 2×AAC), because nothing silenced means the SCK
      path is untouched. 🔴 **An unperformable exclusion is now said, not swallowed** — a bundle ID
      the audio system has never seen yields `silencedAppUnavailable`, the audio twin of M21-T4's
      `excludedAppUnavailable`, and the run prints it. ⚠️ **Unplanned finding, and T3's copy has to
      carry it:** the tap *also captures windowless processes SCK omits entirely*, so an exclusion
      can make more sound appear in a take, not less (docs/07).
- [x] M27-T3 **The UI, and the vocabulary.** Two ideas stop sharing one row: `Everything Except`
      keeps meaning *neither seen nor heard*; the new list means *heard no more*, and it can offer
      apps with no window — which the existing one structurally cannot. **Rulings:** what it is
      called; whether both can be set at once, and on the same app.
      **Re-specified 2026-08-03 — wider than filed, and the honesty problem is new.**
      🔴 **The list is not "running apps".** It is
      `kAudioHardwarePropertyProcessObjectList` — *processes the audio system knows*. An app that has
      never played audio **has no process object, and excluding it is a silent no-op**: its audio
      lands in the take in full, with nothing saying so (measured, docs/07). A picker built from
      `NSWorkspace`'s running applications would therefore **offer exclusions it cannot perform**.
      **New ruling required:** what the UI does about an app the audio system doesn't know — omit it,
      show it disabled with a reason, or offer it and warn when it turns out to be unperformable.
      ⚠️ **And the list is not stable:** a process object appears when an app first plays and can
      disappear later, so the pick must survive its object vanishing (bundle ID is the durable key,
      the `AudioObjectID` is not — M17's "a reused window id is refused" is the precedent).
      ✅ **Done 2026-08-03.** `Mute ▸` sits beside `Everything Except ▸`, and the two dimmed rows are
      one grammar: **`… won't be seen or heard`** against **`… will be seen but not heard`**. Live:
      the row renders, the submenu lists what is playing, and the idle menu is unchanged when nothing
      is muted. **681 tests.**
      🔴 **The list was wrong on the first build, and the fix is a field note:** the process object
      list is *every process the audio system knows* — `caphost`, `audiomxd`, accessibility daemons —
      not apps that play sound. **`kAudioProcessPropertyIsRunningOutput`** separates the two, plus a
      resolvable-app-name filter; the menu went from six daemons to one real app.
      🔴 **And T2 had a bug this task found:** one app owns **several** audio objects (helpers share
      the bundle ID), so silencing "the" object left the rest audible. All of them are taken now.
      ⚠️ **Left to T4 as planned:** the caveat that muting *adds* windowless audio belongs in a
      Settings caption, and the health check must measure level, never a status code.
- [x] M27-T4 **The failure modes are honest.** Tap permission refused, the aggregate device
      disappearing, the excluded process quitting mid-take. **Verify:** each one observed, each one
      leaving a playable file and a true sentence.
      **Re-specified 2026-08-03.** 🔴 **"Permission refused" is not a failure code — it is silence.**
      An ungranted tap returns `OSStatus 0`, a valid UID and a full stream of **zeros** (measured).
      **So the health check must measure level, not return values**, or a permission change ships as
      an audio-less recording — the shape of failure this project has twice let through.
      ✅ **One mode is already measured and benign:** the excluded process quitting mid-take is
      graceful (468 callbacks over 4.99 s, uninterrupted, other audio unaffected) — no handling
      needed beyond not asserting the object still exists.
      ⚠️ **Still unmeasured:** the aggregate device disappearing (default output device changes, or
      AirPods disconnect mid-take — the M8 shape, and this hardware does it routinely).
      ✅ **Done 2026-08-03.** `TapSilenceWatchdog` — pure, **6 tests** — plus `audioTapSilent` through
      the four surfaces. **687 tests.**
      🔴 **The design turns on a cross-check, because silence is not a signal.** An ungranted tap
      streams zeros with `OSStatus 0`, and so does a quiet Mac: identical on the wire. The condition
      is **something is playing** (`IsRunningOutput`, the property T3 already relies on) **and the tap
      is silent for 5 s** — reported once per outage, cleared by any audible buffer. Verified both
      ways: it fires on silence-with-audio-playing, and **stays quiet through a genuinely quiet
      recording**, which is the control the whole design rests on.
      ✅ **Ruled: no fallback to SCK audio.** SCK binds audio per stream, so a mid-take switch means
      restarting the stream — and worse, the fallback *is* the content filter that cannot exclude an
      app's audio without taking its windows, so it would **silently undo the mute**. Recording
      continues and says so (ADR-012).
      ⚠️ **Plan corrected on contact:** it put the "muting also captures windowless audio" caveat in a
      Settings caption, on the belief that the system-audio explanation lives there. It lives in the
      **menu**, so the caveat went beside its siblings as one short dimmed line.
      🔴 **Not verified end to end, and not claimed:** the notice's *positive* path in a real
      recording needs a genuinely ungranted tap, which cannot be produced from a granted binary
      without revoking Franco's own TCC grants. The decision is unit-tested both ways and the
      plumbing matches its three sibling events.

- [x] M27-T5 **One rate, whatever the hardware is doing** (added 2026-08-03 from a measurement, not
      the plan). A tap's sample rate **follows the output device** — 48 kHz and 24 kHz both measured
      on one Mac in a day — where SCK's system audio is always 48 kHz. So a muted take's audio
      quality depended on the hardware, and `ReplayAudioRing` **empties its window** when a format
      changes under it. **Seams:** `ResampledMicInput`, which already solves exactly this for the
      microphone. **Ruling (Franco):** resample rather than accept the device's rate.
      ✅ **Done 2026-08-03.** The converter takes an **injectable target**, defaulting to the mic's —
      so the mic path is unchanged by construction rather than by inspection — and the tap asks for
      **interleaved stereo 48 kHz**, one contiguous block so `PCMSampleBuffer` still writes a single
      buffer. The emitted length now comes from the target's own `mBytesPerFrame`, which is what
      makes mono and interleaved stereo both correct. **694 tests** (+4). ⚠️ **The rename was
      skipped:** `ResampledMicInput` is referenced 22 times across ten gate-verified files, and the
      churn buys nothing the doc comment can't say.
      ⚠️ **Not proven against real 24 kHz hardware:** by the time the code was ready the device had
      returned to 48 kHz, so the live run exercised the **pass-through**. The conversion is pinned by
      a unit test instead (24 kHz stereo in → 48 kHz stereo out, ~2× the frames).
      🔴 **Still owed:** the device-switch-while-armed leg, which is the failure this task exists to
      prevent, and needs Franco's AirPods.

**Gate G27** — ✅ **PASSED 2026-08-03** (evidence in STATUS.md's gate table; two caveats recorded there, not waived). The criterion as filed: a **windowless** app's audio is absent from a take while the rest of the system is
present. ⚠️ Verified with two *windowed* apps as the control, **never `afplay`** — G21 nearly
recorded a false negative that way, because a bare windowless process never appears in the captured
track at all (docs/02 §1a-ii).

## M28 — An `NSMenu`-backed status item (the bridge's bill comes due)

The menu is a SwiftUI `MenuBarExtra(.menu)`, and the bridge to AppKit keeps only text. The
compromises have accumulated: rows are **stamped at open and cannot tick** (M6-T10), a disabled
`Picker` row **will not dim** (M7-T2), and a label renders **only its first `Image`** — which is why
the clock, the level meter, the armed badge and the saved tick are composited into one bitmap by hand
(M16-T5, M23-T3). Its trigger — "the next feature that needs custom row rendering" — is **met three
times over**. **MINOR** (T1 and T2 alone are no user-facing change).

⚠️ **The parity task was split in two before it started (Franco, 2026-08-04).** Removing
`MenuBarExtra` removes the app's only always-alive view, and `@Environment(\.openWindow)` is only
reachable from one — so Settings, Onboarding and Trim lose their opener, `StatusIconLabel`'s `.task`
loses seven launch-time jobs, and `TrimView`'s `dismiss()` becomes a no-op in a plain `NSWindow`.
The windows therefore move first, under an untouched menu, so a dump diff has one candidate cause
rather than two. T2–T4 below are the old T1–T3, renumbered.

- [x] M28-T1 **The windows stop needing a scene.** Settings, Onboarding and Trim become
      `NSWindow`s hosting the same SwiftUI views; `MenuBarExtra` is untouched.
      **Seams:** `RegionSelectionOverlay` and `CountInOverlay` already hand-build `NSWindow`s in
      this module. `TrimView`'s `@Environment(\.dismiss)` becomes an injected closure — it does
      nothing inside a plain `NSWindow`. **Verify:** `menudriver dump` identical (nothing about the
      menu moved, so any diff is a mistake), plus the three windows opening, coming forward and
      dismissing.
      ✅ **Done 2026-08-04.** `WindowPresenter` (68 lines) against 40 deleted; **695 tests**, dev
      loop clean. **Dump byte-identical** across 161 rows against the pre-change baseline.
      ✅ **Measured rather than assumed** (docs/07): content sizing survives through
      `sizingOptions = [.preferredContentSize]` — the four Settings tabs still re-fit the window
      292 → 372 → **437** → 327 pt, that 437 being docs/06's own figure — while **window position
      does not survive** a rebuild-per-open and needed `setFrameAutosaveName` to reach parity.
      ✅ **The `dismiss()` replacement was driven end to end**, not just compiled: `Trim & Save`
      pressed through AX closed the window and wrote a playable 10.04 s file, both tracks.
      ⚠️ **Rebuilt per open on purpose:** Trim's player teardown hangs off `onDisappear`, so the
      window has to genuinely go away.
- [x] M28-T2 **Parity: the same menu, drawn by AppKit.** An `NSStatusItem` + `NSMenu` replacing
      `MenuBarExtra`. **Seams:** `MenuView` (602 lines) and all of docs/06's menu spec, which is
      written in its terms; the inline `Picker` checkmark behaviour in `Source ▸` is load-bearing and
      has to be rebuilt by hand. **Plain `NSMenuItem`s, not custom views** — parity needs none, and
      they arrive with T3/T4, which do. ⚠️ **The reason first given for this was wrong and is
      retracted:** a view-based item was said to hand its Accessibility identity to the view and so
      blind `menudriver`. Measured 2026-08-04 (docs/07): it keeps both its `AXTitle` and its
      checkmark as long as `title` is still set, and dumps identically to a plain row.
      **Verify:** `menudriver dump` **identical**
      before and after — M22's bar, and the one that matters most here, because **every gate since G4
      has leaned on that instrument** — bar three declared diffs: `Mute ▸` stops faking its checkmark
      into the title, the `(not running)` row finally dims (M7-T2, "accepted" in docs/06), and
      `Source ▸`'s trailing rule stops being a side effect of the inline `Picker`.
      ✅ **Done 2026-08-04.** `StatusItemController` + `MenuBuilder` + `MenuRow` (756 lines) against
      `MenuView` and the SwiftUI status-item label (829). **695 tests**, no test edited, zero
      warnings, dev loop clean. **`AppState`'s surface never moved** — M22's forwards are why.
      ✅ **The bar was met on all three menus.** Idle: **byte-identical**, proven twice, in both
      audio states (160 rows with an app playing, 157 + a matching `Mute ▸` block with none).
      Recording and paused: identical row for row, the only differences being **live values** —
      bytes written and the `Stop & Copy` estimate off sub-second elapsed.
      ✅ **All three declared diffs exercised by Franco (2026-08-04) and confirmed**: the muted app's
      tick sits in the checkmark gutter instead of typed into the label, and a picked-but-quit app's
      `(not running)` row genuinely dims. ⚠️ The third was not a diff after all — `Source ▸`'s
      leading and trailing rules reproduce the inline `Picker`'s own separators exactly.
      ✅ **The armed-replay block is dump evidence, not a claim:** armed, the whole menu is identical
      to the SwiftUI baseline bar `Mute ▸` listing a playing app. ✅ **The level meter composites in
      AppKit too** — the status item measures **39 × 24 armed against 27 × 24 disarmed**, M16-T5's
      own figure for icon-plus-meter.
      🔴 **The one thing measurement caught, which parity would have shipped broken:** the first open
      after launch had no app list, no window list and no recents detail. Those come from async
      reads; the SwiftUI menu filled them in **while open**, which is exactly the M6-T10 corruption.
      The caches are primed at launch instead, so the first open matches every later one.
- [x] M28-T3 **A thumbnail per recents row.** **Seams:** `FilmstripThumbnails` (M24-T4) already
      decodes a frame off the main thread and its cost is measured — first frame ~80 ms, and cost
      tracks keyframe spacing × count, not take length. **Rulings:** thumbnail size; whether it is
      cached across menu opens (rows are stamped at open, so a re-decode per open is the naive cost).
      ✅ **Done 2026-08-04.** `MenuThumbnails` (AppCore) + `RecentRowView` (167 lines). **695 tests.**
      **Rulings taken as recommended** (Franco, "let's go"): a **36 × 22 pt** well in a 28 pt row,
      an **empty well** where no frame can be read so titles stay aligned, exports thumbnailed too,
      and the frame taken **10% into the clip** rather than frame 0.
      ✅ **The dump is byte-identical** — all **98 rows** of `Recordings ▸`, unchanged. A view row is
      invisible to `menudriver` as long as the item keeps its `title`, exactly as the spike predicted.
      ✅ **No slower to open:** 0.39–0.40 s over five runs against **G18's recorded 0.57–0.60 s**
      (0.90 s on the first open, which is the cold cache). ⚠️ Same instrument and machine, a
      different day — not a same-session A/B.
      🔴 **A defect only a screenshot could catch:** the chevrons did not line up. A row's view keeps
      the width it was created with, so the chevron tracked the **title length** instead of the
      menu's edge; `autoresizingMask = [.width]` fixed it. No test would have seen this.
      ⚠️ **The live-arrival path is unobservable in the app**, though it is implemented and proven on
      the harness (docs/07): a probe file copied into `~/Movies` already had its frame by the time
      the row could be seen. Its value is the safety net and T4, not thumbnails.
- [x] M28-T4 **A progress row that advances while the menu is open.** The M6-T10 constraint —
      nothing may tick into an open menu — dies here, and with it the stamped-at-open `Exporting …`
      row. **Rulings:** what else may now tick, and what deliberately still should not (a live clock
      in an open menu was never the ask).
      ✅ **Done 2026-08-04.** `ExportModel.exportProgress` + `ExportProgressRowView`. **700 tests**
      (+5). **Rulings taken as recommended:** a bar *and* a percentage, **nothing else starts
      ticking**, and GIF/trim keep the plain row rather than an invented figure — only the MP4 path
      can report, and `Exporter` had been reporting to nobody since M10-T2.
      ✅ **Proven the only way that counts: one menu open, eight samples, six distinct values** —
      `Exporting… 1% → 2% → 3% → 4% → 5% → 6%` read straight off `AXTitle` while the menu was held
      open. The percentage is in the **title**, not just the drawn bar, so VoiceOver gets the same
      row a sighted user does.
      🔴 **Two defects the review caught, both mine:** `menuWillOpen` re-armed the observer on every
      open, so registrations stacked up (progress is nil almost always, so they never fired to
      clear); and the generation stamp I added to fix a stale-report race was captured **before**
      the generation moved, which would have dropped every report. The second is why
      `aReportedFractionReachesTheMenu` exists — it fails rather than hangs.
      ⚠️ **`ScreenRecApp` has no test target**, so the observer logic is covered by the live probe
      and nothing else.
- [ ] M28-T5 **More than five recents, legibly.** `RecentRecordings.limit = 5` exists because a
      longer list of identical timestamps is unreadable, not because five is right. **Rulings:** the
      new cap, and whether rows group by day.

**Gate G28**: the menu does everything it did — proven by dump parity at T2, before any new
capability lands — plus a thumbnail on every recents row, a progress row that advances while the menu
is open, and a recents list longer than five that is still readable.

## Dependency graph

```
M0 ──▶ M1 ──▶ M2 ──▶ M3 ──▶ M4 ──▶ M6 ──┬─▶ M7 (post-v1; per-app capture)
              │                    ▲     └─▶ M8 (post-v1; mic recovery — Route 2, spike-verified)
              └────────▶ M5 ───────┘   (M5 needs M1's router + M2's BitrateModel;
                                        app integration M5-T5 needs M4. M7 & M8 are independent.)
```

M5-T1..T4 (core replay, CLI-driven) can proceed in parallel with M3/M4 if two agents
work simultaneously — they touch disjoint files by design.

The graph above is the v1 (M0–M6) core. **M7–M22 are independent post-v1 milestones**, each building
only on shipped work: M7 (per-app), M8 (mic recovery), M9 (post-review polish/debt), M10 (share export
+ basic editing), M11 (region), then the v1.6.0-review roadmap — **M12 (Share & Surface), M13
(Hardening), M14 (Cleanup)**. M12 and M13 are independent of each other; M14 is pure cleanup best done
after both.

**The 2026-07-24 review roadmap — M15 (Gate & Debt), M16 (Honest State), M17 (Window capture), M18
(Editing & Menu polish).** All four are independent of each other in code, but the intended order is
the numbering, for two reasons: **M15 first** because `swift test` is the only automated gate and it
is currently unreliable (M15-T1) — every later milestone is verified through it, so it is fixed before
anything new lands, the same "clear the deck" logic as M9 and M13. **M16 next** because it is the
review's central thesis and its five tasks are individually small. M17 and M18 are genuinely
interchangeable; two of their tasks touch the same surface in opposite directions (**M17-T2** adds
window rows to a menu **M18-T3** is shortening), so whichever runs second inherits the coordination —
noted in both tasks. **RESOLVED 2026-07-27: M17 shipped first, and it cost M18-T3 one row, not a
dozen.** T2 nested the window list inside a single `Window ▸` row rather than listing windows flat in
`Source ▸` (docs/06 item 5), so M18-T3's diet starts from one extra row.
**🏁 SHIPPED IN FULL 2026-07-28** — v1.7.2 (M15), v1.8.0 (M16), v1.9.0 (M17), v1.10.0 (M18).

**The 2026-07-28 review roadmap — M19, M20, M21, M22. 🏁 SHIPPED IN FULL 2026-07-30** —
v1.10.1 (M19), v1.10.2 (M22), v1.11.0 (M21); **M20 (Marks) closed "won't do"** on the
fragmentation measurement above. Ordering, as it actually ran: **M19 first** (its T1 was a shipped
bug in a safety mechanism — the disk guard could not see a disk filling, and that is the only item
on the roadmap that can lose a recording); then **M22 by Franco's call**, because T4's hotkey
registry and T3's write-path tests were meant to protect the milestone that touched them; then
**M20**, which measurement closed; then **M21**.
The one lesson worth carrying forward: three of M21's four tasks were filed on a premise that
measurement moved (docs/02 §1a-ii, docs/07) — check the API's actual behaviour before designing
around a roadmap sentence.

**The 2026-07-30 review roadmap — M23 (The write path tells the truth), M24 (Finish the share
loop).** Review artifact: `claude.ai/code/artifact/38dcfad1-b8d9-4029-9a96-e7f9ec4544fc`.
**M23 first**, on the same logic that put M19 ahead of its roadmap: T1 is the only finding that can
cost a recording, and the rest of M23 is honesty about work already in flight. **M24 second** because
every one of its tasks is small and each one pays back daily — but none of them matters if a take
can be lost quietly. M23-T5 (collapsing `AppState`'s forwards) is deliberately last and optional: it
is structure, and M22's lesson is that structure is easiest to justify after the features that would
otherwise land on top of it.

**Encoded from the parked list 2026-07-31 (Franco) — M25, M26, M27, M28.** Not a review roadmap:
these are four of the six items that had been parked with triggers, promoted on his call after the
v1.12.0 cut. **Proposed order M25 → M26 → M27 → M28, and it is his to change.** M25 (Swift 6) first
on M22-before-M21's logic — M27 puts a second audio clock into `SampleRouter`, and the compiler
should be checking docs/01's concurrency rules *before* that lands rather than after. M26 (crop) next
because it is the one with a named user and a measured pain. M27 third: real new capability, real new
failure modes. M28 (`NSMenu`) last — the largest, and it buys polish rather than capability, so it
should not sit in front of things that buy capability. The two items that stayed parked are below the
graph.

**Parked, with the trigger that would un-park each (updated 2026-07-31).** Four of the six were
**encoded as M25–M28 on 2026-07-31 (Franco)** and are no longer parked. What remains:

- **Multi-display region capture** — M11 is main-display only and honest about it: the overlay draws
  *"Region capture uses the main display only"* rather than silently cropping the wrong screen.
  `RegionSelection.displayID` already exists and is already persisted, and the filter is per-display
  either way, so the engine side is close to free. **Deferred by Franco (2026-07-31): he does not use
  a second monitor.** Trigger unchanged — a second display is attached. It is the only item here
  gated by hardware rather than by a decision, and an untested multi-display path is worse than an
  honest single-display one.
- **Cursor emphasis / auto-zoom** — click highlights, cursor smoothing, zoom-to-activity, padded
  backgrounds. Needs the **Metal/CoreImage render stage screenrec deliberately does not have**
  (today video goes SCK → encoder untouched, which is most of why a 4112×2570 two-hour take holds
  up). ADR-015 parks it and says crossing that line is a **separate, explicit decision**, not
  something to drift into one convenience at a time; ADR-008's cursor-as-data sidecar is parked with
  it, and ADR-017 closed the webcam fork on the same reasoning. **Deferred by Franco (2026-07-31):
  not wanted for now — kept on this list deliberately, not dropped.** ⚠️ If it is ever taken up, the
  honest framing is that it is not a feature but a **second product identity**, and it wants its own
  review before any milestone: it changes what every other decision was optimising for.

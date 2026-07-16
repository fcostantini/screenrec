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
      **(human)**.
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
      **(human) owed:** ⌥⌘R while another app is frontmost; badge/menu taste pass.
      **Inherits from M4-T4 (Franco, 2026-07-15):** the replay Settings rows (buffer length
      30/60/120, hotkey recorder) and the status-icon's replay-armed badge, plus the keys they
      write — `replayArmed`, `replaySeconds`, `replayHotkey` (names contractual, docs/06). They
      were going to ship in M4-T4 for this task to read later; the ruling is that nothing about
      replay appears in the UI until the ring buffer behind it exists. **So M5-T5 both writes and
      reads them — there is no cross-milestone contract left to get wrong, only a spelling to
      match docs/06.**
      **Verify:** §6.4 — manual recording + armed replay + save simultaneously → both
      files probe-clean. Hotkey fires while another app is frontmost **(human)**.
- [ ] M5-T6 Memory/CPU audit: 30-min armed session.
      **Verify:** §6.1/§6.5 — RSS plateau ≲ 200 MB, CPU < 10% avg, save still < 1 s at
      minute 30; numbers into STATUS.md.

**Gate G5**: 04-testing §6 (clip saved < 1 s, contains last N ± 1 s with audio; works
while a manual recording runs; memory flat over 30 min).

---

## M6 — Ship-quality pass (est. 1–2 sessions)

- [ ] M6-T1 Full acceptance run: every item in 00-product-brief "Success criteria".
- [ ] M6-T2 The 2-hour soak test (04-testing §7) on battery **(human — physical
      unplug)**.
- [ ] M6-T3 Error-message audit: force each failure path; every message says what
      happened AND what to do.
- [ ] M6-T5 Launch at login (`SMAppService`, key `launchAtLogin` — docs/06). **Moved here from
      M4-T4 (Franco, 2026-07-15):** `SMAppService.mainApp` registers a login item pointing at the
      bundle's *current path*, and until the app has a permanent address that path is
      `dist/ScreenRec.app` — a build directory `bundle.sh` deletes on every run. Registering it
      earlier aims a login item at a folder that stops existing. It belongs with M6-T4's
      installability work, not before it.
      **Verify:** toggle on → `SMAppService.mainApp.status == .enabled`; log out/in → the app is
      running **(human)**; toggle off → the login item is gone.
- [ ] M6-T4 Optional (decide then): Developer ID + notarization for distribution
      beyond this machine; `--h264-downscale` compat mode; HDR spike (ADR stretch);
      **mic recovery after device loss** — ADR-012 deferred it to here. Not a research
      question any more: M3-T7 verified both routes and 02 §4 costs them (~2 tasks; a
      fixed-format resampled mic input is a hard prerequisite for either). Decide with
      real usage in hand — does an AirPod dying mid-recording actually bite often enough
      to be worth touching the sample path? If yes, prefer the rebuild-a-mic-only-stream
      route (it also fixes reconnect, which re-pointing provably never can) and settle
      its PTS-coherence assumption first via the §3.5 drift method.
- [ ] M6-T5 README for the repo: build, sign, install, use. Update all docs to
      match reality; close out STATUS.md v1 section.

**Gate G6** = v1 done.

---

## Dependency graph

```
M0 ──▶ M1 ──▶ M2 ──▶ M3 ──▶ M4 ──▶ M6
              │                    ▲
              └────────▶ M5 ───────┘   (M5 needs M1's router + M2's BitrateModel;
                                        app integration M5-T5 needs M4)
```

M5-T1..T4 (core replay, CLI-driven) can proceed in parallel with M3/M4 if two agents
work simultaneously — they touch disjoint files by design.

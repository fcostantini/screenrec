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
- [ ] M0-T3 `Scripts/bundle.sh`: SPM release build → assemble
      `dist/ScreenRec.app` (Contents/MacOS binary, Info.plist with
      NSMicrophoneUsageDescription + LSUIElement=true, PkgInfo) → `codesign --force
      --sign <identity from devsign>`. (`spctl -a -v` failure is OK pre-notarization.)
      **Verify:** `codesign -dv dist/ScreenRec.app` shows our identifier + authority
      "screenrec-dev"; run bundle.sh twice → identical designated requirement (TCC
      stability); `open dist/ScreenRec.app` launches without crash.
- [ ] M0-T4 Port from PoC into `RecorderCore/Support` + `Capture`: `Permissions.swift`
      (preflights incl. ⚠️ mic-device-ID and ⚠️ output-dir lessons, 02 §1–2),
      `OutputLocation.swift`. Design both so decision logic is pure/injectable.
      **Verify:** `swift test` — OutputLocation naming/collision/preflight-failure
      cases; Permissions decision table with injected TCC/device states.
- [ ] M0-T5 CLI skeleton: `screenrec-cli record --duration N` prints config it WOULD
      use (no capture yet); `--list-mics`; unbuffered stdout (02 §10).
      **Verify:** `--list-mics` lists real devices; dry-run `record` prints resolved
      config (incl. explicit mic ID, output path preflight result); output intact
      when piped to a file (buffering test).
- [ ] M0-T6 CI-less verification loop documented in STATUS.md: build, test, bundle
      commands an agent runs after every change.
      **Verify:** execute the documented loop verbatim top to bottom; it passes.

**Gate G0**: 04-testing §1 (build/test/bundle/sign all green; app launches, shows in
menu bar as placeholder or CLI prints config).

---

## M1 — Capture engine (est. 1–2 sessions)

Goal: RecorderCore starts an SCStream and delivers all three sample types to pluggable
consumers. No writing yet.

- [ ] M1-T1 `CaptureConfiguration`: display selection (default main), mic device
      (explicit ID — 02 §1), fps cap, quality preset enum. Pixel math from
      contentRect × pointPixelScale.
      **Verify:** unit tests with mocked rect/scale (e.g. 2056×1285 @2× → 4112×2570);
      preset/fps defaults.
- [ ] M1-T2 `CaptureEngine` actor: build filter + SCStreamConfiguration (02 §1 values),
      start/stop, delegate for `didStopWithError`, `EngineEvent` AsyncStream. Includes
      a `screenrec-cli engine-smoke` subcommand (its own verification instrument).
      **Verify:** `engine-smoke` → events `started` then clean `stopped` after 2 s,
      exit 0; with Screen Recording revoked it must fail in preflight, not in SCK.
- [ ] M1-T3 `SampleRouter`: three serial queues; consumer protocol
      `SampleConsumer { func consume(_ buffer: CMSampleBuffer, type: SourceType) }`;
      attach/detach under lock; frame-status filtering for video (02 §1).
      **Verify:** unit tests with synthetic CMSampleBuffers — two consumers both
      receive; detach mid-stream safe under `swift test --sanitize=thread`.
- [ ] M1-T4 CLI: `screenrec-cli probe-stream --duration 5` — counts buffers per type,
      prints format descriptions (esp. mic native format — we need to SEE it), min/max
      PTS deltas. This is our instrumentation for everything after.
      **Verify:** run 04-testing §2 in full; paste output + mic format into STATUS.md.
- [ ] M1-T5 `SleepGuard` (02 §7) wired to engine start/stop.
      **Verify:** during `engine-smoke --duration 10`, `pmset -g assertions` shows
      PreventUserIdleSystemSleep held by our process; released after exit.

**Gate G1**: 04-testing §2 (probe-stream shows all three types flowing, PTS sane,
mic format captured and documented in STATUS.md).

---

## M2 — MovieRecorder: the real writer (est. 2–3 sessions, the heart of Tier 2)

Goal: three-track `.mov` with tuned HEVC, crash-safe, from the CLI.

- [ ] M2-T1 `BitrateModel` (02 §3 presets).
      **Verify:** unit tests — preset math, pixel-count edge cases, monotone ordering
      Efficient < Balanced < High at fixed resolution.
- [ ] M2-T2 `MovieRecorder` skeleton: writer + 3 inputs (video HEVC from preset; system
      AAC; mic input built lazily from first mic buffer's format — 02 §4),
      `expectsMediaDataInRealTime`, fragment interval 10 s (02 §5).
      **Verify:** WITHOUT ScreenCaptureKit — integration test feeds 2 s of synthetic
      buffers (solid-color CVPixelBuffers + PCM silence in two different audio formats)
      → `finishWriting` → tools/probe shows hvc1 + two aac tracks, duration 2 ± 0.1 s.
      Proves the writer independently of capture.
- [ ] M2-T3 `TimestampRebaser`: epoch at first complete video frame, drop
      pre-epoch audio, monotonic enforcement, pause offset accounting (pause used in M3
      but build the math now).
      **Verify:** pure unit tests — epoch rebase, pre-epoch drop, cumulative pause
      offsets, out-of-order rejection.
- [ ] M2-T4 Wire as SampleConsumer; readiness handling = drop + count (report dropped
      frames at stop). Stop path: tail-frame patch (02 §5), `markAsFinished` ×3,
      `finishWriting`, emit `finished(URL, stats)`. Add bare `record` subcommand
      (defaults only; flags arrive in T5).
      **Verify:** `screenrec-cli record --duration 5` → probe: 3 tracks at full pixel
      res, duration 5 ± 0.5 s, reported dropped-frames = 0 on an idle machine.
- [ ] M2-T5 CLI: full `record [--duration N] [--preset X] [--no-mic] [path]`
      — parity with the Tier-1 PoC UX (progress ticker with NaN guard!).
      **Verify:** matrix — `--no-mic` → exactly 2 tracks; each preset → file sizes
      strictly ordered; explicit path honored; ticker never prints NaN (pipe run).
- [ ] M2-T6 Quality calibration: record same 30 s busy scene (video playing + scrolling)
      at each preset + Tier-1 for comparison; adjust BitrateModel constants.
      **Verify:** comparison table (size + notes) in STATUS.md; Balanced ≤ 50% of
      Tier-1 size. Subjective quality check **(human)**.

**Gate G2**: 04-testing §3 (tracks probe: hvc1 + 2×AAC; kill -9 test playable; sync
clap test; static-screen duration test; 30-min drift test).

---

## M3 — Pause/resume + robustness (est. 1–2 sessions)

- [ ] M3-T1 Pause/resume through CaptureEngine → TimestampRebaser; resume waits for
      next complete video frame. CLI: interactive `p`/`r` keys in `record`, plus
      scripted mode `--script rec10,pause5,rec10` for unattended verification.
      **Verify:** 04-testing §4.1 — scripted run yields 20 s ± 0.2 s file, monotonic
      PTS. Cross-seam A/V sync check **(human)**.
- [ ] M3-T2 Mic format-change detection → clean stop + `failed(reason:)` event with
      human message (02 §4, ADR-007).
      **Verify:** unit test injects a format-changed buffer → clean-stop path taken.
      Live AirPods-off run per §4.2 **(human present for the device action)**;
      afterwards agent confirms playable file + causal message.
- [ ] M3-T3 Disk-space monitor → clean stop at <2 GB (02 §7), `--test-disk-floor N`
      flag to trip it deterministically.
      **Verify:** §4.4 — run with floor above current free space → clean stop, message
      names disk space, file playable.
- [ ] M3-T4 Display-change / sleep handling end-to-end (unplug display, close lid):
      always a playable file + correct event. Document observed behaviors in 02.
      **Verify:** §4.3 **(human)** — both scenarios end in probe-clean files; observed
      SCK error codes recorded in docs/02 field additions.
- [ ] M3-T5 Stall watchdog logging (02 §7), clock injectable.
      **Verify:** unit test with injected clock — 30 s of no video buffers fires
      exactly one log line; buffer arrival resets it.

**Gate G3**: 04-testing §4 (pause math: 10 s rec / 5 s pause / 10 s rec ⇒ 20 s ± 0.2 s
file, A/V in sync across the seam; all three robustness scenarios end in playable files).

---

## M4 — Menu-bar app (est. 2 sessions)

Goal: ScreenRec.app is the daily driver; CLI demoted to debugging.

- [ ] M4-T1 `MenuBarExtra` app shell, LSUIElement, status icon states (idle/recording
      pulse/paused), AppState consuming EngineEvents on MainActor.
      **Verify:** `open dist/ScreenRec.app` → icon appears, no Dock icon; AppState unit
      tests map each EngineEvent to the right icon state. Visual check **(human)**.
- [ ] M4-T2 Menu: Start/Stop/Pause, display picker (NSScreen list), mic picker
      (AVCaptureDevice list + "None"), preset picker, "Open Recordings Folder",
      recent-files submenu (last 5).
      **Verify:** menu-driven 5 s recording produces a probe-clean 3-track file (needs
      the app's own TCC grant — first time is a "Needs Franco" item); recent-files list
      matches ~/Movies contents.
- [ ] M4-T3 Onboarding: permission status view; request buttons; explains the
      restart-after-grant dance (02 §2); blocks record until green.
      **Verify:** unit tests render view model for every permission-state combination;
      fresh-account walkthrough per 04-testing §5.1 **(human)**.
- [ ] M4-T4 Settings window (SwiftUI Form, UserDefaults): output dir (with preflight on
      choose — 02 §2), preset, fps, replay duration (for M5), hotkey (for M5).
      **Verify:** change each setting, quit, relaunch → `defaults read
      dev.fcostantini.screenrec.app` shows persisted values and UI reflects them;
      choosing unreadable dir → immediate friendly error (§5.4).
- [ ] M4-T5 Notifications (UserNotifications): recording ended + reason; click →
      reveal in Finder.
      **Verify:** stop a recording → notification delivered (check via
      `UNUserNotificationCenter` delivered list in a debug hook); click behavior
      **(human)**.
- [ ] M4-T6 Bundle polish: app icon (placeholder ok, iconutil-built .icns),
      `bundle.sh` produces the final artifact, version stamping.
      **Verify:** Info.plist version matches a `VERSION` file; icon renders in Finder;
      `codesign --verify --strict` passes on the final bundle.

**Gate G4**: 04-testing §5 (fresh-account onboarding < 2 min; menu flows; app-identity
TCC grants — app appears by name in System Settings, grants survive rebuild).

---

## M5 — Instant replay (est. 2–3 sessions)

- [ ] M5-T1 `RingBuffer` (generic, duration-bounded, lock-guarded).
      **Verify:** unit tests — eviction by duration, keyframe search, snapshot during
      concurrent append; clean under `swift test --sanitize=thread`.
- [ ] M5-T2 `ReplayEncoder`: VTCompressionSession per 02 §9; consume `.screen` via
      SampleRouter; keyframe flag extraction; ring append. CLI `replay-arm --seconds 60`
      prints ring occupancy/memory every 2 s.
      **Verify:** 3-min `replay-arm` run — occupancy climbs then plateaus at ~60 s;
      keyframes counted ≈ 1/s; RSS stable (§6.1 short form).
- [ ] M5-T3 Audio rings (PCM copies of `.audio` + `.microphone`).
      **Verify:** `replay-arm` occupancy printout includes both audio rings; PCM byte
      counts match duration × format math; rings stay duration-aligned with video ring.
- [ ] M5-T4 `ReplayMuxer`: snapshot → keyframe trim → rebase → passthrough video +
      AAC audio → file. Coalesce concurrent saves. CLI `replay-save` command.
      **Verify:** 04-testing §6.2 + §6.3 — save < 1 s, probe: hvc1 + 2 aac, duration
      N + ≤ 1 s, starts on keyframe; rapid double-save → one clean file, no crash.
      "Genuinely the last minute" content check **(human)**.
- [ ] M5-T5 App integration: "Arm instant replay" toggle (persists), hotkey ⌥⌘R via
      Carbon (02 §9), menu item + notification on save.
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
- [ ] M6-T2 The 2-hour soak test (04-testing §7) on battery.
- [ ] M6-T3 Error-message audit: force each failure path; every message says what
      happened AND what to do.
- [ ] M6-T4 Optional (decide then): Developer ID + notarization for distribution
      beyond this machine; `--h264-downscale` compat mode; HDR spike (ADR stretch).
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

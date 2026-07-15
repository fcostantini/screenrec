# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short; details go to Field notes / History.

## Now

- **Current milestone:** M3 — pause/resume + robustness. M2 COMPLETE, G2 PASSED (5/5).
- **M3-T2 DONE** — mic format-change → fail-stop. `MovieRecorder` captures the mic input's
  ASBD when it builds the input and, on a later mic buffer with a different sample-rate/
  channels/format-ID, fires a one-shot callback and drops the mismatched buffers (docs/02 §4);
  `RecordingSession` injects a handler that calls `engine.stop(reason: .microphoneChanged)`
  (new `stop(reason:)` seam) so the file finalizes as `.finished(reason:.microphoneChanged)`
  via the normal `.stopped`→`.finished` path (ADR-007). Verified: unit test (fires exactly
  once) + live stable-mic regression (no false-positive). **Live AirPods-die run → Needs Franco.**
- **M3-T1 DONE** — pause/resume wired end-to-end (rebaser math, engine `.paused`/`.resumed`,
  RecordingSession coordination, CLI `--script` + `p`/`r`/Return). G3 §4.1 pause-math PASSED.
- **M3-T6 DONE — G3 §4.2 PASSED.** Mic-loss starvation watchdog (`MicrophoneWatchdog`, router
  consumer + 1 Hz poll on the engine) emits `.microphoneLost`; recording continues (ADR-012).
  Live: AirPods cased → warning at ~25s, capture ran to the end, mic track ends at the
  disconnect. §4.2's original premise was wrong (no mic takeover) → docs/02 §4 corrected,
  ADR-012 written. Also proved: **a lost mic never returns** — reconnecting delivers nothing,
  which is what makes the one-shot watchdog safe. See field notes.
- **M3-T7 DONE (spike).** The one rule: **SCK binds the mic once at `startCapture` and never
  re-resolves** — named or nil. That single fact explains every mic-device behavior we've hit.
  Mic recovery IS possible (2 verified routes) but **deferred post-v1**; ADR-012 unchanged.
  Full experiment table + routes in **02 §4**; **02 §1's "nil throws" was STALE** and is fixed.
- **M3-T3 DONE — G3 §4.4 PASSED.** `DiskSpaceMonitor` (Support/) watches the output volume;
  `RecordingSession` polls it and stops via M3-T2's `engine.stop(reason: .diskAlmostFull)` seam
  — third trigger through that seam now, no new plumbing. Live: `--test-disk-floor 500000` vs
  676 GiB free → `finished (diskAlmostFull)`, playable 2.02 s file.
- **M3-T4 DONE.** Display-gone = SCK **-3815** (measured via `pmset displaysleepnow`, which is a
  headless lever for this) → `finished(.displayDisconnected)` + playable file; `.displayDisconnected`
  was declared-but-dead since M1 and is now wired. **Locked-screen bug fixed + verified live**:
  granted-preflight + zero displays no longer demands a permission you already hold. ⚠️ SCK
  collapses sleep/lock/unplug into one code → `.systemSleep` unreachable, not faked (02 §1/§7).
- **M3-T5 DONE — M3 is CODE-COMPLETE (T1–T7 all landed).** `StallWatchdog` logs a wedged capture
  (video silent while the user is demonstrably active) to the unified log — diagnostic only, no
  auto-restart. The idle cross-check IS the design: frame-on-change makes a static screen
  legitimately silent, so "no frames" alone would cry wolf on every coffee break. Shared
  `pollingTask(every:)` extracted here (rule of three: mic-loss, disk, stall).
- **Next: GATE G3** (04 §4). Automated legs already pass (§4.1 pause math, §4.2 mic loss,
  §4.4 disk guard); §4.3's display-sleep leg passes headlessly via `pmset`. Remaining before G3
  can be called: the **human legs in "Needs Franco"** (cross-seam clap-sync; lid-close and
  monitor-unplug). Offered and not yet run: a **`/simplify` sweep** over M3's code — nothing has
  ever swept for cross-task drift, only per-diff correctness (see the 2026-07-15 note below).
- **Now done:** M2-T1..T6 + M3-T1..T2. `record` is a full CLI (real 3-track capture, presets,
  explicit path, progress ticker, pause/resume, scripted timeline, mic-change fail-stop).
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
- [x] **G3 §4.2 mic-disappears — PASSED 2026-07-15 (Franco).** Two runs: the first (pre-M3-T6)
      disproved the gate's premise (no takeover → docs/02 §4 corrected, ADR-012 written); the
      second (post-M3-T6) passed the redefined gate — loss reported, recording continued, file
      playable. A bonus reconnect run proved a lost mic never returns for the session.
- [x] **M3-T7 spike — DONE 2026-07-15** (all legs run; findings in 02 §4).
- [ ] **G3 §4.3 leftovers (human, physical)** — two scenarios still unobserved. Both should end
      in a playable file with a sensible reason; paste the `finished (…)` line + probe output:
      1. **Close the lid mid-recording** (system sleep — distinct from display sleep, which is
         already verified). Note this differs again with an external display attached (clamshell
         = no sleep). Expect `.displayDisconnected` or a new code worth recording.
      2. **Unplug an external monitor mid-recording** while capturing *that* display.
      Everything else in §4.3 is now covered headlessly via `pmset displaysleepnow` (02 §7).
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
| G3   | 🟡 §4.1 passed | §4.1 pause-math: scripted `rec10,pause5,rec10` (--no-mic). Calm box → 4 runs 19.86–19.98s, all ∈ [19.8,20.2], tracks match ≤40ms. Loaded box (post code-review workflow, load ~2.6) → mean 20.05s over 8 runs (25s wall→20s file ⇒ 5s pause exactly removed), 5/8 strictly in-window; the 3 outliers are load jitter (audio starvation stretches the video tail; a load-delayed resume frame), NOT pause-math error. All runs probe monotonic-clean. §4.2 mic-disappears ✅ PASSED 2026-07-15 (Franco, post-M3-T6, per the ADR-012 definition): AirPods cased at ~22s of a 60s run → CLI printed `⚠️ microphone disconnected — still recording` at ~25s (≈3.2s latency = 3s timeout + ≤1s poll), recording ran to the end, `finished (userStopped)`, file playable, mic track 21.82s vs video 59.83s. First run (pre-M3-T6) disproved the gate's premise — no takeover, buffers just stop → docs/02 §4 corrected, ADR-012 written. Also proved: a reconnected device NEVER resumes (mic gone for the session). §4.4 disk-guard ✅ PASSED 2026-07-15: `--test-disk-floor 500000` (GB) vs 676 GiB free → `finished (diskAlmostFull)`, file playable (2.25s); negative verified on a real non-boot volume (4 GB HFS+ image, importantUsage reads 0 → records the full 8s, `userStopped`) after /code-review caught that the recommended capacity key reads 0 on every external volume. §4.3 sleep-lock awaits M3-T4 — though a mid-recording display sleep was already observed behaving correctly (streamError → playable 1.81s file). Cross-seam clap-sync = human. |
| G4   | ⬜ not run | — |
| G5   | ⬜ not run | — |
| G6   | ⬜ not run | — |

## Field notes (append; things learned that docs don't cover yet)

- 2026-07-15 (M3-T5 stall watchdog): the review caught a **logic bug in the one condition the
  class exists for**, and my tests could not have found it.
  - **`idle < silence` is NOT `the user was active`.** I wrote the guard as "did any input land
    after the last frame?". One inert keypress (a lone modifier changes nothing on screen, so no
    frame) leaves idle permanently 1 s behind silence — so it stays true *forever after the user
    walks away*, and every poll then reports a stall on an untouched machine. Exactly the
    coffee-break cry-wolf the class was written to prevent. Correct guard is **recent** activity:
    `idle < timeout`.
  - **My test harness structurally couldn't express the bug.** `advance(_:userActive:)` pins idle
    to 0 or grows it — so every test was "always active" or "always idle", never the realistic
    middle (active, *then* leave). Both extremes passed. Fifth blind-spot test today (see the
    boot-volume-only disk probe, the 400 MB image, the `--nil-follow` window, the lock-only
    repro). **The pattern is always the same: the fixture can only produce states where the code
    is right.** When a condition compares two quantities, test them *diverging*, not just each
    pinned.
  - **The refactor I deferred for safety introduced its own risk anyway.** Moving the mic poll
    onto the nonisolated `pollingTask` means `check()` no longer serializes against the actor, so
    a late `.microphoneLost` can in principle interleave between `.stopped` and
    `continuation.finish()` where the actor-isolated form made that structurally impossible.
    Mitigated by disarming both watchdogs *before* teardown; the residual window needs
    `terminate()` delayed ≥3 s past a stream death. Documented in Polling.swift rather than
    pretended away — if it ever shows up, revert the mic poll to an actor-isolated `Task {}`.
  - **`.hidSystemState`, not `.combinedSessionState`**, for the idle probe: the combined state
    counts *synthetic* events, so a mouse jiggler or keep-awake utility reads as "someone's here"
    on an unattended machine and manufactures the false stall the cross-check exists to prevent.
  - **Accepted false positive (documented, not faked): multiple displays.** The idle probe is
    machine-wide, capture is per-display — working on an uncaptured second display reads as
    active while the captured one is legitimately static. macOS exposes no per-display input
    signal. Costs log noise in a diagnostic, never a recording. Weigh it when reading a
    multi-display soak.
  - **The diff took the package from warning-clean to not** (a bare `@Sendable` method-reference
    default). With no CI the build loop is the only gate we have, so a standing warning is how
    the next real one gets scrolled past. Fixed; a clean build is back to **0 warnings** — worth
    checking that explicitly, since `grep error` won't show it.

- 2026-07-15 (M3-T4 display/sleep): the technical findings are in **02 §1/§7** (the -3815 code,
  the lock+sleep truth table). What belongs here is the process lesson:
  - **I mis-modelled this twice, and each wrong model produced a test that "passed" while
    testing nothing.** First guess: "a locked screen hides displays" → locked, captured fine
    (it records the login window). Second: "display sleep hides displays" → `pmset` slept it,
    captured fine (SCK wakes it). Only lock **AND** display-off does it. Both wrong runs looked
    like clean passes, not errors — that is the whole danger. Fourth time today (see the
    `--nil-follow` window and the 400 MB disk image) that a test's *setup* failed to create the
    state under test and quietly reported success.
    **Rule going forward: for any environment-dependent test, first prove the condition exists,
    then assert on it.** A test that cannot fail for the intended reason is decoration.
  - **`pmset displaysleepnow` is a genuine headless lever** for the mid-recording death
    (-3815 → `.displayDisconnected` → playable file) — that half of §4.3 no longer needs a human.
    The zero-display start path still needs a real lock (a shell keeps running while locked, so
    a human locks and the agent drives `pmset` + the capture).
  - **`EndReason.systemSleep` is unreachable** and was never wired up. SCK collapses sleep, lock
    and unplug into one code, so there is nothing to map it from. Left in place (docs/01 defines
    it, M5/M6 may find a source) but do not fake a distinction to justify it.
  - **The review found my fix only half-fixed the bug.** I gated the permission message on the
    preflight (`granted` → "no displays", else → "grant permission") — but
    `Permissions.screenRecordingState()` never returns `.denied`, so `.notDetermined` is the only
    other live value, and it's exactly what a freshly-built CLI binary reports *while capturing
    fine* (02 §10). So the original misdiagnosis survived on the only path the CLI can reach.
    The deeper point the review surfaced: **zero displays can never mean "ungranted"** — an
    ungranted process throws instead (02 §10) — so the preflight should not gate this at all.
    Now: zero displays ⇒ "no displays available", full stop. Lesson: a decision table looks
    complete until you check which cells the production caller can actually produce.
  - ⚠️ **02 §1 and §10 flatly contradicted each other** on ungranted behavior (empty results vs
    throws) and had done since the planning docs. §10 is measured, so it won. Untestable here
    (revoking TCC would destroy our own grant) → **M4-T3's fresh-account walkthrough settles it**,
    and the task now says so. If §1 turns out right, `startDecision` needs revisiting.
  - **-3817 `SCStreamErrorUserStopped` was landing on the fail-stop path.** macOS's screen-
    recording indicator lets a user stop the capture; that arrived as `.streamError`, which
    ADR-007 defines as fail-stop — so the most ordinary stop there is would have fired M4's
    "ended unexpectedly" notification. Now maps to `.userStopped`.

- 2026-07-15 (M3-T3 disk guard): the review caught a bug my gate **and** my unit test were both
  structurally blind to. Worth internalizing.
  - **`volumeAvailableCapacityForImportantUsage` returns 0 (not nil) on every non-boot volume.**
    Full detail + the fix now in 02 §7. Shipping impact would have been: every recording to an
    external SSD/USB/SD/disk-image self-terminates at ~2 s claiming "disk almost full".
  - **Why nothing I did could have caught it:** the unit test probed `temporaryDirectory` and the
    §4.4 gate wrote to `~/Movies` — *both the boot volume*, the one place the key works. A test
    named "reads real capacity" passed the whole time. Lesson: when an API's behavior is
    **environment-dependent**, testing one environment is testing nothing. The fix splits the
    volume-dependent reconciliation into a pure function over both keys, which IS testable, and
    keeps the live probe as a thin shell.
  - **Verified end-to-end after the fix**: a 4 GB HFS+ image (importantUsage 0, raw 3.7 GB) now
    records the full 8 s and finishes `userStopped`. Test that scenario with `hdiutil create
    -size 4g -type SPARSE` — and make the image **bigger than the floor**, or the guard fires for
    a legitimate reason and the test proves nothing (I did exactly that with a 400 MB image first).
  - **A wall-clock delay is not a startup guarantee.** The poll originally slept 2 s before its
    first check so it couldn't stop the engine pre-first-frame. But engine start can exceed 2 s
    (first launch, Bluetooth mic binding) — and a thrashing near-full volume is *precisely* when
    it does, so the guard's own trigger correlates with the race. Now it waits on
    `recordedDuration` leaving NaN (the writer session actually starting) instead.
  - **Deferred (rule of three):** the disk poll loop is verbatim-identical to CaptureEngine's mic
    watchdog loop. The review flagged the duplication; M3-T5's stall watchdog makes it three, so
    extract a shared `poll(every:)` helper there. Not done here because moving CaptureEngine's
    `Task {}` into a nonisolated helper would silently change its actor isolation — a real
    behavior change to ship as a side effect of a cleanup.
  - **Open design question for M3-T4/M6-T3:** we *guard* a filling disk but never *preflight*
    one — starting a recording with < 2 GB free stops it ~instantly with `.diskAlmostFull`
    (correct, but a refusal up front with "free some space" would be kinder than a 2-second file).

- 2026-07-15 (**free M3-T4 evidence, found by accident during M3-T3**): Franco's display went to
  sleep mid-session and handed us two display-handling findings for nothing.
  - ✅ **Display sleeping MID-recording behaves correctly**: SCK fired `didStopWithError`
    ("Failed to find any displays or windows to capture") → `finished(streamError(…))` → a
    **playable 1.81 s file**. That is ADR-007's fail-stop working in the wild, and it is most of
    what §4.3 asks for. M3-T4 should still do the deliberate lid-close run, but the mechanism is
    already observed.
  - 🐞 **BUG for M3-T4: a LOCKED screen is misreported as a permission failure.** Confirmed
    cause — Franco locked the screen on stepping away, so this is a 2-second repro, not a
    theory: **lock the screen → run `record` → "Screen Recording permission is needed"** while
    `CGPreflightScreenCaptureAccess()` says **granted**. `SCShareableContent` returns **0
    displays** for a locked screen, and `CaptureEngine.startDecision` maps *any* zero-display
    result to `permissionGuidance` — sending the user to System Settings to grant a permission
    they already hold. 02 §1's "empty results = permission missing" is **incomplete**: locked,
    asleep, and disconnected displays are indistinguishable from it. Fix in M3-T4 — gate the
    permission wording on the preflight actually disagreeing, else say "no displays available —
    the screen may be asleep, locked, or disconnected". `CaptureEngineTests.
    failsWhenNoDisplaysAvailable` encodes the conflation and must change with it. Deliberately
    NOT folded into M3-T3 (unrelated to the disk guard).
  - **Capture tests need the screen unlocked and awake.** Zero displays ⇒ nothing captures. If
    capture suddenly fails with a permission message mid-session while the preflight says
    granted, suspect a locked/sleeping screen before suspecting TCC — the message actively
    misleads you here until M3-T4 lands.

- 2026-07-15 (M3-T7 spike — mic device binding): full findings live in **02 §4** (experiment
  table + the two recovery routes) and **02 §1** (the nil correction). Meta-lessons worth keeping:
  - **The spike blew its time-box (30 min → ~2 h) and was worth it.** It killed a stale ⚠️ that
    had been shaping the design, produced a one-line root-cause model, and turned "can we ever
    recover the mic?" from a guess into two costed, de-risked routes. But log it honestly: a
    time-box that gets ignored should at least be noticed.
  - **My priors were 1-for-3.** I predicted leg 1 would fail (it worked), leg 2 would fail
    (right), leg 2b would fail (it worked). In this API, reason less and measure more.
  - **A test that never triggers its event reads exactly like a negative.** The first `--nil-follow`
    run "proved" nil doesn't follow — actually the AirPods never disconnected inside the fixed
    25 s window (buffer counts kept climbing). Fixed by watching for *either* outcome with a
    generous bound, plus an explicit INCONCLUSIVE verdict. Any future device spike should do the
    same rather than assume a duration.
  - **AirPods only disconnect when the case LID CLOSES** — an open case keeps them connected.
    That is what silently invalidated the first run; put it in any test instructions.
  - **`updateConfiguration` returns OK while doing nothing** when asked to bind a died device
    (8/8 attempts). No error path to detect it — you must watch for buffers.

- 2026-07-15 (M3-T6 mic-loss watchdog): what the live runs and the review taught.
  - **SCK keeps delivering mic buffers while paused** — proved by a 5 s scripted pause against
    a 3 s watchdog timeout that did NOT false-fire. That's why the watchdog needs no pause
    handling at all: it's a router-level consumer, and pause never stops the stream (M3-T1).
    If pause is ever changed to stop the stream, this watchdog WILL false-fire — read this first.
  - **Detection latency is timeout + poll interval** (3 s + ≤1 s). Live: mic died at 21.82 s,
    warning at ~25 s. Matches by construction; don't shrink the timeout without checking the
    load-jitter margin (M3-T1 saw ~0.9 s audio starvation under heavy load).
  - **Disarm the watchdog BEFORE `await stream.stopCapture()`, not after** (/code-review). Stop
    halts mic delivery and Bluetooth teardown can take seconds, so a watchdog still polling
    across that suspension reports a disconnect on a recording whose mic track is complete —
    "⚠️ disconnected" immediately followed by "✓ finished". Cancel-on-`terminate()` alone is
    too late. The same reasoning will apply to M3-T5's stall watchdog.
  - **`Task {}` inside an actor method INHERITS the actor's isolation** — it does not run off-
    actor (I had a comment claiming the opposite; the compiler disagrees). Fine here (the poll
    body is one lock-guarded compare) but don't assume a spawned Task escapes the actor.
  - **Dropping a `Task` reference does not cancel it.** An engine released while `.running`
    (never stopped, no error) left the 1 Hz poll waking forever — now cancelled in `deinit`.
  - **`start()` could resurrect a terminated engine**: a stream error can `terminate()`
    reentrantly during the `startCapture()` await, then `start()` resumed and set
    `state = .running` over it (pre-existing; M3-T6 made it worse by stranding an
    uncancellable Task). Now guarded with `guard state == .starting` on resume.

- 2026-07-15 (§4.2 LIVE — **docs/02 §4's mic-takeover claim is FALSE**): Franco recorded 60 s
  with AirPods, cased them at ~22 s. Result — the recording **continued to the full 60 s** and
  finished `userStopped`, dropped frames 0:
  ```
  duration: 59.85s
  track 1: audio aac  48000Hz 2ch  dur 59.79s   ← system audio, full
  track 2: video hvc1 4112x2570    dur 59.85s   ← video, full
  track 3: audio aac  24000Hz 1ch  dur 22.57s   ← mic (AirPods), STOPS at the disconnect
  ```
  - **The built-in mic did NOT take over. The mic buffers just stopped.** No format change, no
    error, no event. So M3-T2's format-compare detector correctly never fired — it is a valid
    guard for a *same-device* format change, but it is NOT the AirPods story it was written for.
  - **Root cause: we pin an explicit `microphoneCaptureDeviceID`** (forced by 02 §1 — nil throws
    "invalid parameter" on 15.6). SCK captures the device you named and won't substitute. With a
    pinned ID a device *switch* essentially cannot occur; only *loss* can. Corrected in 02 §4.
  - **This exposed a real ADR-007 violation in the status quo:** the mic died and nothing told
    the user — 37 s narrated into a void, exit 0, file looks healthy. "Silently degraded" is the
    exact failure ADR-007 forbids. Fix = a starvation watchdog (M3-T6) emitting `microphoneLost`.
  - **Policy decided: ADR-012** — mic loss notifies and KEEPS recording (ending a 90-min screen
    capture over a headphone battery is the worse outcome). Amends ADR-007 for that trigger only.
  - **Open (M3-T7 spike):** re-attaching to the built-in mic to keep recording *sound* needs
    (a) `SCStream.updateConfiguration` to accept a new mic device ID live — unverified, and
    (b) a fixed-format resampled mic input, since the writer input's format is welded to the
    first buffer's and cannot change after `startWriting()`. (a) is spike-able headlessly.

- 2026-07-15 (M3-T2 mic format-change): fail-stop wiring + a reusable seam.
  - **Detection = compare the mic buffer's ASBD to the input's established one** (sample rate,
    channel count, format ID). SCK mic buffers are LPCM and a given device's format is stable,
    so a device switch (AirPods 24 k mono → built-in 48 k mono/stereo) is the only thing that
    changes those fields — no false positives. `MovieRecorder` stores the ASBD when it builds
    the mic input and checks every later mic buffer; on a diff it fires a **one-shot** callback
    and drops the mismatched buffers (never feed a new format into the established input — it
    corrupts the track, docs/02 §4).
  - **New reusable seam: `CaptureEngine.stop(reason: EndReason = .userStopped)`.** A monitor that
    detects a fail-stop condition passes its reason; it flows through the existing `.stopped`→
    `.finished` path so the file finalizes as `.finished(reason:)`. M3-T3 (disk floor →
    `.diskAlmostFull`) and M3-T4 (display/sleep) reuse this — don't reinvent per-condition stops.
  - **The recorder signals OUT via an injected `@Sendable` callback; it never touches the engine.**
    `RecordingSession` builds the callback capturing the `engine` actor (no `self` capture, no
    retain cycle) and injects it at recorder init. The callback fires from a capture queue under
    the recorder lock but only spawns a `Task { await engine.stop(...) }` — non-blocking, and the
    later `recorder.finish()` runs off-lock via the event loop, so no re-entrancy/deadlock.
  - **Detection sits AFTER the writing gate, deliberately** (high-effort /code-review finding).
    Placed before it, a swap in the first frame-interval fail-stopped a recording with nothing
    written → `.failed(noFramesWritten)` + discarded output, while a swap a hair later gave a
    playable file — the outcome flipped on sub-frame timing. Pre-writing mic buffers are already
    dropped by the `guard didStartWriting`, so capture now just carries on until there's
    something worth saving. Two tests pin this (fires-once-and-finalizes / before-writing-
    doesn't-fail-stop) — note the mic-only test only passed originally *because* of the bug.
  - **The callback fires OUTSIDE the lock** (same review): `consume` registers the notify defer
    *before* the unlock defer, so LIFO runs unlock first. `lock` is non-reentrant — firing under
    it made any handler that touched the recorder a capture-queue deadlock waiting to happen.
  - **`stop(reason:)` carries the reason through the `.starting` path too** (same review): the
    branch used to keep only `stopRequested` and terminate as `.userStopped` on resume, so a
    swap during `startCapture()`'s suspension would misreport the cause. Now paired with
    `requestedStopReason`.

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

# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short; details go to Field notes / History.

## Now

- **M6-T3 DONE — error-message audit.** Tested all 21 user-facing failure paths against "says
  what happened AND what to do"; 15 passed, 6 fixed (plan approved by Franco). (1) the write-fail
  title lied — the G4 §5.4 follow-up: `hadStarted` now reads `session?.hasStartedSession` not the
  icon (which flips to `.recording` before the write failure surfaces) → **live-observed "Couldn't
  start recording"** via a temporary forced-write-fail hook (reverted). (2) three raw-NSError
  bodies → plain actionable copy + the raw string to the unified log (recorder setup, finalize,
  replay save). (3) disk-almost-full names the remedy. (4) the CLI no longer says "in Settings"
  (surface-neutral copy). (5) the app's reserve-failure surfaces `OutputLocation`'s specific reason
  instead of a generic line. (6) replay-pipeline-died names the re-arm recovery. /code-review
  (medium) → 4 minor findings, all applied: the shared finalize message over-promised recovery for
  the stranded-file path (now names where the file actually is), a duplicated catch → `finalizeFailed`
  helper, a redundant `@ObservationIgnored` on a static, a 4-line comment trimmed. Verified: #1 live,
  #4/#5 live via CLI, #2/#3/#6 unit-tested on the pure mapper; 248 tests. **Next: M6-T5 (launch-at-
  login + README + docs closeout).** Also queued: T11 (stale mic list), T12 (discard recording).

- **M6-T10 DONE — the open-menu highlight corruption is fixed.** Root cause: a per-second
  refresh published through @Observable and rebuilt every AppKit row of the OPEN menu,
  garbling hover/highlight (the artifact Franco filmed). Fix: refresh once per open
  (`RefreshOnMenuOpen` = `.task` for first appearance + `NSMenu.didBeginTracking` for
  reopens), and every refresher (`refreshProgress`/`refreshSources`/`refreshRecentRecordings`)
  publishes ONLY on a real change — the M4-T3 lesson, applied to all three. The recording
  header consequently **stamps at open and holds** (a live clock isn't implementable in a
  `.menu` MenuBarExtra without the corruption — `Text(timerInterval:)` doesn't animate
  through the bridge); docs/06 amended from "≤ 1 Hz" to "stamps at open". Measured fixed:
  5 one-second hover captures, cursor on Settings, highlight clean in every frame, header
  frozen — not eyeballed (M4-T1 rule). /code-review (high): the adversarial pass REFUTED
  the submenu-refire hazard (didBeginTracking fires once per tracking session, not per
  submenu); 3 real findings applied (unguarded source/recents publishes, stale/lying
  comments, first-open subscription race → the `.task`+notification belt-and-suspenders).
  246 tests. **The armed-drop scare was a MEASUREMENT ARTIFACT** — a single `replayArmed=0`
  read had a stale precondition (disarmed earlier in a messy measurement session); three
  clean trajectories (graceful-quit, hot-swap deploy, kill-relaunch) all hold armed=1
  through 30 s+. T9 stands. **Same lesson as before: assert the precondition before reading
  a persisted flag.** **Next: M6-T3 (error-message audit).**

- **M6-T9 DONE — armed state survives relaunch.** Encoder death now gets bounded patience
  (the pure `recoveryAction` rule: 6 strikes = 5 interval sleeps ≈ 25 s, healthy-run reset,
  deliberate transitions clear the streak) instead of instant self-disarm; stream deaths
  keep infinite patience. /code-review (high) caught 3 real bugs in my first cut, all
  fixed: the riding-a-recording retry had no delay (burned the whole budget in ms — the
  exact transient the task targets), `setOutputDirectory` dropped folder changes while the
  pipeline was down (stamp-first, the `windowChanged` pattern), and the failure streak
  never cleared on deliberate transitions. Retry decision extracted pure → both branches +
  the reset unit-tested without wall-clock; 244 tests. Live: **3× kill→relaunch cycles,
  armed survived each unaided** (plus a 30 s per-second watch), display-sleep regression
  green. One false alarm en route: a cycle run without asserting the armed precondition
  read a pre-existing 0 as a failure — assert the precondition before measuring.
  **Next: M6-T10 (open-menu rebuild artifact), then T11 (stale mic list), T3, T5, T4.**

- **M6-T8 DONE — arm/disarm works mid-recording.** The recording menu carries the shared
  arm toggle + save row (one `replayControls` builder for both menus; readiness-gated; a
  hotkey SwiftUI can't map falls back into the button title so the combo hint never
  vanishes). **The live verify caught the task's real bug:** arming mid-recording was a
  silent no-op — `recordingStarted` guarded on the controller's own `isArmed`, which only
  the idle path set; it now self-arms (all call sites gate on the user's intent; protocol
  doc states the contract; non-vacuous regression test via `isPipelineBuiltForTesting` —
  `requestSave`'s acceptance can't distinguish no-pipeline from empty rings). Mid-recording
  arm/settings paths now resolve the mic pick through `replayCaptureConfiguration()` (no
  dead ring when the picked mic is away). /code-review (high): 8 findings, batch-approved,
  all applied. Live verified on the installed app: toggle unchecked mid-recording → arm →
  16.64 s clip (= span since arming) → disarm mid-recording → recording ran on → 44.61 s
  clean file. 241 tests. ⚠️ **The armed-state drop reproduced on a GRACEFUL quit→relaunch
  during the final redeploy** — the SCK reap race isn't kill-specific (M6-T9's row updated;
  ~1-in-3 across today's restart cycles). /Users/Shared runs the full T6+T7+T8 build.
  **Next: M6-T9 (armed state survives relaunch).** Then T10 (menu rebuild artifact), T3,
  T5, T4 decisions.

- **M6-T7 DONE — the recording file defends itself.** `RecordingFileSentinel` (vnode watch
  on the writer's fd): move/trash → renamed back within a beat + "Still recording · file
  moved back"; unlink → immediate honest fail-stop; unrestorable move → finalized in place
  via the fd and reported *saved* at its new location, never "deleted". `.partial`
  lifecycle: reserve claims the partial, finalize renames (collision-resolving,
  extension-less-safe), launch + CLI-start sweeps recover stale orphans (60 s mtime gate so
  a live cross-process writer is never touched). /code-review (high) returned **10
  findings; triaged with Franco** — GUI-relevant subset all fixed (drain-cancel, teardown
  latch, truthful stranded copy, finalize-failure never claims loss, staleness gate), CLI
  paper cuts all fixed (placeholder cleanup, interrupted-recording error copy, no trailing
  dot, startup sweep), one accepted-as-designed (final name unheld during recording → " 2"
  step at collision; 02 §7 note). Live legs on the final build: move → one warning +
  restore + clean probe; delete → clean fail-stop; kill -9 → playable partial (0.47 s-class
  loss), recovery rename proven. 240 tests, TSan clean (caught a real sentinel init race).
  **Next: M6-T8 (arm/disarm while recording) — then the app swap** (dist now carries T6+T7;
  /Users/Shared still runs the pre-T6 build). Also open: the leg-2 armed-state-drop
  follow-up (retry vs self-disarm on arm-time stream failure), unslotted.

- **M6-T2 DONE — the soak passed whole (2026-07-17).** Leg 1 (2-h battery, real usage,
  Zoom, replay armed, 3 mid-recording replay saves): 19.5 GB / 2:00:23, tracks within
  110 ms, battery 99→62%, CPU avg 12.9%, RSS trendless, no thermal events; Franco's scrub:
  "smooth throughout, no desync". Leg 2 (kill -9, amended to 1 h): killed at 3540 s →
  salvage probes 3539.53 s = **0.47 s lost** (criterion ≤10 s); app relaunched to Ready.
  Leg-2 file had no mic track — AirPods weren't available at start; picked-device-or-
  nothing, by design. Test file deleted; leg-1 file left for Franco. ⚠️ **New finding
  (field note): the crash→relaunch lost the persisted armed state** — re-arm at launch hit
  a pipeline failure (likely SCK refusing a stream while the killed process's stream was
  being reaped) and pipeline-failure self-disarms instead of retrying. Re-armed by hand,
  works — the failure was transient, which is exactly why it belongs in the retry bucket.
  Candidate fix for M6-T3/M6-T8-adjacent work; Franco to slot it.

- **M6-T6 DONE — replay-window resize preserves the buffer.** Grow retains + fills to the
  new length (the muxer's existing short-clip fallback covers the gap); shrink evicts
  eagerly, single-pass, under the ring lock. `replaySeconds` routes to a new
  `windowChanged` (no pipeline teardown); quality/fps keep the rebuild path. **/code-review
  (high) found 2 real bugs in the first cut, both fixed by never replacing the muxer:**
  it now takes `update(seconds:)`/`update(outputDirectory:)` + `perform(afterPendingSaves:)`
  on its serial mux queue, so (1) the `isSaving` coalescing latch survives settings changes
  (was: rapid ⌥⌘R around a length change → two concurrent writer passes), and (2) ring
  eviction is serialized *behind* any in-flight save (was: save 120 s → instant shrink →
  the triggered save silently truncated to 30 s). `setOutputDirectory` got the same
  treatment (its rebuild had the same latent latch loss). 231 tests (+2 muxer regression
  tests), TSan clean; live in-process verify: save racing a grow returned 31.08 s of
  pre-change buffer, post-shrink save 10.03 s. **Not covered by a unit test: the
  mid-recording routing** — `session` is private with no fake seam and the didSet has no
  session branch (structurally can't mis-route); M6-T8's live verify exercises it for real.
  **Next: M6-T2 leg 2 completes (~13:52 kill), then M6-T7 (plan artifact first).**

- **M6-T2 LEG 1 (2-h battery soak) — agent legs PASSED 2026-07-17; human legs pending.**
  Run 10:38:33→12:38:33, Franco's real mixed usage incl. a Zoom call, AirPods mic, replay
  armed throughout, High preset (his setting; §7 is preset-silent). File: 19.5 GB,
  **7223.42 s (2:00:23), hvc1 + aac 48k/2ch + aac 24k/1ch, track ends within 110 ms** —
  probes clean. Battery **99%→62% (37% drain, Zoom-inflated)**; app CPU **avg 12.9% / max
  19.3%** of one core (recording + armed replay + the menudriver rig); RSS 98–485 MB
  oscillating, **no upward trend, no thermal warnings** (120 samples, 60 s cadence).
  Bonus: **3 replay saves mid-recording** (10:52/11:02/11:39) — §6.4 simultaneity at 2-h
  scale, all clips + the main file clean. ⚠️ **Incident, survived: Franco accidentally
  trashed the in-progress file at 11:39** while tidying ~/Movies; the writer's fd followed
  the rename, finalize completed *in the Trash*, file restored intact (probe above).
  Safeguard: Franco picked options 1+3 → task M6-T7 (docs/03). **Human legs PASSED
  2026-07-17 (Franco): "smooth throughout, no desync" — the §3.3 clap scrub at 0/1/2 h
  holds and no visible stutter. Leg 1 is fully closed; the 19.5 GB file may be deleted.
  Pending T2 closure: leg 2 only (kill -9 at ~1:59 of a second 2-h run).**
  **Next now: M6-T6 (replay-window resize preserves buffer — plan approved 2026-07-17).**

- **M6-T1 DONE — acceptance run adjudicated, all five rows closed (2026-07-17).**
  C3 PASSED (measured). **C2 resolved by AMENDMENT (Franco: "not that concerned about the
  size")** — 00-product-brief's ≤1.5 GB/h is now "meaningfully smaller than Tier-1", met
  at ≈6×; the 2.59 GB/h measurement stays on record below. C1 delegated to M6-T2's soak;
  C4/C5 waived. Brief checkboxes ticked/annotated accordingly; evidence recording deleted
  per ruling. **Next: M6-T2 (2-h battery soak — HUMAN, physical unplug + 2 h of Franco's
  mixed usage; agent preps the rig when he schedules it). Next agent-actionable task:
  M6-T3 (error-message audit).**
- **M6-T1 detail (was in progress) — C3 (instant replay)
  PASSED 2026-07-16, headless, against the live install** (`/Users/Shared/ScreenRec.app`,
  byte-identical to today's dist, v0.1.0): not recording, armed via menu, 70 s fill,
  Save Replay Now → signal→file **0.30 s** adjusted (raw 1.17 s incl. the measured 0.87 s
  menudriver overhead), write-complete ≈0.8 s; probe: 60.55 s (60 + ≤1 keyframe interval),
  hvc1 + aac 48k/2ch + aac 24k/1ch (AirPods mic), first video sample pts 0.000 sync=true
  (keyframe start). Content-is-last-minute carried from G5 §6.2 (Franco). Plan rulings
  (Franco, 2026-07-16): **C1 delegated to M6-T2's soak** (one 2-h run counts for both);
  **C4 (fresh-account <2 min) and C5 (player/NLE matrix) WAIVED** ("no need for this
  test" — recorded as waivers, not passes). **C2 MEASURED 2026-07-17 — FAILED:** 30.5-min
  Balanced menu-driven recording during Franco's real usage → 1.295 GB ⇒ **2.59 GB/h** vs
  the brief's ≤1.5 (≈5.7 Mbps avg vs the ≈3.4 implied; retained video averaged 25.9 fps —
  an active-screen morning). File probes clean (1829.06 s, hvc1 + 2×AAC, tracks within
  40 ms). The measurement stands; remedy is **Franco's open decision**: (a) amend the
  criterion (the brief's actual differentiator — 2–4× smaller than Tier-1 — is met at ~6×
  vs Tier-1's ~34 Mbps), (b) retune Balanced's AVVideoAverageBitRateKey target + re-run,
  or (c) hard caps, which for the *recording* path means leaving AVAssetWriter for direct
  VT (M2-T6: DataRateLimits isn't reachable through AVAssetWriter) — M6-T4-sized. T1's
  run itself is complete (C1 delegated, C2 measured-failed, C3 passed, C4/C5 waived);
  the checkbox stays unticked until Franco rules on C2.
- **🎉 M5 COMPLETE — GATE G5 PASSED 2026-07-16 (all legs).** T6's audit: burst leg (busyscene,
  4.5 min max load) CPU 7.2% avg / RSS flat 201–202 MB; main leg (30.2 min armed during Franco's
  real usage) CPU 4.7% avg / RSS median 216 MB, drift min5→end +7 MB (no leak) / min-30 save
  0.17 s write, ≈0.6 s end-to-end (menudriver rig overhead 0.87 s measured and subtracted —
  raw 1.53 s). §6.2 content check + §6.4 simultaneity + §6.3 coalescing all previously green.
  Bitrate ruling: (b) Balanced parity, no replay cap (04 §6.1 amended to ≲400 MB busy;
  DataRateLimits is the ready lever). **Next: M6 — ship-quality pass. M6-T1 (full acceptance
  run against 00-product-brief success criteria).** Owed to nobody: the only open observation
  is the toggle-off Slack suppression A/B (docs/06, purely documentation).
- **M5-T5 DONE — replay is in the app.** Arm toggle +
  ⌥⌘R Carbon hotkey + Save Replay Now + armed badge + Settings section + notifications, all on
  the shared-stream design (recording and armed replay are consumers of ONE stream; the buffer
  deliberately resets at record start/stop — Franco's ruling, and record-start implies the
  replay was already saved if wanted). §6.4 ✅ headless; armed survives relaunch and display
  sleep (5 s retry); 222 tests. /code-review found 10 confirmed bugs (presented first, batch
  approved) — see field note; the re-home buffer wipe was verified fixed live (53.9 s clip
  after two menu opens). **Next: M5-T6 (30-min memory/CPU audit — ASK FRANCO before any
  busy-screen leg).** Needs Franco (quick): ⌥⌘R while another app is frontmost; badge/menu
  taste pass; §6.2 content check from T4. Also owed (small, separate commit): trim long
  output-folder paths in the menu row (Franco, 2026-07-16).
- **M5-T4 DONE — replay saves real files.**
  (`ReplayMuxer`: rings → keyframe-trimmed, rebased, passthrough-video + AAC `Replay … .mov` in
  ~0.3 s; SIGUSR1 + `s`+Return triggers, coalescing, drain-before-exit; window anchored at the
  newest pts across all rings + docs/02 §5 tail patch so a static screen still saves the true
  last N seconds. §6.2 ✅ §6.3 ✅ headless; 207 tests, TSan-clean; /code-review findings presented
  → batch approved — see field note.) **Next: M5-T5 (app integration — arm toggle, ⌥⌘R Carbon
  hotkey, menu item, "Replay saved" notification; owns `replayArmed`/`replaySeconds`/
  `replayHotkey` per docs/06).** Owed to Franco (non-blocking): §6.2's "genuinely the last
  minute" content check.
- **M5-T3 DONE** (`ReplayAudioRing`: deep PCM copies of
  `.systemAudio` + `.microphone` into per-source rings; ASBD latch that **clears + re-latches on a
  format change** (Franco picked re-latch over drop-forever, 2026-07-16 — "see how it works in the
  wild"); `replay-arm` grew `--mic/--no-mic`, format lines and a per-ring ticker; 2-min live verify
  exact on byte math; 201 tests, TSan-clean; /code-review applied — see field note).
  ⚠️ G5 risk to settle by M5-T6: §6.1's "RSS ≲ 200 MB" was written against 02 §9's ~10 Mbps
  estimate, but Balanced at this display is 19 Mbps ⇒ a busy 60 s video ring alone is ~141–190 MB
  payload. Candidate fix: VT `DataRateLimits` on the replay session (we drive VT directly, unlike
  AVAssetWriter — the M2-T6 limitation doesn't apply here). Franco's call at T6.
- **M5-T2 DONE** (`ReplayEncoder`: VTCompressionSession →
  the ring; CLI `replay-arm --seconds 60 --duration N`; verify green — 3-min run plateaued at
  62.0 s / keyframes ≈ 1/s / ring bytes flat; 194 tests, TSan-clean; /code-review high applied —
  see field note). ⚠️ Verifies needing a busy screen: ask Franco before running
  `busyscene` — it takes over his display (his ruling, 2026-07-16).
- **M5-T1 DONE** (`RingBuffer`: generic, duration-bounded,
  keyframe-aligned clip, NSLock-guarded, TSan-clean, 7 tests; /code-review medium applied). M4 is
  code-complete; G4 is §5.1 ✅ / §5.2 ✅ / §5.3 ✅, and **§5.4's fix landed** (the unwritable-folder
  wedge — see field note + `fix:` commit) with the **fresh-account re-run DEFERRED (Franco,
  2026-07-16)** along with the two /code-review follow-ups. M5 core (T1–T4) is CLI-driven and
  doesn't need G4 (dependency graph); M5-T5's app integration does. Also shipped: the menu now
  shows the output folder (`Open Recordings Folder — ~/Movies`).
- **Current milestone (was):** M4 — the menu-bar app. M3 COMPLETE, G3 PASSED (all legs).
- **M4-T1 DONE.** `AppCore` library target exists (RecorderCore-only deps, no AppKit/SwiftUI):
  `AppState` (@MainActor @Observable) folds `EngineEvent` → `StatusIcon`; SwiftUI views stay in
  `ScreenRecApp`. All three icon states verified by screenshot, not by eye-of-faith — including
  the pulse (measured 2.15× redness swing vs the 2.22× the 0.45 alpha floor predicts). No Dock
  icon confirmed via `lsappinfo` (`ApplicationType=UIElement`). 108 tests (+11).
- **M4-T2 DONE.** The menu works end-to-end: menu-driven Start → 5 s → Stop & Save produced a
  playable 6.38 s file (probed: hvc1 4112×2570 + aac 48k/2ch), with the recording then appearing
  in the recent-files rows. **Verified headlessly** via `tools/menudriver.swift` + the new
  Accessibility grant — docs/03's "(human)" tax on M4/M5 menus is largely gone. `AppState` now
  owns a `RecordingSession`; pickers/recent-files/header text live in AppCore, views in
  ScreenRecApp. RecorderCore untouched. 133 tests (+25).
- **M4-T3 DONE.** Onboarding ships: the window opens itself at launch when blocked, and from
  the menu header always. `OnboardingModel` is a pure truth table (AppCore); the window, the
  requests and the relaunch are the app's. **M4-T2's 3-track probe closed** — mic granted through
  the new window → menu-driven recording → `hvc1 + aac 2ch + aac 1ch`, 7.36 s, playable. 147
  tests (+13).
- ✅ **The M3-T4 question is SETTLED — an ungranted process throws `-3801`, never enumerates
  zero.** Measured on both paths via a throwaway bundle (02 §1's recipe); `startDecision` was
  right and is unchanged. The docs had called this untestable without a fresh account; it wasn't.
- **M4-T4 DONE (pending Franco's look at the window).** The app remembers: `outputDirectory`,
  `qualityPreset`, `fpsCap` persist under exactly docs/06's names and survive a relaunch —
  verified with `defaults read` + a quit/relaunch, headlessly. Settings window (⌘, and the menu)
  with the output-folder preflight. **Descoped by Franco**: replay settings → M5 (with the
  feature), launch-at-login → M6-T5 (the app has no permanent address until then). 162 tests.
- **M4-T5 DONE.** Notifications ship: menu-driven recording → Stop & Save → relaunch with
  `--print-delivered-notifications` → `Recording saved · 00:00:05 / Recording … .mov`, docs/06's
  copy exactly. 174 tests. **docs/06's table covered four fewer cases than the engine emits** —
  amended (see field notes). Owed to a human: does a banner appear, and does a click reveal.
- **M4-T6 DONE — M4 is CODE-COMPLETE.** App icon (candidate C, a display + record dot; code-drawn
  via `tools/makeicon.swift` → `.icns` via `Scripts/makeicns.sh`, checked in) and single-source
  version stamping (`VERSION` → `bundle.sh` stamps `__VERSION__`, fails loud if either missing).
  docs/03's three checks green: Finder icon resolves from the bundle (NSWorkspace), version ==
  VERSION, `codesign --verify --strict`. ⚠️ **The notification BANNER still shows the generic
  placeholder icon** — my own T5/T6 stretch claim, not a docs/03 requirement. `usernoted` caches
  the icon per bundle-id and cached the icon-less build; `lsregister -f` didn't clear it and I'm
  not restarting a system daemon to force it. Expected to resolve at M6 (real install path +
  notarization). Recorded, not faked.
- **G4 IN PROGRESS — headless legs closed, human legs handed to Franco (walkthrough artifact).**
  - **§5.2 grants-survive-rebuild — PASSED headlessly.** Designated requirement byte-identical
    across an A→B `bundle.sh` rebuild (`codesign -d -r-` diff empty), `--verify --strict` passes,
    and — the behavioral half — the rebuilt app launched to `ScreenRec — Ready` and a menu-driven
    Start→Pause→Resume→Stop produced a playable 19.43 s file (hvc1 4112×2570 + aac 48k/2ch) with
    no re-grant. Grants attach to that identical DR, so screen (and by the same mechanism mic,
    proven live in M4-T3) survive.
  - **§5.3 menu-flow + notification delivery — PASSED headlessly.** `menudriver` drove
    Start→Pause→Resume→Stop; the `Pause`→`Resume` label swap and the recording/paused headers
    match docs/06. Both notification copies delivered with fresh dates: normal stop
    `Recording saved · 00:00:19` and — via a **temporary `--force-fail-stop` disk-floor probe,
    reverted, tree clean** — the fail-stop `Recording saved · 00:00:02 / Ended: disk almost full.
    File is playable.` (playable 2.05 s file). Exact match to `RecordingNotification.swift`.
  - **§5.1 ✅ + §5.3 ✅ LIVE (Franco, 2026-07-16, fresh account + this one).** Auto-relaunch on the
    screen-grant transition confirmed (had to force the ungranted state — the fresh account's
    Screen Recording was already on); banner renders + click reveals in Finder confirmed. The
    macOS 15 "bypass the private window picker" consent shows our icon as the badge (LaunchServices
    resolves it — the notification-banner cache is the separate stale one). §5.1 WATCH ② (Grant→
    Settings switch) is reasoned-not-watched.
  - **§5.4 ❌ FOUND A REAL BUG, now FIXED (see field note + the fix commit).** Choosing an
    unwritable output folder (Desktop w/o Files & Folders) **wedged the app** — swallowed
    `startWriting()` failure, no terminal event, live SCStream stuck. Fixed both halves: the
    recorder now surfaces the failure → clean `.failed` (no wedge), and preflight probes with the
    real `AVAssetWriter` API so Desktop is rejected at selection. Verified: unit + headless
    forced-failure integration (no wedge, "Couldn't write…" notification). **Owed: fresh-account
    end-to-end re-run with the fixed build.**
- **The `/simplify` sweep over M3 was run** (commits `fff901e`, `2522e26`) — an ARC cycle that
  made `CaptureEngine.deinit` unreachable, and the M3-T7 spike held to the CLI's bar.
- **Replay-armed toggle + icon badge: deferred to M4-T4** (Franco, 2026-07-15), which owns the
  `replayArmed` key. Nothing can arm replay until M5, so a switch now would arm nothing.

## M3 (closed)

- **Was:** M3 — pause/resume + robustness. M2 COMPLETE, G2 PASSED (5/5).
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
- **🎉 M3 COMPLETE — GATE G3 PASSED 2026-07-15 (all legs; see the gate table).** Pause/resume,
  mic-loss reporting, disk guard, display-loss classification and the stall watchdog all land,
  with every §4 leg verified. Only §4.3's monitor-unplug is N/A (hardware).
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

- [x] **M6-T1 C2 ruling — RESOLVED 2026-07-17 (Franco): amend the criterion** ("I'm not
      that concerned about the size of the video"). Brief updated; the 2.59 GB/h Balanced
      measurement stands on record; evidence file deleted after the ruling.
- [ ] **M6-T2 — the 2-h battery soak (physical unplug + 2 h mixed real usage, AirPods,
      replay armed):** needs Franco to pick the block; agent preps and instruments it.
- [x] ~~G4 §5.4 fresh-account re-run~~ — **DISCARDED by Franco 2026-07-16** ("let's discard it,
      not worried about it"). The fix itself stands verified: unit + headless forced-failure
      integration (no wedge, clean "Couldn't write…"), plus Fix B's preflight probing the real
      AVAssetWriter API. Only the fresh-account *end-to-end* rerun is waived. G4 closes on this.
  - **§5.1 WATCH ② (Grant… → Open System Settings…)** — reasoned-not-watched; catch it if convenient.
- [x] **M5-T5 human legs — PASSED 2026-07-16 (Franco):** ⌥⌘R fired from another app (saves worked,
      and with the mirroring/sharing toggle enabled the banner renders — the user-side remedy is
      now MEASURED); "the UI looks great" (badge, menu rows, Settings section).
- [x] **G5 §6.2 content check — PASSED 2026-07-16 (Franco):** the saved clip is genuinely the
      last minute.

- [x] DONE 2026-07-14: Franco granted the Claude Code runtime ("2.1.209") Screen
      Recording AND Microphone, so capture tests (engine-smoke/record/probe) run directly
      via the agent's shell. Both applied immediately, no restart. If Claude Code's
      identity changes, the grants may need re-doing.

- [x] M0-T2 prerequisite DONE (2026-07-14): self-signed Code Signing identity
      "screenrec-dev" created in login keychain and trusted for codeSign policy
      (`security add-trusted-cert -r trustRoot -p codeSign`). Verified: signs and
      passes `codesign --verify --strict`. devsign.sh should find and use this
      identity; it must NOT try to create a new one.
- [x] **Screen Recording for the .app — GRANTED 2026-07-15 (Franco)**, by hand via the "+" button
      (System Settings → Screen & System Audio Recording → dist/ScreenRec.app). Survives
      `bundle.sh` rebuilds, as M0-T3's stable designated requirement promised. Real users will
      never do this: M4-T3's `Grant…` button calls `CGRequestScreenCaptureAccess()` and macOS
      handles it.
- [x] **Microphone for the .app — GRANTED 2026-07-15 (Franco), through M4-T3's own Grant…
      button** — the first permission the app obtained for itself, which is the whole point of
      the task. Unblocked M4-T2's 3-track probe immediately.
- [x] **Notifications for the .app — GRANTED 2026-07-15 (Franco)**, via the route T4-T3 added
      (menu header → Set Up ScreenRec → Notifications). All three rows are now green, so M4-T5
      can send one the day it lands.
- [x] **M4-T3 visual check — PASSED 2026-07-15 (Franco).** "looks good now", after he caught two
      things live: a granted row with no route out (→ quiet `System Settings` links), and the
      intro line truncating mid-sentence (→ it wraps). ⚠️ **Two paths remain verified by
      reasoning + review only, not by observation** — this machine can't reach them without
      revoking its own grant: (1) the auto-relaunch when a grant lands mid-session, and (2) the
      `Grant… → Open System Settings…` switch on the screen row. Both are reachable on a fresh
      account, so **G4 §5.1's walkthrough is where they finally get watched**.
- [x] **Accessibility for Terminal — GRANTED 2026-07-15 (Franco).** Unblocks
      `tools/menudriver.swift`. Note it's on **Terminal**, not a "Claude Code" entry. Broad grant
      (anything in Terminal can drive any app) — fine to revoke once M4/M5 menu work is done; the
      product never needs it (M5's hotkey uses Carbon RegisterEventHotKey, no TCC).
- [x] **M4-T1 visual check — PASSED 2026-07-15 (Franco).** "i like how it looks currently".
      Agent did the existence half (all three states screenshotted, pulse measured); Franco
      signed off the taste half. The icon constants are now settled: 12 frames / 2 s cycle,
      0.45 alpha floor, `record.circle` / `record.circle.fill` red / `circle.lefthalf.filled`
      amber. Don't churn them without a reason.
- [x] **G3 §4.1 cross-seam A/V sync — PASSED 2026-07-15 (Franco).** Sync holds across the seam.
- [x] **G3 §4.2 mic-disappears — PASSED 2026-07-15 (Franco).** Two runs: the first (pre-M3-T6)
      disproved the gate's premise (no takeover → docs/02 §4 corrected, ADR-012 written); the
      second (post-M3-T6) passed the redefined gate — loss reported, recording continued, file
      playable. A bonus reconnect run proved a lost mic never returns for the session.
- [x] **M3-T7 spike — DONE 2026-07-15** (all legs run; findings in 02 §4).
- [x] **G3 §4.3 lid-close — PASSED 2026-07-15 (Franco).** Machine slept mid-recording → suspended
      → finalized `displayDisconnected` + playable 11.2 s file on wake. Confirms lid-close is the
      same -3815 as display sleep, and that `.systemSleep` has no signal to map from.
- [ ] **G3 §4.3 monitor unplug — N/A on this hardware** (built-in display only; no external ever
      attached). Worth one run if an external display ever exists: unplug it mid-recording while
      capturing *that* display. It could reveal a code other than -3815, which would need a new
      `endReason` mapping (02 §7). Not blocking G3.
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
| G3   | ✅ **PASSED 2026-07-15** | §4.1 pause-math: scripted `rec10,pause5,rec10` (--no-mic). Calm box → 4 runs 19.86–19.98s, all ∈ [19.8,20.2], tracks match ≤40ms. Loaded box (post code-review workflow, load ~2.6) → mean 20.05s over 8 runs (25s wall→20s file ⇒ 5s pause exactly removed), 5/8 strictly in-window; the 3 outliers are load jitter (audio starvation stretches the video tail; a load-delayed resume frame), NOT pause-math error. All runs probe monotonic-clean. §4.2 mic-disappears ✅ PASSED 2026-07-15 (Franco, post-M3-T6, per the ADR-012 definition): AirPods cased at ~22s of a 60s run → CLI printed `⚠️ microphone disconnected — still recording` at ~25s (≈3.2s latency = 3s timeout + ≤1s poll), recording ran to the end, `finished (userStopped)`, file playable, mic track 21.82s vs video 59.83s. First run (pre-M3-T6) disproved the gate's premise — no takeover, buffers just stop → docs/02 §4 corrected, ADR-012 written. Also proved: a reconnected device NEVER resumes (mic gone for the session). §4.4 disk-guard ✅ PASSED: `--test-disk-floor 500000` (GB) vs 676 GiB free → `finished (diskAlmostFull)`, file playable (2.25s); negative verified on a real non-boot volume (4 GB HFS+ image, importantUsage reads 0 → records the full 8s, `userStopped`) after /code-review caught that the recommended capacity key reads 0 on every external volume. §4.1 cross-seam clap-sync ✅ (Franco — sync holds across the seam). §4.3 ✅ both ways in: display sleep (headless via `pmset`) → playable 3.3s, and lid-close/system sleep (Franco) → `finished (displayDisconnected)` + playable 11.2s file finalized on wake, confirming lid-close is the same -3815 and that `.systemSleep` is genuinely unreachable. §4.3 monitor-unplug N/A — built-in display only. |
| G4   | ✅ **PASSED 2026-07-16** (§5.4 fresh-account rerun waived by Franco) | §5.2 ✅ headless: DR byte-identical across A→B rebuild + `--verify --strict` + rebuilt app `Ready` → menu-driven 19.43 s playable file, no re-grant. §5.3 ✅ headless (delivery) + ✅ live (Franco: banner renders + click reveals). §5.1 ✅ live (Franco: auto-relaunch on grant transition, forced the ungranted state). §5.4 ❌→**FIXED + verified** (unit + headless forced-failure integration: no wedge, clean "Couldn't write…"; preflight probes the real AVAssetWriter API → Desktop rejected at selection); the fresh-account end-to-end rerun was **discarded by Franco 2026-07-16** — the waiver, not a pass, is the record. |
| G5   | ✅ **PASSED 2026-07-16** | §6.1 ✅ burst: 4.5 min busyscene max load → CPU 7.2% avg (cumulative), RSS flat 201–202 MB (+1 MB), occupancy pinned (T2 evidence). §6.2 ✅ save <1 s (0.08 s signal→file external, T4) + probe hvc1+2aac 60.56 s keyframe-aligned + content genuinely the last minute (Franco). §6.3 ✅ two rapid triggers → one coalesced clean file (T4 live + OS-level signal merge). §6.4 ✅ recording (35.99 s) + mid-recording replay (32.29 s) off one shared stream, both probe-clean (T5). §6.5 ✅ 30.2 min armed real usage: RSS drift min5→end +7 MB (no leak), CPU 4.7% avg, min-30 save 0.17 s write / ≈0.6 s end-to-end (rig overhead subtracted; raw 1.53 s incl. 0.87 s menudriver). |
| G6   | 🟡 soak legs passed (G6 = v1 done awaits the rest of M6) | §7 leg 1 ✅ 2026-07-17: 2 h battery, real usage + Zoom, replay armed, 3 mid-run replay saves; 19.5 GB / 7223.42 s, tracks ≤110 ms apart; battery 99→62%, CPU avg 12.9% / max 19.3%, RSS 98–485 MB trendless, zero thermal warnings; Franco: "smooth throughout, no desync" (claps at 0/1/2 h). §7 kill leg ✅ (amended to 1 h, Franco): kill -9 at 3540 s → playable 3539.53 s, **0.47 s lost** (≤10 s); app relaunched Ready. ⚠️ relaunch dropped the persisted armed state (transient pipeline failure → self-disarm; field note) — open follow-up, not a gate fail (§7 doesn't cover it). |

## Field notes (append; things learned that docs don't cover yet)

- 2026-07-16 (M6-T1 C3): two observations from the acceptance leg.
  - **The app has a live install at `/Users/Shared/ScreenRec.app`** (found running there;
    binary byte-identical to today's dist build). A stable path outside `dist/` — which
    `bundle.sh` deletes every run — is exactly what M6-T5's login item needs, but no doc or
    STATUS entry records who put it there or whether it's the intended permanent address.
    Settle at M6-T4/T5.
  - **The menu's recent-replay rows list files that no longer exist** (~/Movies had zero
    Replay files; the menu showed two — moved/deleted externally). Recents don't revalidate
    on menu open; what a click on a dead row does is unverified. Candidate for M6-T3's
    error-path audit, not fixed here.

- 2026-07-16 (M5-T5 follow-up — the banner that can't render): **macOS suppresses notification
  banners while the display is captured, and armed replay means the display is always captured.**
  Franco pressed ⌥⌘R from another app: file saved, notification delivered (in the Center's
  list), no banner — the first notification this app fires *mid-capture*, so the first time the
  suppression could show. Both remedies measured:
  - `.timeSensitive` **with** its entitlement, self-signed: AMFI refuses to launch the app
    (POSIX 153 spawn failure) — restricted entitlements need a provisioning profile.
  - `.timeSensitive` **without** the entitlement: silently downgraded, no break-through.
  So: `interruptionLevel` stays set (free once M6-T4's Developer ID signing carries the parked
  `Scripts/entitlements.plist`); until then the user-side fix is System Settings → Notifications
  → "Allow notifications when mirroring or sharing the display". docs/06 amended. Also settled:
  the capture indicator itself is OS-mandated for any SCK stream — no opt-out exists, armed
  replay always shows it.
  - **The likely wider blast radius — armed replay suppressing EVERY app's banners — is
    documented (docs/06 + 02 §9) but deliberately marked inferred:** the policy is global by
    design, our own banner's suppression is measured, third-party suppression is not yet
    observed (the osascript probe has no notification grant of its own, so the headless A/B
    was inconclusive — the confirmation is Franco arming and Slacking himself). Franco's call
    2026-07-16: document now, decide on remedies later.

- 2026-07-16 (M5-T5 app replay): the widest review haul yet (10 confirmed), and the pattern is
  worth naming: **every serious one was a second writer to state I'd only considered the user
  writing.**
  - 🔴 **`refreshSources` re-homes picks on every menu open — my source-change `didSet`s
    treated those writes as user intent and restarted the armed pipeline**, wiping the replay
    buffer on the first menu open after launch, and right after a mic vanished (the exact
    moment someone opens the menu to save). A suppression flag scopes the didSets to genuine
    picks; regression test pins it; verified live (53.9 s clip after two menu opens). **When
    adding a didSet to a property, grep for every existing writer first** — one of them is
    usually not the user.
  - 🔴 **"Restore persisted state at launch" must re-check the permissions the state assumes.**
    Armed + revoked screen grant would have spun a 5 s SCK retry loop forever behind a lying
    badge. Launch activation now requires the grant usable; the grant→relaunch flow re-arms.
  - **Carbon hotkey lessons:** `RegisterEventHotKey` fails silently for combos other apps own
    (now surfaced as a notification); a registered hotkey intercepts its own combo before any
    local NSEvent monitor (the recorder must suspend it while listening); and a recorder that
    accepts plain-⌘ combos lets one reflexive ⌘C hijack copy system-wide — combos now require
    ⌥ or ⌃. Also: hotkey ints from the plist feed trapping `UInt32()` — bounded at load
    (the M4-T4 "bad plist is forever" rule, again).
  - **Replay's own streams must resolve the mic ID the way `start()` does** — a stale picked ID
    fed raw to SCK is the opaque "invalid parameter" (02 §1), which under the armed retry loop
    becomes an infinite failing respawn. One resolver, both paths.
  - **docs/06 amendments:** two notification rows added (mic lost while armed — the docs table
    predates armed replay; shortcut unavailable). The armed badge shows on all icon states, not
    just idle ("armed is orthogonal to recording"); menudriver now renders shortcut modifiers
    (it printed plain ⌘ for everything — a dump-only artifact that mislabelled ⌥⌘R).

- 2026-07-16 (M5-T4 ReplayMuxer): instant replay produces files; two findings worth keeping.
  - 🔴 **The clip window must be anchored at the newest pts across ALL rings, never the video
    ring's own newest** — frame-on-change means a static screen's video ring can be minutes
    stale while audio tracks wall-clock. /code-review caught my first pass anchoring on video:
    a static-screen save would have written minutes-long files of *old* content. The fix is the
    same idea as MovieRecorder's tail patch (02 §5), applied at mux time: window ends at the
    audio clock, the last frame is re-appended at the clip end, and a fully-static window
    rebases audio from the window start with the stale GOP frozen at the top.
  - 🐞 **AVAssetWriter infers a track's LAST sample duration from the *previous* pts delta when
    durations are invalid** (VT compressed samples: we encode with `duration: .invalid`). A
    tail patch 9 s after the last real frame therefore got a 9 s duration and inflated the
    track — video 19 s in a 10 s clip. Only the *last* sample misbehaves (interior samples get
    their real delta, which is exactly the frozen-frame display we want). Fix: the patch copy
    carries an explicit duration (`SampleTiming.retimed(_:to:duration:)`). Caught by the
    fully-stale-window unit test before it ever reached a live run.
  - **Process note: findings presented to Franco before fixing** (his rule from M5-T3), batch
    approved incl. option (b) on the window anchor. One finding was refuted by a verifier that
    actually reproduced disk-full against a tiny APFS image — the writer keeps accepting and
    fails cleanly at `finishWriting`; the drain's writer-status escape stays as cheap insurance
    for any state where `requestMediaDataWhenReady` stops re-firing.

- 2026-07-16 (M5-T3 audio rings): the live run earned its keep twice in one afternoon.
  - **/code-review's theme was silent-failure observability, and it was right four ways at once:**
    a format change pinned a minute of stale audio forever (eviction only runs on append — a ring
    that stops appending stops evicting, and its stats freeze looking healthy); `.microphoneLost`
    hit `default: break` in replay-arm while record prints a warning for the same event; the
    system ring's trouble counter was computed but never printed; and the T3 ticker redesign had
    dropped the video sample count, the only signal separating "spans 60 s" from "spans 60 s
    holding half the frames". All fixed. **Policy call (Franco): on a format change the ring
    clears + re-latches** rather than dropping forever — replay self-heals across AirPods codec
    flips (the only realistic trigger; SCK never re-binds devices, M3-T7, and the stream config
    pins system audio's format) at the cost of a second policy besides MovieRecorder's fail-stop.
    Revisit if the wild shows format thrash (`format ×N` in the ticker is the tell).
  - **The "device switched" ASBD identity now lives in one place** (`AudioFormatIdentity`,
    Support/) and gained the layout fields (`mFormatFlags`, `mBitsPerChannel`) — same
    rate/channels in a different layout is just as unmixable. MovieRecorder's fail-stop uses it
    too, so recording and replay can't disagree on what "switched" means. Note this slightly
    widens M3-T2's fail-stop trigger (a pure layout flip now also stops); that's more correct —
    the welded mic input corrupts on layout changes exactly as on rate changes.
  - 🔴 **SCK's system audio is planar (non-interleaved) Float32 — and two APIs quietly mislead on
    planar buffers.** (1) `CMSampleBufferGetTotalSampleSize` returns **0** for them (the live
    symptom: system ring at 62 s span, "0.0 MB"); count payload via
    `CMBlockBufferGetDataLength` instead. (2) The ASBD's `mBytesPerFrame` is **per-plane** when
    `kAudioFormatFlagIsNonInterleaved` is set, so naive rate math is short by the channel count
    (187 vs 375 KB/s). The mic (mono) hid both bugs. G1's probe recorded "48kHz/2ch/32-bit" but
    not the interleave — **when a format has a layout dimension, record the layout.**
  - 🔁 **The fixture-blind-spot pattern again** (sixth occurrence, still the same shape): every
    unit test fed 16-bit *interleaved* PCM, the one family where the code was right, and passed.
    The fix ships with a planar Float32 fixture (`makeAudioFormat(planarFloat32:)`) and a test
    that reproduces the live bug. When a code path branches on a format flag, the suite needs a
    fixture on **each side of the flag**.
  - 📏 **Second data point on RSS attribution variance** (see M5-T2 note): identical binary, two
    2-min runs — buggy-run RSS climbed to ~536 MB tracking ring fill; post-fix run plateaued at
    ~147 MB with a similar-sized ring. Whatever governs whether VT/CM buffer memory lands in our
    `phys_footprint`, it isn't our code. Also: **§6.1's ≲ 200 MB target collides with the
    19 Mbps reality** (02 §9 estimated ~10) — a busy 60 s ring can't fit. Flagged in "Now" as a
    T6 decision: VT `DataRateLimits` is available on the replay session (we drive VT directly,
    so M2-T6's AVAssetWriter limitation doesn't bind here).
  - **Deep-copying the audio was the right call for an unexpected reason too:** the copy is where
    the planar byte-length truth lives (`CMBlockBufferGetDataLength` of what we allocated) — a
    retained SCK buffer would have left us trusting the same lying sample-size bookkeeping.

- 2026-07-16 (M5-T2 ReplayEncoder): the encoder went in clean; the surprises were measurements.
  - 🔴 **/code-review (high) caught VT session bring-up running on SCK's screen queue** —
    `VTCompressionSessionCreate` + `PrepareToEncodeFrames` allocates the hardware encoder
    (tens–hundreds of ms) and my first pass did it inside `consume()` under the lock, on the
    same serial queue MovieRecorder shares. With queueDepth 5 at 60 fps (~83 ms of headroom),
    arming replay during a live recording would have visibly stuttered it — invisible in every
    T2 verify because nothing else consumed the queue yet. Bring-up now runs on a dedicated
    setup queue; frames arriving before readiness are dropped (the ring just starts a beat
    later). **"Doesn't block the callback queue" has to be checked against the slowest call on
    the path, not the average one** — the same docs/01 rule, still finding new ways to break.
  - Also from the review, all applied: `replay-arm`'s encoder failure now routes through
    `engine.stop(reason: .streamError(…))` (the M3-T2 seam) instead of `exit(1)` from a VT
    thread; `ReplayEncoder.init` preconditions on a finite positive window (a negative/NaN
    ring capacity silently evicts everything); `frameRateCap` is passed from the engine's
    `CaptureConfiguration` instead of a duplicated default; the synthesized-frame fixture is
    consolidated into `SyntheticBuffers.swift` (MovieRecorderTests' copy deleted); the
    keyframe-cadence test asserts cadence against *retained* span rather than absolute counts
    (RealTime sessions may shed frames, and the old assertions contradicted each other's
    tolerance); a test's captured `var` in the `@Sendable` onFailure closure became a locked
    latch; `stats()` is single-pass; the `--seconds 600` cap comment now states the real cost
    (~1.4 GB, not 0.9).
  - 📏 **`phys_footprint` attribution of VT output varies run to run.** Same code, same 3-min
    verify: one run plateaued at 16–17 MB (with `ps` RSS at 33 MB), the next at 113–128 MB with
    a slow upward drift — while the ring's payload bytes sat flat at ~141 MB in both. Whatever
    memory the HW encoder's output block buffers land in, the task-level number is not a stable
    measure of it. For §6.1, treat "RSS ≲ 200 MB" as satisfied but weak evidence; M5-T6's
    30-min audit should watch the drift and system-wide pressure, not one instrument.
  - ⚠️ **`tools/busyscene.swift` takes over Franco's screen — never run it without asking him
    first** (his ruling, mid-verify). Future busy-screen verifies: name the run and its length,
    let him pick the moment.
  - **VideoToolbox needs no TCC grant — the replay encoder is fully unit-testable headlessly.**
    Real HEVC encodes against synthesized IOSurface-backed pixel buffers, in-process, no
    permissions: keyframe cadence, eviction and stats are all asserted against actual encoder
    output, not mocks. The suite runs in ~0.7 s. This generalizes: anything VT-only in M5 (the
    muxer's AAC encode at T4, likely) can be tested the same way.
  - 📏 **Compressed VT output is NOT attributed to our process's memory.** The 3-min run held
    ~141 MB of compressed payload in the ring (measured by `CMSampleBufferGetTotalSampleSize`,
    and it matches Balanced's 19 Mbps × 62 s math exactly) while in-process `phys_footprint`
    read 17 MB and external `ps` RSS read 33 MB — both flat. The HW encoder's output block
    buffers live in memory the kernel doesn't charge to the task. Two consequences: (1) §6.1's
    "RSS plateau ≲ 200 MB" will pass trivially and is therefore a *leak* check, not a *usage*
    check; (2) M5-T6's audit should also watch system-wide memory pressure, not just our RSS,
    or the ring's real cost is invisible. Both instruments agreeing on "flat" is the part that
    matters for T2.
  - **02 §9's "~80 MB video @ 60 s" estimate is ~2× low for this display.** It assumed ~10 Mbps;
    Balanced at 4112×2570@60 computes 19 Mbps → ~141 MB/62 s. Not a bug — the model is doing
    what M2-T6 calibrated — but worth knowing before anyone sizes a 120 s ring (docs/06 offers
    one: ~282 MB payload).
  - **`--seconds` is capped at 600** so a typo can't ask for a multi-GB ring; docs/06's largest
    offered buffer is 120 s, so the cap is generous.

- 2026-07-16 (G4 §5.4 — the wedge bug the gate caught, and its fix): the whole reason gates exist.
  - 🔴 **An unwritable output folder WEDGED the app — a live SCStream with no way out.** Choosing
    Desktop without Files & Folders (or any folder that becomes unwritable): `AVAssetWriter.
    startWriting()` returns `false`, `MovieRecorder.beginWriting()` **swallowed it**, `consume()`
    then `guard didStartWriting else { return }` on every frame, and the recorder had **no channel
    to report "I couldn't begin."** `RecordingSession`'s event loop only ends when `engine.events`
    finishes — but the engine happily keeps capturing — so **no `.failed`/`.finished` ever reached
    the app.** Symptoms Franco hit: idle icon (no first frame written) + a menu stuck on "Stop &
    Save" (session ≠ nil) + inert Stop + dead screenshot shortcut (live capture holding the display).
  - **Fix A (the wedge):** `MovieRecorder` gained `onWriteFailure` (mirrors `onMicrophoneFormatChange`);
    `beginWriting` latches the failure and fires once, outside the lock; `RecordingSession` stops
    the engine and yields `.failed("Couldn't write the recording to …")`. Any `startWriting()`
    failure now ends in a plain message + a live app.
  - **Fix B (catch it early):** `OutputLocation.preflight` probed with a POSIX `createFile`, which
    **succeeds on a TCC-protected Desktop where `AVAssetWriter` fails** (measured: createFile→true,
    startWriting→NSCocoa 513/-12204). Now it probes with a throwaway `AVAssetWriter.startWriting()`
    (one input, self-cleaning) — the exact call a recording makes — so Desktop is rejected at
    selection. **Check a preflight against the API that actually gets blocked, not a cheaper proxy.**
  - ⚠️ **`~/Movies` is safe for a fresh user** — it is NOT TCC-protected, so the default path needs
    no grant (the whole point of the M0-T4 default). Only *changing* the output to Desktop/Documents/
    Downloads triggers this.
  - 🐞 **I could not reproduce the unwritable-Desktop state on the dev account** — launching the app
    via `open` from the agent's Terminal appears to lend it Terminal's Desktop access (the app is in
    NEITHER Files & Folders NOR Full Disk Access, yet wrote to Desktop). Don't state the mechanism as
    fact, but the lesson stands: **the honest repro is a Finder-launched app on a fresh account.** I
    verified the *integration* headlessly instead via a temporary forced-`startWriting`-failure hook
    (reverted): Start → no wedge, back to Ready, "Couldn't write…" delivered.
  - **Two /code-review follow-ups (deferred, out of scope for the RecorderCore fix):**
    - **Finding 1 (confirmed, observed live):** the write-fail `.failed` fires *after* `.started`
      (StartedDetector on the first complete frame is writer-independent), so `AppState` computes
      `hadStarted = statusIcon != .idle = true` → notification titled **"Couldn't save the recording"**
      when nothing was ever written (should be "Couldn't start"). Body is clear, so low-harm. Fix
      touches M4-T5's title heuristic — a small AppCore follow-up.
    - **Finding 3 (plausible):** preflight now does `AVAssetWriter` I/O synchronously on the main
      thread in `SettingsView.chooseFolder`; on a slow/network volume the folder pick could briefly
      hang. One-time action already behind a modal panel; move off-main if it ever bites.

- 2026-07-16 (G4 headless prep): docs/04 §5 is labelled "human-driven", but **half of it isn't**.
  - **§5.2 grants-survive-rebuild is fully headless on this account.** Two-part proof: (1) the
    signing half — `codesign -d -r-` designated requirement is byte-identical across an A→B
    `bundle.sh` rebuild (diff the `designated =>` line), `--verify --strict` passes; (2) the
    behavioral half — after the rebuild, launch the app, confirm the menu header reads
    `ScreenRec — Ready` (readiness is a *live* TCC read, so `Ready` == grant still attached), then
    `menudriver` a real recording. A successful post-rebuild capture IS the proof the grant survived.
  - **The fail-stop notification IS deliverable headlessly — the seam already exists.** The app has
    no `--test-disk-floor` (that's the CLI's), but `RecordingSession.init(diskFloorBytes:)` is
    public and the app just passes `nil`. A ~4-line temporary launch-arg hook at `AppState.start()`
    (`--force-fail-stop` → `diskFloorBytes: 500_000 GB`) trips the disk guard right after the first
    frame → `finished(.diskAlmostFull)` → the app posts its real fail-stop copy. Verified the exact
    docs/06 string delivered live, then reverted (tree clean). No product change needed for the gate.
  - **`--print-delivered-notifications` stamps dates in UTC (`…Z`), not local.** For the "is this
    *this* run?" check (M4-T5's warning), convert: on this box local = UTC−3, so a 09:53 local run
    shows `12:53Z`. Assert against the converted time or the whole thing looks stale.
  - **What stays human, and why it can't be faked:** a *rendered banner* and a *click* (Notification
    Center draws them; delivery ≠ appearance), the fresh-account never-granted paths (this Mac holds
    every grant — the throwaway-bundle trick proves TCC *logic* but not the *onboarding UX*), and
    the `NSOpenPanel` Desktop-preflight (`menudriver` can't drive a system file panel). Those three
    are the whole of what's left, and they're in the walkthrough artifact.

- 2026-07-16 (M4-T6 bundle polish): small task, one honest miss.
  - **The icon is code-drawn, not a checked-in mystery PNG.** `tools/makeicon.swift` renders the
    1024 master; `Scripts/makeicns.sh` runs `sips` + `iconutil` to the 10-slot `.icns`. Same
    reproducible-not-binary reasoning as `busyscene.swift`. Candidate C — a display with a record
    dot — because the icon most needs telling apart in the Screen Recording permission list,
    where every neighbour is also a recorder.
  - **Version has one source now.** `Info.plist` carries `__VERSION__` placeholders; `bundle.sh`
    stamps them from `VERSION` and fails loud if `VERSION` or the icon is missing. The checked-in
    plist literally cannot disagree with the built bundle — you can't stamp what you didn't read.
  - 🐞 **"icon renders in Finder" ≠ "icon renders on the notification banner" — I conflated them.**
    `NSWorkspace.icon(forFile:)` resolves the icon from the assembled bundle immediately (docs/03's
    actual check, passing). But the notification banner still shows the generic placeholder:
    `usernoted` caches the icon per bundle-id, cached the icon-less earlier build, and `lsregister
    -f` doesn't flush that cache. The clean flush (`killall usernoted`) is restarting a system
    daemon, which the sandbox correctly refused on my own initiative. **Two different icon caches
    with different flush rules** — Finder/LaunchServices vs the notification daemon. The banner
    icon is expected to come good at M6 (app at a real path + notarized); until then it's a known
    gap, watched at G4, not a claimed pass. It was never a docs/03 requirement — it was my stretch
    goal in the T5/T6 plans, so no gate is blocked, but the plan overpromised.

- 2026-07-15 (M4-T5 notifications): mostly wiring; the value was in the copy.
  - 🔴 **docs/06's copy table covered four fewer cases than the engine emits**, and the gaps were
    invisible until the two were laid side by side. `streamError` (reachable — SCK dies for
    reasons we don't classify) had no copy; mic-loss had none though **ADR-012 promises a
    notification**; `failed` had none because the table assumes "always a playable file"; and
    `Mac went to sleep` was copy for `EndReason.systemSleep`, which M3-T4 measured as
    unreachable. **Check a copy table against the enum, not against the happy path** — a spec
    written before the code knows only the cases the author imagined.
  - **The notification needs a duration `.finished` doesn't carry.** `elapsedSeconds` only
    advances while the menu is open, so it's usually stale or zero at finish. The writer's
    `recordedDuration` is the only accurate source, and it's readable only *before* the session
    is torn down — hence `notify(about:)` runs at the top of `apply`, ahead of the fold.
  - **The notification delegate must be installed before launch completes** (hence
    `NSApplicationDelegateAdaptor`, not a view's `.task`): a click can *launch* the app, and a
    response delivered before a delegate exists is dropped — losing the one interaction docs/06
    specifies for notifications.
  - **`willPresent` must return `.banner`** or the notification is silently swallowed whenever
    ScreenRec happens to be frontmost (Settings or Onboarding open). Easy to miss: the app is an
    accessory and rarely frontmost, so it works in testing and fails in the one case a user is
    looking at the app.
  - 🔴 **The feature was dead for every normal install, and the live test passed anyway.**
    `requestAuthorization` was only reachable from onboarding's Notifications row — but that
    window opens when a permission *blocks*, notifications never block, and it stops auto-opening
    once the blocking rows go green. So: fresh install → grant screen → relaunch → the window
    never opens again → authorization stays `.notDetermined` → **every notification silently
    dropped, forever**, with the error discarded inside `add(request)`. The verify passed only
    because this machine had been granted by hand. /code-review found it. The app now asks once
    at launch; onboarding's row still shows the state and routes to Settings.
    **Whenever a permission gates a feature, ask where it gets requested on a machine that never
    saw the setup screen.**
  - 🐞 **`.failed` means two things and its own doc comment says one.** `EngineEvent.failed` is
    documented as "preflight/start failure", but `RecordingSession` also yields it from the
    `finish()` catch — a *finalize* failure after a full recording. The notification mapper
    trusted the doc, so losing a 90-minute capture at the last step announced "Couldn't start
    recording" over a body saying finalization failed. Only the caller can tell them apart
    (`statusIcon != .idle`). **A doc comment is not a contract; grep the emitters.**
  - 🐞 **Two start-failure paths posted nothing at all.** `start()`'s `reserveRecordingURL` and
    `RecordingSession.init` catches set `lastFailure` and returned — no session, so no event
    stream, so no notification; and `lastFailure` reaches no idle surface since the header shows
    readiness. Net effect: click Start with an unwritable folder, get *no banner and no visible
    change*, walk away believing you're recording. They now route through `apply(.failed(…))`.
  - **What `--print-delivered-notifications` proves, and what it can't.** It asserts real copy
    from a real delivery — docs/03's verify, no human needed. ⚠️ But it reads Notification
    Center's **persisted** list, not this run's: it happily prints week-old entries, so the gate
    could pass with nothing delivered. It now prints each notification's date — **assert on the
    date, not just the copy** (verified: run at 22:24:19, notification at 22:24:26). It still
    says nothing about whether a banner *appeared* or what a click does.
  - **Fail-stop copy is unit-tested but never delivered live** — the app has no
    `--test-disk-floor` (that's the CLI's), so provoking one needs a patch. G4 §5.3 covers it.

- 2026-07-15 (M4-T4 settings): the app finally remembers something. Two lessons, one of them
  the same one as always.
  - 🔴 **`tools/menudriver.swift` CANNOT verify window activation, and it took an hour and a
    design change to learn that.** A synthetic click doesn't confer activation the way a real one
    does, so after `click "Settings…"` the app stays un-frontmost and the window looks like it
    opened behind everything — *whatever the app does*. I read that as a bug, replaced
    `Settings` + `SettingsLink` with a plain `Window` chasing it, tried an AppKit selector,
    and wrote "verified — Terminal stayed frontmost" into the source as fact. Then **Franco said
    "the menu opens fine for me"** and the whole thing evaporated. **Third false negative from my
    own tooling in two tasks** (unopened submenus; `AXDescription` vs `AXTitle`; now this) — the
    warning is in the tool's header now. Trustworthy from it: structure, titles, checkmarks,
    enabled/disabled, that a click landed. Not trustworthy: anything about focus or z-order.
    **When a tool says the app is broken and a human says it isn't, the tool is the defendant.**
  - **The `Settings` scene buys an LSUIElement app nothing** — it exists to route ⌘, through the
    app menu, which an accessory doesn't have. ⌘, is bound on the menu item instead. That's why
    the plain `Window` stayed after the false alarm: one way of opening a window rather than two.
    But it is a *preference*, not a fix, and the source says so — `SettingsLink` is not known to
    be broken.
  - 🐞 **A setting that persists perfectly and reaches nothing.** `fpsCap` round-tripped through
    UserDefaults, showed in the UI, and never reached the capture: `captureConfiguration` didn't
    pass `frameRateCap`, so the engine used its own default. Persistence tests all passed. The
    test that catches it asserts the *configuration*, not the stored value — **a settings test
    that stops at the plist is testing a drawer, not a setting.**
  - 🐞 **Tests were writing to the real `UserDefaults`.** `AppState()` defaults to `.standard`,
    and settings persist on `didSet` since this task — so one test's `state.quality = .high`
    leaked into another test's launch, and onto disk between runs. Found because a test that had
    passed for hours suddenly failed. Every AppState in a test now gets a throwaway suite.
    **The moment state persists, "just construct one" stops being free in tests.**
  - **Persisted state is a different risk in kind, and this is the task where it starts.**
    In-memory state self-corrects on the next launch; a bad plist value is the app's problem at
    *every* launch until someone fixes it — and `defaults write dev.fcostantini.screenrec.app
    fpsCap 0` is one command. So the load validates rather than trusts: unknown preset → the
    default, fps not in {30,60} → the default (not clamped: 0 divides by zero downstream and
    "clamped to 30" is a value nobody chose), a folder that's gone → `~/Movies`. The realistic
    one isn't a hand-edited plist — it's the external drive that was mounted when they chose it.

- 2026-07-15 (M4-T3 onboarding): the TCC findings are in **02 §1/§2** (measured tables — read
  them before touching permissions). What belongs here is everything else.
  - 🔴 **The same question — "is this state current?" — has OPPOSITE answers for a menu and a
    window, and I got each one wrong once.**
    - A **menu** is rebuilt on every open, and SwiftUI decides `.disabled` *before* any `.task`
      on those rows runs ⇒ a stored-and-refreshed value is always one open behind ⇒ **compute
      live** (`readiness`). Shipped stale; the live run caught it.
    - A **window stays open** while the user walks to System Settings and back ⇒ computing live
      keeps the values right and **still never redraws**, because TCC changes outside the
      process and `@Observable` has nothing to observe ⇒ **store it and poll**
      (`onboardingRows`). Shipped broken; *Franco* caught it — he granted the microphone and
      watched the row sit on `○ Grant…`.
    The two look inconsistent side by side and are not. **Rule: ask whether the surface is
    rebuilt or persistent before deciding where the state lives.**
  - **`@Observable` publishes on every set, not every change** — so a 1 Hz poll that assigns
    unconditionally redraws the window every second forever. Assign only on a real change
    (`OnboardingRow` is Equatable for exactly this).
  - **Verification tooling: SwiftUI puts a button's label in `AXDescription`, not `AXTitle`.**
    Matching on title finds zero buttons and looks exactly like "the window has no buttons".
    `tools/menudriver.swift`-style helpers must match either. (Same false-negative family as the
    unopened-submenu bug from M4-T2 — twice in two tasks.)
  - **`osascript` + System Events needs an Automation grant** ("Terminal wants access to control
    System Events"). It prompts the human unannounced — warn Franco before running one. Dev
    tooling only; the product never needs it.
  - **The throwaway-bundle trick generalises and is now the house method for permission work**
    (recipe in 02 §1): same signing identity + a different bundle ID = a TCC subject macOS has
    never granted, on this account, with our own grants untouched. It settled a question the
    docs had called untestable-without-a-fresh-account since M3-T4, in ten minutes. Cleanup is
    `tccutil reset <service> <that bundle id>` — **always with the bundle ID**; the bare form
    would destroy our grant (02 §2).
  - ⚠️ **A probe bundle must be launched via `open`, not run from the shell.** A bare binary is
    attributed to the *responsible process* (Terminal), which holds every grant — it would have
    measured the exact opposite of what was intended, and looked like a clean result.
  - **I asserted something about Franco's screen I never verified, and it was wrong.** From run 1
    I concluded "-3801 says *user declined* although nobody was asked" — a nice finding, entirely
    false: a prompt *had* appeared and he *had* declined. He corrected it; otherwise it would
    have gone into 02 as measured fact. **Never narrate the user's screen.** The re-run in the
    genuinely-denied state is what actually earned the second row of that table.
  - **Two spec bugs found by building, both the same shape — a door that only opens outward:**
    1. docs/06's `Grant…`-only row is dead for anyone who ever declined (02 §2). Fixed: ask once,
       then offer System Settings forever after. It flips on *having asked*, not on *being
       denied*, because macOS won't tell us which state we're in — and the remedy is identical.
    2. The header was spec'd disabled-unless-blocked, which strands the *optional* Notifications
       row: it never blocks ⇒ `needsOnboarding` goes false ⇒ the window stops auto-opening ⇒ a
       user who dismissed the prompt has no route back from anywhere in the app. Franco hit this
       for real. Fixed: the header always opens Onboarding; only *auto*-opening is gated on a
       blocking row. **Auto-appearing and being reachable are different questions — docs/06
       conflated them, and so did I.**
  - 🔴 **`CGPreflightScreenCaptureAccess()` goes true the instant the switch lands — and the
    process still can't capture until it restarts (02 §2). Believing it is how you build an app
    that says `Ready` and fails every recording.** /code-review found this and it was the root of
    most of the task's defects: `readiness` trusted preflight, so Start enabled the moment the
    user toggled Settings, whether or not the restart had happened. **Only a launch-time snapshot
    can tell the difference** — permissions alone cannot, because "granted, usable" and "granted,
    needs restart" are the same TCC answer. `AppState.screenWasGrantedAtLaunch` +
    `needsRelaunchForScreenGrant` are that snapshot, and `readiness` now reports blocked until
    the relaunch happens.
  - **A promise the user can close is not a promise.** The relaunch first lived in the onboarding
    window's `.task`, so closing the window (or granting straight in System Settings without
    pressing our button) silently dropped the "we'll relaunch automatically" the row's own copy
    makes. It now lives on the status item's task, which lives as long as the app, and keys on
    the **grant transition** rather than on our button being pressed — the user may never touch
    the button, and that grant needs the same restart. **Rule: a background promise belongs on a
    surface the user can't dismiss.**
  - **My fix for Franco's header request quietly created a way to abandon a recording.** Making
    the header always-clickable broke the invariant the relaunch's safety argument rested on
    ("the window only exists while recording is blocked") — so a click on a *status readout* could
    silently quit and reopen the app, discarding every in-memory pick. Two lessons: **an
    invariant defended by a comment in another file is not defended**, and a small UI change can
    invalidate a safety argument three files away. `Relaunch.now()` is now guarded on
    `isSessionActive` even though `readiness` should already make it unreachable — "should be" is
    not a thing to abandon a live writer on.
  - **Copy has to follow the gate.** The mic row said "Only needed if you record a microphone"
    while Start was greyed out *because of that row* — telling the one person who is blocked that
    it isn't their problem. Detail text now depends on whether the row is actually blocking.

  - **The good news that reframes M4-T3: asking is the add button.** Neither the Microphone nor
    the Notifications pane has a "+", but neither needs one — *the request itself creates the
    row*, whatever the user answers. So there is exactly **one** unrecoverable state, **never
    having asked**, and it is the state the app was in before this task. That is the whole case
    for onboarding, and it's stronger than the spec's.

- 2026-07-15 (M4-T2 the menu): the task that made M4 verifiable — and the first task where a
  **live run found a bug the unit tests structurally could not**.
  - 🐞 **A stored `readiness` is always one menu-open behind.** SwiftUI builds a menu's rows —
    including which are `.disabled` — *before* any `.task` attached to them runs. So refreshing
    readiness from that task lands after the decision it was meant to inform, and the menu shows
    the answer from the **previous** open. Live symptom: pick a microphone, and the menu went on
    offering an enabled Start that silently did nothing (the ungranted mic flipped readiness, the
    stale menu didn't know). Now a **computed** property — both TCC queries are cheap local
    checks, so asking during body evaluation is affordable and cannot lag. **Rule: anything the
    menu's structure depends on must be readable at build time, not refreshed from `.task`.**
    `.task` is only good for things that change *while* the menu is open (the elapsed clock).
  - **`EngineEvent.fileProgress` is declared but nothing emits it** — a dead case, exactly like
    `.systemSleep` was before M3-T4. The CLI's ticker polls `recordedDuration` + the file size on
    disk; the menu now does the same. That suits docs/06 better anyway ("≤1 Hz, menu open only"):
    a pull happens exactly when someone is looking, which no push could arrange. Left dead rather
    than wired up — M4-T2 had no business changing RecorderCore. Whoever needs it should ask
    whether it should exist at all before implementing it.
  - **`isSessionActive` must be `session != nil`, NOT derived from the icon.** Between `start()`
    and the first complete frame the icon still reads `.idle` while a session exists. Keying the
    menu off the icon would offer "Start Recording" a second time in that window (a second
    session over the first) and let ⌘Q skip its confirm and abandon a live writer.
  - **A `Picker` in menu content already *is* docs/06's submenu-with-checkmark.** Wrapping it in
    an explicit `Menu` + `.pickerStyle(.inline)` reads closer to the spec's wording and renders
    further from it — it adds stray separators around the group. Verified with `menudriver dump`.
  - **RecorderCore stayed untouched, but only just.** `DisplaySelection`/`MicrophoneSelection`
    carry associated values and aren't `Hashable`, so they can't be SwiftUI picker tags. Rather
    than add conformances to a capture type to suit a menu, `AppState` stores the raw picked
    identifiers and builds a `CaptureConfiguration` at start. Better shape anyway — but note the
    pull: the UI *will* keep asking for small favours from RecorderCore. Refuse them.
  - **My own comment lied and a test caught it.** I claimed the recent-files filename tie-break
    "keeps the newer of two same-second files first". It does not — `Recording.mov` sorts above
    `Recording 2.mov` descending, though the suffixed one was written second. The tie-break buys
    *determinism* (`sorted(by:)` isn't stable), nothing more. The test now asserts stability
    rather than pinning the quirk as if it were intent.

- 2026-07-15 (M4-T2 verification — **the "(human)" tax on M4/M5 mostly evaporated**):
  - **`tools/menudriver.swift` + Franco's Accessibility grant = headless menu testing.** The
    whole T2 verify (open menu → pick sources → Start → wait → Stop → probe the file) ran with no
    human. `dump` prints the open menu as text — titles, checkmarks, shortcuts, disabled rows,
    submenus — so docs/06's structure is **assertable**, not a screenshot to squint at. Use it.
  - ⚠️ **`AXPress` on a menu-bar item returns `.success` and does nothing.** Menu tracking runs a
    modal event loop the action never enters. Third instance of this project's oldest trap (SCK's
    `updateConfiguration` OK-on-a-dead-device, 02 §4; the `--nil-follow` window). The menu opens
    via a synthetic `CGEvent` click at the item's own reported frame. Menu *items* do respond to
    AXPress once their menu is open.
  - 🔴 **A submenu's AX children don't exist until the submenu is opened — and I shipped that as a
    false negative into the very tool built to prevent false negatives.** `dump` read the children
    without opening, so the Microphone submenu printed as empty. It looked exactly like a real
    regression (the app "losing" its device list), I believed it, and I was one edit from
    "fixing" an app that was never broken — until **Franco sent a screenshot showing the two
    devices right there**. The tool now opens each submenu, retries, and prints
    `(unread — submenu never populated)` rather than printing nothing. **The rule this project
    keeps relearning, now in its fifth costume: an empty reading is not evidence of emptiness.
    Any instrument that can't distinguish "nothing there" from "didn't look" will eventually
    invent a bug for you.** Verified fixed: three consecutive dumps now identical and complete.
  - **The grant is on Terminal, not "Claude Code"** — Claude Code here is a CLI hosted by
    Terminal.app, so it never requests Accessibility and never appears in that list. It's a broad
    grant (anything run in Terminal can drive any app); revoke it after M4/M5 if desired.
  - 🔴 **The Microphone pane has NO "+" button** (verified by screenshot, 2026-07-15) — unlike
    Screen Recording / Accessibility / Full Disk Access. Apps appear there *only* after calling
    `requestAccess`. **Consequence: in M4-T2 the app is an unrecoverable dead-end the moment a mic
    is picked** — Start greys out, and neither the app nor the user can grant it. This is the
    strongest possible argument that M4-T3's onboarding is load-bearing, not polish. It also
    means: **any permission the app needs, the app must ask for — you cannot document your way
    around it.**
  - **Screen Recording CAN be granted by hand** (`+` → the .app), which is how T2 was tested at
    all. The grant survived a dozen `bundle.sh` rebuilds — M0-T3's stable designated requirement
    holding up in practice, exactly as promised.

- 2026-07-15 (M4-T1 menu-bar shell): the first UI task, and the headless-verification story is
  better than expected — **the agent does not have to hand the visual check to a human.**
  - **`screencapture -x -R x,y,w,h` works from this terminal** (same foreground-TCC rule as
    capture — see the M2-T5 note). `NSScreen.main.frame` is **2056×1285 points** at 2× on this
    machine; the menu bar is the top ~32 points. So any menu-bar state can be captured and read
    back. Combined with the next point, docs/03's `(human)` visual checks for M4 are mostly
    self-serviceable — leave the human the *judgement* calls (does it look right), not the
    *existence* ones (does it render at all).
  - **To photograph a state the UI can't reach yet, patch the app temporarily and revert.** T1
    has no Start button (that's T2), so `.recording`/`.paused` were unreachable. A throwaway
    `.task {}` in `App.swift` drove `state.apply(.started)` → `.paused` on a timer; captured;
    reverted. Cheaper than a debug launch argument and it ships nothing.
  - **Don't eyeball an animation — measure it.** Two pulse screenshots looked identical to me;
    the mean red channel said otherwise (redness 0.198→0.426 across phases, a 2.15× swing vs the
    2.22× the 0.45 alpha floor predicts). The pulse was working *and* the floor was right, but I
    could not have told you either from the pictures. Same lesson as the M3 field notes in a new
    costume: a check that can't fail for the intended reason is decoration.
  - **SwiftUI's implicit animations do NOT drive a `MenuBarExtra` label** — the status item is
    rendered to an `NSImage`, so `.animation`/`withAnimation` do nothing there. A `Timer.publish`
    + `onReceive` flipping `@State` *does* re-render it (verified above). That's why the pulse is
    hand-driven at 12 frames / 2 s cycle rather than declared.
  - **Menu-bar colour requires `isTemplate = false`.** The menu bar tints template images to
    match itself, which would flatten the red and amber — the two icons whose entire meaning is
    their colour — into the same monochrome as idle. Only `.idle` stays a template (it *should*
    follow the system). Colour is baked in via `NSImage.SymbolConfiguration(paletteColors:)`.
  - **`lsappinfo info -only ApplicationType <pid>` → `"UIElement"` is the headless proof of "no
    Dock icon"** — better than "I looked at the Dock", and scriptable for the G4 gate.
  - **Scope call worth knowing:** docs/06's status-item table has four states, but the fourth
    (replay-armed badge) has nothing that can set it until M4-T2's toggle, so `StatusIcon` has
    three. `AppState.statusIcon` is therefore currently a 1:1 image of the event fold with no
    second input — when T2 adds arming, that likely becomes a derived property over
    (activity, isReplayArmed). Deliberate: the badge design would have been improvised now.
  - 🐞 **UI has a whole class of bug the CLI never had: the invisible-to-sighted-testing kind.**
    /code-review found the pulse dropping the status item's accessible name on every faded frame
    (~92% of them) — `NSImage(size:flipped:)` returns a fresh image, and I copied `isTemplate`
    across but not `accessibilityDescription`. So VoiceOver announced an unnamed image in the one
    state where the icon is the app's only signal. **Two lessons.** (1) `Image(nsImage:)` does
    NOT adopt an `NSImage`'s `accessibilityDescription`, and a label-based `MenuBarExtra` has no
    title to fall back on — the accessible name must be applied in SwiftUI with
    `.accessibilityLabel()`, so that is where it now lives (one source of truth, in the layer
    that works). The old `MenuBarExtra("ScreenRec", systemImage:)` had been carrying the name for
    free; switching to a custom label silently dropped it. (2) Every screenshot I took was of a
    state that *looked* right — the a11y tree is not in the picture. For M4+, "I captured it" is
    not the same evidence it was for the CLI.
  - **I put a number in the audit trail that I never measured** (claimed 15 AppCore tests; there
    are 11) and it reached docs/03 AND STATUS before the review caught it. docs/03 + STATUS are
    the per-task audit trail, so an invented figure quietly devalues the measured ones beside it.
    `swift test --filter AppCoreTests` prints the count in one second. **Never write a count you
    didn't just read off the harness** — and note the count is @Test *declarations*, not expanded
    parameterized cases (11 here, not the 21 the arguments would suggest).
  - **The review is the only thing that catches cross-cutting scope drift.** It flagged an
    unrelated CLAUDE.md process change riding inside the M4-T1 diff (Franco had asked for it
    mid-session, so it was wanted — but it belonged in its own `docs:` commit, not smuggled into
    a task commit whose message claims to be a menu-bar shell). "One task, one commit" is
    enforced by nobody but the reviewer.

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

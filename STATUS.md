# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

- **🎉 v1.8.0 CUT AND INSTALLED (2026-07-27) — M16 (Honest State) earns the MINOR.** `VERSION` +
  `CoreInfo.version` → 1.8.0 (pin test green), committed (`7f074c4`), cut via **`Scripts/release.sh`
  run in the BACKGROUND** — full gate green (clean tree · version pin · build · 470 tests · encode×3 ·
  release build · bundle-sign), tagged **`v1.8.0`**, pushed main + tag. **0 unpushed; tag on origin.**
  **DEPLOYED to `/Users/Shared/ScreenRec.app`** (pid changed; plist `CFBundleShortVersionString` =
  1.8.0, and the app now says so itself: onboarding + Settings footers read `ScreenRec 1.8.0` — the
  first release where that question is answerable from inside the app, which is T6's point).
  MINOR not PATCH (ADR-013): six user-facing features. VT stayed healthy — the release ran to
  completion in the background and was never killed mid-encode.
  **Next: Franco's call — dogfood 1.8.0, or start M17 (Window capture) / M18 (Editing & Menu polish).**
  Note **M17-T2 adds menu rows that M18-T3 is removing** — whichever runs second inherits the
  coordination (flagged in both tasks).

- **✅ M16-T6 DONE (2026-07-27) — onboarding proves capture works, and the app finally names its
  build. M16 IS COMPLETE (T1–T6); the MINOR bump to 1.8.0 is Franco's call.** `Run a test` records
  5 s into scratch, reads the finished file's tracks, deletes it, and reports one line per source.
  **Four outcome states on purpose** — "you turned it off" must not read like "it's broken" — and
  the mic verdict reuses **T4's measured −90 dBFS floor**, so *silent* means the same thing
  everywhere. Audio tracks are told apart by **channel count** (system stereo, mic normalized mono).
  It runs its **own** session, so an armed replay keeps its ring.
  **Verified live on the deployed app, driven through the AX API** (System Events can't see these
  windows, and the setup window closes when unfocused — `scratchpad/windrive.swift`):
  `✓ screen · 4112 × 2570` / `✓ system audio` / `✓ microphone · AirPods Pro`; **muted** →
  `! microphone · silent — check that it isn't muted`; **mic None** → `— microphone · not selected`;
  scratch directory gone afterwards; both footers read `ScreenRec 1.7.2`, matching `VERSION`.
  Franco's mic pick and input volume restored after every leg. **470 tests (+7)**, dev loop green,
  deployed. **Next: cut 1.8.0** (bump `VERSION` + `CoreInfo.version`, record G16, `Scripts/release.sh`
  **in the background** — never under a short foreground timeout, or it gets SIGTERM'd mid-encode).

- **✅ M16-T5 DONE (2026-07-27) — the menu-bar label shows the input level; DEPLOYED.** Three bars
  beside the icon while recording **or armed** (Franco's ruling — that's what makes it useful
  *before* a take), opt-out `showsMenuBarLevel`.
  **⚠️ THE FINDING: a `MenuBarExtra` label renders only its FIRST `Image`.** The planned
  bars-beside-the-icon `HStack` drew **nothing** — measured live via the status item's AX frame:
  icon only `27×24`, icon + `Text("XX")` → `51×24` (text renders), icon + a second `Image` → still
  `27×24`. So the meter is **composited into the icon image**, the trick the armed badge already
  used; the item now measures `39×24`. **The same latent bug sits in the replay-saved checkmark** —
  by this measurement it has never rendered (filed in docs/07, not fixed here).
  **Scale set by M16-T4's measurements:** first bar at **−35 dBFS**, above the loudest measured room
  tone (−42.7, built-in), so an unlit meter means "nothing is reaching this mic", not "quiet room".
  No amber top bar — the idle icon is a template, where only alpha survives.
  **No new cost on the sample path or in the observation graph:** the peak reuses T4's existing scan
  (read-and-clear), `AppState` offers it as a **method** not a published property, and the view
  writes state **only when the bucket changes** — a silent room is zero redraws (M6-T10 restated).
  **463 tests (+7)**; **pixel-measured, not eyeballed:** forcing the four buckets gave **four
  distinct rendered states** (0/89/153/189 differing px, all inside the meter's columns), and a live
  capture with real audio lit it and returned to the silent bitmap exactly. ⚠️ **`md5` of two
  screencaptures is NOT a pixel comparison** (identical pixels, different bytes) — it fooled a first
  pass; `scratchpad/pixdiff.swift` decodes and compares properly.
  **Next: M16-T6** (onboarding capability self-test + version string) — the last M16 task, then the
  MINOR bump.

- **✅ M16-T4 DONE (2026-07-27) — a connected-but-silent mic now says so, and the threshold was
  measured rather than picked.** The product defended hard against a mic *disappearing* and not at
  all against the commoner failure: one that is connected, delivering, and carrying nothing.
  **Measurements first** (full table in docs/07): a **muted** device delivers **exact digital zeros**;
  the same quiet room reads **−65.5 dBFS median on AirPods (quietest window −78.9)** and **−42.7 on
  the built-in** — a **23 dB spread between two mics in one room**, which is why no threshold can be
  eyeballed. Franco's ruling: **−90 dBFS sustained 10 s, paired notices, microphone only** (silent
  system audio is normal — saying so would train the user to ignore it).
  ⚠️ **SCK delivers ~1 s of exact zeros while a Bluetooth route spins up** — so the decision judges a
  *run*, never a buffer; that also made the planned 2 s start grace unnecessary (the 10 s run subsumes
  it), the one deviation from the plan. **As built:** `MicrophoneSilenceWatchdog` beside
  `MicrophoneWatchdog` on the router path; `.microphoneSilent`/`.microphoneAudible` folded like
  `microphoneLost` (recording continues, ADR-012); **armed replay gets the pair too**.
  **456 tests (+13)** — every measured level is a must-not-fire case. **Live:** muted record →
  **exactly one** notice at ~10 s, recording ran to completion, file playable with a full-length
  (silent) mic track; **unmute mid-recording → the paired recovery notice**; control run → **neither
  notice**. Input volume restored after every leg (71). **Next: M16-T5** (input level in the menu-bar
  label) — plan artifact first. Two M16 tasks left (T5, T6), then the MINOR bump.

- **✅ M16-T3 DONE (2026-07-27) — system audio has an off switch; ADR-019 amends ADR-004.** Until
  now the only way to record without capturing the music/the call/the video you're narrating was to
  mute the Mac. Now: a checkmark row **`Capture System Audio`** (a boolean doesn't earn a submenu, and
  M18-T3 is cutting rows), persisted `capturesSystemAudio` **absent ⇒ on**, plus `--no-system-audio`
  on `record` and `replay-arm`. **ADR-019: "never mixed" survives ADR-004, "always two tracks" does
  not** — a recording may carry two, one or no audio tracks, and never an empty one. When both
  sources are off the menu says **`This recording will have no audio`** *before* you start.
  **Measured, three probes:** control **3 tracks** · `--no-system-audio` → **video + 1ch mic, no
  empty track** · both off → **video only, playable**. An armed save with system audio off → mic
  track, no system track (system ring 0.0 s throughout). **The replay path needed no change** —
  `makeAACInput` already returns nil for an empty ring. **449 tests (+7)**, dev loop green.
  **Bonus, closing M16-T1's loop: with all audio off, SCK opens NO audio tap** — assertion count
  3→3 (all off) vs 3→4 (system audio on), so that's the only configuration where an armed Mac could
  idle-sleep (ADR-018 keeps it awake there anyway, deliberately). ⚠️ **Known, unfixed by ruling:**
  with no audio at all, `ReplayMuxer` loses the continuous clock it anchors saves on, so a still
  screen can yield a stale clip (field note). **DEPLOYED and verified live on the menu:** the row
  renders checked between `Microphone ▸` and `Quality ▸`; `menudriver click` → unchecked +
  `capturesSystemAudio = 0` persisted; click again → checked + `= 1` (Franco's setting restored),
  and the sleep assertion's age reset to 00:00:01 each time — incidental proof that a capture-
  affecting change really does rebuild the armed stream.
  **Next: M16-T4** (notice when audio is arriving but silent) — plan artifact first.

- **✅ M16-T2 DONE (2026-07-27) — an armed buffer now says what it costs, and 1.7.2+T1+T2 is
  DEPLOYED.** Settings gained a caption under the slider and the armed menu a dimmed row; measured
  on Franco's own live settings (4:30 buffer, 60 fps, mic Automatic): **`A 4:30 buffer holds about
  800 MB in memory. While armed, ScreenRec keeps your Mac awake.`** and **`4:30 buffer · ≈800 MB ·
  Mac stays awake`**. He had been holding 800 MB with nothing on screen saying so. **Two things the
  code review / measurement caught before they shipped: (1) `ReplayEncoder` hardcodes `.balanced`,
  so Quality must NOT be an estimator input** — billing his High preset would have quoted ~1.6× the
  truth; **(2) an app-scoped pick composites on the MAIN display** (02 §1a), not the remembered
  `selectedDisplayID`, which would have mis-billed on a two-display Mac. Also measured:
  `CGDisplayPixelsWide` returns **points**, not pixels (4× error waiting to happen — field note).
  **442 tests (+12)**, full dev loop green, before/after `menudriver` dumps + Settings screenshots
  recorded. **⚠️ Slider-drag tracking is proven by unit test only** — driving the live slider would
  have restarted his armed ring. **DEPLOY: `/Users/Shared/ScreenRec.app` is now the current build
  (pid changed, `ditto` per the field-note recipe, TCC intact, assertion reads `Instant replay is
  armed`).** It reports **1.7.2** — M16's MINOR bump comes when the milestone closes (ADR-013).
  **Next: M16-T3** (system audio becomes optional) — plan artifact first.

- **✅ M16-T1 DONE (2026-07-27) — the sleep assertion stops lying; ADR-018 rules that arming keeps the
  Mac awake on purpose.** Measured before planning: the running 1.7.1 held `PreventUserIdleSystemSleep
  named: "Recording the screen"` while merely **armed** (no `.partial` on disk), and `pmset -g` listed
  `ScreenRec` under "sleep prevented by". **The filed task's premise was false, and the measurement
  killed it before any code was written:** dropping our assertion would *not* let an armed Mac sleep —
  any SCK stream capturing audio also carries one held by `coreaudiod` for `/usr/libexec/replayd`,
  present with `--no-mic` too, released only at stream teardown (field note + 02 §7). Only tearing the
  armed stream down would deliver sleep. **Franco's ruling: keep the assertion, fix the reason, put the
  cost on screen in T2** — the idle stand-down alternative declined with it. Built as
  `CaptureEngine.Purpose` (`.recording` / `.replayBuffer` / `.diagnostic`), a **required** init
  argument, with `assertionReason` the only place the strings live. **Verified live on all four CLI
  entry points** — `record` → `Recording the screen`, `replay-arm` → `Instant replay is armed`,
  `probe-stream`/`engine-smoke` → `Capturing the screen`, nothing surviving exit. **430 tests (+1)**,
  full dev loop green. G16's first criterion was rewritten to match the ruling; **T2 inherits the
  "keeps your Mac awake" caption**. ⚠️ `dist/ScreenRec.app` is now **1.7.2 + this task**, not the
  pristine v1.7.2 tag build (step 4 of the dev loop rebuilt it). **Next: M16-T2** (armed replay states
  its cost) — plan artifact first.

- **🎉 v1.7.2 CUT (2026-07-24) — M15 (Gate & Debt) earns the PATCH.** `VERSION` +
  `CoreInfo.version` → 1.7.2 (pin test green), committed (`b01772f`), cut via **`Scripts/release.sh` run
  in the BACKGROUND** — full gate green (clean tree · version pin · build · test · encode×3 · release
  build · bundle-sign), tagged `v1.7.2`, pushed main + tag; the pre-push hook's gate passed too.
  **0 unpushed; tag on origin; `dist/ScreenRec.app` reports 1.7.2.** PATCH not MINOR (ADR-013): M15 is
  reliability + process, no new user-facing feature. VT stayed healthy — the release ran to completion
  and was never killed mid-encode.
  **⚠️ NOT INSTALLED: `/Users/Shared/ScreenRec.app` is still 1.7.1 and running (pid 72381).** Deploying
  means quitting the live menu-bar app, so it's left for Franco — the built bundle is at
  `dist/ScreenRec.app`. **Next: Franco's call — deploy 1.7.2, or start M16 (Honest State).**

- **🎉 M15 COMPLETE — GATE G15 PASSED (2026-07-24). Roadmap: M16 → M17 → M18 remain.** Four tasks
  shipped (T1 test determinism, T3 export partials, T4 drift/dead-code, T5 this rotation); **T2 closed
  "won't do"**. G15's four criteria all met: `swift test` green **20×** with no run over 10 s (was 8/10
  failing at ~123 s); a killed mid-export leaves **nothing at the final name** (A/B measured); no stale
  comment or dead enum arm remains; STATUS.md is **237 lines** (was 2,769) and the reading order works
  cold. **M15 is reliability + process with no new user-facing feature → PATCH-worthy (1.7.2), Franco's
  call to cut** (bump `VERSION` + `CoreInfo.version`, then `Scripts/release.sh` — run it in the
  **background**, never under a short foreground timeout, or it gets SIGTERM'd mid-encode).
  **4 commits unpushed.** **Next: Franco's call — cut 1.7.2, or start M16 (Honest State).**

- **✅ M15-T5 DONE (2026-07-24) — STATUS.md 2,769 → 237 lines.** Field notes → their own
  **`docs/07-field-notes.md`** (1,236 lines), now **#4 in CLAUDE.md's reading order**: they were the
  most valuable artefact in the repo and the least findable, buried 1,400 lines into a file every
  session must read. Closed session logs + the v1 status write-up + the M2-T6 calibration table →
  **`docs/history/2026-07-sessions.md`** (1,320 lines), explicitly unmaintained. **Rotation verified
  lossless** — every original non-blank line accounted for across the three files except the two
  headings deliberately rewritten. CLAUDE.md's five "STATUS.md field notes" pointers and README's doc
  map now resolve to the new homes, and the session-end checklist gained a standing "re-rotate past
  ~250 lines" instruction so this can't silently regrow.

- **✅ M15-T4 DONE (2026-07-24) — stale comments, two dead `EndReason` cases, one duplicated helper.**
  `EndReason.microphoneChanged` (unreachable since M8-T1 normalized every mic buffer) and `.systemSleep`
  (never reachable — SCK reports sleep, lock and lid-close as one code) are **deleted**, per M14-T3's
  precedent, rippling through the CLI's `describe`, the notification `cause` switch, two test fixtures
  and docs 01/02/05/06. Three stale doc comments corrected (`makeMicrophoneInput` claimed device-native
  audio format; `Settings.replaySeconds` and `AppState.replaySeconds` both still said "30/60/120" after
  M9-T8 made it a range). `isSameFile` is now one `URL` extension (`FileIdentity.swift`), kept distinct
  from `Exporter.sameFile` on purpose — that one resolves symlinks and file identity, this one answers
  "does this receipt point at that row" and must still work once the file is gone.
  **A fifth drift surfaced while fixing the fourth:** docs/06's fail-stop cause list was wrong in *both*
  directions — it named `microphone changed` **and** omitted `the recorded app quit` (M7). Now matches
  the `cause` switch exactly. **429 tests unchanged, full dev loop green, CLI verified by hand.**
  **Next: M15-T5** (rotate this file) — the last M15 task.

- **✅ M15-T3 DONE (2026-07-24) — exports get the recording path's `.partial` discipline.** The three
  exporters (`Exporter`/`GifExporter`/`Trimmer`) write to a `.partial` companion and rename only on
  success, and the launch sweep learned to tell a recording partial from an export one. **Premise
  confirmed by A/B, not assumed:** `kill -9` mid-export **before** left a torn `Take.mp4` **at the real
  name** (which M12-T2 would list in Recent Exports as a finished file); **after**, only
  `Take.mp4.partial` and nothing at the final name.
  **Two design changes from the plan, both found by doing it:** **(1)** it went into the **exporters**,
  not `ExportModel.performExport` — the funnel looked like the one-place win, but its injected spies
  deliberately never touch the filesystem, so a rename there failed 5+ pure wiring tests and would have
  forced them to create real files; putting it at each exporter's entry point kept every test untouched
  **and closed the CLI gap the plan had written off**. **(2)** the sweep is **three-way**: "recover
  `.mov`, delete the rest" would have deleted the CLI's extension-less exact-path partials
  (`take1.partial`), which `finalizePartial` explicitly supports — so it recovers `.mov` + extension-less,
  deletes only known export extensions, and **leaves anything unrecognized alone** (deletion is
  irreversible). `OutputLocation.exportExtensions` is now the one list the sweep and `RecentRecordings`
  share. **429 tests (+4)**, three gated encode suites green through the new path, live CLI
  mp4/gif/trim all landing correctly, dev loop green. **Next: M15-T4.**

- **🚫 M15-T2 DECLINED (Franco, 2026-07-24) — closed "won't do", not deferred.** The settings-mirror
  collapse is off the board; full reasoning in docs/03 under M15-T2. Two planning-pass findings killed
  it: **(1)** the bug it claimed to prevent barely exists — `Settings` uses the memberwise init and
  `persist()` passes all 17 args, so a new field **breaks the build**; only a field declared *with a
  default* slips through silently. **(2)** `@Observable` tracks **stored** properties, so one backing
  `settings` struct would coarsen granularity **17 → 1** — every preference write notifying every
  preference reader, on a codebase where M6-T10 makes spurious publishes actively harmful. The
  `PermissionsModel`/`ExportModel` precedent doesn't transfer (those are `let` refs to `@Observable`
  **classes** with individually-tracked properties; a struct has none), and the class-backed variant
  preserves granularity while **not doing the task** — it relocates the mirror, the exact shape M9-T7
  rejected. **Ruling: ~70 lines isn't worth loosening the observation graph.** **Next: M15-T3**
  (export partial-file discipline) — plan artifact first.

- **✅ M15-T1 DONE (2026-07-24) — `swift test` is deterministic again: 8/10 failing → 0/20, slowest 3 s.**
  Two changes, both in `Tests/`, **no production code touched**: `@Suite(.serialized)` on
  `ReplayEncoderTests` + `ReplayMuxerTests`, and the `SyntheticBuffers.swift` readiness `precondition`
  replaced with `Issue.record` + early return. **Option (a) from the plan — gating the two suites behind
  `SCREENREC_HW_ENCODE_TESTS=1` — proved unnecessary, so replay-encoder coverage stays in the default
  loop.** Evidence:

  | Stage | Runs | Failed | Wall clock |
  |---|---|---|---|
  | Baseline (unmodified) | 10 | **8** | 2–3 s green / 122–124 s failing |
  | `Issue.record` only | 10 | **7** | unchanged — *no improvement* |
  | `+ @Suite(.serialized)` | 20 | **0** | slowest **3 s** |

  Also: the three gated encode suites green in isolation (Exporter 12, Trimmer 4, GifExporter 4); full
  dev loop green (build · **425 tests / 3 s** · release · signed bundle).
  **⚠️ Two premises I asserted in the review were wrong; the measurement corrected them —**
  **(1)** the `precondition` was never the common failure (it fired **0 times in 10 real runs**), and
  removing it alone changed nothing (7/10). It is worth keeping — forced to fire it now records **13
  issues with 0 aborts and all 425 tests still reporting**, where before one flake killed the run — but
  it is robustness, not the cure. **(2)** The ~120 s is not a prior run's abort poisoning the next; it
  is spent *inside* each test, which then mostly **passes** at ~122 s. See the field note for the real
  mechanism. **Next: M15-T2** (collapse the settings mirror) — plan artifact first.

- **✅ RESOLVED by M15-T1 — the "`swift test` failed 3× in a row" entry below overstated it.** The
  correct characterisation is **flaky, with strong autocorrelation**: a 10-run baseline measured 8
  failures in the pattern `pass, fail×6, pass, fail, fail` — so it recovers on its own and re-trips,
  rather than staying broken. Everything else in that entry stands; the *cause* it named (VT
  oversubscription) was right, the *amplifier* it named (the `precondition` poisoning the next run) was
  not. Kept below unedited as the original observation.

- **🗺️ ROADMAP REFILLED (2026-07-24) — a full-repo review produced M15–M18; nothing implemented yet.**
  A code/architecture + product review of v1.7.1 (clean tree at `6c6dd0e`) produced **18 findings — 6
  code (A1–A6), 12 product (B1–B12)** — now encoded as four milestones in docs/03. **Next: M15-T1**
  (plan artifact first, per the working contract). Order and rationale:
  - **M15 — Gate & Debt** (A1–A6, **PATCH**). Do first. **The headline is that `swift test` is not
    reliably green** — see the finding below; the rest is the settings mirror (A2), export partial-file
    discipline (A3), stale comments + dead `EndReason` cases (A4/A6) and rotating this file (A5).
  - **M16 — Honest State** (B1–B4, B8, B9, **MINOR**). The review's thesis: extend ADR-007 from "never
    a broken file" to "never a lying state" — armed replay's sleep assertion (B1) and its cost (B8),
    optional system audio (B2), silent-audio detection + a level indicator (B3), an onboarding
    capability self-test (B4), and showing the version (B9).
  - **M17 — Window capture** (B5, **MINOR**). The last missing scoping mode; M11's shape exactly.
  - **M18 — Editing & Menu polish** (B6, B7, B10–B12, **MINOR**). Trim honesty + precise mode, MP4
    export options, menu row-count, and five small papercuts.
  M17/M18 are interchangeable; **M17-T2 adds menu rows that M18-T3 is removing** — whichever runs
  second inherits the coordination (flagged in both tasks). Review artifact:
  `claude.ai/code/artifact/b5915b92-c083-4e2e-8cc9-f590901d8e8c`.
  **⚠️ Two things the review changed about how to read this repo:** (1) the running app was **not**
  driven during it — no menus opened, no screenshots — so every UI finding is read from view source
  and docs/06, i.e. inference, not measurement; (2) B4 was **missing** from the artifact's bundle
  table (Franco caught it) and is now M16-T6.

- **🔴 FIELD NOTE / OPEN — `swift test` failed 3× in a row on a clean tree (2026-07-24), no source
  changes.** This is M15-T1 and the most urgent item on the board, because with no CI this suite *is*
  the gate and it fronts the pre-push hook. Measured at v1.7.1, `6c6dd0e`:
  - **Run 1 — aborted.** `Precondition failed: encoder session never became ready`
    (`SyntheticBuffers.swift:24`). It's a `precondition` in a *shared helper*, so the process dies and
    the other 424 tests never report — one flake costs the whole run's signal.
  - **Run 2 — 6 issues, 121.7 s** (`ReplayEncoderTests` 5, `ReplayMuxerTests` 1).
  - **Run 3 — 4 issues, 121.6 s**, one carrying `The replay encoder failed on a frame (VT error
    -12912)` — VideoToolbox encoder malfunction / resource exhaustion. Each failing test burns a 120 s
    timeout first; the suite historically runs in ~2 s.
  **The mechanism was already known** (field note 2026-07-21: swift-testing parallelises suites,
  several hold a live `VTCompressionSession`, Apple Silicon allows only a handful) — **but the
  mitigation only ever reached the three env-gated encode suites.** The pre-push hook runs those one
  at a time with `--filter` and its comment says exactly why; `ReplayEncoderTests`/`ReplayMuxerTests`
  are always-on, carry no `.serialized` trait, and run concurrently with everything else. Candidate
  fixes and the trade-offs are in M15-T1's Rulings; the recommendation is to gate the two VT suites
  the same way the other three already are, plus replacing that `precondition` with a recorded
  failure. **Until this lands, treat a red `swift test` as unproven rather than as a regression, and
  re-run the encoder suites in isolation to tell the two apart.**

- **🎉 v1.7.1 CUT (2026-07-23) — M14 (Cleanup) earns the PATCH; roadmap empty.** `VERSION` +
  `CoreInfo.version` → 1.7.1 (pin green), committed (`3581e3d`), cut via **`Scripts/release.sh` run in the
  BACKGROUND** (VT-wedge lesson) — full gate green (build · test · encode×3 · release · bundle-sign),
  tagged `v1.7.1`, pushed main + tag. **0 unpushed; tag on origin; installed 1.7.1** (/Users/Shared).
  PATCH not MINOR: M14 is behaviour-preserving refactors (ExportModel extraction · WriterDrain dedup ·
  hygiene), no new user-facing feature (ADR-013). VT stayed healthy — background run never killed
  mid-encode. **🏁 The v1.6.0-review roadmap (M12 Share&Surface · M13 Hardening · M14 Cleanup) is fully
  SHIPPED.** Tags this arc: v1.6.1 (M13), v1.7.0 (M12), v1.7.1 (M14). **Next: Franco's call — dogfood, or
  scope new work (no planned milestones remain; webcam DECLINED ADR-017, studio/compositing parked
  ADR-015).**


## Needs Franco (human-only items)

- [x] **M6-T1 C2 ruling — RESOLVED 2026-07-17 (Franco): amend the criterion** ("I'm not
      that concerned about the size of the video"). Brief updated; the 2.59 GB/h Balanced
      measurement stands on record; evidence file deleted after the ruling.
- [ ] **Display-sleep lever (declined for now, 2026-07-27 — "headless legs only").** Two open questions
      need `pmset displaysleepnow` while armed, which blanks the screen mid-session: does
      `ReplayController`'s 5 s retry loop **wake the display back up** (02 §11 says SCK wakes a slept
      display to capture it — the two facts have never been measured together), and does the ring
      refill unaided after a real sleep/wake. Recorded as UNMEASURED in docs/07 under M16-T1.
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
| G8   | ✅ **PASSED 2026-07-20 (v1.2.0)** | (1) Armed replay: case → armed held → in-ear return → ring refilled unaided → 60.2 s clip, mic track spans the full window (gap included), video+system audio uninterrupted, post-recovery −8.8 dB. (2) Recording: case → return → `finished(userStopped)`, mic track 72.35 s of 90 s, resumed across the gap. (3) No regression: stable-mic 12 s run 3-track clean; never-returns leg = today's ADR-012 outcome (no substitution, playable file). Sync: measured cross-stream PTS coherence (±0.6 ms/min) + per-leg track alignment ≤150 ms; human scrub offered. Automatic-policy bonus leg: recovery onto the built-in while the pick's device stayed away. |
| G7   | ✅ **PASSED 2026-07-20 (v1.1.0)** | App-scoped recording (32.25 s, hvc1 + 2×AAC, menu-driven) + app-scoped **mid-recording** replay save (14.76 s, same shared stream — G5 §6.4 simultaneity under an app filter): both probe clean, both **content-clean** (a flashing bystander window on screen throughout appears in NO checked frame of either file). Bystander *audio* scoping: measured same-day at the engine level (M7-T1: −91 dB app-scoped vs −10.6 dB whole-screen control through the identical filter-construction path; SCK-level spike 0.0000 vs 0.2931) — not re-measured through the menu path, which diverges only above the filter. App-quit handled: CLI `finished(appQuit)` (T1) + armed-stream quit → held armed → auto re-arm on relaunch → clean clip (T2). |
| G6   | ✅ **v1 declared 2026-07-20 (v1.0.0)** — M6 complete bar the deferred T4 bucket; G6 = the sum of the soak legs (below) + acceptance criteria, all green | §7 leg 1 ✅ 2026-07-17: 2 h battery, real usage + Zoom, replay armed, 3 mid-run replay saves; 19.5 GB / 7223.42 s, tracks ≤110 ms apart; battery 99→62%, CPU avg 12.9% / max 19.3%, RSS 98–485 MB trendless, zero thermal warnings; Franco: "smooth throughout, no desync" (claps at 0/1/2 h). §7 kill leg ✅ (amended to 1 h, Franco): kill -9 at 3540 s → playable 3539.53 s, **0.47 s lost** (≤10 s); app relaunched Ready. ⚠️ relaunch dropped the persisted armed state (transient pipeline failure → self-disarm; field note) — open follow-up, not a gate fail (§7 doesn't cover it). |
| G16  | ✅ **passed 2026-07-27** | **No stream misreports itself:** the deployed app's assertion reads `Instant replay is armed` (T1; the original "an armed Mac idle-sleeps" criterion was replaced by ADR-018 — measurement showed SCK's own audio tap keeps the Mac awake regardless of `SleepGuard`). **The armed cost is stated where it's chosen:** Settings caption + menu row, live on Franco's own settings — `4:30 buffer · ≈800 MB · Mac stays awake` (T2). **System audio off:** probe shows video + 1ch mic, **no empty track**; on: 3 tracks, no regression vs G2 §3.1; all-off: playable video-only (T3). **Muted mic:** exactly one notice at ~10 s, recording ran to completion, file playable with a full-length silent mic track; unmute → the paired recovery notice; control run → neither (T4). **Menu-bar level measurably tracks audio:** four distinct rendered states by pixel diff (0/89/153/189 px, all inside the meter's columns), and a live capture lit it and returned to the silent bitmap (T5). **Setup proves capture and names the build:** `✓ screen · 4112 × 2570 / ✓ system audio / ✓ microphone · AirPods Pro`, muted → `! microphone · silent`, None → `— microphone · not selected`, scratch cleaned, footers match `VERSION` (T6). **No regression in the other capture modes:** region → 1600×1200 3-track, app-scoped → display-sized 3-track; export/trim/GIF encode suites green in the release gate. 470 tests. |
| G15  | ✅ **passed 2026-07-24** | T1: `swift test` 20 runs green, none over 10 s (baseline 8/10 failed at ~123 s). T3: `kill -9` mid-export leaves nothing at the final name (A/B measured; before, a torn `.mp4` survived). T4: no stale comment or dead `EndReason` arm remains; 429 tests. T5: STATUS.md 2,769 → 237 lines, rotation verified lossless, all doc references resolve. T2 closed "won't do". |


## Where the rest lives

| What | Where |
|---|---|
| Measured platform behaviour and gotchas (the most re-read artefact here) | `docs/07-field-notes.md` |
| Closed session logs — M0–M14, the v1 status write-up, calibration tables | `docs/history/2026-07-sessions.md` |
| Per-task specs, rulings and tick boxes | `docs/03-milestones.md` |

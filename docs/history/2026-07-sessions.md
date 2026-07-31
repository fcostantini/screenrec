# History — closed session logs (M0–M22)

Rotated out of STATUS.md by M15-T5, verbatim and newest-first. **Nothing here is maintained**: it is
the record of how the work went, not a description of how things are. For current state read
`STATUS.md`; for the per-task specification and tick boxes read `docs/03-milestones.md`; for measured
platform behaviour read `docs/07-field-notes.md`.

## Rotated from STATUS.md 2026-07-31 — M23 (the write path tells the truth) and the 2026-07-30 review

- **✅ M23-T5 DONE (2026-07-30) — `AppState` is 130 → 95 public members, 1,420 → 1,355 lines.**
  Views and tests read `state.sources.x` / `state.session.x` / `state.exports.x` /
  `state.permissions.x` directly; the scaffolding M22 left is gone. **636 tests green**, and the
  deployed menu dumped identical — M22's own bar — bar live window titles retitling between dumps
  (which M22 also saw) and the mic list gaining AirPods Pro, which connected between the two.
  Plan artifact: `claude.ai/code/artifact/5e82d5c8-e490-448d-9516-655d516c1401`.
  🔴 **The second half of the agreed scope was abandoned on measurement, and the fault is mine.**
  I proposed extracting the replay and self-test clusters because docs/03 called them **548 lines**;
  Franco picked that scope on my recommendation. Counted properly they are **178** — replay 143,
  self-test 35. Extracting replay would also inject a bigger surface than it moves: its 14 members
  reach settings persistence, the capture configuration, the hotkey registrar, `sources`, `session`
  and `notifier`, and since M23-T3 the save flash is **shared** with a take stopping while armed, so
  it is not replay-only state. **T5 as filed is complete** — its title and its Verify are the
  forwards; the extractions were the task's own conditional "if this is worth continuing", and on
  the true numbers it isn't.
  ⚠️ **Ten of the 47 "forwards" were adapters, not scaffolding** — they inject `microphoneRequired`
  or an export configuration, inputs only `AppState` holds. They stay, and say why in-line. Also:
  SwiftUI won't write a binding through a `let`, so the source Pickers take `Bindable(state.sources)`.

- **✅ M23-T3 SHIPPED (2026-07-30) — the menu bar stops hiding work, and a silent stop stops being
  silent. M23 is complete; G23 is next.** An export in flight now draws a **second dot, top-trailing**
  (Franco's ruling), composited like the armed badge rather than added as a fourth `StatusIcon` case —
  an export is orthogonal to the session, so an enum couldn't say "recording *and* exporting".
  **636 tests**, dev loop green, plan artifact
  `claude.ai/code/artifact/871b879f-7e8e-4dc0-a387-267c9f944810`.
  🔴 **The flash it was told to mirror had never rendered.** M9-T3 put it in the label's `HStack` as a
  second `Image`, and a `MenuBarExtra` draws only the first — M16-T5 measured exactly that and left it
  out of scope. So VoiceOver has been announcing a tick nobody could see, since M9-T3. Now composited;
  **captured rendering for the first time** (icon width 39 → 51 at the stop, tick visible, back to 39
  after the window).
  🔴 **And the live leg caught a second one that the unit tests could not.** The stop-flash hook went
  into `AppState.apply`, which **production never calls** — `consume` forwarded the stream straight to
  `session.consume`. Green test, dead code. `consume` now drives the loop through `apply`, with a test
  that fails if they diverge. Third variant of today's theme: a test only proves the code it runs.
  ✅ **Live evidence, magnified captures:** idle; idle + export dot (top-trailing, gap ring notching
  the circle like the armed one); **armed + exporting — both dots, no collision, meter intact**; and
  the tick on a stop-while-armed. Franco's replay setting was armed for the leg and **set back to off**.
  ⚠️ **Pixel-diffing the menu bar is not trustworthy here** and M16-T5's clean numbers were a quiet
  neighbourhood: live third-party widgets slide our item a point, and `kAXExtrasMenuBarAttribute`
  reported an *identical* frame for two visibly-offset crops. Translucency turns a one-point slip into
  99.96% differing pixels. Visual captures are the evidence; a pixel count is corroboration (docs/07).

- **✅ M23-T4 SHIPPED (2026-07-30) — the two extracted models now fail as themselves.**
  `SessionModelTests` (18) and `ExportModelTests` (15) construct the models **directly** — confirmed
  while planning that neither class was built once in the whole suite; both were reached only through
  `AppState`. **631 tests** (598 → 631), **no source change**, and the 90 existing
  `AppStateTests`/`ExportWiringTests` are **unedited** — M22's "passed untouched" property is what
  caught two inverted guards, so the new tests sit beside it, not instead of it. Plan artifact:
  `claude.ai/code/artifact/c11a6c3a-2bd1-4a0f-8547-3a24e1641c69`.
  ✅ **Bar met the M22-T3 way: 12 breaks applied, 12 turned the right suite red** — and each named
  `SessionModelTests`/`ExportModelTests`, not somebody else's. The matrix is in the plan artifact;
  the script is throwaway.
  🔴 **11 of 12 on the first pass — and the twelfth is the point of doing this.**
  `pauseFreezesTheClockAndResumeKeepsWhatWasBanked` compared two values that were **both ~0** (the
  test runs in microseconds), so "resume restarts the clock at zero" satisfied it and stayed green.
  Fixed with a 30 ms wait and an explicit `banked > 0`; the break now fails it `0.0 == 0.032`.
  **Second time this shape has bitten** (M22-T3's `Polling`) — docs/07.
  ⚠️ One honest limit: `notify(about:)` reads duration off a live `capture`, which a bare model has
  none of, so these pin *which* notification is posted, not its clock. That stays
  `RecordingSessionTests`' territory.

- **✅ M23-T2 SHIPPED (2026-07-30) — an export refuses what can't land, and quit no longer eats one.**
  The fit check sits at `ExportModel.performExport` (the one funnel) with an **injected estimate**,
  because the four actions have different size models: MP4 uses `ExportConfiguration.projectedBytes`
  (now shared with the menu row that quotes a weight), trim uses the source's own size as a ceiling,
  and **GIF is deliberately ungated** — LZW output can't be predicted, and a guess would refuse GIFs
  that fit. Quit now waits: `finishWorkInFlight()` serves both the menu's Quit and
  `applicationShouldTerminate`. **598 tests**, dev loop green, plan artifact
  `claude.ai/code/artifact/d19a9bb7-b534-4b4e-8416-2f5729e0cc76`.
  ✅ **Live, through the deployed menu.** **A1:** 15.1 MB free vs a 34.7 MB export → refused with
  **zero bytes written**, no receipt, notice read `Not enough room to export / This needs about 35 MB
  and SCRECFIT has 16 MB free. The recording is untouched.` **A2:** ballast removed → exported clean,
  `avc1 1920×1200` + AAC, 45.05 s, receipt correct, no `.partial`/`.sb-`. **B:** quit through a live
  export → the alert appears with **`Wait for Export` as the default**; pressing it kept the app
  alive **17 s** until the 75.7 MB `.mp4` landed, then quit; `Quit Anyway` exited in **0 s** and its
  `.mp4.partial` was deleted by the next launch's sweep (`isAbandonedExportPartial`).
  🔴 **`Quit Anyway` was a lie until leg B was designed.** Every quit route ends in
  `NSApplication.terminate`, whose delegate waits for an in-flight export — so the abandon button
  waited exactly like the wait button. Fixed by clearing `exportInProgress` **synchronously** before
  `terminate`. The general rule is in docs/07: an alert in front of `terminate` cannot decide the
  outcome; the delegate gets the last word.
  ✅ **RULED: strict stands (Franco, 2026-07-30), with the cost known.** A2's real export was 9.4 MB
  against its 35 MB estimate, so A1 refused a job that would have fitted — the ~3.7× ceiling docs/07
  predicted, arriving on a path where it *decides* rather than labels. The trade was taken with that
  number in hand: a false refusal is instantly recoverable, a false accept costs minutes and ends in
  the failure the check exists to remove. **Don't re-open without a new measurement** — a fraction
  would be invented, and the spread is content, not a constant (5× static vs 1.02× busy, M19-T4).
  ⚠️ Also found: an abandoned export leaves an `.sb-` temp nothing sweeps (pre-existing; `Quit Anyway`
  makes it one click) — cheap follow-up noted in docs/07.

- **🧹 The test suite had leaked 49,668 preference plists — 194 MB, 99.3% of `~/Library/Preferences`**
  (2026-07-30, found while reading the app's own settings). Deleted with Franco's OK: **50,027 → 359
  files, 302 MB → 109 MB**. Cause fixed by `TestDefaults`, which records every throwaway suite and
  sweeps on the way **in** as well as out. ⚠️ **The exit sweep cannot be made reliable** — it races
  `cfprefsd`, and a single clean run fooled me before two later runs leaked 154 each; the entry sweep
  is what bounds it. Measured over three runs — **154 → 308** (growing, pre-fix), **308 → 308**
  (holding), **616 → 308** (a backlog reclaimed). Steady state is one run's residue (~150), and it
  self-corrects rather than needing a human with `rm`.

- **✅ M23-T1 SHIPPED (2026-07-30) — the write path can no longer lie about a take.** The recorder
  checks `input.append`'s `Bool`, confirms `writer.status == .failed`, and stops the session with a
  new `EndReason.writeFailed`; finalize **salvages the fragments** instead of finishing a dead writer.
  `ReplayMuxer` line 277's identical discarded call now reports too. **584 tests** (576 → 584), dev
  loop green, plan artifact `claude.ai/code/artifact/f68dd711-864e-44b8-bb93-ed33c97b1d5a`.
  🔴 **The A/B is the evidence** (500 MB APFS image, ballast to ~20 MB free, the take fills the rest —
  M19-T1's standard): **before**, the CLI ran the **full 60 s**, 38 s of it after the writer was
  already dead, and ended `✗ Couldn't finish saving the recording` offering nothing — while the
  `.partial` it abandoned probes **23.05 s** once renamed. **After**, `✓ finished (writeFailed)` at
  **20 s**, handing back a **19.05 s** playable file (hvc1 4112×2570 + AAC, tracks ≤80 ms apart).
  Also run: volume **detached** mid-take → ended at 8 s with the honest "the file is no longer where
  it was being saved" (never a claimed save); **control** → `finished (userStopped)`, 12.20 s clean;
  `~/Movies` regression → 3 tracks, 8.08 s.
  ⚠️ **Three measurements worth knowing before touching this** (all in docs/07): `isReadyForMoreMediaData`
  stays **`true`** on a `.failed` writer — which is *why* it was invisible; **no synthetic buffer can
  fail a writer** (four tried, all accepted), so the mechanism is not unit-testable and the tests
  cover the decision instead; and on a full volume the `.partial` → final **rename can itself fail**
  (2 of 4 runs), leaving a file `AVURLAsset` won't open until the launch sweep renames it.
  **Rulings taken** (Franco's defaults): new `EndReason` case over reusing `.streamError`; a refused
  append confirms against `writer.status` before ending anything; `onWriteFailure` renamed
  `onCannotBeginWriting` now it has a sibling; a `.writeFailed` take is **not** offered for naming or
  Stop & Copy (writing to the volume that just refused a write is the wrong next move); no `VERSION`
  bump until the M23 cut.
  **✅ G23 PASSED 2026-07-30** — see the gate table. **M23 is complete** bar T5, which is optional,
  explicitly last, and unasked-for.
  **Next: Franco's call.** The obvious candidate is **M24** (finish the share loop): its T3 mirrors
  the flash M23-T3 just repaired, so it inherits one that works, and T5 stays available if structure
  is wanted before more features land on it.

- **🔍 REVIEW (2026-07-30) — 15 findings; M23 and M24 encoded in docs/03, T1 done.**
  Artifact: `claude.ai/code/artifact/38dcfad1-b8d9-4029-9a96-e7f9ec4544fc`. Code, architecture and
  product pass over v1.11.0, read against the source and the running app.
  🔴 **The headline is a reliability gap: the recording write path never checks whether the write
  succeeded.** `MovieRecorder.append` discards `input.append()`'s `Bool` and nothing watches
  `writer.status` during a session, so a failed `AVAssetWriter` keeps a pulsing icon and a ticking
  clock until Stop — up to forty minutes late on a long take. M19-T1's shape exactly. The *export*
  path checks the same call, so the discipline exists; it just isn't on the path that matters.
  **The rest, in short:** exports have no disk guard and quitting mid-export loses them silently;
  `AppState` regrew **1,288 → 1,382 / 127 public members** because M22's forwarding scaffolding taxes
  every feature twice; `SessionModel` and `ExportModel` are the two units nothing tests by name;
  Swift 6 is **7 error sites** away in RecorderCore; the keyboard path stops one step short of the
  clipboard; the Trim window won't hand you the clip it just made; and a take that stops while replay
  is armed is **completely silent** (banner suppressed, no receipt row, no flash).
  ✅ **ENCODED IN docs/03 (2026-07-30): M23 → M24**, with tasks, seams, rulings and gates G23/G24,
  plus the ordering rationale and a refreshed parked list (the `NSMenu` item's trigger has arguably
  been met; **crop on export needs Franco's ruling**; Core Audio taps written up as their own
  milestone). **Nothing implemented.**
  ⚠️ **Every code finding is read-from-source, not reproduced** — each one wants a real reproduction
  before anyone calls it fixed. M23-T1 got one (above); the other fourteen have not.
  ℹ️ Worth knowing: Franco's saved WhatsApp ffmpeg recipe is now **redundant** — 1920 scale, both
  audio tracks mixed to one, H.264 VideoToolbox 6 Mbps, AAC 160k, faststart is exactly what
  `Export as MP4` does today.

- **Shipped and in daily use: M0–M22, v1.11.0** (2026-07-30). **576 tests**, dev loop green.
  **Deployed** at `/Users/Shared/ScreenRec.app` — pid 94518, plist 1.11.0, signature valid, menu
  **Ready**. Release: https://github.com/fcostantini/screenrec/releases/tag/v1.11.0
  **Next: Franco's call.** The 2026-07-28 review roadmap (M19 → M22) is complete; every gate's
  evidence is in the table below, and per-task detail is in `docs/history/2026-07-sessions.md`.

## Rotated from STATUS.md 2026-07-30 — the closed "Needs Franco" ledger (M0–M6)

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

## Rotated from STATUS.md 2026-07-30 (docs cleanup) — M20's closure and M20-T1, M22's tasks and the v1.10.2 cut, the 2026-07-28 review

- **🚫 M20 (Marks) CLOSED "won't do" 2026-07-28 (Franco) — and M20-T1's shipped code was reverted.**
  Plan artifacts: T1 `claude.ai/code/artifact/17df26d2-c25d-4671-a12f-91248a3b9168`, T2
  `claude.ai/code/artifact/cf022a1e-a02d-42f3-b4b7-5de3e64ad237`. **557 tests** — exactly the
  pre-marks count.
  🔴 **The measurement that ended it: a sparse extra track disables fragmented writing, and with it
  crash safety.** `AVAssetWriter` emits a fragment only when *every* input has data up to the
  boundary, so a chapter track fed once per mark starves it. **Mid-write — the only state a crash
  sees — no track → 3 `moof` atoms · track never marked → 0 · track + one mark → 0.** End to end:
  two takes, same build, same `kill -9`, **marks off recovered as a playable 10.99 s file; marks on
  was unreadable**. A 40-minute take would have been total loss.
  **Every other route was measured and closed:** movie metadata can't be set after writing starts;
  a sidecar `.json` works but Franco won't have a companion file beside every recording; post-hoc
  atom surgery on a multi-GB take is not worth entertaining. Franco: *"if there's no better
  alternative i'd just discard the entire marks feature"* — there isn't.
  ⚠️ **The generalised trap is in docs/07 and outlives the feature:** anything that ever adds a
  track to `MovieRecorder` must be measured *while writing*, by counting `moof` atoms on disk before
  finalize. A clean `finishWriting` and a readable output prove nothing about the crash case — that
  is exactly what fooled my first harness.
  **Kept:** the menu-bar clock alignment fix (`ab59095`), which was independent.
  **Next: Franco's call.** The roadmap has **M21** left (One step from "it happened" to "here it
  is") — T1's ranged export, T2's Stop &amp; Share, T3's named takes, T4's per-app audio exclusion.

- **~~M20-T1 (reverted)~~ — ⌥⌘M marks the running take.** Plan artifact (rulings A/B/C
  approved): `claude.ai/code/artifact/17df26d2-c25d-4671-a12f-91248a3b9168`. **564 tests (+7)**,
  dev loop green, deployed (pid 23380).
  **As built:** opt-in shortcut seeded ⌥⌘M (the M9-T4 pattern), a ~2 s menu-bar **bookmark badge**
  (the `replaySavedFlash` shape — no notification, since a demo can carry twenty marks), and one
  dimmed menu row `N marks · last at M:SS`, stamped at open, absent at zero.
  **Ruling A — the position is `RecordingClock`**, not the writer's `recordedDuration`: the clock is
  the number the menu bar is *showing* when the key is pressed. **Ruling B — a paused take declines
  the mark**, since every press would stack on the same frozen frame. **First shortcut on M22-T4's
  typed registry** (`addMark = 5`; a collision is now a compile error — the payoff for running M22
  first).
  **Verified live, and the take checked itself:** ⌥⌘M fired **from another process** (so it is
  genuinely global) → `1 mark · last at 0:05`; a press while paused was declined; resumed →
  `2 marks · last at 0:29`; the file was **33 s with the ~13 s pause absent**. Because a full-screen
  take records its own menu bar, the marked frames were read back: **00:00:05** at the 0:05 mark and
  **00:00:28** at 0:29 — within the label's 1 Hz tick (docs/07).
  ⚠️ **I filed a false bug mid-leg** — that the header clock advanced during the pause — by reasoning
  from my own sleeps rather than the app's clock. Every `swift tools/…` run compiles first, so the
  pause landed much later than my arithmetic assumed; Franco caught it because he was watching the
  menu bar. Nothing reached the docs but the lesson (docs/07).
  ⚠️ **⌥⌘M is currently bound on Franco's machine** (seeded for the leg). Say the word and it goes.
  **Next: M20-T2** (marks survive the file) — the task with the real decision, and the one that
  makes marks usable at all: today they die with the take.

- **🎉 GATE G22 PASSED + v1.10.2 (2026-07-28) — M22 (Structure) is complete, and the release cut
  itself.** Evidence in the gate table. **PATCH (ADR-013):** no user-facing change anywhere.
  **The cut is the gate's fourth criterion**, so it is worth reading as evidence: `Scripts/release.sh`
  run in the background printed **`no terminal — pushing (--no-push to stop)`**, then
  **`✓ push main + v1.10.2`** · **`✓ zipped ScreenRec-1.10.2.zip (988K)`** ·
  **`✓ github release v1.10.2`** — the first cut in this project's history that needed no human
  after it started. Verified independently: **0 unpushed**, the tag is on origin, and the release
  carries `ScreenRec-1.10.2.zip` (1,010,602 B, not a draft).
  https://github.com/fcostantini/screenrec/releases/tag/v1.10.2
  **DEPLOYED** to `/Users/Shared/ScreenRec.app`: pid 19088 → **20789**, plist reads 1.10.2, menu
  **Ready**, Source Entire Screen.
  ⚠️ **Instant replay is OFF because Franco turned it off** — noted here because the earlier entries
  in this file record it as normally armed, and a future session should not "restore" it. I re-armed
  it during this deploy on a wrong inference and turned it straight back off; `replayArmed = 0`.
  **Next: Franco's call.** The 2026-07-28 roadmap has **M20 (Marks)** and **M21 (One step from "it
  happened" to "here it is")** left — M22 ran first by his ordering call, and M22-T4's hotkey
  registry and T3's write-path tests were the two tasks that were meant to land before M20 touches
  them.

- **✅ M22-T2 DONE (2026-07-28) — `AppState` sheds the session. All six M22 tasks are done; G22 is
  the only thing left in the milestone.** Plan artifact (rulings A/B/C approved):
  `claude.ai/code/artifact/3c800991-74e7-4187-badc-01ef4e61eab0`. **557 tests passed untouched**,
  dev loop green, deployed (pid 19088).
  **As built:** `SessionModel` (187 lines) owns the capture handle, the counters, the clock, the
  `active*` facts and `apply(_:)`. **The actions stayed on `AppState`** — `start()` needs the
  count-in, permissions, the output location and replay, and moving it would have relocated the
  tangle rather than cut it. 1,391 → **1,288 lines**.
  **Ruling A held up in the code:** `lastFailure` is set *before any session exists*, so it stays on
  `AppState`; the fold reports through `reportFailure(message, outlivesSession:)` and the policy
  lives with the state. **Ruling B:** `activeMicrophoneName` moved, and `resolvedMicrophone()` now
  **returns** the name rather than assigning it, since it runs before there is a session to hold it.
  🔴 **Two guards silently inverted** when `session` stopped being an optional — `guard session ==
  nil` (always false now → Start became a no-op after a cancelled count-in) and `session != nil ||
  isReplayArmed` (always true → the meter would show when idle). **Both were caught by tests that
  did not move**, which is the whole argument for that bar.
  **Verified live:** the deployed menu dumped identical (only my own Terminal window's spinner
  differed), and Start → Pause → Resume → Stop froze the clock at **00:00:06 across three seconds**,
  resumed to **00:00:10**, and wrote an **11.90 s** 3-track file — the paused wall-clock correctly
  absent.
  **Next: G22** — all four criteria are now met on paper (`AppState` 1,569 → 1,288 with the menu
  unchanged; six units named by failing-capable tests; one timecode type; a background release that
  pushes and leaves a download). Then the **PATCH bump to 1.10.2**.

- **✅ M22-T1 DONE (2026-07-28) — `AppState` sheds its sources.** Plan artifact (rulings A/B/C
  approved): `claude.ai/code/artifact/029afaee-ad23-4a1b-a253-707826543efb`. **557 tests passed
  untouched**, dev loop green, deployed (pid 15658).
  **As built:** `SourcesModel` (288 lines, `@Observable` **class** — M15-T2's ruling) owns the
  lists, the four picks, `sourceChoice`, the missing-pick rows, the labels and the pick's geometry.
  `AppState` forwards, so no view binding and no test moved — except `regionLabel`, deliberately
  renamed (3 call sites) rather than left as a second name for one thing. Persistence and the
  armed-stream rebuild come back through two injected closures; the display pick fires only the
  rebuild, since it isn't persisted.
  **1,568 → 1,391 lines (11%) — I predicted ~1,290 and was wrong by 100**: the forwarding surface
  costs more than estimated. The win is that M20/M21 have a seam; it is not a small file yet.
  ⚠️ **The `// MARK: - Sources` section was mis-filed** — quality, frame rate, both menu-bar
  toggles, GIF/MP4 sizes and Stop-After all sat under it and are *settings*. They stayed, under a
  new `// MARK: - Settings`.
  🔴 **A python range-cut ate 190 lines of `AppState`** (the `regionLabel` end marker sat below the
  whole Actions section) — the same failure as M18-T6's doc rewrite, in code this time. Reverted,
  then redone with every cut declaring its expected line count and aborting on a mismatch; two wrong
  markers then surfaced as aborts instead of silent deletions (docs/07).
  **Verified live:** the deployed menu dumped identical (only a live Slack window retitled itself
  between dumps), and a menu-driven recording produced **4112×2570 hvc1 + 2 audio tracks**.
  **Next: M22-T2** (`AppState` sheds the session) — the last task in M22, and where the
  microphone's `presentMicrophonePreference` question lands.

- **✅ M22-T3 DONE (2026-07-28) — the six unnamed units now have tests that can fail.** No plan
  artifact (Franco waived it for this one). **557 tests (+17)**, dev loop green.
  **Each test verified by mutation, not by passing:** I broke every unit and confirmed its test
  noticed — `WriterDrain` (never leave the group → the deadlock, caught by a bounded `wait` rather
  than a hung suite), `SampleTiming` (drop the duration override), `PCMSampleBuffer` (ignore
  `fill`'s failure), `Polling` (swallow cancellation), `MediaFile` (never read a duration),
  `VideoFrameReader` (drop the fps gate).
  🔴 **That pass earned its keep immediately:** the first `Polling` test **passed against broken
  code**. Swallowing cancellation costs *exactly one* extra tick (`Task.sleep` throws the instant
  it's cancelled, so the loop wakes, ticks, then exits on `!Task.isCancelled`) — and the assertion
  tolerated one. Rewritten to check a window **shorter than the interval**. 🔴 **And that rewrite
  then flaked the gate** — a fixed-sleep assertion (`atCancel == 1` after 400 ms) passed alone and
  failed inside the 557-test suite, where the tick hadn't been scheduled. Now it waits for the tick
  with a deadline, *then* measures the short window; **5/5 clean full-suite runs**, and it still
  fails against the mutation. Mutate before believing a new test — and never time one with a fixed
  sleep (docs/07).
  ⚠️ Two CoreMedia facts found on the way: `CMSampleBufferGetDuration` returns the **total**, so a
  per-entry duration reads back ×480 on an audio buffer; and CoreMedia **refuses to create** an
  audio buffer with an invalid PTS, so that case can only come from `makeMarkerBuffer()`.
  `VideoFrameReader`'s subsample test needs the encoder → gated, and **added to the pre-push hook
  and `release.sh`**, because a gated test nothing runs is not a test.
  **Next: M22-T1** (`AppState` sheds its sources) — or hold T1/T2 for M20/M21 to show the seams, as
  docs/03 argues. Franco's call.

- **✅ M22-T4 DONE (2026-07-28) — one timecode type, one hotkey registry.** Plan artifact (rulings
  A/B/C approved): `claude.ai/code/artifact/229b2108-d4ea-4ae3-b31f-a4365f4275e2`. **540 tests**,
  dev loop green, deployed (pid 4080).
  **As built:** `Timecode.cutPoint` (floored — a point you can cut at) · `.clock` (`HH:MM:SS`,
  truncated, NaN-safe) · `.length` (rounded — a finished thing's label), in `RecorderCore/Support`,
  replacing **five renderers with three roundings across two modules**. The rounding is in the
  **name**: a style parameter invites a default, and a default is how the next caller silently picks
  the wrong rule. `HotkeyID: UInt32` types `setHotkey`, so the four ids cannot collide —
  **duplicate raw values don't compile**, which is the actual guarantee; `GlobalShortcut` stays in
  AppCore naming intent, so AppState still knows nothing about Carbon.
  ⚠️ **Correction to docs/03's premise:** the `In 0:05` above `Starts exactly at 0:04` bug was
  **already fixed** by M18-T1 — both surfaces call the same renderer, and its doc says why. What
  remained was the *condition*, with M20's mark list about to become the sixth caller. Said plainly
  in the task entry rather than justifying the work with a bug that wasn't there.
  **Verified:** the 14 pinned strings moved to `TimecodeTests` with their assertions unchanged, and
  the deployed menu dumped **byte-identical** before/after (90 rows compared; the single diff was a
  live Slack window retitling itself between the two dumps).
  **Next: M22-T3** (six units get a test that names them) — plan artifact first. Then T1/T2, which
  docs/03 argues could wait for M20/M21 to show the seams.

- **✅ M22-T5 + M22-T6 DONE (2026-07-28) — a cut now pushes itself and leaves a download.** Plan
  artifact (rulings A/B/C approved): `claude.ai/code/artifact/48258a07-0588-472b-9ea5-894cfd24f3a2`.
  One file (`Scripts/release.sh`), 539 tests unchanged (no product code).
  **T5:** **no terminal ⇒ push**, said out loud, `--no-push` to opt out; an interactive run keeps its
  `[y/N]`. A `--push` flag was rejected — same "remember it" failure mode as today. Verified five
  ways through the shipped block; ⚠️ **`script -q /dev/null cmd <<< "y"` cannot answer a prompt**
  (the heredoc feeds `script`, not the pty — `y` and `n` both "answered" identically and would have
  passed a broken decision). `expect` drives a real pty (docs/07).
  **T6:** `ditto` (never `zip -r`) + `gh release create`, notes leading with the Gatekeeper install
  steps then `git log` for the range; a `gh` failure **warns** rather than failing a cut whose
  irreversible half is already pushed.
  **Verified against the real `v1.10.1`**, by sourcing the shipped functions rather than a copy:
  **https://github.com/fcostantini/screenrec/releases/tag/v1.10.1** carries `ScreenRec-1.10.1.zip`
  (992,374 B — 2.9 MB bundle → 972 KB). Downloaded it back, set `com.apple.quarantine`, and after
  `ditto -x -k` the app **inherited the quarantine** and still read **`valid on disk` · `satisfies
  its Designated Requirement`**; `spctl` rejects it (`origin=screenrec-dev`) — ADR-014 as designed,
  and precisely what the install note is for.
  **Ordering amended in docs/03:** M22 runs **before** M20/M21 (Franco) — no dependency clashes, and
  T4/T3 protect M20. **Next: M22-T4** (one timecode, one hotkey registry) — plan artifact first.

- **🎉 GATE G19 PASSED + v1.10.1 (2026-07-28) — M19 (The disk tells the truth) is complete.** Three
  criteria, all re-run against the release build; evidence in the gate table. **PATCH, not MINOR
  (ADR-013):** with T2/T3 closed "won't do" the milestone adds no user-facing capability — a safety
  fix, a picker that states its cost, and a preference that stops being written.
  ⚠️ **The one that matters: the disk guard had never worked.** From M3-T3 to M19-T1 the fail-stop
  floor could only trip on a disk that was *already* too full at Start; the gate that "verified" it
  used a floor above the volume's free space, so it tripped on the first poll and a frozen reading
  passed. 04 §4.4 now rests on a falling volume instead.
  **CUT AND INSTALLED:** `VERSION` + `CoreInfo.version` → 1.10.1 (pin test green), committed
  (`50947b5`), `Scripts/release.sh` run in the **background** — full gate green (clean tree · version
  pin · tag free · build · **539 tests** · encode ×3 · release build · bundle-sign) — tagged
  **`v1.10.1`**, and main + tag pushed **by hand afterwards** (the background run's `Push? [y/N]`
  reads N with no terminal — unchanged, and M22-T5 is the fix). **Deployed** to
  `/Users/Shared/ScreenRec.app`: pid 93702 → **96618**, plist `CFBundleShortVersionString` = 1.10.1,
  menu **Ready**, replay re-armed unaided, Source Entire Screen.
  **Next: Franco's call.** The 2026-07-28 review roadmap has **M20 (Marks)** next by the documented
  order, then M21 (One step from "it happened" to "here it is") and M22 (Structure — which now
  carries T6, the GitHub release asset).

- **M19's task entries (T1–T5) — rotated to `docs/history/2026-07-sessions.md`** on
  2026-07-28; the milestone's outcome is the G19 row in the gate table.

- **🔍 FULL REVIEW (2026-07-28) — 18 findings; nothing implemented yet.** Code, architecture and
  product review of v1.10.0, **driven against the running app** (the 2026-07-24 review's caveat was
  that it wasn't): `claude.ai/code/artifact/63e7d73a-c519-4498-8f1b-e662f49393c4`.
  **🔴 The headline is a shipped bug: the disk guard reads free space once and never again** — see
  docs/07, measured. A long recording can still fill the disk, and the gate that "verified" the
  guard trips on the first poll so a frozen reading passes it.
  **The rest, in short:** `AppState` is 1,572 lines / 122 public members (two more extractions
  along seams that already worked); six units have no test naming them (`WriterDrain` the worst);
  four `M:SS` formatters and loose hotkey ids; window titles persist in plaintext preferences;
  nothing prunes `~/Movies` (one take = 5.5 GB); trim→export is two steps where Franco's own recipe
  is one; and the highest-value missing feature is a **mark-this-moment hotkey**.
  **✅ ENCODED IN docs/03 (Franco, 2026-07-28): M19 → M20 → M21 → M22**, with tasks, seams, rulings
  and gates G19–G22, plus the ordering rationale after the dependency graph. Nothing implemented.
  **Next: M19-T1** — the disk guard fix — plan artifact first, per the working contract. It is the
  only item on the roadmap that can lose a recording; the rest is improvement.
  **Parked from the review:** multi-display regions (the week a second display arrives), an
  `NSMenu`-backed status item (trigger: the next feature needing custom row rendering), and
  cursor emphasis / auto-zoom (still behind ADR-015's render stage).

- **Older entries — M18 (all six tasks), the v1.10.0 cut, and the v1.9.0 cut — rotated to
  `docs/history/2026-07-sessions.md`** on 2026-07-28, per the session-end checklist.


- **Older entries — M15, M16, M17 and the v1.7.1/v1.7.2/v1.8.0 cuts — rotated to
  `docs/history/2026-07-sessions.md`** on 2026-07-27, per the session-end checklist. The
  milestones themselves live in `docs/03-milestones.md`; measured platform behaviour in
  `docs/07-field-notes.md`; gate evidence in the table below.

## Rotated from STATUS.md 2026-07-30 — M21 (One step from "it happened" to "here it is"), shipped as v1.11.0

- **✅ M21-T4 DONE (2026-07-30) — `Source ▸ Everything Except ▸`. All four M21 tasks are done; G21 is
  the only thing left in the milestone.** Plan artifact (measurement first, three directions, Franco
  took the recommendation): `claude.ai/code/artifact/4f5cd208-0781-4bb3-a4a8-cf491614e0f7`.
  **576 tests (+6)**, dev loop green, deployed (pid 74408 → **91541**).
  ⚠️ **The task's premise moved under measurement.** SCK's exclusion is not audio-only: it removes the
  app's **picture** too, and it **cannot touch an app with nothing on screen** — the "music in the
  background" case F3 actually named. So it shipped as what it is: `Entire Screen except Slack`, with
  a dimmed `Slack won't be seen or heard` row. The true audio-only route (Core Audio process taps,
  `AudioHardwareCreateProcessTap`) is written up in **docs/02 §1a-ii** as its own future milestone,
  not attempted here.
  **Verified twice over:** raw SCK **−9.1 → −∞ dBFS** (buffers still flowing — silent, not stalled),
  the app's window present in one frame and absent in the other; then the shipped path,
  `record --exclude-app` → **−∞ dBFS** full-length system-audio track vs a **−8.3 dBFS** control, and
  the same through a menu-driven take.
  🔴 **The honesty path is measured, not assumed:** with the app minimised the take ran, the menu read
  **"The app to leave out wasn't on screen — nothing was excluded."**, and the file's system audio came
  back at **−9.0 dBFS**. A new `EngineEvent.excludedAppUnavailable` carries it (the
  `microphoneDroppedAtStart` shape) — degraded, never silent (ADR-007).
  ⚠️ **The mic still hears an excluded app through the speakers** (−35.2 dBFS on the mic track while
  system audio was −∞) — docs/07.
  **Everything restored:** Source back to Entire Screen, QuickTime quit, all test files deleted.
  **Next: G21** — the gate, then the **MINOR** cut (T1–T4 are all user-facing features).

- **✅ M21-T3 DONE (2026-07-29) — a take can be named the moment it stops.** Plan artifact (rulings
  A–C, "go with your picks"): `claude.ai/code/artifact/b0de032c-ec0d-4cfe-8528-c679a6e93fcf`.
  **570 tests (+4)**, dev loop green, deployed (pid 73163 → **74408**).
  **As built:** opt-in (`Settings → Recording → Ask for a name when a recording stops`, **off by
  default**, beside Count in). A finished take raises the `Rename…` alert with take-time copy —
  *Name this recording* / *0:10 · Esc keeps the date name* — and the answer goes straight into
  M12-T2's `rename`, collisions and receipt re-pointing included.
  **Two orderings carry the design:** it runs **after teardown** (a dialog left open can't delay
  re-arming replay or cancelling the stop timer) and **before the share export** (so Stop & Copy MP4
  copies the *named* `.mp4`).
  🔴 **The quality pass caught the second one broken:** the share path looked the take up by its
  pre-rename URL, which no longer existed — it would have silently exported nothing.
  `lastFinishedRecording` now records where the take actually landed.
  **Verified live, three legs:** named → `Bug-1204 repro.mov`, recents row agreeing; Esc →
  `Recording 2026-07-29 at 16.25.59.mov` kept; Stop & Copy MP4 + a name → `Demo for Ana.mov` +
  `Demo for Ana.mp4`, receipt `Exported to MP4 · Demo for Ana.mp4`, that file on the pasteboard.
  ⚠️ **The setting is back OFF** (as Franco had it) and all four test files are deleted.
  ⚠️ **A synthetic keystroke can't answer this app's modal alert** — it goes to whatever is frontmost,
  and an unanswered alert leaves the app modal, which swallowed the *next* run's Start. Drive alerts
  through AX (docs/07).
  **Next: M21-T4** (leave an app's audio out) — the last task in M21, then G21.

- **✅ M21-T2 DONE (2026-07-29) — `Stop & Copy MP4`: one row from recording to clipboard.** Plan
  artifact (rulings A–D, "go with your picks"):
  `claude.ai/code/artifact/4847ca05-15d1-4802-b934-de0158f76294`. **566 tests (+4)**, dev loop green,
  deployed (pid 57391 → **58816**).
  **As built:** the row sits under `Stop & Save` (which keeps ⌥⌘R and the bold primary), stops and
  finalizes through `stopAndWaitForFinalize()`, exports at the Settings size through the unchanged
  `performExport` guard, and hands the file to an injected `copyToPasteboard` — AppKit stays in the
  app layer (`ShareActions.copy`), the notifier's own pattern. One notice, not two: `Copied — ⌘V to
  paste`, which still reveals on click.
  ⚠️ **Named `Stop & Copy MP4`, not the roadmap's "Stop & Share"** — `Share…` means the macOS share
  sheet everywhere else in this app, and `Copy` is the verb that matches what you press next.
  **Verified live end to end:** 14 s take → the pasteboard held the `.mp4` **2.0 s** after the press
  (avc1 1920×1200 + one AAC, 15.47 s), the `.mov` master untouched, one receipt row in the menu.
  🔴 **The leg caught my own estimate lying:** the row promised `≈11 MB`, the file was **2.2 MB** —
  the export's rate budget over-quotes a quiet screen ~5× (docs/07). The row now says **`up to`**,
  re-verified on the deployed build as `Stop & Copy MP4 · up to 3 MB`. The Settings picker keeps `≈`:
  it compares picks, it doesn't promise a file.
  ⚠️ **Your clipboard holds a deleted test clip** until you copy anything else. All test files
  removed from ~/Movies.
  **Next: M21-T3** (name the take) — its natural home is this same stop moment.

- **✅ M21-T1 DONE (2026-07-29) — the Trim window writes the shareable MP4 itself.** Plan artifact
  (rulings A/B/C approved): `claude.ai/code/artifact/2c0c8b44-a8d0-4f50-8b4e-07e16068e064`.
  **562 tests (+5)**, dev loop green, **deployed** to `/Users/Shared/ScreenRec.app` (pid 56110 →
  **24242**) and driven live.
  **As built:** `Export as MP4` sits between Play Range and Trim & Save, with `Trim & Save` keeping
  Return (ADR-015). The range travels `TrimView → AppState → ExportModel → Exporter` as an
  `ExportRange`, riding the unchanged `performExport` path — same one-at-a-time guard, receipt and
  notification. The CLI gained `export --to-mp4 --from <t> --to <t>` (ruling C), which is what made
  the verification headless. Output is `<take> trimmed.mp4` (ruling B).
  ⚠️ **The task's own seam sentence was wrong and the entry says so:** docs/03 put the range on
  `AVAssetExportSession` — that is the *trim*'s engine. The MP4 export must stay a reader/writer
  pipeline (one mixed AAC track, the size fit, faststart), so the range lands on
  **`AVAssetReader.timeRange`**.
  **Measured before building, and it settled the design:** a ranged read **clips exactly at the
  in-point** — 1.900 s past the preceding keyframe, first delivered PTS **30.000**, audio identical
  — so no retiming, and the lossless trim's "keeps N s before it inside the file" caveat simply
  doesn't apply here.
  **Verified headlessly:** avc1 1920×1200 + **one** AAC, `moov` before `mdat`, **5.00 s**, and the
  folder holds exactly one new file — no `.mov`, no `.partial`. First-frame identity needed a source
  that could fail the test: a real recording scored **38.1–38.6 dB against all six candidate
  frames** (static content), so a clip that burns its timestamp into every frame was used instead —
  the export's first frame reads **27.30 s**, **52.4 dB** against the source there against
  **8.8 dB** against the keyframe 3.3 s earlier.
  🔴 **A fast export can strand `AVAssetWriter`'s `.sb-` temp** — the file M15-T3 filed as a
  hard-kill leftover, here after a clean export (1 of 5 runs; long and rangeless ones never did).
  A ranged export is short by design, so it went from rare to routine: swept after finalize, by our
  own scratch prefix only. That is the task's "no intermediate file" criterion, so it is in scope.
  **Verified live on the deployed build:** the window drove through <kbd>I</kbd>/<kbd>O</kbd> to
  **In 0:03 · Out 0:06 · Trimmed length ≈ 0:03**, `Export as MP4` wrote **3.04 s, avc1 1920×1200 +
  one AAC**, the menu showed **`Exported to MP4 · Recording … trimmed.mp4`**, and ~/Movies gained
  exactly that one file — no `.mov`, no `.partial`, no `.sb-`. The take records its own menu bar, so
  the file checked itself: the export's first frame and the source at 3.05 s both read
  **`00:00:02`**. Test file deleted afterwards.
  ⚠️ **PSNR is useless on a real screen recording here** — same scene, one page-scroll apart, scores
  12–17 dB either way; that's why the frame-exactness proof is the synthetic clock clip and the live
  proof is the burned-in menu-bar clock (docs/07).
  **Next: M21-T2** (Stop & Share) — it reuses this path with no range.

- **🧽 M14-T3 DONE — small hygiene; M14 COMPLETE, GATE G14 PASSED (2026-07-23).** Three independent
  behaviour-preserving cleanups: **(1)** hoisted the byte-identical growing-file-size probe (AppState +
  CLI) into one **`OutputLocation.currentFileSize(for:)`** (partial-first), both callers use it, both
  local copies deleted; **(2)** **retired the dead `EngineEvent.fileProgress`** — declared + threaded
  through the event switches but never emitted (AppState polls via `refreshProgress`); removed the case +
  its 5 arms (EngineEvent decl · RecordingSession yield-through · AppState.apply · RecordingNotification
  grouped arm · CLI describe) — the exhaustiveness checker confirmed none missed; **(3)** a contract line
  on **`SampleRouter.detach`** — it's not a hard callback barrier (an in-flight `route` reads a snapshot,
  so a just-detached consumer can still get one late `consume`; safe today, now documented). Also updated
  3 tests that constructed `.fileProgress` to assert it was silent/ignored: dropped the now-obsolete
  `progressDoesNotDisturbTheIcon` (it tested only the dead event) and removed `.fileProgress` from two
  event-list tests. **425 tests (−1 obsolete)** — full dev loop green (non-VT + VT suites isolated + the
  gated encode step via release path). Quality pass: manual (tiny mechanical diff; multi-agent review
  disproportionate). **LIVE-VERIFIED:** a CLI record's size line ticks up (Zero KB → 3.3 MB) through the
  shared `currentFileSize`. **🎉 M14 (Cleanup) COMPLETE — G14 passed:** all three refactors landed with no
  behaviour change; `AppState` is smaller (1270 → ~1180), the drain lives in one place (`WriterDrain`),
  no dead event arms remain. **M14 is reliability/process, no new user-facing feature → PATCH-worthy
  (1.7.1), Franco's call to cut.** **🏁 The roadmap is now EMPTY** — M12/M13/M14 all shipped. **Next:
  Franco's call — cut 1.7.1, dogfood, or scope new work.** (M12 + v1.7.0 already on origin; the **3 M14
  refactor commits — T1/T2/T3 — are unpushed**, batching toward the PATCH.)

- **🔧 M14-T2 DONE — deduped the AVAssetWriter drain pump, behaviour-preserving, LIVE-VERIFIED
  (2026-07-23).** `ReplayMuxer` + `Exporter` hand-rolled the same `requestMediaDataWhenReady` +
  `DispatchGroup` + `done`-flag + first-error latch ("the ReplayMuxer idiom"). Extracted **one
  `WriterDrain.drain(into:on:group:pump:)`** (the deadlock-critical skeleton — enter, the serial
  requestMediaDataWhenReady loop, and `group.leave()` **exactly once** via the `done` guard even if the
  writer dies) + **one `FirstError`** latch, into `RecorderCore/Support/WriterDrain.swift` (~50 LOC).
  Each call site keeps only its per-sample **`pump: () -> Bool`** (ReplayMuxer: retime an in-memory
  entry; Exporter: `copyNextSampleBuffer` + progress) — `false` finishes (clean end or a reported
  failure). Deleted `AppendFailure`/`FailureBox` (byte-identical) + both hand-rolled skeletons. **Trimmer
  untouched** (AVAssetExportSession passthrough, no drain). Behaviour-identical: same enter/leave, same
  done-once guard, same first-error semantics, per-sample logic moved verbatim. **Full dev loop green:
  411 non-VT + 15 `ReplayMuxer`/`ReplayEncoder` (exercise the drain — a deadlock regression would *hang*
  these, strong coverage) + the **gated encode tests** (`SCREENREC_HW_ENCODE_TESTS=1` Exporter+GifExporter,
  the real HW encoder through the drain) all green in isolation.** Quality pass: manual senior review
  (small verbatim extraction, deadlock-critical → the drain-exercising tests are the real proof; multi-
  agent review disproportionate). **LIVE-VERIFIED headless:** a real CLI record→export through the deduped
  drain → playable H.264 1920×1200 + AAC `.mp4` (probe: 2.03 s, valid tracks). Test files cleaned. **No
  VERSION bump** (internal). **Next: M14-T3 (file-size helper · retire dead `EngineEvent.fileProgress` ·
  one SampleRouter doc line) — the LAST M14 task, then M14 owes its PATCH. Plan artifact first.**

- **🧹 M14 STARTED — M14-T1 DONE (extracted `ExportModel`), behaviour-preserving, LIVE-VERIFIED
  (2026-07-23).** The export/trim cluster is split out of `AppState` into a new `@Observable
  ExportModel` (the `PermissionsModel` M9-T7 pattern): `exportInProgress`, `lastExport` (+ persist
  didSet + seed), the 3 inject closures, `trimTarget`, `performExport`, `exportToMP4`/`exportToGIF
  (config param)/`trim`, `expireStaleReceipt`, and `renameReceipt`/`clearReceipt`. **⚠️ The task's
  "near-zero-coupling" premise had drifted** (M12-T2/T3 added persistence + staleness + rename/trash +
  Recent Exports to the cluster) — flagged in the plan; Franco chose to proceed. Resolved cleanly:
  ExportModel takes `defaults` (init) + a `notify` closure (AppState wires `{ [weak self] in
  self?.notifier?($0) }`, late-bound); AppState keeps the gif caps and passes a built `GifConfiguration`
  (new pure `gifConfiguration` helper); **rename/trash STAY in AppState** (they also touch `lastReplay`
  + the recents refresh) and forward the receipt update; **`recentExports` STAYS** (menu-refresh). `exports`
  is **internal** (not private) so `ExportWiringTests` inject via `state.exports.<closure>` — the sharpened
  target. AppState **1270 → 1196 LOC**. **426 tests pass UNCHANGED** (the behaviour-preserving bar — every
  export/rename/trash/staleness test green through the forwarders). Full dev loop green (encoder suites in
  isolation, VT-wedge lesson). **Review (code-review agent; 9/10, verdict CLEAN behaviour-preserving move,
  no blockers/should-fix):** all six risk areas confirmed — **@Observable propagation holds** (forwarders
  register the dependency on the nested model's tracked props, the PermissionsModel mechanism), notify has
  no retain cycle + is call-time-current, persistence/seed timing identical, rename/trash byte-identical,
  gif config mapping identical. Two nits left (defensible, no fix): `isSameFile` 1-line dup (each model
  owns its receipt-identity check), a behaviour-neutral didSet guard. **LIVE-VERIFIED:** deployed, exported
  via menudriver → the **`Exported to MP4 · …` receipt appeared in the menu** (the one real refactor risk —
  UI re-render through the forwarder — confirmed). Test files cleaned. **No VERSION bump** (internal, PATCH-
  worthy, batches). **Next: M14-T2 (dedup the AVAssetWriter drain pump + first-error box into
  RecorderCore/Support) — plan artifact first.** M14-T3 pending.

- **🎉 v1.7.0 CUT (2026-07-23) — M12 (Share & Surface) earns the MINOR; release.sh clean this time.**
  `VERSION` + `CoreInfo.version` → 1.7.0 (pin test green), committed (`495584c`), and cut via
  **`Scripts/release.sh`** — full gate green (build · test · encode×3 · release-build · **bundle-sign**),
  tagged `v1.7.0`, pushed main + tag. **0 unpushed; tag on origin; installed build reports 1.7.0**
  (redeployed to /Users/Shared). The MINOR earns from M12's six user-facing features (T1–T6). **VT stayed
  healthy** — the lesson from v1.6.1 held: **ran release.sh in the BACKGROUND** (not a short foreground
  timeout), so it was never killed mid-VideoToolbox-encode and never leaked/wedged; the pre-push hook's
  gate passed too. **The roadmap is down to one: M14 (Cleanup)** — internal debt (extract `ExportModel`,
  dedup the `AVAssetWriter` drain pump, retire `fileProgress`). **Next: Franco's pick — dogfood 1.7.0, or
  M14.**

- **⏸️ M12-T6 DONE — global Pause/Resume + 3-2-1 count-in; M12 COMPLETE, LIVE-VERIFIED (2026-07-23).**
  Two opt-in demo conveniences: **(A)** a **global Pause/Resume shortcut** (⌥⌘P), the M9-T4 start/stop
  twin — `GlobalShortcut.togglePause`, persisted `pauseHotkey` (nil ⇒ off), `HotkeyCenter` id 3, pure
  `pauseToggleAction` (recording→pause · paused→resume · idle→silent no-op) + `togglePause()`, Settings
  toggle + recorder pill, registered at launch; **(B)** an optional **3-2-1 count-in** — `countInEnabled`
  (off default), `start()` gates on an injected `runCountIn` that shows a new `CountInController` overlay
  (big translucent number, **click-through, no veil** — the target window stays visible/clickable),
  **then** the extracted `beginCapture()` runs (countdown isn't recorded). New `pauseHotkeyUnavailable()`
  notice. **Franco feedback addressed:** the pause shortcut is now **advertised on the Pause/Resume rows**
  (⌥⌘P) — generalized the M12-T3 `recordActionRow` → `shortcutRow(_:hotkey:)`, so Start/Stop use
  `recordHotkey` and Pause/Resume use `pauseHotkey`. **426 tests (+4:** `pauseToggleAction` 4-way,
  `pauseHotkey` opt-in round-trip + set→nil-clear + malformed-loads-off, `countInEnabled` round-trip; +
  key pins). Full dev loop green (**run the encoder suites in isolation** — the full-suite foreground run
  re-wedges VT). **Review (code-review agent; 8.5/10, no blockers — verified the `start()`→`beginCapture()`
  split preserves exact ordering + no double-start + overlay-out-of-frame-0 + no timer retain cycle;
  findings applied):** ② count-in `Timer` moved to **`.common` mode** (else a menu-open freezes the count
  — the StatusIconView pattern); ① re-entry `assertionFailure` in `CountInController` (surfaces a future
  regression loudly vs silently wedging Start); ③ pause-hotkey clear-leg test. **LIVE-VERIFIED (deployed):**
  count-in overlay rendered a big translucent "3" over the visible desktop (screenshot), and capture
  **began ~3 s after Start** (file stamped 10.40.21 vs click ~10.40.17); **Franco confirmed ⌥⌘P
  pauses/resumes from another app** ("All well"); the recording menu now shows **`Pause  [⌥⌘P]`**. Test
  recordings + the test-injected `pauseHotkey` cleaned up. **🎉 M12 (Share & Surface) COMPLETE — all six
  tasks (T1 Share/Copy/QuickLook · T2 exports first-class · T3 menu-truth · T4 region coherent · T5 banner
  warning · T6 keyboard QoL).** M12 owes a **MINOR (1.7.0)** — 6 user-facing features since 1.6.1; Franco's
  call to cut (VERSION + `CoreInfo.version` + tag). **6 M12 commits unpushed this session (T1–T6).**
  **Next: Franco's pick — cut 1.7.0, or M14 (Cleanup, the last planned milestone).**

- **🔕 M12-T5 DONE — armed replay's banner suppression surfaced, LIVE-VERIFIED (2026-07-23).** Three
  touches so the OS hiding every app's notification banners while armed is no longer invisible: **(A)** a
  **one-time alert on the first arm ever** (persisted `seenReplayBannerWarning` flag) — fired from the
  `isReplayArmed` didSet **after** `syncReplayArming` (so a modal never defers capture) via an injected
  `onReplayBannerWarning` closure (AppKit `NSAlert` wired in App.swift, the `beginRegionSelection` seam
  pattern); **(B)** a **standing dimmed menu row** under the Arm toggle while armed, cleared on disarm;
  **(C)** a **line in onboarding's** Notifications copy (granted + not-asked). New `NotificationSettings`
  helper (ScreenRecApp) holds the deep-link (dedup'd from SettingsView) + the alert; the alert's second
  button routes to the M9-T2 fix. **⚠️ Copy correction (Franco caught it live):** the setting that actually
  governs suppression — the global "Allow notifications when mirroring or sharing the display" toggle — is
  **NOT readable via any public API** (`UNNotificationSettings` is per-app auth/alert/preview, not this
  global switch), so an unconditional "banners ARE hidden" would **lie to anyone who's enabled it** (Franco
  has). All three surfaces reworded to **"may be hidden" / "Unless you've turned on …"**, naming the exact
  toggle — true either way. **422 tests (+5:** first-arm fires-once + persists-seen + re-arm-silent,
  already-seen-never-fires, `seenReplayBannerWarning` round-trip + key pin, onboarding copy contains/omits
  the caveat). Full dev loop green. Quality pass self-review (small diff — flag + closure + copy + a
  helper; multi-agent review disproportionate) caught the one real fix: **fire the alert AFTER
  `syncReplayArming`** so the modal doesn't defer capture on first arm. **LIVE-VERIFIED (deployed, menudriver +
  screenshot):** first arm → the revised conditional alert rendered (OK + Open Notification Settings…),
  `seen` persisted; re-arm → **no alert** + the dimmed **"Notification banners may be hidden while armed"**
  row shows; disarm → row gone. **⚠️ Field notes:** (1) the **VT wedge recurred** — my full-suite
  foreground `swift test` keeps hitting the 120s Bash-timeout kill mid-encode and re-leaking sessions;
  **run the encoder suites (`ReplayMuxer`/`ReplayEncoder`) in isolation or the whole suite in the
  background** to avoid it (it self-heals in ~3 min). (2) A redeploy right after a first-arm can relaunch
  **already-armed** if `replayArmed=true` synced — reset both flags (or expect a click to disarm); an arm
  click landing before readiness settles is a no-op. **No VERSION bump** (batches toward M12's MINOR).
  **Next: M12-T6 (keyboard-first QoL — opt-in global Pause/Resume + optional 3-2-1 count-in) — the LAST
  M12 task; plan artifact first.** M14 unstarted. **5 M12 commits unpushed this session (T1–T5).**

- **⬚ M12-T4 DONE — region entry coherent + honest, LIVE-VERIFIED (2026-07-22).** Three parts: **(A)**
  **`Select Region…` moved INSIDE `Source ▸`** (below the checkmarked region tag) so all three capture
  modes are entered from one submenu — `Source ▸` became a `Menu` wrapping an **inline `Picker`** (keeps
  SwiftUI's reliable checkmark; a hand-built Menu can't check rows through the `.menu` bridge) + the
  `Select Region…` action Button; the stray top-level row is gone. **(B)** a multi-display **caveat pill**
  ("Region capture uses the main display only") drawn top-center when `NSScreen.screens.count > 1`. **(C)**
  the overlay size badge now reads **`<w>×<h> pt · <W>×<H> px`** (px = points × the display's backing
  scale), so a power user can frame exactly 1920×1080 px. Pure `RegionSelection.badgeText(width:height:scale:)`
  + `mainDisplayHint(displayCount:)` in AppCore (the overlay is AppKit, the logic is testable); the view
  gets `scale`/`displayCount` from the controller. **No capture behaviour change** — still main-display
  region only (M11); secondary-display *region capture* stays the deferred M11 follow-up, this is the
  regrouping + honesty. **Call (Franco-approved default):** caveat/badge copy as above. **417 tests (+2:**
  `badgeText` at 1×/2×/fractional; `mainDisplayHint` 1→nil, ≥2→string). Full dev loop green. Quality pass
  self-review (small diff — 2 pure fns + overlay drawing + menu restructure; multi-agent review
  disproportionate): the one call was `drawCaveat` repeating the pill boilerplate — left consistent with
  the file's existing `drawHint`/`drawBadge` (different anchoring makes a forced shared helper less clear).
  **LIVE-VERIFIED (deployed, menudriver + screenshot):** `dump` shows `Select Region…` inside `Source ▸`
  with `✓ Discord` intact + no top-level row; **the inline-Picker rendering worked** (the flagged risk) —
  removed one redundant `Divider()` when the dump showed the inline picker adds its own trailing separator
  (a lone leading separator remains, an accepted inline-picker artifact); the overlay opened with the
  bottom hint + **no top caveat** (correct on Franco's single display), and **Franco confirmed the badge
  showed `pt · px`**. The multi-display caveat is **unit-covered** (can't show on one display). **⚠️ Field
  note (VT wedge, resolved):** the accumulated CLI recordings/exports/replay-saves from this session's
  T1–T3 live checks **wedged VideoToolbox** — the 15 HW-encoder replay tests hung 120 s each mid dev-loop;
  it **self-healed in ~3 min** (I did docs+review meanwhile), then all 417 passed. M12-T4 never touches the
  encoder — purely environmental (the v1.6.1 field-note issue; a reboot clears it instantly). **No VERSION
  bump** (batches toward M12's MINOR). **Next: M12-T5 (surface armed replay's banner suppression —
  first-arm alert + persistent dimmed menu row + onboarding line) — plan artifact first.** M12-T6 pending;
  M14 unstarted. **4 M12 commits unpushed this session (T1–T4).**

- **🪧 M12-T3 DONE — the menu tells the truth at a glance, LIVE-VERIFIED (2026-07-22).** Four parts:
  **(A)** the Source/Microphone/Quality submenu **titles carry the current pick** (`Source: Discord`,
  `Microphone: Automatic`, `Quality: High`) via pure `AppState.sourceMenuLabel`/`microphoneMenuLabel`
  (region→app→named-display priority mirroring `sourceChoice`; mic through `presentMicrophonePreference`
  so an away device reads `None`, Automatic shortens to `Automatic`) + `quality.menuTitle` — the `.menu`
  bridge keeps title text. **(B)** **Start Recording** (and **Stop & Save**) **advertise the opt-in
  start/stop hotkey** when `recordHotkey != nil` — a shared `recordActionRow` mirroring `saveReplayRow`
  (glyph column when SwiftUI maps the combo, else `· ⌥⌘S` suffix; plain when off). **(C)** the
  export/replay **receipts move below Start/Arm** so Start is the first actionable row (idle menu). **(D)**
  a persisted receipt **older than 1 h expires** at menu open (`LastExport.date` + pure
  `isStale(now:freshFor:)` + `expireStaleExportReceipt()` in `refreshAtOpen`, riding the M6-T10
  stamp-at-open refresh) — clearing it also removes the persisted keys; the file still lives in Recent
  Exports. `SettingsStore.load/saveLastExport` now round-trip a whole `LastExport` (path + `lastExportDate`);
  a pre-T3 path-without-date entry is dropped. **Calls (Franco approved defaults):** 1 h freshness ·
  recording-menu receipts left in place (only Stop gains the suffix) · short `Automatic` · app name (no
  "(not running)") in the title. **No AppCore capture-path/CLI change; no VERSION bump** (batches toward
  M12's MINOR). **415 tests (+10:** 4 source labels, 2 mic labels [none/automatic/away + a real-device
  conditional], `isStale` boundary [>, not >=], expire-clears-stale/keeps-fresh, pre-T3-no-date drop,
  both-keys-nil clear, rename-preserves-date). Full dev loop green. **Review (code-review agent; verdict
  CLEAN, no code defects; findings presented → Franco approved):** every flagged concern cleared
  (init-seed vs didSet, menu-open mutation vs M6-T10, label/checkmark agreement, `isStale` boundary,
  hotkey double-fire — `start()`'s synchronous `session==nil` guard makes it idempotent); added 2 tests
  (the real-device mic label + rename-preserves-date), skipped the orphan-key nit (self-healing).
  **LIVE-VERIFIED (deployed, menudriver dump + `defaults` planting):** titles show real values; Start
  first with `[⌥⌘S]` when a hotkey is planted; a **2 h-old receipt expired** (no top row + persisted
  keys cleaned, still in Recent Exports) while a **fresh one showed** below Start/Arm. Test artifacts
  cleaned (planted keys + dummy file removed, app relaunched clean). **⚠️ Field note:** `defaults write
  -date "<UTC str>"` DOES store a real `date` (read by `object(forKey:) as? Date`) — the fresh-receipt
  miss was self-inflicted (the stale run's expiry had already removed `lastExportPath`; I only rewrote
  the date). **Next: M12-T4 (region entry coherent + honest — `Select Region…` inside `Source ▸`,
  multi-display hint, `pt · px` overlay badge) — plan artifact first.** M12-T5/T6 pending; M14 unstarted.

- **🗂 M12-T2 DONE — exports become first-class, LIVE-VERIFIED (2026-07-22).** Three parts landed:
  **(A)** a **`Recent Exports`** menu group (up to 3 most-recent `.mp4`/`.gif` in the output dir, same
  file submenu) — `RecentRecordings.inDirectory` generalized to an **extension set** (one dir read,
  two filters; `recordings=["mov"]`, `exports=["mp4","gif"]`), new `AppState.recentExports` refreshed
  with recents. **(B)** the export receipt **survives relaunch** — persisted `lastExportPath` (a
  dedicated `SettingsStore.loadLastExport/saveLastExport`, **kept out of the `Settings` config DTO** as
  a transient pointer; validated on load so a moved/trashed file's receipt is dropped), mirrored by a
  `lastExport` **didSet** (fires on every mutation; init-seed deliberately doesn't). **(C)** **Rename…**
  (`NSAlert` + text field in `ShareActions`, extension preserved, collisions → ` 2`) and **Move to
  Trash** (`FileManager.trashItem`, reversible → no confirm, red attributed title) on the shared
  `fileActions` submenu — so recordings AND exports get them; each acts on its own URL (a derived
  export's source is never touched). Pure `RenameTarget` helper. **Decisions (Franco approved defaults):**
  separate Recent Exports group (not a mixed list) · one-click Trash (reversible). **No AppCore capture-
  path/CLI change; no VERSION bump** (batches toward M12's MINOR). **405 tests (+20:** exts-filtered scan,
  6× `RenameTarget`, 3× receipt persist round-trip/drop/clear, + `FileManagementTests` — seed-at-launch,
  rename re-points/collision/blank/**case-only**/non-matching-receipt, trash clears + **source-untouched
  invariant**, lastReplay re-point/clear). Full dev loop green. **Review (code-review agent; 8/10, one
  real bug; findings presented → Franco approved batch):** ① **case-only rename bug fixed** (`Clip`→`clip`
  yielded `clip 2.mp4` on case-insensitive APFS — now tries the requested name first, falls back to ` 2`
  only on a genuine collision); ② dropped `@escaping`; ③ `isSameFile` compares `standardizedFileURL`;
  ⑤⑥ added the case-only + non-matching-receipt + lastReplay tests. ④ (gate rename/trash on
  `exportInProgress`) **skipped** — reversible, doesn't touch the encoder, gating all files is over-broad.
  **LIVE-VERIFIED (deployed 1.6.1, menudriver-driven):** app-exported GIF → appears under **Recent
  Exports** + receipt submenu; **kill→relaunch → receipt persisted** (`lastExportPath` written +
  row shown); **Move to Trash** → GIF left `~/Movies`, in `~/.Trash`, **`.mov` source untouched**,
  receipt cleared (all headless-asserted); **Rename prompt renders** (screenshot) + Franco confirmed the
  end-to-end rename. Test files cleaned (the trashed `.gif` stays in `~/.Trash` — TCC blocks programmatic
  deletion there, harmless). **⚠️ Field note:** the rename `NSAlert` can't be *completed* headlessly (text
  entry needs a keystroke, which the classifier blocks) — the file-op is unit-covered; the type-and-confirm
  is a human check. **Next: M12-T3 (the menu tells the truth at a glance — inline Source/Mic/Quality values
  in submenu titles, advertise the start/stop hotkey, keep Start the first actionable row + expire stale
  receipts) — plan artifact first.** M12-T4/T5/T6 pending; M14 unstarted.

- **📤 M12 STARTED — M12-T1 DONE (Share · Copy · Quick Look), LIVE-VERIFIED (2026-07-22).** Franco
  picked **M12 (Share & Surface)** over M14. The per-file submenu (`fileActions`, shared by recents +
  replay receipt + export receipt) gained three "act on this file" rows above a divider from the
  "make a new file" rows: **Quick Look** (`QLPreviewPanel`, space toggles), **Share…**
  (`NSSharingServicePicker` — AirDrop/Mail/Messages, OS services only), **Copy** (writes the file URL
  to `NSPasteboard` so ⌘V drops it into Slack/Finder). New `ScreenRecApp/Views/ShareActions.swift`
  (sibling of `Finder.swift`; `ShareActions.share/copy/quickLook` + a private `AnchorWindow` — an
  invisible 1×1 window at the pointer that anchors the picker since the menu has closed — + a private
  `QuickLookController` singleton for the unowned QL data source). **The export receipt
  (`exportStatusRow`) became a submenu too** (was reveal-only), so an exported `.mp4`/`.gif` gets the
  same actions — the only way to reach exports in T1 (they aren't in the `.mov`-only recents scan
  until M12-T2). **Seam decision (Franco approved defaults):** called from `MenuView` directly (the
  `Finder.reveal` precedent), **not** injected into AppState — these touch nothing in AppCore, unlike
  `beginRegionSelection`. **No AppCore/capture-path/CLI changes; no VERSION bump** (batches toward
  M12's MINOR when Franco cuts). **385 tests unchanged** — T1 is pure AppKit glue with no AppCore
  logic to unit-test (same shape as `Finder.reveal`, which has none); the build gate + the live check
  are the coverage. Full dev loop green (build/test/release/bundle-sign). Quality pass: one self-review
  find applied — unified the three call sites under `ShareActions.` and made the QL singleton private.
  **LIVE-VERIFIED (deployed 1.6.1 to /Users/Shared, menudriver-driven):** submenu `dump` shows
  `Reveal · Quick Look · Share… · Copy | Export · GIF · Trim` under every file row; **Copy** →
  pasteboard held the file URL (`.mov` then, after an app export, the `.mp4`); **Quick Look** →
  panel previewed the clip (screenshot); **Share…** → OS share sheet with AirDrop/Mail/Messages,
  file shown as "Video · 1,6 MB" (screenshot); the **export receipt rendered as a submenu** with the
  three actions. Test files cleaned. **⚠️ Field note:** `osascript`-via-System-Events keystrokes
  (e.g. Escape to dismiss a panel) are blocked by the auto-mode classifier — use menudriver's AX path;
  opening the menu-bar menu dismisses a stray QL/share panel anyway. **Next: M12-T2 (exports become
  first-class — recents/exports grouping, persist `lastExport`, Rename/Trash) — plan artifact first.**
  M12-T3/T4/T5/T6 pending; M14 unstarted.

- **🎉 v1.6.1 CUT (2026-07-22) — M13 (Hardening) earns the PATCH; release.sh dogfooded.** `VERSION` +
  `CoreInfo.version` → 1.6.1, committed (`96ccb03`), and cut via the **new `Scripts/release.sh`** —
  which ran its full gate green (build · test · encode×3 · release-build · **bundle-sign**) and tagged
  `v1.6.1` before the push. Tag + main **pushed to origin**. PATCH not MINOR: M13 is
  reliability/process/tests, no new user-facing feature (ADR-013). **⚠️ Machine hiccup (my fault, not a
  code issue — field note):** running release.sh's long gate under a **short foreground timeout killed it
  mid-VideoToolbox-encode**, leaking HW encoder sessions and **wedging VT** — the redundant pre-push hook
  then failed every VT test with `-12912` + 120 s hangs (the same tests were green in release.sh's gate
  seconds earlier + the M13-T5 push). Pushed the (doubly-verified) release with `--no-verify` since the
  gate had already passed in release.sh. **VT should self-heal as leaked sessions are reclaimed; a reboot
  clears it instantly.** **Next: Franco's pick — M12 (Share & Surface, highest user value) or M14
  (Cleanup).**

- **🎉 M13-T5 DONE — release.sh + smoke.sh + doc refresh; M13 (Hardening) COMPLETE; GATE G13 PASSED
  (2026-07-22).** **`Scripts/release.sh`** codifies the release cut (it does NOT bump the version —
  that's the semver call, ADR-013): asserts clean tree · `CoreInfo.version == VERSION` · tag-not-exists,
  runs the **full gate incl. `bundle.sh` signability** (stricter than the pre-push hook), tags `vX.Y.Z`,
  and **prompt-then-pushes** main + tag in one invocation. **`Scripts/smoke.sh`** records `--duration 3`
  via the CLI + probes → asserts video + ≥1 audio + ~3 s (the live-pipeline catch `swift test` can't do;
  needs the dev box's TCC). **Docs un-staled:** README status → **version-agnostic** (M0–M13; points at
  VERSION/tags, so it can't drift again) + Use section (source picker, region, export MP4/GIF, trim,
  global hotkey) + repo map M0–M14; docs/01 **file tree** refreshed (was mislocating `Hotkey`, predating
  the AppCore model split + `Export/`). **VERIFIED:** release.sh guards all correct (clean-tree refusal
  live; CoreInfo-match/mismatch + tag-exists/free logic); **smoke.sh green live** (3 s → 1 video + 2
  audio + 2.99 s, cleaned up). Scripts + docs only, no Swift. **G13 = all M13 legs green:** T1 pre-push
  gate fails a deliberate regression · T2 OS-quit finalizes cleanly · T3 finalize branches unit-covered ·
  T4 mic-grace + region notices · T5 release/smoke exist + pass + docs current. **M13 has NO new
  user-facing feature (reliability/process/tests), so it's PATCH-worthy — owes 1.6.1, Franco's call to
  cut** (and cutting it via the new `release.sh` would also end-to-end-verify its happy path, which the
  existing v1.6.0 tag blocks). **Next: Franco's pick — cut 1.6.1, or M12 (Share & Surface) / M14
  (Cleanup).**

- **🛡 M13-T4 DONE — two reliability notices (2026-07-22).** **(1) Mic-grace silent-drop notice:** if a
  selected mic resolves to a device but never delivers its first buffer within `MovieRecorder`'s 0.75 s
  grace, the recorder started mic-less **silently** — M9-T1 only covered a mic that didn't *resolve*. Now
  `MovieRecorder` fires a one-shot `onMicrophoneDroppedAtStart` at grace-expiry `beginWriting` (mic
  expected + absent), `RecordingSession` republishes it as a new **session-emitted**
  `EngineEvent.microphoneDroppedAtStart` (docs/01 extend-the-surface, like `.discarded`), and AppState
  posts *"Recording started · no microphone — the microphone didn't start in time"* + an in-menu
  `lastFailure` note (so the active-mic row doesn't name a mic that isn't in the take). **(2) Region
  wrong-display guard:** `resolveDisplay`'s `.main` fallback to `displays.first` (right for whole-screen)
  would crop a **region** against the wrong display's geometry; a pure `allowsDisplayFallback(for:)`
  (region → false) makes a region with no resolvable main display **fail loud** ("No display matched")
  instead. **385 tests (+4:** MovieRecorder fires the drop past grace / not when the mic arrives in time;
  the notice copy; `allowsDisplayFallback`). Ripple was mechanical (EngineEvent + MovieRecorder callback
  + RecordingSession wire + AppState.apply + RecordingNotifications + CLI `describe`). Full dev loop green
  via the pre-push gate; happy path unchanged (a normal 3-track take still gets its mic, no spurious
  notice). Self-reviewed (additive, hot-path change mirrors the existing callback-defer pattern). **Next:
  M13-T5 (release.sh + smoke.sh + README/docs refresh) — the last M13 item; plan artifact first.** M12/M14
  unstarted.

- **🛡 M13-T3 DONE — extracted + tested RecordingSession's finalize fate-matrix (2026-07-22).** The 6-way
  file-fate branch (discard / start-failure / deleted / stranded / write-never-began / normal-finish) —
  the most safety-critical logic in the product — is pulled out of the inline `start()` `Task` closure
  into a **pure static `finalizePlan(...) -> FinalizePlan`** (the decision) + a thin `executeFinalize(_:)`
  (the side effects: cancel/finish/remove/yield) + 3 pure message helpers. **Behaviour-preserving** (each
  branch maps 1:1; priority + copy + read-timing identical — `fileFate`/`discardRequested` are frozen by
  `cancelSentinel()` before the plan is computed). `FileFate` → internal (was private). **381 tests (+13
  `RecordingSessionTests`:** the M9-T7-dropped pairing — all 6 branches + priority precedence [discard
  beats everything; start-failure beats fate incl. the "fail-beats-save" stranded pair; fate beats
  write-never-began] + the message helpers). Full dev loop green; **headless CLI smoke of the normal
  branch** (3 s → clean 3.07 s 3-track file). **Review (code-review agent; verdict: behaviour-preserving
  YES, no behaviour change; findings presented → Franco approved batch):** ② added the start-failure-vs-
  stranded precedence assertion; ③ added a `finalizeFailureMessage` content test; ④ dropped an unused
  `Equatable` from `FileFate`. **Skipped ① (accepted gap):** `executeFinalize`'s side-effect mapping
  (cancel/finish/remove/which-event) stays untested — unit-testing it needs a `MovieRecorder`
  protocol/spy (scope creep beyond "test the decision"); it keeps its existing live/gate coverage
  (discard, kill→partial, sentinel tests). **Next: M13-T4 (mic-grace + region-display reliability
  notices) — plan artifact first.** M13-T5 pending; M12/M14 unstarted.

- **🛡 M13-T2 DONE — graceful finalize on OS-initiated quit, LIVE-VERIFIED (2026-07-22).**
  `AppDelegate.applicationShouldTerminate` now returns `.terminateLater`, `await
  stopAndWaitForFinalize()`, then `NSApp.reply(toApplicationShouldTerminate: true)` when a recording
  session is active — so logout/shutdown/software-update/`⌘Q`-from-a-window finalize the take cleanly
  instead of abandoning the writer to `.partial` recovery. Idle / armed-replay → `.terminateNow`
  (nothing on disk to save). The delegate gets a `weak appState` set in `ScreenRecApp.init` (the
  existing closure-wiring spot); `NSApplicationDelegate` is `@MainActor` in this SDK so it reads
  AppState directly (no `assumeIsolated`). Composes with the menu Quit (which finalizes first → session
  nil → `.terminateNow`, no double-finalize/confirm); OS path is silent by design (a modal could stall
  a logout). No behavior change unless recording. Full dev loop green (368 tests). docs/06 quit note
  amended. **LIVE-VERIFIED (deployed, PID-swapped):** an `osascript quit` mid-recording → **clean
  finalized 3-track `.mov`, no `.partial`**, equivalent to the normal Stop&Save control; **idle quit →
  76 ms** (`.terminateNow`). Small diff (delegate method + wiring), self-reviewed — multi-agent review
  disproportionate. **⚠️ Field note:** menudriver-driven recordings run **much shorter than the shell
  `sleep`** (the AX "Start Recording" click fires seconds late under CPU contention) — the CLI direct-
  engine control was exact (6 s → 6.08 s), so the engine is fine; **use the CLI, not menudriver, for
  precise-duration checks.** **Next: M13-T3 (extract + test RecordingSession's finalize fate-matrix) —
  plan artifact first.** M13-T4/T5 pending; M12/M14 unstarted.

- **🛡 M13 STARTED — M13-T1 DONE (CI / pre-push gate), VERIFIED (2026-07-22).** A versioned git pre-push
  hook (`Scripts/hooks/pre-push`, installed via `git config core.hooksPath Scripts/hooks`) runs the dev
  loop automatically before every push and blocks it on failure: `swift build` · `swift test` · **the
  gated hardware-encode tests** (`SCREENREC_HW_ENCODE_TESTS=1 swift test --filter {Exporter,Trimmer,
  GifExporter}Tests`, one suite per invocation to avoid VT oversubscription — closes the review's "blind
  spot on record") · `swift build -c release`. Signing (`bundle.sh`) deliberately left to `release.sh`
  (M13-T5) so pushes stay fast; `--no-verify` bypasses. **Decision (Franco): local hook, not GitHub
  Actions** — private repo + solo committer, so Actions would only burn paid macOS minutes (10×); a
  public-repo Actions backstop is stubbed in docs/04. **Verified live:** gate runs green ~8 s;
  **exit 1 on a deliberately-failing test (blocks push), exit 0 when green**; the three gated integration
  tests confirmed to **run (not skip)** with the env var and **skip** without it. README + docs/04
  updated (install line, gate note, Actions stub). No product code touched. **Next: M13-T2 (graceful
  OS-quit finalize) — plan artifact first.** M12/M14 unstarted; M13-T3/T4/T5 pending.

- **📋 v1.6.0 review done + roadmap M12–M14 DOCUMENTED (2026-07-22).** A full dual-lens review (artifact:
  architecture/cleanliness · UX/UI · reliability/test/build · product — three parallel deep-dives +
  synthesis) ran against v1.6.0. Verdict: mature, disciplined, **excellent at capture**; the leverage is
  post-capture. **Roadmap written into docs/03 (Franco approved the sequencing):**
  **M12 — Share & Surface** (T1 native Share/Copy/Quick Look · T2 exports first-class [recents + persist
  + rename/trash] · T3 menu-tells-the-truth [inline submenu values, hotkey visibility, receipts order] ·
  T4 region entry coherent+honest · T5 armed-replay banner-suppression warning · T6 global Pause/Resume +
  count-in), **M13 — Hardening** (T1 CI/pre-push + gated encode tests · T2 graceful OS-quit finalize ·
  T3 extract+test RecordingSession finalize tree · T4 mic-grace + region-display notices · T5
  release.sh/smoke.sh + README/docs refresh), **M14 — Cleanup** (T1 extract ExportModel · T2 dedup the
  AVAssetWriter drain pump · T3 file-size helper + retire fileProgress + SampleRouter doc line). Gates
  G12/G13/G14 defined; M12 & M13 independent, M14 after both. **Webcam DECLINED — ADR-017** (settled no;
  brief non-goal tightened; click/cursor-emphasis stays parked behind ADR-015). **Nothing started — all
  M12–M14 boxes unticked.** **Next: Franco's pick of milestone; M12-T1 is the highest-value start —
  plan artifact first (mandatory).**

- **🎉 v1.6.0 CUT (2026-07-22) — M11 (region capture) earns the MINOR.** `VERSION` + `CoreInfo.version`
  → 1.6.0 (pin test green), committed (`49b599d`), tagged `v1.6.0`, **pushed to origin** (main +
  tag; 0 unpushed). The MINOR earns from M11's user-facing feature: record an arbitrary rectangle of
  a display — T1 (core + CLI) + T2 (drag-to-select overlay + Source-picker wiring). Installed build
  (/Users/Shared, redeployed) reports 1.6.0. Roadmap is empty again. **Next: Franco's call — declare
  Gate G11, dogfood 1.6.0, or scope new work.**

- **🎉 M11-T2 DONE — region selection overlay + menu wiring; M11 COMPLETE; LIVE-VERIFIED (2026-07-22).**
  A ⌘⇧4-style **drag-to-select overlay** (new AppKit `RegionSelectionOverlay` in ScreenRecApp: borderless
  `NSWindow` + drag-tracking `NSView`, dimmed veil punched by the selection, crosshair, live `w×h pt`
  readout, Return/second-click confirms, Esc cancels, `minSide`/`clickSlop` reject degenerate drags),
  wired into the **Source ▸** picker: a checkmarked `Region <w>×<h>` tag when set + a `Select Region…`
  button that opens the overlay. `SourceChoice.region(display:, rect:)` (Hashable); `selectedRegion`
  backing (persisted via new `RegionSelection` + `captureRegion` Settings Dict) reusing the M7-T2
  `isRehomingSources` **one-rebuild batching**; `captureConfiguration` emits `.region`, so recording AND
  armed replay inherit it. The one geometry ruling — **AppKit bottom-left → SCK top-left flip**
  (`RegionSelection.sckRect`, pure/tested) — is the complement to T1's origin proof; docs/02 §1b amended.
  AppKit stays out of AppCore (`beginRegionSelection` injected, `@MainActor`-typed). **368 tests (+10:**
  the flip incl. the menu-bar case, `SourceChoice.region` ⇄ config, region persistence round-trip +
  malformed/overflow-display-id fallback, one-rebuild batching, `regionLabel`; +1 case in the
  malformed-region test). Full dev loop green. **Franco's decisions (asked + locked):** persist the
  region · main display only (secondary deferred) · no live boundary. **LIVE-VERIFIED (deployed,
  PID-swapped):** Franco drew a region — **"felt great"** (taste call); it persisted (`x=233,y=247,
  1645×721`, display 1), the menu showed **`✓ Region 1645×721`**, and the **app recorded exactly that
  rect** (3290×1442 px = 1645×721 pt ×2; content matched a `screencapture -R` of the persisted rect at
  image-diff **0.056**); the rect's center (1055,607) ≈ screen center (1028,642) — the flip's magnitude is
  right; the pick **survived a cold relaunch** (persist round-trip + the crash-fix load path). **Review
  (code-review agent; 8/10; findings presented → Franco approved batch):** ① **crash-on-load fix** — a
  persisted display id > `UInt32.max` trapped the `CGDirectDisplayID` cast (crash-loop); now
  `CGDirectDisplayID(exactly:)` + an overflow test; ② `beginRegionSelection` `@MainActor`-typed to match
  the injection convention; ③ `acceptsFirstMouse → true` so the first drag draws through a focus race.
  Skipped ⑤ (unavoidable cross-module format dup). **Flip DIRECTION** is unit-tested (menu-bar top → y=0)
  + T1-live-proven (SCK origin top-left); a centered drag can't disambiguate it live — an optional
  menu-bar draw was offered as belt-and-suspenders, not taken. **Armed-replay-with-region** shares the
  same `captureConfiguration` path (unit-covered), not separately live-driven. **No VERSION bump** — M11
  is complete and owes a MINOR **1.6.0**; Franco's call to cut it with Gate G11. **Next: Franco's call —
  cut 1.6.0 / declare G11, dogfood, or scope new work.** M11-T1 note below.

- **🎉 M11-T1 DONE — region capture core + CLI, LIVE-VERIFIED (2026-07-22).** Third `ContentSelection`
  case `.region(display: DisplaySelection, rect: CGRect)` — record an arbitrary rectangle of a display.
  `CaptureEngine` builds the whole-display filter + `SCStreamConfiguration.sourceRect` (display points,
  top-left origin) and sizes the output to the region in **even pixels**; new pure
  `resolveRegion(rect:displayPointSize:scale:)` clamps an edge-straddle and **fails loud** (off-screen /
  zero-area / non-finite / sub-2px) — never a silent whole-screen fallback. `destinationRect` left
  default (the fill is 1:1). Region flows through `RecordingSession → CaptureEngine` **untouched**, so
  recording AND armed replay both inherit it; **AppState unchanged** (region isn't UI-selectable till T2).
  CLI **`record --region x,y,w,h`** + **`replay-arm --region …`** (display points, main display; mutually
  exclusive with `--app`), shared `parseRegion`/`contentSelection`/`describeRegion` helpers. **358 tests
  (+9:** resolveRegion matrix — inside/clamp/even-snap/off-screen/zero-area/non-finite/sub-2px/fractional-
  straddle-no-overrun, `attachesStallWatchdog(.region)`, Equatable). Full dev loop green (build/test/
  release/bundle-sign). **New platform-facts §1b in docs/02** (the sourceRect rulings, like M7-T1's §1a).
  **LIVE-VERIFIED headless:** dimensions exact (800×500 pt → **1600×1000 px**, 1200×120 pt → 2400×240 px,
  probed); all fail-loud paths correct copy + no file (off-screen via engine; zero/malformed/non-numeric/
  `--region`+`--app` via CLI); **origin/crop proven by measurement** — `record --region 0,0,1200,120` frame
  matched `screencapture -R 0,0,1200,120` (menu bar, top-left points) at image-diff **0.019**, vs **0.170**
  for the bottom strip → **top-left display-points confirmed** (viewed: the frame is the menu bar + Firefox
  top, crop tight); region clips carried whole-machine system audio (region has no audio scoping).
  **Review (code-review agent; 8/10, no crash bugs; findings presented → Franco approved batch):** ① wrote
  the owed docs/02 §1b; ② **floor (not round) the pixel snap** so `sourceRect` can't overrun the display
  edge by ≤0.5px on a fractional straddle (+ boundary test); ③ dropped a redundant `scale > 0` guard that
  would have misreported; ④ trimmed a 5-line doc comment. Skipped ⑤ (cross-module format duplication —
  unavoidable). **No VERSION bump** — the CLI is the dev harness, not the shipped app (M7-T3 precedent);
  the MINOR lands with **M11-T2** (the overlay + Source picker) or when Franco cuts. **Next: M11-T2 —
  region selection overlay + menu wiring; plan artifact first.** The three T2 decisions still need Franco
  (persist-vs-fresh region · secondary-display region · no live boundary — see the M11 scope note below).

- **📋 M11 (region capture) SCOPED (2026-07-22) — pausing here.** Franco's ask: record an arbitrary
  rectangle of a display (a third `ContentSelection` mode beside whole-screen and per-app). Written up
  in docs/03 M11 — **T1** region core + CLI (`.region(display:, rect:)`, SCK `sourceRect`, even-pixel
  snap, fail-loud resolution) · **T2** a drag-to-select overlay + Source-picker `Select Region…`.
  Confirmed it was **never previously discussed** (no ADR/task/field note/commit; docs/00 said "later:
  window/app" = M7). **Open decisions for Franco (in the M11 writeup):** persist the last region vs.
  fresh each time; secondary-display region in T2 or deferred; no live recording-boundary overlay.
  Nothing started; all M11 boxes unticked. **Next when Franco resumes: M11-T1 — plan artifact first.**

- **🎉 v1.5.0 CUT (2026-07-22) — M10 (share export & basic editing) earns the MINOR.** `VERSION` +
  `CoreInfo.version` → 1.5.0 (pin test green), tagged `v1.5.0`, pushed. The MINOR earns from M10's
  user-facing features: MP4 share export (T1/T2), GIF export (T3) + GIF settings, and lossless trim
  (T4). Gate G10 passed; the roadmap is now empty. **Next: Franco's call — dogfood 1.5.0, or scope new
  milestones.**

- **🎉 M10-T4 DONE — lossless trim; GATE G10 PASSED; M10 COMPLETE (2026-07-22).** Trim a recording to
  `[in, out]` by **copying the streams — no re-encode** (`AVAssetExportSession` passthrough +
  `timeRange`, `export(to:as:)`). New `Trimmer` (RecorderCore/Export/): guards output==input +
  empty-range, writes `<stem> trimmed.mov` (collision-resolved), original read-only. CLI **`trim <in>
  --from <t> --to <t> [<out>]`** (M:SS or seconds). App: a **`Trim…`** submenu row opens a spare **Trim
  window** (`AppState.trimTarget` + a fixed `Window`): an **`AVPlayerView`** preview, **Set In/Set
  Out** from the playhead, **Trim & Save** → `AppState.trim` reusing T2's off-main / one-at-a-time /
  receipt / notification (`trimmed`/`trimFailed`; `LastExport.menuTitle` now picks the verb by
  extension: `.mov`→"Trimmed"). **349 tests (+8:** trimmedSibling, output==input, empty-range, a
  **gated** integration proving hvc1 preserved + ~1 s + the clamp-to-duration empty-range branch; the
  trim wiring — range plumbing + "Trimmed" receipt/notification; copy). Full dev loop green.
  **LIVE-VERIFIED:** CLI on a real 4112×2570 hvc1 recording, trim [3–9] → **same hvc1, exactly 6.00s,
  plays, original untouched** (edit-list exact trim; b-frames preserved — probe's non-monotonic warning
  is benign, `has_b_frames=2` on both); the **Trim window rendered live** (player + Set In/Set Out +
  Trim & Save + keyframe note, deployed build, settingsdriver shot). **⚠️ Live crash found + fixed:**
  SwiftUI's `VideoPlayer` fatal-errors instantiating metadata in the CLT (no-Xcode) SPM build
  (`getSuperclassMetadata` in `_AVKit_SwiftUI`, SIGABRT) — replaced with `AVPlayerView` via
  `NSViewRepresentable` (field note). **Review (code-review agent; clean, no correctness bugs;
  findings presented → Franco approved batch):** ④ CLI rejects negative/invalid timecodes with a clear
  message; ⑤ `trimmedSibling` always `.mov`; ② pinned the clamp-to-duration empty-range branch (gated
  test); ① the losslessness (same-codec) assertion is gated behind `SCREENREC_HW_ENCODE_TESTS` — the
  routine `swift test` can't catch a regression to a re-encoding preset (**blind spot on record**; I
  run the gated test each verify). Also enabled `settingsdriver shot --window <title>` (any window, not
  just Settings). **No VERSION bump** — M10's features (T1–T4 + GIF settings) owe a MINOR **1.5.0**;
  **Franco's call to cut it now that M10 is complete.** **Next: M10 is done — the roadmap is empty.
  Franco's call (cut 1.5.0, dogfood, or new milestones).**

- **M10-T3 follow-up DONE — GIF settings (Settings pickers + CLI flags), LIVE-VERIFIED.** The T3 caps
  (480/15/30) were fixed; now a **GIF** section in the Settings window — three Pickers, **Frames per
  second** (12/15/20/24) · **Width** (320/480/640/800, caps height too) · **Maximum length**
  (10/15/30/60 s) — steers `Save as GIF`, and the CLI gained **`--fps/--width/--seconds`** flags. New
  persisted `Settings.gifFPS/gifWidth/gifMaxSeconds` (+ 3 contractual keys, snap-to-nearest-choice on
  load); `AppState.exportToGIF` builds a `GifConfiguration` from them (the `gifExportFunction` seam grew
  a config param). No change to `GifExporter`/`VideoFrameReader` — they already take a config. **343
  tests (+5:** gif-caps round-trip, absent→defaults + snap, non-positive→defaults, far-out-of-range→
  nearest bound, `exportToGIF` builds the config from the settings; + the 2 contractual-key pins gained
  the 3 keys). Full dev loop green. **LIVE-VERIFIED (deployed, PID-swapped):** `settingsdriver shot`
  shows the GIF section rendering (15 fps / 480 px / 30 s); **a persisted `gifWidth=640` → relaunch →
  menudriver `Save as GIF` → a 640×400 GIF** (the setting reaches the encoder end-to-end); the CLI
  `--width 640 --fps 20 --seconds 3` → 640×400 `· first 3s`. Prefs + test files restored/cleaned.
  **Review (code-review agent; clean, one real CLI edge + polish; findings presented → Franco approved
  batch):** ① CLI `--fps 0.9` truncated to 0 → broken GIF, now `max(1, round)`; ② `nearest` made
  internal; ③ CLI dies on an unexpected extra positional; ④ snap tests for 0/neg + far-range; ⑤ a
  shadowed `let fps` renamed. **No VERSION bump** — batches with T3 toward the owed MINOR (1.5.0).
  **Next: M10-T4 (lossless trim) — the last M10 item; plan artifact first.**

- **M10-T3 DONE — GIF export from a clip (core + CLI + app action), LIVE-VERIFIED.** A recording or
  saved replay → a **looping animated GIF** via ImageIO (zero-dep). New `GifExporter` + `VideoFrameReader`
  (RecorderCore/Export/): the frame reader is the M10-T1 `AVAssetReader` read side adapted to **CFR** —
  an `AVMutableVideoComposition` `renderSize` scales, and a **PTS subsample in `readFrames` caps the
  fps** (the composition output emits one frame per *source* frame and ignores `frameDuration` for the
  output rate — the reason a naive frameDuration=1/15 rendered 30 fps; **field note**). Streams frames
  one-at-a-time into a `CGImageDestination` (256-color, **loops forever**), never the whole clip in
  memory. **Caps: 480 wide · 15 fps · first 30 s** (`GifConfiguration`; fps bumped from the planned 12
  at Franco's ask). CLI **`export --to-gif <in> [<out>]`** (the export verb now takes exactly one of
  `--to-mp4`/`--to-gif`); app **`Save as GIF`** in the same fileActions submenu, reusing T2's
  `exportInProgress`/`lastExport`/one-at-a-time via a shared `performExport` (MP4 refactored onto it,
  behavior-preserving). New `RecordingNotifications.savedAsGIF`/`gifExportFailed`; `LastExport.menuTitle`
  now picks the verb by extension (a GIF receipt no longer reads "Exported to MP4"). **338 tests (+8:**
  4 `GifExporterTests` — gifSibling, GIF fittedSize, output==input, + a **gated** integration proving a
  480×270 15 fps looping GIF from a 30 fps fixture; 4 `ExportWiringTests` — GIF receipt+notify with the
  right title, cross-format one-at-a-time, GIF copy). The GIF hardware integration test is **gated**
  (`SCREENREC_HW_ENCODE_TESTS=1`, same VT-oversubscription reason as MP4). Full dev loop green.
  **LIVE-VERIFIED:** CLI on a **real 4112×2570 recording** → ImageIO reports `com.compuserve.gif · 60
  frames · 480×300 · loopCount 0`, valid + looping; **Franco visually confirmed** a sent demo GIF; the
  deployed build (PID-swapped, kill-9) shows **`Save as GIF`** in the submenu (menudriver). **Review
  (code-review agent; 8/10, one real bug found + fixed; findings presented → Franco approved batch):**
  ① the mislabeled GIF receipt (fixed), ② `expectedFrames` crash-guard on non-finite duration, ③
  `VideoFrameReader` made internal, ④ all `make` loads mapped to `ReaderError`, ⑤ fps cadence advances
  only on an emitted frame, ⑥ reader cancelled on `readFrames` throw, ⑦ GIF-receipt test assertion.
  **No VERSION bump** — T3 is a new feature since 1.4.0 and owes the next MINOR (**1.5.0**) whenever
  Franco cuts. **Next: M10-T4 (lossless trim) — the last M10 item; plan artifact first.**

- **v1.4.0 CUT (2026-07-21) — the MP4 share export (M10-T1 CLI + M10-T2 app) earns the MINOR.**
  `VERSION` + `CoreInfo.version` → 1.4.0 (pin test green), tagged `v1.4.0`, pushed. M10-T3 (GIF) and
  T4 (trim) remain; they'll fold into a later bump. **Next: M10-T3 (GIF export) — plan artifact first.**

- **M10-T2 DONE — Export as MP4 wired into the app (LIVE-VERIFIED).** Each recent-recording row and
  the saved-replay receipt is now a **submenu** — `<name> ▸ { Reveal in Finder · Export as MP4 }` —
  over a thin `AppState.exportToMP4(_:)` on M10-T1's `Exporter`. Runs **off the main path** (an
  unstructured MainActor-inheriting `Task` that `await`s the injectable `exportFunction`; blocking
  transcode runs off-main on the Exporter's queue), **one at a time** (synchronous guard on
  `exportInProgress`), output = the `.mp4` sibling (collision-resolved), source read-only. Completion
  signal reuses M9-T2: a top-of-menu **`Exported to MP4 · <name>` receipt** (new `LastExport`, reveals
  on click; stamped at open, M6-T10) + an **`Exported to MP4` notification** (new
  `RecordingNotifications.exported`/`exportFailed`, docs/06 table). An `Exporting <name>…` row shows
  while it runs. `exportFunction` is injected so tests skip the hardware encoder. **331 tests (+6:**
  5 `ExportWiringTests` — in-progress→receipt+notify, failure clears + no receipt, a failed re-export
  keeps the prior receipt, one-at-a-time, copy; +1 net after gating, see below). **LIVE-VERIFIED
  (deployed to /Users/Shared, PID-swapped):** menudriver → the newest recording's submenu → Export as
  MP4 → **`Recording ….mp4` appeared in ~1 s**, ffprobe **h264 High / yuv420p / 1920×1200 / aac 2ch /
  moov-before-mdat**, and the menu showed the **`Exported to MP4 · …` receipt row**. Full dev loop
  green. **Review (code-review agent; 8.5/10, no correctness bugs; findings presented → Franco approved
  batch):** ④ dropped `lastExport = nil` at start so a failed re-export keeps the prior receipt (the
  in-progress row shadows it anyway); ⑥ tightened the test gate to `== "1"`. Deferred: ① a pre-existing
  misplaced doc comment in RecordingNotification.swift (separate `docs:` commit), ② quit-mid-export can
  leave a partial `.mp4` (low-stakes — derived copy, source untouched; field note), ③ export during
  record+replay is best-effort (can fault VT, fails cleanly; field note). **No VERSION bump** — the
  accumulated M10 features (T1 CLI, T2 app export) owe a MINOR **1.4.0** whenever Franco cuts.
  **Owed:** a live export failure path (unit-covered; not driven live — would need `~/Movies`
  unwritable). Left a test `.mp4` in `~/Movies` (Franco's real recording, exported) — his to keep or
  delete. **⚠️ VT-encoder test flakiness (see field note):** the Exporter's one hardware-encode
  integration test oversubscribes the VideoToolbox pool under the parallel suite (~half the runs fault
  with -12912), so it's **gated behind `SCREENREC_HW_ENCODE_TESTS=1`** and run in isolation
  (`swift test --filter ExporterTests` with that env); the default `swift test` skips it and is stable.
  The real transcode is CLI-verified (ADR-011) and `fittedSize` covers the downscale math. **Next:
  M10-T3 (GIF export from a clip) — plan artifact first.**

- **M10-T1 DONE — transcode-to-MP4 share export (core + CLI).** New `Exporter` (RecorderCore/Export/)
  over `AVAssetReader → re-encode → AVAssetWriter`: HEVC `.mov` → **H.264 High + AAC `.mp4`, yuv420p,
  `+faststart`**, downscaled to **≤1920 wide** (Franco's recipe value, and forced anyway — 02 §3's
  4096×2304 H.264 cap, which capture's 4112×2570 exceeds), the **two audio tracks mixed to one** stereo
  AAC (`AVAssetReaderAudioMixOutput`, the recipe's `amix`). **No B-frames** (monotonic, most compatible;
  bitrate-capped so they barely help size). CLI **`export --to-mp4 <in> [<out>]`**; default `<out>` is
  the `.mp4` sibling, collision-resolved (` 2`), source read-only. Reuses `AudioEncodingSettings.aac` +
  the ReplayMuxer write/drain idiom. **Capture default unchanged** (still HEVC `.mov`, ADR-004) — this is
  a derived share copy (ADR-016). **326 tests (+8** ExporterTests: fittedSize downscale/no-upscale/even/
  height-cap, mp4Sibling, availableURL collision, reject output==input, reject symlink-alias, one
  integration — 2400×1500 3-track HEVC → 1920×1200 h264 + single mixed aac, playable, faststart moov<mdat,
  audio spans the clip). Full dev loop green. **Verified LIVE headless:** a real 4112×2570 recording →
  `export` → ffprobe **h264 High / yuv420p / 1920×1200 / aac 2ch single track / moov before mdat**;
  re-export wrote `… 2.mp4`, original untouched. **Review (code-review agent; findings presented → Franco
  approved batch):** ① collision guard is now **file-identity** (`fileResourceIdentifier` after resolving
  symlinks) not string-equality — a string compare let an aliased `<out>` (symlink, `/tmp` alias, APFS
  case) pass and the pre-write delete destroy the *input recording*; the alias test I added caught that
  `resourceValues` reports the symlink's OWN identity (needs resolve-first). ② audio `canAdd` failure now
  **throws** (was silent video-only + an undrained-output retention hazard). ③ duration = `assetDuration −
  sessionStart`. ④ `removeItem` moved into `run()` beside `startWriting` (a construction failure leaves an
  existing `<out>` intact). ⑤ reader/writer **cancelled on error paths** (frees the HW encoder). Deferred
  ⑦ (field note). **No VERSION bump** — the CLI is the dev harness, not the shipped app (M7-T3 precedent);
  the MINOR (1.4.0) lands with **M10-T2** (app wiring) or when Franco cuts. **M9 live-checks (global hotkey
  ⌥⌘S, replay slider) CONFIRMED DONE by Franco (2026-07-21).** **Next: M10-T2 (Share… / Export as MP4 menu
  action + progress/completion reusing M9-T2's confirmation) — plan artifact first.**

- **🎉 M9 COMPLETE + v1.3.0 CUT — tagged `v1.3.0`, pushed to origin, deployed to /Users/Shared (2026-07-21).**
  VERSION + `CoreInfo.version` → 1.3.0 (pin test green); the MINOR earns from T3 menu-bar clock + T4
  global hotkey + T8 slider. All 15 M9 commits + the tag are on origin (0 unpushed). Installed build
  reports 1.3.0. Owed live-checks (Franco, at leisure): global hotkey (⌥⌘S from another app) + slider
  end-to-end (set 3:20, arm, save → ≈3:20 clip). **Next: M10 (share export & basic editing) on Franco's
  go.** M9-T8 detail below.
  The Settings Picker (30/60/120 s) is now a **Slider, 5 s → 15 min, seconds granularity**, live `M:SS`
  value, **applied on release** (a draft `@State` committed to `replaySeconds` on
  `onEditingChanged(false)`, so a drag while armed resizes the ring **once** via M6-T6's `windowChanged`,
  not per tick). `Settings.allowedReplaySeconds [30,60,120]` → `replaySecondsRange 5...900`; load
  **clamps** a positive value into range (1000→900, 3→5), absent/≤0 → 60. New pure
  `Settings.replayBufferLabel` (M:SS). **317 tests (+2:** clamp-high/low, in-range survives incl. odd
  137, non-positive→60, the label formatter; the windowChanges test now uses 137). Full dev loop green;
  docs/06 amended (key range + settings line). **Reworked after Franco's look (approved):** the `step:1`
  slider's dense tick marks were ugly — now a **continuous, tick-free slider that snaps to 15 s** (a
  rounding binding) beside an **editable `M:SS` field** for exact/finer values
  (`Settings.parseReplayBuffer` accepts `M:SS` or plain seconds, clamps 5–900, reverts garbage). 318
  tests. **Live-verify owed (deploy + Franco):** set 3:20, arm,
  save → clip ≈ that length. **M9 (T1–T8) is done.** The accumulated MINOR features (T3 menu-bar clock,
  T4 global hotkey, T8 slider) owe **v1.3.0** — Franco's call to cut (VERSION + `CoreInfo.version` + tag).
  **Next: cut 1.3.0, then M10 (share export & basic editing) when Franco says go.**

- **M9-T7 DONE — split `AppState`: extracted `PermissionsModel`.** The permission/onboarding cluster
  (onboarding rows, `refreshOnboarding`, the request/relaunch/readiness surface, `notificationState`,
  `hasAskedForScreenRecording`, `screenWasGrantedAtLaunch`) is now a `@Observable` `PermissionsModel`
  AppState owns and forwards to; its one input is `microphoneRequired` (from the mic pick), and
  observation propagates through the nested `@Observable` so the view/CLI surface is unchanged.
  **315 tests (+2 `PermissionsModelTests`;** no existing test needed changing — the forwarders keep the
  surface). AppState **962 → 917 LOC**. Full dev loop green. **The source-picker split was deliberately
  DROPPED — not deferred (Franco, 2026-07-21):** the picks + quality/fps are *intrinsically* coupled to
  `persist()` + `replayConfigurationChanged()` via non-uniform didSets (display reconfigures replay but
  doesn't persist; others do; `isRehomingSources` batches) — they ARE the capture config that drives
  persistence/replay, so extracting them adds a callback layer over intrinsic coupling for negative
  clarity. Left in AppState on purpose; docs/03 M9-T7 says don't re-attempt. No T7b. No VERSION bump
  (internal). **Next: M9-T8 (replay-length slider) — the last M9 item; plan artifact first.**

- **M9-T6 DONE — allocation-free `SampleRouter.route`.** The per-buffer `Array(consumers.values)` on
  the SCK capture queue (~140×/s, against docs/01's allocation-light rule) is gone: a pre-built
  immutable `consumerList` snapshot, rebuilt only on attach/detach (rare), is what `route` reads under
  the lock (a COW retain, not a heap allocation) then delivers outside it. Thread-safe because the list
  is always *replaced*, never mutated in place — so an in-flight route snapshot stays a stable view.
  Behavior unchanged (the dict stays the identity-keyed source of truth). Verified: build + **313
  tests**, **TSan clean** on the concurrent route/attach/detach suite, release + bundle green. 12-line
  diff. No VERSION bump (internal perf). **Next: M9-T7 (split AppState), then T8 (slider).**

- **M9-T5 DONE — retired `MicSwapSpike.swift` (822 LOC, 8 modes).** Completed research scaffolding
  removed: the file + the `mic-swap-spike` CLI dispatch + the printUsage modes block. Purpose served
  and recorded (02 §4, ADR-012, shipped M8); M8 G8 live gates are the standing regression (field note).
  Verified: build + **313 tests** unchanged, release + bundle green; `--help` no longer lists it and
  `mic-swap-spike` now errors "Unknown command"; the 6 real subcommands
  (record/list-mics/list-apps/engine-smoke/probe-stream/replay-arm) intact. No VERSION bump (internal
  cleanup). **Next: M9-T6 (allocation-free `SampleRouter.route`), then T7 (split AppState), then T8
  (slider).**

- **M9-T4 DONE — global start/stop recording shortcut (+ `ReplayHotkey`→`Hotkey` rename, Franco's ask).**
  An **opt-in** global Start/Stop shortcut: off by default (an always-live combo the user didn't choose
  can clash, unlike replay's ⌥⌘R which only fires while armed); a Settings toggle enables it, seeding
  **⌥⌘S** (`Hotkey.recordDefault`), with the recorder pill to change it. `HotkeyCenter` generalized from
  one hotkey to **N keyed by id** (replay=1, record=2; the Carbon handler reads the fired
  `EventHotKeyID` and dispatches) — replaced the single `onHotkey`. New persisted `recordHotkey: Hotkey?`
  (nil ⇒ off), registered at launch (`activateRecordHotkey`) + on change, not gated on arming.
  `AppState.toggleRecording()` over a pure `recordToggleAction`: **active session (recording OR paused)
  → Stop & Save; idle+ready → Start; blocked → notify** (never a silent no-op). The registrar seam is
  now `(Hotkey?, GlobalShortcut) -> Bool`; App.swift maps each kind → Carbon id + action (weak captures,
  no cycle). **Rename** `ReplayHotkey` → `Hotkey` (generic combo type; persisted key `replayHotkey`
  unchanged) across 6 files via sed. Pause/resume + discard stay menu-only (out of scope). **313 tests
  (+6:** `recordToggleAction` 3-way; `recordHotkey` opt-in round-trip + malformed-loads-off; register
  on-set/unregister-on-clear; blocked + refused notification copy). Full dev loop green
  (build/test/release/bundle-sign); the `hotkey(from:)` parse helper now DRYs replay+record load.
  docs/06 amended (key row + Settings line). **Live-verify needs Franco (can't synthesize a global
  key-press headlessly):** enable the shortcut, switch to another app, press ⌥⌘S → starts; press → stops
  & saves. Not deployed yet. No VERSION bump (batched — M9's features (T3 clock, T4 shortcut) owe a MINOR
  1.3.0 whenever Franco cuts it). **M9 QoL (T1–T4) COMPLETE. Next: debt T5–T7, then slider T8.**

- **M9-T3 DONE — live menu-bar clock + replay-saved flash + hide toggle.** The status-item *label*
  (not the menu — it isn't bridged, unlike the frozen in-menu clock, M6-T10) now shows a live
  monospaced `HH:MM:SS` while recording, ticking off its own 1 s timer like the pulse; frozen with the
  amber icon when paused; icon-only when idle or when the new **Show recording time in the menu bar**
  Settings toggle is off (`showsMenuBarTimer`, opt-out — absent ⇒ on). A pure, pause-correct
  `RecordingClock` value type is the basis (updated only on start/pause/resume/end — nothing published
  per second, so no menu churn; the label computes the ticking value locally). The M9-T2-deferred
  **replay-saved flash** landed here: a ~2 s `checkmark.circle.fill` appended to the label on ⌥⌘R save,
  visible without opening the menu. **307 tests (+10:** RecordingClock math incl. pause/resume banking;
  the apply-fold clock transitions; `showsMenuBarTimer` opt-out round-trip + key pin/set; the flash
  flag). Full dev loop green (build/test/release/bundle-sign). docs/06 amended (status-item live-clock
  note + Settings toggle bullet + the contractual key row). Quality pass: `recordingClock` defaulted to
  nil so `StatusIconView(icon:)` stays constructible. **LIVE-VERIFIED 2026-07-21:** deployed to
  /Users/Shared (PID-swap confirmed) and **Franco visually confirmed the ticking menu-bar clock** on a
  menudriver-started recording (which he then discarded — no stray file). The finer sub-checks (flash
  appears/clears, Settings-off ⇒ icon-only, pause-freeze) are unit-covered + spot-checkable. No VERSION
  bump (batched). **Next: M9-T4 (global start/stop hotkey), then debt T5–T7, then T8 (slider).**
  **Slotted as M9-T8 (Franco, 2026-07-21):** replay buffer length as a slider (small floor → 15 min,
  seconds granularity), replacing the 30/60/120 Picker. **RAM/disk cost accepted — no cap** (his call);
  floor over zero. `allowedReplaySeconds` list → a `5...900` range with clamp-on-load; Slider applies on
  drag-end via the existing `windowChanged` in-place resize (M6-T6). See docs/03 M9-T8.

- **M9-T2 DONE — in-app replay confirmation + banner-suppression discoverability.** A saved replay now
  shows a top-of-menu **`Replay saved · N s`** row (idle + recording), set from a new `AppState.lastReplay`
  (new `LastReplay` value type) in `saveReplay`'s success branch, cleared on disarm, click-reveals the
  clip — so the confirmation reaches the user even though the `Replay saved` banner is suppressed while
  armed (docs/06 §Notifications). Settings' Instant Replay section gains a caption naming the real fix
  (the "Allow notifications when mirroring or sharing the display" toggle) + an `Open Notification
  Settings…` deep-link. **297 tests (+2:** save sets the receipt with rounded seconds + `menuTitle`;
  disarm clears it). Full dev loop green (build/test/release/bundle). Quality pass: caption quotes/`›`
  matched to codebase style (straight quotes, literal `›`). **Deferred to M9-T3 (approved):** the
  menu-bar label "flash" (a save signal visible *without* opening the menu) — it folds into M9-T3's
  label rebuild, so the label is touched once. Live menudriver render-check offered, not yet run (needs
  Franco — drives the desktop). No VERSION bump (batched). **Next: M9-T3 (live menu-bar clock + the
  deferred replay-saved label flash) — plan artifact first.**

- **M9-T1 DONE — mic-less-start notification.** A recording that wanted a mic but resolved to none
  now posts `Recording started · no microphone` at start (pure `RecordingNotifications.recordingStart`,
  fired from `AppState.start()` after the session commits), closing the gap where only a
  *mid*-recording loss notified while a walked-away take went silently mic-less (ADR-007/ADR-012).
  Silent for a deliberate None; body splits specific-pick ("The selected microphone isn't connected")
  vs Automatic ("No microphone is connected") — plan-approved copy, device left unnamed. Capture
  behavior unchanged (still records screen-only); the menu `lastFailure` row is untouched. **295
  tests (+4** on the pure mapper: both variants + None-silent + resolved-silent). Full dev loop green
  (build/test/release/bundle-sign). Quality pass done manually — 54-line pure-fn diff, multi-agent
  review disproportionate; call-site comment trimmed of duplication with the factory doc. **No VERSION
  bump** — PATCH-worthy but batched (the M9 note leaves per-commit bumps to Franco; M7-T1 precedent).
  **Next: M9-T2 (in-app replay confirmation, banner-independent) — plan artifact first.**

- **📋 Product/code review done + roadmap reopened (2026-07-21).** A full review (artifact: product +
  code, three parallel deep-dives — architecture, UX, competitive) ran against v1.2.0. **Two product
  forks resolved by Franco and recorded as ADRs so no future agent re-litigates:**
  (1) **Distribution — ADR-014:** personal tool, limited private sharing only, **no
  notarization** (self-signed + one-time "Open Anyway"; grants persist via the stable DR). M6-T4's
  notarization item is closed "won't do". README "Sharing this build" rewritten.
  (2) **Direction — ADR-015:** stays a recorder; **basic editing (lossless trim + shareable-format
  export) is now in-scope** as a future, but the Metal render/compositing "studio" stage (auto-zoom,
  backgrounds) stays parked. Brief non-goal amended to point here.
  **New roadmap in docs/03 (two milestones, Franco chose 2 over 4):**
  **M9 — post-review polish & debt** (T1 mic-less-start notification · T2 in-app replay confirmation
  [banner suppression] · T3 live menu-bar clock · T4 global start/stop hotkey · T5 retire
  MicSwapSpike · T6 allocation-free SampleRouter.route · T7 split AppState), then
  **M10 — share export & basic editing** (T1 MP4 export core+CLI [ADR-016, the WhatsApp step] · T2
  export app wiring · T3 GIF-from-replay · T4 lossless trim). Independent of each other; build only on
  shipped milestones. **NEXT TASK: M9-T1 — plan artifact first (mandatory), then implement.** Nothing
  from M9/M10 is started; all boxes unticked.

- **🎉 M8 COMPLETE — v1.2.0 (M8-T2 DONE, GATE G8 PASSED 2026-07-20). The AirPods come back.**
  New `MicrophoneRescue` (Capture/) lives INSIDE `CaptureEngine`, so recording, idle-armed
  replay and shared-stream mode all inherit recovery from one implementation: on
  `.microphoneLost`, a HAL device-list listener (`kAudioHardwarePropertyDevices`, event-driven)
  waits for the rebind target — `.sameDevice` for a specific pick, `.systemDefault` for
  Automatic (`MicrophoneRecovery`, set by AppState/CLI) — then builds the spike-proven mic-only
  `SCStream` and splices through its own `ResampledMicInput` into the same router; first-buffer
  confirmation guards dead-but-listed devices; `MicrophoneWatchdog.rearm()` restarts the loss
  cycle so all-day case/uncase works. New `.microphoneRecovered` event → notifications
  ("Still recording · microphone reconnected" / "Replay still armed · microphone reconnected",
  docs/06 rows) and the loss copy de-lied ("…until it reconnects"). **Verified LIVE with Franco
  casing/uncasing on voice cues (`say`):** (1) recording + sameDevice — loss → AirPods return →
  mic track resumed, 72.35 s of 90 s (the gap = the case window); (2) **armed replay** (the
  priority scenario) — loss → return → ring refilled → 60.2 s clip saved mid-armed, mic track
  spanning the FULL window, video/system audio uninterrupted, post-recovery signal −8.8 dB;
  (3) Automatic — AirPods cased and left cased → recovered onto the BUILT-IN mic (the policy);
  (4) never-returns — no substitution under sameDevice, mic track ends at 19.7 s, clean file
  (the ADR-012 floor holds). Stable-mic regression clean. 291 tests (+6). Sync evidence: the
  measured two-stream PTS coherence (±0.6 ms/min, field notes 2026-07-20) + every leg's tracks
  aligned ≤150 ms; a human scrub of the leg files is offered, not yet done. ADR-012 superseded
  note written; 02 §4 rewritten; VERSION → **1.2.0**. Review (2 agents; findings presented,
  Franco approved batch): **one real gap fixed — a rescue-stream death with no HAL event never
  retried** (now self-schedules a delayed re-attempt); locks narrowed off the enumeration path;
  a dedicated sample queue (the listener queue must never carry live buffers); the rescue now
  OWNS its watchdog (`WeakRescueHolder` deleted; `MicrophoneWatchdog.onLoss` became settable);
  a mute latch closes the orphaned-stream teardown window; docs/01 amended with the
  satellite-stream exception; audio-config contract unified (`applyAudioCapture`), HAL address
  builder shared, CLI pick→policy folded into `resolveMicrophone`, the re-arm test moved beside
  the watchdog suite. Skipped w/ comment: confirm-at-first-buffer (the flat 3 s wait only
  delays the notification). Re-verified live post-refactor (Automatic leg: loss → recovery,
  41.2 s mic track of 45 s). v1.2.0 deployed to /Users/Shared. **The roadmap is now empty — no
  planned milestones remain. Next: Franco's call (dogfood, new milestones, or polish).**

- **M8-T1 DONE — fixed-format resampled mic input (M8 mic recovery underway; plan approved).**
  New public seam `ResampledMicInput` (Support/): every mic buffer converts to **48 kHz mono
  Float32** via a primeless `AVAudioConverter` (output PTS = input PTS, converter state carries
  across buffers) in the engine's mic path **before `SampleRouter` fan-out** — no consumer ever
  sees a device format, including T2's future rebuilt-stream splice. **Retired:** M3-T2's mic
  format-change fail-stop (`MovieRecorder` latch/diff/callback + `RecordingSession` wiring);
  `EndReason.microphoneChanged` stays declared-but-unreachable (the `.systemSleep` precedent);
  the ring's re-latch now guards system audio only. ADR-007 amended; 02 §4 rewritten.
  **Behavior change (flagged in plan, approved):** a mid-recording mic codec flip no longer ends
  the recording — the track continues. **Verified:** 6 unit tests (exact scaled counts 480→960,
  PTS equality, mid-stream 24k→48k flip continuous, stereo downmix, pass-through identity, and
  a composed resampler→recorder flip that finalizes one full-length mic track) + LIVE
  `mic-swap-spike --record-repoint`: a real recording rode an AirPods→built-in
  `updateConfiguration` re-point — **one continuous 31.2 s mic track spanning the swap, signal
  on both sides** (pre-T1 this fail-stopped at the swap); stable-mic regression clean. 285
  tests. ⚠️ Observable change: **the mic track is always 48 kHz mono now** — it no longer
  reveals the device rate, killing M6-T13's verify-by-sample-rate method (02 §4 notes the
  replacement). Implementation note: `CMSampleBufferCopyPCMDataIntoAudioBufferList` rejects the
  fixture's valid PCM layouts (-12731) — the retained-ABL wrap works for all. Review (2 agents,
  4 angles; findings presented, Franco approved batch): mic path is now allocation-minimal —
  input wraps the buffer's payload no-copy (`AVAudioPCMBuffer(bufferListNoCopy:)`), ABL scratch
  stack-allocated, the emitted block is the only per-buffer heap allocation (the floor);
  derivable converter state dropped; shared `PCMSampleBuffer.make` helper (also serves
  `ReplayAudioRing`'s deep copy); spike sinks merged (RecordingSink now mirrors the production
  mic path); comment hygiene. **Deferred to T2 (deliberate):** router-level resampler placement
  — decide when T2's rebuilt stream becomes the third producer. All re-verified live
  post-refactor (25.6 s re-point file, mic track full-length, post-swap signal −5.7 dB max).
  **Next: M8-T2 (reconnect watchdog + mic-only stream rebuild) — plan artifact first.**

- **M7-T3 DONE — CLI parity: `replay-arm --app` (Franco's ask, post-G7).** The record
  precedent's flag on the replay harness: one `ContentSelection` line + parsing + help; app-quit
  while armed ends the stream as `stopped (appQuit)` — deliberately NO CLI auto-retry (that loop
  is the GUI ReplayController's). Verified headless: app-scoped arm → USR1 save → 14.3 s clip,
  probe clean, frame contains only TextEdit; quit-while-armed leg exits `appQuit`; whole-screen
  regression clean; 281 tests. `probe-stream` stays display-only on purpose. No VERSION bump —
  the CLI is the dev harness, not the shipped app (plan approved). Also this session (post-M7
  QQ): **why app-scoped recordings look choppy when the target is backgrounded** — macOS/Chromium
  throttle occluded apps' rendering; SCK can't capture frames never drawn. Discord recipe
  (untested): relaunch with `--disable-backgrounding-occluded-windows --disable-renderer-backgrounding
  --disable-background-timer-throttling` (+ `NSAppSleepDisabled`); measuring + docs deferred at
  Franco's call. **Next: M8 (mic recovery) when Franco says go; dogfooding v1.1.0 meanwhile.**

- **🎉 M7 COMPLETE — v1.1.0 (M7-T2 DONE, GATE G7 PASSED 2026-07-20).** The menu's `Display ▸`
  became **`Source ▸`**: Entire Screen (per-display when several) above a divider, running apps
  below — live via `CapturableApps` at menu open (async, publish-on-change), filtered to
  `activationPolicy == .regular` (the raw list included Dock/Control Center/SystemUIServer —
  caught live) and excluding ScreenRec itself. New contractual key `captureAppBundleID`
  (docs/06 table). **The absence ruling (approved via plan artifact):** the pick survives the
  app not running — shown as a checkmarked `<name> (not running)` row (`.disabled` does NOT
  survive the `.menu` bridge; renders undimmed, accepted) — Start fails loud with T1's copy,
  and **armed replay retries until the app returns** (M6-T9's stream-death patience, measured
  live: quit → armed held → relaunch → re-armed unaided → clean 18.2 s clip). Recording menu
  gains `Recording <app> only`. **Verified LIVE, all menudriver-driven:** pick TextEdit →
  key persisted → survives app relaunch; app-scoped 32 s recording + **mid-recording 14.8 s
  replay save off the shared stream, BOTH content-clean** (flashing bystander window absent
  from every checked frame of both files); recording menu shows subject + lock row, no
  pickers. 281 tests (+9; +2 settings). VERSION 1.0.0 → **1.1.0** + tag (ADR-013, first
  post-v1 MINOR). /simplify (4 agents) → 1 real find + polish, findings presented, Franco
  approved batch: **the `sourceChoice` setter batched to ONE armed-stream rebuild** (was two —
  the second wiping the replay buffer against a microsecond-lived config; regression test on
  the ReplaySpy), app-list fetch/membership policy consolidated into
  `AppState.refreshCapturableApps()` + an injected whole-list `recordableAppsFilter` (one
  process-table snapshot), one `appName(for:)` chain, LaunchServices name lookups cached in
  the app-layer resolver. Skipped w/ rationale: `SourceChoice.display` non-optional (low
  stakes, mirrors stored state). All re-verified live post-refactor on the deployed 1.1.0. Verification-rig find: **menudriver's `dismiss` posted a GLOBAL Escape** —
  when the menu wasn't tracking it landed in the focused app (the driving terminal!) and
  interrupted the agent session mid-run; now AXCancel on the menu element (field note).
  **Next: M8 (mic recovery) is the only planned milestone left — Franco's call on when.**

- **M7-T1 DONE — per-app capture core + CLI (Franco picked M7 over M8, 2026-07-20; plan
  artifact approved, `list-apps` included).** `CaptureConfiguration.display` → `content:
  ContentSelection` (`.display(…)` / `.app(bundleID:)`); the engine builds
  `SCContentFilter(display:including:)`, resolves the app against the same enumeration
  `list-apps` prints, fail-stops as `finished(.appQuit)` when the recorded app quits — via the
  new `AppTerminationWatch` (`DispatchSourceProcess`/`NOTE_EXIT`), because **SCK fires NO
  stream error on app-quit** (measured; it keeps delivering frames of the empty filter) — and
  does NOT attach the StallWatchdog under an app filter (its user-active ⇒ frames-expected
  premise fails there; both rulings docs/03 assigned to T1 are made and coded). CLI:
  `record --app <bundle-id>` + `list-apps` (backed by `CapturableApps`, reused by T2's menu
  picker). **Verified LIVE:** app-scoped frames show ONLY TextEdit on black while a flashing
  bystander window + the full desktop fill the whole-screen control frames; system audio
  scoped — same afplay stimulus reads −91 dB (silence) app-scoped vs −10.6 dB max in the
  control; TextEdit killed mid-recording → `finished (appQuit)`, playable 7.92 s file, tracks
  ≤70 ms apart. 271 tests (+10). New platform facts in **02 §1a** (incl.: an app filter
  delivers ~constant fps even for static content — no VFR savings). /simplify (4 agents) →
  no bandaids found, layering endorsed; 5 cleanups presented → Franco approved batch → all
  applied (app check folded into the one `startDecision` seam, shared
  `SCShareableContent.forCapture()` so listed ⇒ bindable is structural, exhaustive switches,
  queue drop) + live re-verified; 3 findings skipped with rationale (field note). Also fixed
  (separate commit): `CoreInfo.version` had missed the 1.0.0 bump — the version-pin test
  caught it.
  VERSION unchanged; the MINOR bump (1.1.0) lands when M7 completes at T2. **Next: M7-T2
  (menu source picker, persistence, sources-locked-while-recording, armed replay follows the
  pick — plan artifact first).**

- **🎉 v1.0.0 DECLARED (Franco, 2026-07-20).** Feature-complete (M0–M6); M6-T4's remaining items
  deferred — distribution/notarization → when Franco actually shares the app; mic recovery →
  graduated to milestone **M8** (Route 2, spike-verified). **Semantic versioning adopted (ADR-013):**
  `VERSION` = 1.0.0, tagged `v1.0.0`; going forward MINOR for a new feature (M7/M8), PATCH for fixes.
  G6 closed as the sum of already-green M6 legs + the acceptance criteria. **Post-v1: M7 (per-app
  capture) and M8 (mic recovery), both planned in docs/03 — Franco's pick on order.**

- **M6-T13 DONE — Automatic (system-default) microphone.** The mic pick is now a
  `MicrophonePreference` enum (`none`/`automatic`/`device`) replacing `selectedMicrophoneID: String?`;
  the Microphone picker gains an opt-in **Automatic (System Default)** row (above the device list,
  separated by a divider). `.automatic` resolves the system default at **record/arm start** via the
  resolver's existing `fallingBackToDefault` flag (SCK binds once, 02 §4 — no mid-session hot-switch,
  that's M6-T4); a specific pick is never overridden. Persisted as a new `microphoneAutomatic` bool
  (wins over a stored `microphoneID`). Resolution is shared by the record and replay paths
  (`microphoneResolution()`) so they can't bind different mics. **Verified LIVE on Franco's AirPods,
  conclusively by sample rate:** Automatic + AirPods → mic track **24 kHz** (AirPods = the default) and
  the active-mic line named "AirPods Pro"; control — built-in picked while AirPods connected → **48 kHz**
  (built-in), pick unmoved. 261 tests (+ automatic persistence round-trip; the pure resolver's
  default-fallback was already covered). /code-review (high) → 2 cleanups, **no correctness bugs** (the
  init-didSet concern verified safe), both applied: the shared resolver helper + a stale comment.
  **Menu finding:** a `.menu` Picker honors `Divider()` (docs/06), unlike text color. **Next: the M6
  tail is down to the T4 decision bucket** (Developer ID + notarization, mic recovery, H.264 compat) —
  the last thing between here and G6/v1.

- **M6-T12 DONE — discard an ongoing recording.** A subordinate, confirmed **Discard Recording…**
  row (red via an `NSColor` attributed title; placed low and set apart from Stop & Save; the alert's
  **safe** choice is the default) drops the take instead of finalizing it. Seam:
  `RecordingSession.discard()` sets a `discardRequested` LockedBox, stops the engine, and the event
  loop routes to `MovieRecorder.cancel()` + an **unconditional file removal** (covers a `.failed`
  writer and a stranded/moved path) — never `finish()`; it yields a new session-emitted
  `EngineEvent.discarded` → `endSession()` → Ready, **silently** (no notification). **Verified LIVE**
  (menudriver + an AX alert-press): discard mid-recording → no `.mov`/`.partial`, app Ready; the
  Stop & Save control still saved a clean 3-track file. 260 tests (+3: cancel-after-write removes the
  file, `.discarded` folds to idle, no notification). /code-review (high, workflow) → 4
  data-integrity findings, all "a confirmed discard could leave the file": **B (`.failed` writer) +
  C (stranded path) FIXED** by the unconditional removal; **A + D (a concurrent fail-stop landing in
  the confirmation window) documented as known edges** (Franco's call — the fail-stop already saved a
  playable file; see field note). **Menu text styling discovered + documented** (Franco's find):
  SwiftUI `.foregroundStyle`/`role: .destructive` don't survive the `.menu` MenuBarExtra bridge; an
  `NSColor` attributed title does (docs/06 "Menu text styling" + field note). **Next: the M6 tail is
  Franco's pick — the T4 bucket or T13 (auto-mic).**

- **M6-T11 DONE — the mic list is live.** Root cause: `AudioInputs.available()` enumerated via
  `AVCaptureDevice.DiscoverySession`, which caches in a long-running process and misses devices
  hot-plugged after launch (Franco's AirPods — captured by armed replay yet absent from the
  picker, checkmark stuck on None). Fix: enumerate device UIDs **live via the CoreAudio HAL**
  (`kAudioHardwarePropertyDevices` + input-stream check), then validate + name + mark-default
  through `AVCaptureDevice` (live per device) so a listed device is always one the recorder can
  bind. `AudioInputDevice` seam unchanged → menu picker, CLI `list-mics`, ReplayArm inherit it.
  **Reproduced + fixed LIVE on Franco's AirPods:** staleprobe showed HAL tracking connect/disconnect
  1→2→1 while DiscoverySession sat frozen at 1 the whole run; the installed app's Microphone
  submenu (menudriver) then showed AirPods appear on connect + drop on disconnect, both directions.
  /code-review (high, workflow) → 7 findings; the real one — pure-HAL "show all" could list devices
  the AVCaptureDevice resolver then rejects (silent no-mic) — reopened the device-scope call; Franco
  chose **"show all bindable"** → the AVCaptureDevice-validation design above (which also folds the
  default-source, name-source, and wasted-read findings). 257 tests (+5: pure `select` seam,
  resolvable/unresolvable fixture on each side). **Also answered Franco's "why did replay capture my
  voice while the picker said None?":** the pick was never None — the stale list just couldn't
  *show* it, while the live capture-side resolver bound it; this fix aligns display with capture.
  **Slotted M6-T13** (opt-in Automatic/system-default mic) from his follow-up. **Next: the M6 tail
  is Franco's pick — T12 (discard recording) or the T4 bucket.**

- **M6-T5 DONE — launch at login + README + docs closeout.** Launch-at-login: a Settings
  toggle backed by `SMAppService.mainApp` (register/unregister; `.status` is the self-
  persisting truth, so **no `launchAtLogin` UserDefaults key** — docs/06 amended). **The
  plan's one unknown resolved in our favor: `SMAppService.register()` works for the self-
  signed build, no notarization needed** (probed live: status enabled↔notRegistered; toggle
  driven live via a new AX settings-driver, 0↔1 both stick). /code-review (high) → 4 findings,
  all applied: the `.requiresApproval` status (user disabled it in System Settings) now counts
  as on + prompts via notification, a failed register reverts on the next runloop (SwiftUI
  observability) + notifies, a stale comment fixed. 252 tests. README rewritten for humans
  (build/sign/install/use + the "self-signed = this machine only" caveat) and its commands
  dry-run-verified. **Next: nothing forced — the M6 tail is Franco's pick** (see v1 status).
- **Tools graduated (`tools:` commit c04a2af).** The session's four reusable verification tools
  now live in `tools/`, cleaned to bar (headers, arg-driven, warning-free) and listed in CLAUDE.md:
  `frames.swift` (PNG frames at timestamps — clip content vs probe's metadata), `settingsdriver.swift`
  (drive the Settings *window* via AX — the complement to menudriver's menu), `hoverprobe.swift`
  (per-tick open-menu screenshots — caught M6-T10), `axdump.swift` (dump an app's AX tree). The
  one-off diagnostics (`interfere.sh`, `micprobe.swift`) stayed scratch — `micprobe`'s logic will
  land inside the T11 fix.

## v1 status (M6 in progress — updated M6-T5)

Shipped and gated: **M0–M5 complete, G0–G5 passed.** M6 (ship-quality) is most of the way:
- **Done:** T1 (acceptance run, C2 criterion amended), T2 (2-h soak — clean + kill-leg 0.47 s
  loss), T3 (error-message audit), T5 (launch-at-login + README + docs), plus the dogfooding
  fixes T6 (replay resize) / T7 (recording-file safeguard) / T8 (arm-while-recording) /
  T9 (armed survives relaunch) / T10 (menu-highlight) / T11 (live mic list via CoreAudio HAL) /
  T12 (discard recording) / T13 (Automatic/system-default mic).
- **Deferred (Franco, 2026-07-20):** T4 decision bucket (Developer ID + notarization, H.264 compat,
  HDR). Distribution/notarization is revisited **when Franco actually shares the app with someone**
  (he'd rather not pay for a Developer account until then); the others are demand-/usage-driven.
  **v1 is feature-complete** — M0–M5 done, M6 done bar this deferred bucket; G6 is the only unrun gate
  and it's the sum of what's already green. **Post-v1 milestones:** **M7** (per-app capture) and
  **M8** (mic recovery — graduated from M6-T4; Route 2 spike-verified both phases, full plan in
  docs/03). Order is Franco's pick; they're independent.
- **G6** = v1 done: not formally run; it's the sum of M6 + the acceptance criteria, most
  already green.

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

## History

- 2026-07-14 — docs/06-ui-spec.md added (menu states, notification copy, onboarding,
  contractual UserDefaults keys). Independent-agent audit of all milestones/tasks run;
  fixes applied across docs/01–06 (EngineEvent surface defined in 01, replay-save
  trigger = SIGUSR1/stdin on replay-arm, record subcommand lifecycle reconciled, probe
  extensions assigned to M2-T4, unrunnable Verify steps fixed or marked human). See
  git log for the diff.

- 2026-07-13 — Research + Tier-1 PoC completed in ~/code/screenrec-poc. Tier-2 planning
  docs authored (docs/00–05, CLAUDE.md, this file). No Tier-2 code exists yet.

## Rotated from STATUS.md 2026-07-27 (M18-T2 session) — M15 through M17, and the
v1.7.1 / v1.7.2 / v1.8.0 cuts

Closed entries, moved verbatim to keep STATUS.md's "Now" readable. Unmaintained.

- **✅ M17-T2 DONE (2026-07-27) — you can pick a window from the menu, and a stale pick can never
  bind the wrong one.** `Source ▸` gains **one** row, `Window ▸`, whose submenu lists on-screen
  windows as `<App> — <Title>`. **495 tests (+13)**, full dev loop green, every leg driven on the
  real menu.
  **Ruling (a) — persist `{id, bundleID, title}`, verify the owner.** A window id is the only thing
  this app persists that names nothing durable: **measured, a TextEdit window went 1498 → 1512 across
  a relaunch**, and ids are *reused* — so a restored bare id could bind another app's window,
  recording the wrong thing while looking like it worked. `ContentSelection.window` now carries an
  optional `ownerBundleID` and capture refuses a mismatch. Title is display-only and never matched on
  (a browser title changes every tab switch). Live: relaunching TextEdit left the new window
  selectable and the old pick as `✓ (closed)` — no silent re-bind.
  **Ruling (b) — nested, not flat.** ✅ **The `.menu` bridge DOES carry a `Menu` inside a `Menu` with
  its own inline `Picker`** (spiked before building on it): checkmark lands two levels deep, Source
  grew by exactly one row, so **M18-T3's diet doesn't get harder**. **Ruling (c)** — a gone pick reads
  `<App> — <Title> (closed)`, checkmarked, the `(not running)` precedent.
  **Verified live:** menu-driven window recording → 1800×1056, 3 tracks, **0.000% same-app bystander
  green vs 92.6% target magenta** across three frames (the leg per-app capture cannot pass).
  **🔴 Fixed a pre-existing defect this task exposed (Franco's call to fix here):** a Start that failed
  said **nothing** — `lastFailure` rendered only in the recording-state menu, and a failed start lands
  in *idle*. Worse, `endSession()` **cleared it** microseconds later, since a start failure does have a
  session; the comment claiming otherwise had always been wrong. Both halves fixed and now
  live-verified (the row renders under Start with the real copy). Applies equally to M7-T2's
  not-running app pick, which has shipped this way since M7. ⚠️ **Both first-cut unit tests were
  vacuous** — they drove `apply(.finished)`, which never reaches `endSession()` (docs/07).
  **🎉 M17 COMPLETE — GATE G17 PASSED (2026-07-27).** M17 is T1+T2; both shipped, gate
  evidence in the table below. **M17 adds a user-facing capture mode → MINOR (ADR-013): 1.9.0,
  Franco's call to cut** (bump `VERSION` + `CoreInfo.version`, then `Scripts/release.sh` **in the
  background**, never under a short foreground timeout or it gets SIGTERM'd mid-encode).
  **Next after that: M18** (Editing & Menu polish) — its T3 menu diet now has exactly one extra
  row to account for, `Window ▸`.

- **✅ M17-T1 DONE (2026-07-27) — `.window` is the fourth `ContentSelection` case; window capture
  records one window and nothing else, including against an overlapping window of the SAME app.**
  `list-windows` + `record --window` + `replay-arm --window`, `EndReason.windowClosed`, all four
  docs/03 rulings measured into **docs/02 §1c**. **482 tests (+12)**, full dev loop green.
  **Proven, with a positive control:** a window-scoped recording of an animated TARGET while a green
  same-app BYSTANDER overlapped it in front → **0.000% bystander pixels across four frames**, while a
  whole-screen capture of the same moment reads **10.7%**. That control is load-bearing: the first
  run "passed" at 0.000% only because the detector was looking for the nominal `NSColor` and the
  display profile shifts it by 93 counts (02 §1c).
  **⚠️ Two mechanisms were built and then deleted by measurement — the task's real story (docs/07):**
  **(1)** `WindowPresenceWatch` (poll SCK for the window) was designed on the `.app` precedent that
  SCK stays silent when its subject vanishes. **A window filter is the opposite: it ends the stream**,
  immediately, for both a close (TextEdit closing a document, app alive) and an app quit. Watch
  deleted, poll cost gone, and the reason is now deterministic instead of a race.
  **(2)** The real bug it hid: `noCaptureSource` is the **same code a disconnected display uses**, so
  killing the recorded app reported **`finished (displayDisconnected)`** — a lie that sends the user
  to check a monitor cable. `endReason(forStreamError:content:)` now disambiguates by filter.
  **🔴 Also fixed a crash on the shipped path:** `SCContentFilter(desktopIndependentWindow:)` **traps
  with `CGS_REQUIRE_INIT`** in a plain CLI binary — `record --window` died on it. One CoreGraphics
  display call fixes it, no AppKit (which RecorderCore may not import).
  Rulings: **(a)** a mid-recording resize does **not** change output size — SCK scales into the pinned
  buffer; **(b)** a minimised window delivers nothing and recovers unaided → no StallWatchdog;
  **(c)** system audio **is** scoped to the owning app (other app −inf dBFS, own app −8.9, control
  −8.9) — but to the *app*, not the window; **(d)** output = `SCWindow.frame` × scale, titlebar in,
  no shadow gutter, corners opaque black. Window capture is **frame-on-change**, unlike `.app`.
  Regressions clean: whole-screen 4112×2570, `--app` 4112×2570, `--region` 1600×1200.
  **Next: M17-T2** (window picker in `Source ▸`, and the persistence ruling) — plan artifact first.
  T2 inherits the M18-T3 menu-length coordination.

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

## M18 (Editing & Menu polish), v1.9.0 and v1.10.0 — rotated from STATUS.md 2026-07-28

- **🎉 v1.10.0 CUT, PUSHED AND INSTALLED (2026-07-28) — M18 (Editing & Menu polish) earns the MINOR.**
  `VERSION` + `CoreInfo.version` → 1.10.0 (pin test green), committed (`9478de3`), cut via
  **`Scripts/release.sh` run in the BACKGROUND** — full gate green (clean tree · version pin · tag
  free · build · **530 tests** · encode ×3 · release build · bundle-sign), tagged **`v1.10.0`**.
  MINOR not PATCH (ADR-013): six user-facing improvements. **0 unpushed; tag on origin**
  (`v1.10.0` → `9478de3`). ⚠️ As always, **the background run does not push** — its `[y/N]` prompt
  reads N with no terminal — so main + tag went up manually afterwards.
  **DEPLOYED to `/Users/Shared/ScreenRec.app`** by the *new* recipe (M18-T4): **`menudriver click
  "Quit"`, not `kill -9`** — it exits in ~2 s and tears the SCK stream down properly, releasing the
  audio tap a SIGKILL strands. **pid 73378 → 76580**, plist `CFBundleShortVersionString` = 1.10.0,
  and the app says so itself: Settings › General reads **`ScreenRec 1.10.0`**. Replay re-armed
  unaided, Source still Entire Screen, TCC intact across the swap.
  **Next: Franco's call — dogfood 1.10.0, or scope new work.** The 2026-07-24 review roadmap
  (M15 Gate & Debt · M16 Honest State · M17 Window capture · M18 Editing & Menu polish) is now
  **fully shipped**; no planned milestones remain.


- **✅ M18-T6 DONE (2026-07-28) — Settings is four tabs; 1137 pt → 437. ALL SIX M18 TASKS ARE
  DONE.** Plan artifact (rulings A1/B1 approved):
  `claude.ai/code/artifact/1e6438cb-3c97-49fb-843e-3981ebfa596c`. **530 tests unchanged** (layout
  only — no binding, key or `AppState` property moved), deployed.
  **Measured first:** 420 × **1137 pt** against **1260 pt** of usable screen — **90%** — and as one
  `Form` with `.fixedSize()` it had no ceiling; a 13-inch Air would lose ~200 pt off the bottom.
  **As built:** **General** (folder, launch at login, menu-bar toggles, version) · **Recording**
  (quality, frame rate, count-in, both global shortcuts) · **Instant Replay** · **Sharing**
  (MP4 + GIF). Recording collects what changes what a take *is*.
  ⚠️ **`TabView` was the wrong mechanism and only a screenshot said so:** at this width SwiftUI
  collapsed all four toolbar tabs into a **`»` overflow menu** — Franco saw it before I did. A
  `Picker(.segmented)` over a `Page` enum can't collapse.
  **Verified live per tab:** General 292 · Recording 289 · Instant Replay 372 · **Sharing 437 pt**
  (tallest), every row in its intended tab, and a Sharing picker round-tripped (`gifFPS` 15 → 20 →
  15, restored). **90% → 35% of the usable screen.**
  🔴 **Also found: a python range-rewrite in the M18-T5 commit silently deleted the filed M18-T6
  entry from docs/03** — committed and pushed before it was noticed, restored here. Third
  silent-replace casualty this session (docs/07).
  **🎉 GATE G18 PASSED (2026-07-28)** — evidence in the table below; its first criterion was
  **amended**, because M18-T1 measured the premise it was written on to be false (a lossless trim
  never cut early). **The capture path is untouched: `git diff v1.9.0..HEAD` over
  `RecorderCore/Capture` and `RecorderCore/Recording` is empty**, and a regression capture is
  4112×2570 hvc1 + 2 audio tracks.
  **M18 is six user-facing improvements → MINOR (ADR-013): 1.10.0** (bump
  `VERSION` + `CoreInfo.version`, then `Scripts/release.sh` **in the background** — never under a
  short foreground timeout, or it gets SIGTERM'd mid-encode — then push main **and** the tag, which
  the background run does not do).

- **✅ M18-T5 DONE (2026-07-28) — a region pick can be corrected instead of redrawn.** Plan artifact (rulings A1/B1 approved):
  `claude.ai/code/artifact/0929e0e2-113e-4d2e-b09c-c19c1941607c`. **530 tests (+5)**, dev loop green,
  deployed; Source restored to Entire Screen.
  **Two premises measured first, both cheap:** the SCK↔view flip is **its own inverse**, so seeding
  the overlay is the shipped function applied twice; and the overlay is **already a key window with
  a live `keyDown`**, so arrows are a new `case`, not a new mechanism.
  **As built:** `present(seededWith:)` (only for a pick that belongs to this display and still fits),
  arrows nudge 1 pt / ⇧ 10, ⌥+arrows resize from the far edge, and a drag snaps magnetically onto
  1920×1080 / 1280×720 / 3840×2160 / 1080×1080 **px** within ~6 pt with the badge appending
  `· snapped`. Keys never snap, so an odd size stays reachable.
  **Verified live:** the overlay re-opened with `800 × 500 pt · 1600 × 1000 px` drawn; two ⇧→ moved
  it to **x 120**, size untouched; ⌥⇧ gave **810 × 510**; Esc discarded; a 956 × 543 drag became
  **`960 × 540 pt · 1920 × 1080 px · snapped`**; the adjusted region recorded **1620 × 1020 px**
  (M11's gate unaffected).
  ⚠️ **The first deploy was stale despite reporting success** — the new hint line was in the running
  app while the new badge suffix wasn't, from the same build; a second build + bundle + ditto fixed
  it. And a synthetic menu click doesn't activate the app, so synthetic keys went to Firefox until
  the driver activated ScreenRec first (both in docs/07).
  **Next: M18-T6** (the Settings window's height — tabs), then **G18** and the MINOR bump.

- **✅ M18-T4 DONE (2026-07-28) — four silences, each now saying what it knows.** Plan artifact
  (rulings A1/B1/C1 approved): `claude.ai/code/artifact/d3555144-9393-4af5-8e1f-750f470ae5b5`.
  **525 tests (+11)**, dev loop green, deployed and re-armed.
  **(1) <kbd>Esc</kbd> cancels the count-in.** The overlay is click-through and never key, so no key
  event can reach it and a global monitor needs a TCC grant this product has never required —
  measured that a **bare-Esc Carbon hotkey registers and fires** in an accessory app, not frontmost
  (02 §9). Registered only while the count runs, since it swallows Esc system-wide.
  **(2) `Stop After ▸`** (Off/5/15/30/60) stops through the shipped `.userStopped` path; the
  recording menu states `Stops at 2:35 PM` — absolute, locale-formatted, never ticking.
  **(3) `Room for about 40 min at High`** under Start, below a 2-hour threshold.
  **(4)** Every file action is built through one `fileButton` that checks the file first, so an
  unguarded one can't be written; the export receipt is existence-checked at menu open and the
  replay receipt is cleared too — it was the one row nothing else dropped.
  **🔴 Review caught the disk row over-promising by the entire 2 GiB fail-stop reserve** — 4 GiB
  free would have read "about 30 min" for a take that stops at ~15. It now subtracts the reserve
  and says `Not enough room to record` when there is none; measured after the fix at 2.7 GiB →
  **2 min** and 1.2 GiB → **Not enough room**. Review also found three actions (Trim/Rename/Trash)
  still bypassing the check, and the room figure doing volume I/O on every menu body build through
  a URL whose cached values never cleared — yesterday's `URL` lesson, repeated.
  **Verified live:** Esc cancelled twice with no file written and Start immediately reusable; a take
  begun at 09:30 under a 5-minute bound read `Stops at 9:35`; a row whose file was deleted under an
  open menu dropped itself on click.
  ⚠️ **Deploy hygiene changed:** stop using `kill -9` — `menudriver click "Quit"` exits cleanly in
  ~2 s **and releases the SCK audio tap** (assertions went 2 → 1). A SIGKILL skips stream teardown,
  which is how a tap gets stranded; this machine carries an unrelated 18-hour-old one.
  **Next: M18-T5** (a region pick can be adjusted) — plan artifact first. Then G18 and the MINOR.

- **✅ M18-T3 DONE (2026-07-27) — the menu's file browser is one `Recordings ▸` row.** Plan artifact
  (rulings A1/B1 approved): `claude.ai/code/artifact/e6b55bd5-fe54-455a-a06d-f55aa11b8431`.
  **513 tests (+5)**, full dev loop green, deployed and re-armed.
  **Measured before designing:** the idle menu is **20 rows** today (3 recordings, no exports) and
  **32 at worst**; the folder + 5 recents + the `Recent Exports` label + 3 exports are 9 of them.
  Folding leaves **17 / 23**. Duration per row is affordable — **1–8 ms**, and the 657 MB file was
  the *fastest* of three (header read, not a scan) — so rows read `<name> — 23:04 · 5.5 GB`, read
  off the open and cached by modification date (M6-T10).
  ⚠️ **A test caught a bug review would not have:** `URL` caches resource values per instance and
  the menu holds its URLs across opens, so a re-recorded file kept its first size forever until the
  cache check started clearing them.
  **Verified live:** `menudriver dump` before/after → **20 → 17** rows; every action still present
  (the only diffs are three window titles that changed between dumps and the intended `Open
  Recordings Folder` → `Open Folder` rename); open time **0.57–0.60 s** vs the **0.57–0.59 s**
  baseline — not measurably slower; rows carried their details on the *first* open
  (`Replay … .mov — 4:30 · 656,9 MB`); the rewired folder row opened `~/Movies` in Finder.
  **Next: M18-T4** (four small honesties) — plan artifact first. Its item (4) is where the stale
  export-receipt row Franco hit belongs.

- **✅ M18-T2 DONE (2026-07-27) — `Export as MP4` has a Size, and the ceiling is a decoder's, not
  an API's.** Plan artifact (rulings A1/B1/C1 approved):
  `claude.ai/code/artifact/6ded5178-712a-4862-990d-547be5f1a39d`. **508 tests (+6)**, dev loop green,
  deployed.
  **🔴 The measurement that bounded the task: docs/02 §3's "AVAssetWriter's H.264 path caps at
  4096×2304" is false.** The writer encodes **4112×2570** H.264 fine — at **Level 6.0**, which most
  phone decoders refuse. 4096×2304 is exactly **Level 5.2's** frame size, so the ceiling is a
  *compatibility* one and **there is no honest "Original"** for a full-screen recording; the largest
  safe output is **3686 × 2304**. 02 §3 corrected.
  **As built:** an **MP4** Settings section above GIF with one **Size** picker — `1280 px · 1920 px ·
  2560 px · Largest (3686 × 2304)`, the ceiling row naming what it would really produce for the
  current source. Persisted `mp4Width` (absent ⇒ 1920, snap-on-load, the GIF pattern). Bitrate is not
  a picker: it rises with the output's pixel count from 6 Mbps at 1920×1200 and **never falls below
  it** — so no existing export gets softer, only larger picks get more. `export --to-mp4 --width` on the CLI.
  **Verified:** four CLI exports — 1280×800 **L3.2** / 1920×1200 **L5.0** / 2560×1600 **L5.0** /
  3686×2304 **L5.2**, every one yuv420p + faststart, bitrate up to 19.6 Mbps, 4.9 → 34.5 MB; and
  live, the real picker set to `Largest (3686 × 2304)` → persisted `mp4Width = 4096` → menu export →
  **3686 × 2304, High, Level 5.2**. Franco's setting restored to 1920 and the test files deleted.
  ⚠️ **The review caught a real regression before it shipped:** my first cut scaled *symmetrically*,
  so a 1280×800 region or window export would have dropped from 6 Mbps to 2.7 — every small share
  clip quietly softer, at the untouched default setting. Floored at the reference and re-measured
  (1280×800 → 5.94 Mbps). Also from the review: the Level 5.2 box is now enforced inside
  `Exporter.fittedSize`, so no configuration can opt out of it, and the ceiling has one definition
  instead of three literals across three modules.
  **Next: M18-T3** (the menu diet) — plan artifact first. ⚠️ **Franco flagged the Settings window
  itself is now too tall** (this task added a section): filed as **M18-T6**, tabs recommended.

- **✅ M18-T1 DONE (2026-07-27) — the defect the task was filed on did not exist; the real one does,
  and the window now states it.** Revised plan artifact (rulings A1 + B1, approved mid-task):
  `claude.ai/code/artifact/0fc6e6c3-2d4b-4e14-a8f2-c97218ce6ab4`. **502 tests (+2)**, full dev loop
  green, deployed to `/Users/Shared/ScreenRec.app` and re-armed.
  **🔴 The premise was false and only opening a trimmed file said so.** A passthrough trim writes an
  **edit list**: playback starts *exactly* at the in-point — the first presented frame is
  **byte-identical** to the source frame there (md5), and ffmpeg agrees independently. "Up to two
  seconds early" was inferred from "passthrough cuts at a sync sample" and had been in docs, copy and
  a review finding for two milestones. **What is true: the cut frames stay inside the file**
  (`ffprobe -ignore_editlist 1` → **13.56 s inside a 10.00 s clip**, decoding 3.43 s before the
  in-point; video only — audio packets are all sync samples). Mechanism now in **docs/02 §6a**.
  **🔴 Yesterday's precise path was a no-op.** `AVAssetExportPresetHEVCHighestQuality` + `timeRange`
  **passes an HEVC source straight through** — **23,578,074 bytes both ways**, 0.1 s. It "preserved"
  size, codec and both audio tracks because it never touched them; `--precise` would have written the
  lossless file while printing "precise re-encode". `AVVideoComposition(propertiesOf:)` forces the
  real encode, and the new unit test **fails without that one line** (verified by removing it).
  **✅ The `non-monotonic timestamps` blocker was `probe`'s bug**, not the encoder's, and never
  precise-specific — every trim triggered it, lossless included. Our capture emits B-frames (459 of
  923 samples step back in PTS; DTS clean) and probe fell back to PTS for the four boundary samples
  with no DTS, mixing two clocks. It now judges one clock per track; eight files re-probe clean.
  **As built:** `TrimMode.lossless/.precise` on `Trimmer` (one exhaustive `switch`, so a preset can't
  drift from its composition), `--precise` on the CLI, and in the window the lead-in line, a
  **Re-encode** checkbox, <kbd>I</kbd>/<kbd>O</kbd> and **Play Range**.
  **Live legs (deployed build, driven by AX):** `I`/`O` set In/Out by real key event; the lead-in
  line reads **`Starts exactly at 0:02 · keeps 0.8 s before it inside the file`**; the toggle's label
  tracks the range; Play Range starts at the in-point and advances; an app-driven precise Trim & Save
  produced **hvc1 4112×2570 + 2ch + 1ch, no lead-in, probe clean**.
  **🔴 Fixed a bug Franco hit mid-session:** closing the Trim window left the preview **playing**
  (measured 72.22 s → 85.51 s across a 10 s closed window — a `Window` scene keeps its `@State`, and
  reopening the same clip reused the running player). `.onDisappear` now unloads it; after: reopen
  reads `pos 0, playing 0`.
  **Next: M18-T2** (MP4 export options) — plan artifact first. ⚠️ **Also reported by Franco and NOT
  fixed here (scope):** an export receipt whose file is deleted mid-session keeps its menu row, and
  every action in it silently does nothing — the receipt is existence-checked only at launch. Same
  class as M18-T4 item (4); fold it in there or take it as a one-commit fix first.

- **🎉 v1.9.0 CUT, PUSHED AND INSTALLED (2026-07-27) — M17 (Window capture) earns the MINOR.**
  `VERSION` + `CoreInfo.version` → 1.9.0 (pin test green), committed (`aec7685`), cut via
  **`Scripts/release.sh` run in the BACKGROUND** — full gate green (clean tree · version pin · build ·
  495 tests · encode×3 · release build · bundle-sign), tagged **`v1.9.0`**. MINOR not PATCH (ADR-013):
  a new user-facing capture mode. **0 unpushed; tag on origin** (`v1.9.0` → `aec7685`).
  ⚠️ **The background run does NOT push** — the script's `Push? [y/N]` prompt reads N with no terminal,
  so main + tag went up manually afterwards; the tag push runs its own pre-push gate (docs/07).
  **DEPLOYED to `/Users/Shared/ScreenRec.app`**, by the field-note recipe (`kill -9` the pid, not
  `killall`, which does not terminate it and leaves the OLD binary running): **pid 8195 → 10819**,
  plist `CFBundleShortVersionString` = 1.9.0, the M17 fail-loud copy present in the deployed binary
  (`strings`), replay re-armed unaided, Source back to Entire Screen, TCC intact across the swap.
  **Next: M18 (Editing & Menu polish)** — the last milestone on the 2026-07-24 review roadmap. Its T3
  menu diet inherits exactly one extra row from M17-T2, `Window ▸`, not the dozen a flat list would
  have cost; and M18-T4's “small honesties” is the natural home for the duplicate-label wrinkle a
  relaunched app produces (a live row and a `(closed)` row with the same text).

## M19 (The disk tells the truth) — rotated from STATUS.md 2026-07-28

- **✅ M19-T5 DONE (2026-07-28) — a window pick is an identity, not a title. M19's five tasks are
  all closed (T1/T4/T5 shipped, T2/T3 won't-do).** Plan artifact (rulings A/B/C approved):
  `claude.ai/code/artifact/45e7cf23-0703-4e5b-aaed-50222cebe3fa`. **539 tests (+3)**, dev loop green,
  deployed (pid 93702).
  **As built:** `WindowSelection` is `id` + `bundleID` only — the field is *gone*, not merely
  omitted at the save site. A legacy `title` is ignored on load and erased by the next save (the
  whole dict is rewritten — no migration). A gone pick reads **`Firefox (closed)`** in the row and
  the `Source:` header alike; without the marker it reads like an app-scoped pick, a different mode.
  🔴 **The probe found a shipped UI bug on the way:** the menu tags each row with a `WindowSelection`
  built from the **live** window while the selection came from the **stored** pick, and the type was
  `Hashable` over `title` — so **a retitled window lost its checkmark** (measured `match=false`).
  Every browser tab switch did it. It hid because the header is computed separately and stayed
  correct, with a passing test for the header. Generalised in docs/07: a Picker tag must carry
  identity only.
  **Verified live:** the menu did list a private-browsing window and a Slack channel by name (the
  review's point) → picked one → plist held **`{bundleID, id}` only** → renaming the folder under
  Finder retitled the window and the row **stayed `✓`** → closing it gave **`✓ Finder (closed)`** in
  row and header → Start **failed loud** with the M17-T2 copy. Source restored to Entire Screen and
  the pick cleared.
  **Next: G19** — three surviving criteria (the disk guard's falling-volume leg is already recorded
  under M19-T1; the plist has no window title; the MP4 picker names what its sizes cost) — then the
  **PATCH bump to 1.10.1** and a release cut (`Scripts/release.sh` **in the background**, then push
  main **and** the tag by hand).

- **📋 FILED 2026-07-28: M22-T6 — a tag carries a downloadable build** (Franco asked mid-session).
  Nothing is missing tooling-wise: `gh` is installed and authenticated (`fcostantini`, keyring, ssh),
  `release.sh` already tags and pushes, `bundle.sh` already leaves a signed `dist/ScreenRec.app`. The
  addition is ~6 lines in the push branch — `ditto -c -k --sequesterRsrc --keepParent` (never
  `zip -r`, which mangles a bundle and can void the signature) then `gh release create --generate-notes`.
  **Filed beside M22-T5 to be done in the same edit** (same file, same region).
  ⚠️ **The real constraint is Gatekeeper, not tooling:** ADR-014's build is self-signed and
  deliberately not notarized, so a *downloaded* zip is quarantined and macOS 15 refuses it until the
  recipient uses System Settings → Privacy & Security → Open Anyway — the instruction has to ride
  with the release or the download is a trap. Notarization stays closed (ADR-014); noted only that
  `notarytool`/`stapler` do ship with the Command Line Tools here.

- **✅ M19-T4 DONE (2026-07-28) — the Size picker says what each pick costs, and one row is gone.**
  Plan artifact (rulings A/B/C approved): `claude.ai/code/artifact/e7d999a2-d9b8-4a03-b3a7-0d809feba4f4`.
  **536 tests (+3)**, dev loop green, deployed to `/Users/Shared/ScreenRec.app` (pid 89360).
  🔴 **Measured before designing: `1280 px` was a decoy** — one 7.47 s source exported at all four
  picks gave **6,764,917 B at 1280 vs 6,688,557 B at 1920**, the smaller pick 1% *heavier* for 2.25×
  fewer pixels, because M18-T2's rate floor gives every output ≤ 1920×1200 exactly 6 Mbps. Dropped;
  a stored 1280 snaps to 1920 on load, and `--width 1280` still works on the CLI.
  **As built:** rows read `1920 px · ≈46 MB per minute` · `2560 px · ≈81` ·
  `Largest (3686 × 2304) · ≈170`, computed from the same `ExportConfiguration` the encoder uses, at
  `≈`-grade through a new shared **`ApproximateBytes`** (extracted from `ReplayFootprint`, which had
  the only copy). Destination words (`Message / web`) were **rejected**: a 46 MB minute already
  exceeds what several services take, so the row would promise what clip *length* decides.
  **Verified live on the deployed build:** the picker reads `1920 px · ≈46 MB per minute`, and a
  menu export of a 20 s take produced **15,809,145 B = 45.1 MB/min** against that ≈46.
  ⚠️ **`strings` can't see a Swift literal ≤ 15 bytes** (immediate values, not data) — the
  deploy-freshness check reported 0 matches for `" per minute"` from a binary that had it. Grep
  something longer (docs/07).
  **Next: M19-T5** (a window pick stops storing its title) — plan artifact first. Then **G19**, then
  the PATCH bump to 1.10.1.

- **🚫 M19-T2 AND M19-T3 CLOSED "WON'T DO" (2026-07-28, Franco) — the app does not delete the
  user's files.** Ruled out at the plan gate, before any code: plan artifact
  `claude.ai/code/artifact/1fb4f5fa-a182-485f-a929-ef11730eed67`. T2 was a GB cap on the recordings
  folder (swept after finalize, Trash-only); T3 was trashing a recording once its export landed —
  both out, background policy or per-export offer alike. Cleaning up stays a Finder job.
  **Worth keeping from the plan:** the real `~/Movies` holds **two clips Franco made himself, and
  they are the oldest files in it** — so the obvious "trash the oldest `.mov`s over the cap" would
  have taken his files first. Any future retention idea starts from "only files ScreenRec named".
  **Consequences:** G19 amended (the cap criterion removed), and **M19 is now a PATCH, not a MINOR**
  — with retention gone the milestone adds no new capability.
  **Next: M19-T4** (MP4 picker sizes named by destination, not by pixels) — plan artifact first.
  Then M19-T5 (a window pick stops storing its title), then G19.

- **✅ M19-T1 DONE (2026-07-28) — the disk guard can finally see the disk filling.** Plan artifact
  (rulings A/B/C/D approved): `claude.ai/code/artifact/59035276-224a-457b-b5e7-089fa5d7c780`.
  **533 tests (+3)**, full dev loop green.
  **The A/B is the whole story, at the real 2 GB floor with no test hook** — 4 GB APFS image,
  ~2 GiB of `dd` ballast landing 12 s into a 60 s take, free space crossing to 1.78 GiB:
  **before**, the take ran all 60 s and said `finished (userStopped)`; **after**,
  `finished (diskAlmostFull)` at **15.3 s** (~3 s after the crossing, 2 s poll) with a playable
  **14.89 s** file (hvc1 4112×2570 + AAC).
  **As built:** `DiskSpaceMonitor.availableBytes(forVolumeAtPath:)` builds the `URL` inside the
  read, so freshness is structural and no caller can hold a stale one; the `watching:` init keeps
  the path; `AppState.refreshRecordingRoom` routes through it too (ruling C), which retires the
  copy-and-clear idiom on the volume probe.
  ⚠️ **Two dead ends measured before designing** (docs/07): `setTemporaryResourceValue` **cannot**
  poison the capacity keys, so the obvious deterministic test does not exist; and `URL` copies
  **share** one cache — clearing the copy unfroze the original, so copy-and-clear was never
  reading "through a private copy".
  **The regression test that replaces it** sets the floor 32 MB under a live reading, writes
  64 MiB (12–18 ms; the boot volume moves by exactly 67,108,864, 5/5 trials) and polls again —
  **verified to fail on the held-`URL` code** by reinstating it.
  **Ruling A:** `--test-disk-floor` stays as a smoke check; **04 §4.4 no longer rests on it** —
  the gate is now the falling-volume leg, since the old criterion tripped on the first poll and a
  frozen reading satisfied it for four milestones.
  **Next: M19-T2** (a ceiling on `~/Movies`) — plan artifact first. It carries the milestone's
  MINOR; T1 alone is a PATCH.

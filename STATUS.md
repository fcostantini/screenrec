# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

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
| G22  | ✅ **passed 2026-07-28** | **`AppState` is materially smaller with the menu unchanged:** **1,572 → 1,288 lines (−18%)**, its sources and session lifted into `SourcesModel` (288) and `SessionModel` (187), and the deployed menu dumped **identical** across both extractions (the only diffs in either run were live window titles retitling themselves between dumps — a Slack channel, my own Terminal's spinner). ⚠️ **The public member count did *not* shrink** (118 → 119): the forwards preserve the surface on purpose, which is exactly why **557 tests passed untouched** through both moves. That bar earned itself in T2, where two guards inverted silently when `session` stopped being optional (`session == nil` on a non-optional; `session != nil \|\| isReplayArmed`) and only the unmoved tests noticed. **The six units are named by tests that can fail:** each of `WriterDrain`, `VideoFrameReader`, `PCMSampleBuffer`, `SampleTiming`, `Polling`, `MediaFile` was verified by **breaking its unit and watching its test fail** — and that pass caught a test of my own that passed against broken code (`Polling`, docs/07). **One timecode type serves every surface:** `Timecode.cutPoint`/`.clock`/`.length` replaced five renderers with three roundings across two modules, with the 14 pinned strings moved verbatim and the menu byte-identical. **A background release pushes without a human and leaves a downloadable, still-signed build:** proven by this very cut — see the v1.10.2 entry. **557 tests.** |
| G19  | ✅ **passed 2026-07-28** | All three surviving criteria re-run against the release build (T2/T3 were closed "won't do", so the folder-cap criterion is gone). **A volume that fills *during* the take stops the recording:** 4 GB APFS image, the **real 2 GB floor with no `--test-disk-floor`**, ~2 GiB of `dd` ballast landing 12 s into a 60 s take → free space crossed to 1.79 GiB → **`✓ finished (diskAlmostFull)` at 15.28 s** (~3 s after the crossing, 2 s poll) leaving a **playable 14.51 s** file (hvc1 4112×2570 + AAC). The same script on the pre-fix binary ran all 60 s and reported `userStopped` — the guard had never been able to see a disk fill (M19-T1, docs/07). **No window title reaches the plist:** picked a live Finder window through the menu → `captureWindow` = **`{bundleID = "com.apple.finder"; id = 3443;}`** and `defaults read <domain> \| grep -i title` returns **nothing**, in a session whose window list included a private-browsing window and a Slack channel by name. Restored to Entire Screen; the entry is removed with the pick. **The MP4 picker names what its sizes cost:** the deployed Settings row reads **`1920 px · ≈46 MB per minute`** (AX value), and a menu export of a 20 s take landed at **45.1 MB/min** against it. **539 tests.** |
| G18  | ✅ **passed 2026-07-28** | **The trim tells the truth about what it keeps** (criterion amended — the premise it was filed on was false): a lossless trim's first presented frame is **byte-identical** to the source at the in-point in AVFoundation *and* ffmpeg, while `ffprobe -ignore_editlist 1` shows **13.56 s inside a 10.00 s clip**; the window states `Starts exactly at 0:02 · keeps 0.8 s before it inside the file`, and a **re-encoding trim holds only the kept range** (edit-list segment `0.000..5.000`, 4112×2570 hvc1, both audio tracks — ADR-004 intact). **An MP4 export honours a chosen size:** the real Settings picker set to `Largest (3686 × 2304)` → persisted → menu export → **3686 × 2304, High, Level 5.2**, yuv420p + faststart; four CLI sizes measured at **L3.2 / L5.0 / L5.0 / L5.2**, none crossing the decoder ceiling. **The idle menu is materially shorter and no slower:** **20 → 17 rows** (32 → 23 worst case) by `menudriver dump`, every action still present, open time **0.57–0.60 s** against a **0.57–0.59 s** baseline (5 runs each). **The count-in is cancellable:** Esc during the beat returned to idle **twice in a row** with no file written and Start immediately reusable — via a bare-Esc Carbon hotkey, since the click-through overlay never becomes key and a global monitor would need a TCC grant this product has never required. **A region pick can be adjusted:** the overlay re-opened with `800 × 500 pt · 1600 × 1000 px` drawn, two ⇧→ moved it to **x 120** with the size untouched, ⌥⇧ resized to **810 × 510**, Esc discarded, a 956 × 543 drag snapped to **`1920 × 1080 px · snapped`**, and the adjusted region **recorded 1620 × 1020 px** (M11 unaffected). **No capture-path change:** `git diff v1.9.0..HEAD -- RecorderCore/Capture RecorderCore/Recording` is **empty**; a regression capture is 4112×2570 hvc1 + 2 audio tracks. Also in the milestone: Settings **1137 → 437 pt** (90% → 35% of usable height), and four small honesties (a bounded take states `Stops at 2:35 PM`, the disk row subtracts the fail-stop reserve, dead rows say so). **530 tests.** |
| G17  | ✅ **passed 2026-07-27** | **A window-scoped recording captures exactly the chosen window** — including the case per-app capture structurally cannot exclude: an overlapping window of the SAME app, in front, is absent from every checked frame (**0.000%** of its measured green) while the target fills **92.6%**, both via the CLI (T1) and menu-driven (T2). A whole-screen capture of the same moment reads **10.7%** — the positive control, without which a broken detector reads as a pass (it did once). **Dimensions:** `SCWindow.frame` × scale, titlebar included, no shadow gutter (900×528 pt → 1800×1056 px; TextEdit 586×476 → 1172×952). **Armed replay** scoped to a window: 10.93 s clip, 1800×1056, hvc1 + AAC. **Mid-recording resize and close behave as T1 measured:** a resize does not change the output size (SCK scales into the pinned buffer, frames uninterrupted at 20/s); a close ends the session with a playable file and an honest `windowClosed`, by both routes (a real app closing its window, and the app quitting). A minimised window delivers nothing and recovers unaided — no stream error, no StallWatchdog. **The pick never silently falls back:** a gone window fails loud, and a **reused id is refused** by the owner check (ids are not durable — measured 1498 → 1512 across an app relaunch); live, a relaunched TextEdit left the new window selectable and the stale pick `(closed)`. **The other three modes are unaffected, re-verified through the menu after T2:** whole-screen 4112×2570, `--app` 4112×2570 (display-sized per §1a), region 1600×1200. 495 tests. |
| G16  | ✅ **passed 2026-07-27** | **No stream misreports itself:** the deployed app's assertion reads `Instant replay is armed` (T1; the original "an armed Mac idle-sleeps" criterion was replaced by ADR-018 — measurement showed SCK's own audio tap keeps the Mac awake regardless of `SleepGuard`). **The armed cost is stated where it's chosen:** Settings caption + menu row, live on Franco's own settings — `4:30 buffer · ≈800 MB · Mac stays awake` (T2). **System audio off:** probe shows video + 1ch mic, **no empty track**; on: 3 tracks, no regression vs G2 §3.1; all-off: playable video-only (T3). **Muted mic:** exactly one notice at ~10 s, recording ran to completion, file playable with a full-length silent mic track; unmute → the paired recovery notice; control run → neither (T4). **Menu-bar level measurably tracks audio:** four distinct rendered states by pixel diff (0/89/153/189 px, all inside the meter's columns), and a live capture lit it and returned to the silent bitmap (T5). **Setup proves capture and names the build:** `✓ screen · 4112 × 2570 / ✓ system audio / ✓ microphone · AirPods Pro`, muted → `! microphone · silent`, None → `— microphone · not selected`, scratch cleaned, footers match `VERSION` (T6). **No regression in the other capture modes:** region → 1600×1200 3-track, app-scoped → display-sized 3-track; export/trim/GIF encode suites green in the release gate. 470 tests. |
| G15  | ✅ **passed 2026-07-24** | T1: `swift test` 20 runs green, none over 10 s (baseline 8/10 failed at ~123 s). T3: `kill -9` mid-export leaves nothing at the final name (A/B measured; before, a torn `.mp4` survived). T4: no stale comment or dead `EndReason` arm remains; 429 tests. T5: STATUS.md 2,769 → 237 lines, rotation verified lossless, all doc references resolve. T2 closed "won't do". |


## Where the rest lives

| What | Where |
|---|---|
| Measured platform behaviour and gotchas (the most re-read artefact here) | `docs/07-field-notes.md` |
| Closed session logs — M0–M14, the v1 status write-up, calibration tables | `docs/history/2026-07-sessions.md` |
| Per-task specs, rulings and tick boxes | `docs/03-milestones.md` |

# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

- **🗓️ M25–M28 ENCODED (2026-07-31, Franco's call) — nothing started.** Four of the six parked
  items are now milestones in docs/03, with tasks, seams, rulings and gates: **M25 Swift 6 language
  mode** (debt, PATCH), **M26 Crop on export** (MINOR), **M27 Audio-only per-app exclusion via Core
  Audio process taps** (MINOR), **M28 an `NSMenu`-backed status item** (MINOR).
  ✅ **RULED: crop on export is in scope (Franco, 2026-07-31)** — the one parked item marked
  🔴 *needs a ruling*. **ADR-015 is amended, not contradicted** (docs/05): crop goes in on the
  mechanism — the export path already scales every frame, so a source rect is an argument to work
  that happens anyway — and the render/composite/animate line does **not** move.
  ⚠️ **Proposed order, his to change: M25 → M26 → M27 → M28.** Swift 6 first because M27 puts a
  second audio clock into `SampleRouter` and the compiler should be checking docs/01's rules before
  that lands — M22-before-M21's logic. M28 last: largest, and it buys polish rather than capability.
  ✅ **Measured today, so the milestones quote facts:** Swift 6 is **7 distinct sites in
  `RecorderCore`** (named in M25-T1) and **5 in `AppCore`**, all one cluster; `ScreenRecApp`, the CLI
  and both test targets are **unmeasured**, because the build stops at the first failing target.
  ⚠️ The 2026-07-30 count of "7" still holds by luck — its *composition* changed (M24-T4 added one,
  `MicrophoneRescue` lost one).
  🔴 **Deferred, and recorded as deferred:** multi-display region capture (no second monitor) and
  cursor emphasis / auto-zoom (not wanted now). Both stay in docs/03's parked section with their
  triggers — the auto-zoom entry says out loud that taking it up is a second product identity, not a
  feature.

- **✅ G24 PASSED (2026-07-31) — M24 is complete, cut as v1.12.0.** Evidence in the gate table.
  🔴 **The gate earned its keep: criterion 1 failed on the first run.** `Export & Copy` had no key
  equivalent, so a chosen range could not reach the clipboard without a click — the two halves
  existed separately (T1 was one action with the mouse; T2 was mouse-free but whole-take). Fixed
  with ⌘↩ (`625488b`) and re-run. **A gate that only confirms what you already believe isn't one.**
  ⚠️ **The keyboard criteria are Franco's to run and always will be** — `LSUIElement` plus synthetic
  input cannot confer activation, checked three ways this session (docs/07).

- **✅ M24-T5 SHIPPED (2026-07-31) — M24's five tasks are all done.**
  A trim now **keeps its container** and the derive group is offered only where it applies.
  **660 tests** (654 → 660), dev loop green, deployed. Plan artifact:
  `claude.ai/code/artifact/3deb6330-efaa-4f0a-a06e-cc58a275562f`.
  ✅ **Headless verify, container proved with `mdls` rather than the extension:** `sample.mp4` →
  `sample trimmed.mp4`, **`kMDItemContentType = public.mpeg-4`**, 3.00 s `avc1` + AAC, passthrough.
  `.mov` regression → `com.apple.quicktime-movie`. A second trim gave `sample trimmed 2.mp4` — the
  stutter gone, the ` 2` being `availableURL`'s normal collision suffix.
  ✅ **The submenus, by `menudriver dump` before and after:** a `.gif` lost all three derive rows
  **and its divider**; an `.mp4` lost only `Export as MP4`, keeping `Save as GIF` and `Trim…`; a
  `.mov` is unchanged.
  🔴 **On a GIF those rows could only fail.** docs/03 called it "quietly re-encoding something
  already encoded" — true for `.mp4`, but `AVURLAsset` on a `.gif` reads **`isReadable false`, no
  video tracks, duration `-1`**, and `AVAssetExportSession` is **still created** for it, so the
  failure only ever surfaced once the export ran.
  🔴 **The `.mov` was our own hard-code and the comment defending it was false** — it claimed
  passthrough writes QuickTime "regardless of the input's extension"; `supportedFileTypes` reports
  **`mpeg-4`** for both presets. Fourth roadmap/code claim this milestone that didn't survive
  measurement (docs/07).

- **✅ M24-T4 SHIPPED (2026-07-31) — the Trim window can find a moment. Next: M24-T5, then G24.**
  The Trim window gained a **16-thumbnail filmstrip** that fills progressively, and **←/→ steps one
  real frame** (⇧ a second). **654 tests** (650 → 654), dev loop green, deployed. Plan artifact:
  `claude.ai/code/artifact/3f8024d7-d1e2-48a2-8f01-c9fd1151c05b`.
  ✅ **Verified:** the strip builds and renders — captured filling left-to-right, then 16/16 on the
  2:09 take. And the step mechanism is **exact**: five consecutive steps landed **0.000000 s** off
  the source's presentation times, and the backward step round-tripped exactly.
  ✅ **Both input paths confirmed live by Franco (2026-07-31)** — arrow navigation *and*
  click-to-seek, the half I could not reach. This app is `LSUIElement`, so `activate` leaves
  Terminal frontmost (checked) and every synthetic keystroke went to the wrong app; the
  window-scoped `NSEvent` monitor and the `SpatialTapGesture` both work in a real focused window.
  🔴 **Three findings, all measured, all in docs/07.** `AVPlayerItem.step(byCount:)` **does not step
  a frame on our recordings** — frame-on-change capture has no fixed cadence, and one step moved
  **0.25 s and landed 25 ms off any real frame**; the sample cursor lands exactly. A **bare arrow is
  not a key equivalent**, so `.keyboardShortcut(.leftArrow)` never fires and `AVPlayerView` scrubs
  instead (90 presses → 47.7 s); a scoped local `NSEvent` monitor takes them. And a strip's cost is
  **keyframe spacing × count, not take length** — the 270 s replay is 6× cheaper per thumbnail than
  the 129 s recording, so a 40-minute take costs what a two-minute one does.
  🔴 **docs/03's stated seams were wrong twice.** `VideoFrameReader` reads sequentially from zero and
  cannot build a strip; `AVPlayer.step` is on `AVPlayerItem` and is the wrong call anyway. Third time
  a roadmap parenthetical hasn't survived contact (after M23-T5's line counts).
  ⚠️ **A bug the live leg caught that the tests could not:** the strip keyed its callback lookup on
  the `Double` it asked for, but `AVAssetImageGenerator` reports the **quantised** `CMTime` —
  12.10406 s comes back as 12.10333. **Only 6 of 16 thumbnails ever appeared**, and the unit tests
  (which cover the time ladder, not the callback) were green throughout. Now keyed on `CMTimeValue`.

- **✅ M24-T3 SHIPPED (2026-07-31) — the take you just stopped has a row. Next: M24-T4.**
  `Recording saved · 0:22` sits first in the receipt group with the same `fileActions` submenu
  `Replay saved` has had since M9-T2. Titled by **length, not filename** — "identified by timestamp"
  is the finding, so repeating the timestamped name would have moved the problem. **650 tests**
  (644 → 650), dev loop green, plan artifact
  `claude.ai/code/artifact/08baa782-550f-4b91-8fdf-1b1e1384486b`.
  ✅ **Live, with Franco's replay armed** — the case where a stop is otherwise silent. A 22 s take
  through the menu → the row read **`Recording saved · 0:22`** with Reveal/Quick Look/Share/Copy
  under it; the flash measured **100 pt (recording clock) → 51 pt (idle + tick) → 39 pt** (M23-T3's
  exact signature), tick captured beside the armed badge; `Reveal in Finder` opened `~/Movies` with
  **that file selected**. Deleting the take made the row **vanish at the next menu open** — the
  expiry rule demonstrated live rather than only in a test.
  ✅ **Half of T3 was already done:** the flash ruling docs/03 filed was answered by M23-T3
  (`stopNeedsFlash` — armed only, since an ordinary stop already gets a banner). Left untouched and
  said so in the plan rather than re-litigated.
  ⚠️ **The receipt is not persisted, unlike the export's** — an export receipt is its file's *only*
  pointer (the `.mov`-only recents list can't show one), while a take already lives in
  `Recordings ▸`. So this row is prominence, not access, and expires on the same one-hour clock.
  🔴 **The assignment had to move to be testable at all.** It lived inside `start()`'s consume task,
  which no test can reach — M23-T3's trap exactly. Extracted as `finishTake(_:)`, which production
  and tests both run; **five breaks applied, five turned their tests red**.
  ⚠️ **Renamed `lastFinishedRecording` → `lastRecording`**; docs/03's M21-T2 seam pointer updated so
  the name stays greppable. `docs/history` left alone (unmaintained by contract).

- **✅ M24-T2 SHIPPED (2026-07-31) — the keyboard reaches the clipboard. Next: M24-T3.**
  The start/stop shortcut gained an ending: **`When it stops: Save · Save and copy`**
  (`stopHotkeyCopies`, absent ⇒ Save, so no existing install changes). **No new hotkey** — a picker
  under the existing shortcut, because `Save and copy` keeps the `.mov` too (ADR-004) and so loses
  nothing, costs zero Settings height while the shortcut is off, and adds no combo to clash.
  **644 tests** (641 → 644), dev loop green, plan artifact
  `claude.ai/code/artifact/1ab7e7d0-3e63-4c22-9d1c-a0bb88a42aa7`.
  ✅ **Live, fired from Terminal** (a global Carbon hotkey, so genuinely another app): ⌥⌘S started a
  take, and the recording menu showed the combo had **moved to `Stop & Copy MP4 · up to 1,5 MB
  [⌥⌘S]`** with `Stop & Save` carrying none. ⌥⌘S again → 22.06 s `avc1` 1920×1200 + AAC on the
  clipboard (sentinel replaced), the 4112×2570 hvc1 `.mov` kept beside it. **Busy-export leg, twice:**
  take saved, **no `.mp4` derived**, clipboard untouched, `Saved — the copy had to wait` delivered.
  🔴 **That notice was delivered and invisible.** Posted right after `stop()` returns — *before*
  `.finished` drains — so "Recording saved" replaced it **within 0.3 s**. Three runs sampling at
  0.3 s caught it **zero times**; `--print-delivered-notifications` had it every time. Now awaits
  `stopAndWaitForFinalize()`, so the exception posts last and is the banner left standing (docs/07).
  ✅ **RULED: two notices per stop is fine as it is (Franco, 2026-07-31).** The take's own
  `Recording saved · 0:22`, then `Copied — ⌘V to paste` ~8 s later. docs/03's Verify says "one
  notice" and it was flagged rather than silently changed; the behaviour is pre-existing (the menu's
  Stop & Copy MP4 has done this since M21-T2) and the two notices describe two different files
  arriving at two different times. **Don't "fix" this** — suppressing the save notice was offered
  and declined.
  🔴 **I toggled `Launch at login` off by accident** — a `checkbox 1` press landed on the General tab
  while Settings was still opening. Restored within seconds and verified re-registered. The driver
  now addresses controls **by label**; docs/07.
  ✅ **Settings restored and verified against `defaults read`:** `recordHotkey` absent,
  `stopHotkeyCopies` 0, `pauseHotkey` absent, `replayArmed` 0. All test files deleted, clipboard
  cleared.

- **✅ M24-T1 SHIPPED (2026-07-31) — the Trim window hands you the clip. Next: M24-T2.**
  `Export as MP4` is now **`Export & Copy`**: one press writes the ranged `.mp4` *and* leaves it on the
  pasteboard, ending the three moves (menu → receipt row → `Copy`) it used to cost. The change is one
  parameter — `ExportModel.exportAndCopy` gained `range:`, and every other seam already took one
  (`mp4Sibling(of:range:)` names the ` trimmed.mp4`, M23-T2's estimate is range-aware). **641 tests**
  (636 → 641), dev loop green, plan artifact
  `claude.ai/code/artifact/0d750213-d48e-4308-acd0-9b25bc3bac82`.
  ✅ **Live, through the deployed build.** A sentinel on the clipboard, `Trim…` on the 2:09 take,
  range 0:00–0:06, one press → the sentinel was **replaced by the clip's file URL**, and the file
  probes **6.53 s `avc1` 1920×1200 + AAC** out of a **129 s** source. The banner read
  **`Copied — ⌘V to paste`** (captured). No `.partial`, no new `.sb-`; the window dismissed; the
  receipt row expired itself when the test clip was deleted. Both clips cleaned up.
  ✅ **Rulings taken:** one button over a pair — the row has **39.5 pt of slack** and a fourth button
  needs **~112 pt** (measured off a capture, docs/07), so a second button would truncate titles or
  widen the window; and the title names the copy because the clipboard is taken either way. The
  notice is M21-T2's, reused.
  ⚠️ **Two findings for later, both in docs/07:** `exportToMP4`'s `range:` now has **no production
  caller** (TrimView was its only one) — left in place for M24-T5, delete it if M24 closes without
  one; and deriving from a derived file stutters its name (**`… trimmed trimmed.mp4`**), which is
  M24-T5's case arriving early. ⚠️ Also: **`menudriver click` takes the first match**, and with an
  export receipt row present that is not the row you meant — the second live run trimmed the *clip*.
  ⚠️ **Franco's clipboard was overwritten** by the leg (sentinel → clip URL → cleared). Unavoidable
  for this task; worth saying rather than leaving him to find it.

- **M23's per-task detail and the 2026-07-30 review are in `docs/history/2026-07-sessions.md`** (rotated 2026-07-31, when "Now" reached 313 lines). G23's evidence stays in the gate table below.

- **⚠️ Franco's current settings — do not "restore" these.** Instant replay is **ARMED**: he armed
  it himself on 2026-07-31 (`replayArmed` 1). ⚠️ **This entry said OFF until then, and it was
  right at the time** — an earlier session had re-armed it on a wrong inference and had to undo
  that, which is why the warning exists. Read the live value before acting on this line either way.
  `Ask for a name when a recording stops` is **off**; the start/stop and pause/resume shortcuts are
  **off** (`recordHotkey`/`pauseHotkey` absent) and `stopHotkeyCopies` is **0**; `Launch at login`
  is **on**; Source is **Entire Screen**. If a session changes any of them for a test leg, change
  it back and verify against `defaults read`.

- **🚫 M20 (Marks) CLOSED "won't do" (Franco, 2026-07-28); M20-T1's code was reverted.**
  🔴 The measurement that ended it: **a sparse extra track disables fragmented writing, and with it
  crash safety.** `AVAssetWriter` emits a fragment only when *every* input has data up to the
  boundary, so a chapter track fed once per mark starves it — mid-write, the only state a crash sees:
  no track → 3 `moof` atoms, track present → **0**. Same build, same `kill -9`: marks off recovered a
  playable 10.99 s file, marks on was unreadable. Sidecar `.json` worked but Franco won't have a
  companion file beside every recording; movie metadata can't be set after writing starts.
  **Don't re-file without a new mechanism.** The generalised trap — measure any new
  `MovieRecorder` track *while writing*, by counting `moof` atoms — is in docs/07.

- **Parked: two items, both deferred by Franco 2026-07-31** — multi-display region capture (he
  doesn't use a second monitor; trigger unchanged) and cursor emphasis / auto-zoom (behind ADR-015's
  render stage, kept on the list deliberately). ⚠️ **Read `docs/03`'s parked section, not this
  line** — this summary was lossy until today: it listed four items when docs/03 had six, and the
  two it dropped were crop on export (the one waiting on a ruling) and Swift 6.

- **Per-task session logs for M15–M22 live in `docs/history/2026-07-sessions.md`.** This file keeps
  current state, live decisions, the human-only list, and the gate table.

## Needs Franco (human-only items)

**Open:**


- [ ] **Display-sleep lever** (declined 2026-07-27 — "headless legs only"): two questions need
      `pmset displaysleepnow` while armed, which blanks the screen mid-session. Does
      `ReplayController`'s 5 s retry loop wake the display back up (02 §7 says SCK wakes a slept
      display to capture it — never measured together), and does the ring refill unaided after a real
      sleep/wake? UNMEASURED in docs/07 under M16-T1.
- [ ] **Monitor unplug mid-recording** — N/A on this hardware (built-in display only). Worth one run
      if an external display ever exists: it could report a code other than -3815, which would need a
      new `endReason` mapping (02 §7).
- [ ] **G4 §5.1 WATCH ②** (`Grant…` → `Open System Settings…` on the screen row) — reasoned and
      reviewed, never watched; only reachable on a fresh account. Catch it if convenient.

**Standing facts a session should not re-derive:**

- **TCC grants that make headless work possible:** the dev terminal holds Screen Recording +
  Microphone (2026-07-14), and **Terminal** holds Accessibility (2026-07-15) so `tools/menudriver.swift`
  can drive the menu. The grant is on Terminal, not on a "Claude Code" entry. The deployed `.app` has
  its own Screen Recording, Microphone and Notifications grants, which survive `bundle.sh` rebuilds
  (M0-T3's stable designated requirement).
- **The signing identity already exists:** self-signed `screenrec-dev`, trusted for codeSign in the
  login keychain. `devsign.sh` finds and uses it — it must never try to create another.
- **Settled by taste, don't churn:** the status-icon constants (12 frames / 2 s cycle, 0.45 alpha
  floor, `record.circle` / filled red / `circle.lefthalf.filled` amber — M4-T1), and Balanced quality
  (M2-T6: "balanced looks pretty good" on real busy content, ~2× Tier-1's efficiency).
- Closed human legs (M2–M6 gates, the granting sequence, the waived fresh-account and NLE checks)
  are in `docs/history/2026-07-sessions.md`; each gate's outcome is a row below.

## Gate status

| Gate | Status | Evidence |
|------|--------|----------|
| G24  | ✅ **passed 2026-07-31** | All four criteria re-run against **one release build** (`625488b`, deployed, signature valid). **A chosen range reaches the clipboard in one action without the mouse:** in the Trim window, ←/→ to navigate, `O` to set the out-point and **⌘↩** — driven entirely from the keyboard by Franco — replaced a `SENTINEL-G24` clipboard with `Recording 2026-07-28 at 17.19.30 trimmed.mp4`: **5.19 s out of a 129 s source**, `avc1` 1920×1200 + AAC, `kMDItemContentType = public.mpeg-4`, window dismissed, **one** notice (`Copied — ⌘V to paste`, delivered list). ⚠️ The button had **no key equivalent** until this run — the gate found it, and ⌘↩ was added before re-running (`625488b`). **The take you just recorded is actionable from the top of the menu:** a take stopped **while replay is armed** — the case that was silent on every channel — produced `Recording saved · 0:07` as the first receipt row with the full `fileActions` submenu. **The Trim window can find a moment without blind scrubbing:** 16/16 filmstrip thumbnails on the 2:09 take, first at ~80 ms; arrow stepping walks the **sample table** and lands **0.000000 s** off the source's presentation times (`AVPlayerItem.step(byCount:)` moved 0.25 s and missed every frame — docs/07); ←/→ and click-to-seek confirmed live by Franco. **Deriving from an export never silently re-encodes it:** the export receipt's submenu offers `Save as GIF` and `Trim…` but **no `Export as MP4`** (the source `.mov` keeps all three), and trimming that `.mp4` through the Trim window landed `… trimmed.mp4` at **`public.mpeg-4`**, passthrough — while a `.gif` row loses all three derives, because `AVURLAsset` cannot read one at all. **660 tests.** ⚠️ Method note: the keyboard legs are **Franco's** — `LSUIElement` plus synthetic input cannot confer activation, so no agent can press a key into this app (docs/07). |
| G23  | ✅ **passed 2026-07-30** | All four criteria re-run against **one release build** (`c7509ec`, deployed, signature valid). **A recording that cannot be written stops itself and keeps what it wrote:** 500 MB APFS image, ballast to ~20 MB, the take fills the rest → **`✓ finished (writeFailed)` at 27 s** leaving **26.03 s** playable (hvc1 4112×2570 + AAC). The pre-fix binary on the identical rig ran the **full 60 s** — 38 s of it after the writer was already dead — and offered nothing. **An export that cannot fit refuses before it starts and names the disk:** 15.2 MB free against a 34.7 MB export → `Not enough room to export / This needs about 35 MB and SCRECFIT has 16 MB free. The recording is untouched.`, with **zero bytes written** (no `.mp4`, no `.partial`, no `.sb-`) and no receipt row. **An export in flight is visible without opening the menu:** the top-trailing dot, captured with the export confirmed in flight; and **armed + exporting shows both dots** without collision, meter intact. **A take that stops while replay is armed is never silent:** the tick renders beside the armed badge (item 39 → 51 pt, back to 39 after the window) — ⚠️ **the first time that flash has ever appeared**, since M9-T3 shipped it as a second `Image` a `MenuBarExtra` never draws. **Both extracted models fail when broken:** **12 breaks applied, 12 turned red**, each naming `SessionModelTests`/`ExportModelTests` rather than `AppStateTests`; tree clean after. **636 tests.** ⚠️ Method note: the icon states are evidenced by **magnified capture, not pixel count** — pixel-diffing this menu bar is unreliable (docs/07). |
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
| G21  | ✅ **passed 2026-07-30** | All three criteria re-run against the **release build**, deployed. **(1) Stop to a pasteboard-ready `.mp4` in one action:** `Stop & Copy MP4` on a 6 s take put `Recording 2026-07-30 at 09.06.25.mp4` on the pasteboard **1.5 s** after the press, and ~/Movies gained exactly that `.mp4` and its `.mov` — **no `.partial`, no `.sb-`** (the one `.sb-` in the folder is a July 23 M14-T2 leftover, pre-dating the sweep). **(2) A named take carries its name everywhere:** naming on → `G21 acceptance take` typed at the prompt → **file** `G21 acceptance take.mov` + `.mp4`, **recents rows** `G21 acceptance take.mov — 0:06 · 3,6 MB` and `.mp4 — 0:06 · 3 MB`, **receipt** `Exported to MP4 · G21 acceptance take.mp4`, **pasteboard** `G21 acceptance take.mp4` — four surfaces, one name. **(3) An excluded app is absent while the rest of the system is present:** a 440 Hz −9 dBFS tone in QuickTime → excluding QuickTime gave **−∞ dBFS** over 672,360 samples; excluding a *silent* windowed app (Terminal) in the same breath gave **−9.0 dBFS** — so the exclusion removes its target and nothing else. ⚠️ **The first attempt at (3) nearly passed on nothing:** `afplay` was the "rest of the system" and read −∞ **even with no exclusion at all** — a windowless bare process SCK's tap doesn't carry (docs/02 §1a-ii; a minimised *app* is carried, so the rule is unestablished). Re-run with two windowed apps. **576 tests.** |
| G19  | ✅ **passed 2026-07-28** | All three surviving criteria re-run against the release build (T2/T3 were closed "won't do", so the folder-cap criterion is gone). **A volume that fills *during* the take stops the recording:** 4 GB APFS image, the **real 2 GB floor with no `--test-disk-floor`**, ~2 GiB of `dd` ballast landing 12 s into a 60 s take → free space crossed to 1.79 GiB → **`✓ finished (diskAlmostFull)` at 15.28 s** (~3 s after the crossing, 2 s poll) leaving a **playable 14.51 s** file (hvc1 4112×2570 + AAC). The same script on the pre-fix binary ran all 60 s and reported `userStopped` — the guard had never been able to see a disk fill (M19-T1, docs/07). **No window title reaches the plist:** picked a live Finder window through the menu → `captureWindow` = **`{bundleID = "com.apple.finder"; id = 3443;}`** and `defaults read <domain> \| grep -i title` returns **nothing**, in a session whose window list included a private-browsing window and a Slack channel by name. Restored to Entire Screen; the entry is removed with the pick. **The MP4 picker names what its sizes cost:** the deployed Settings row reads **`1920 px · ≈46 MB per minute`** (AX value), and a menu export of a 20 s take landed at **45.1 MB/min** against it. **539 tests.** |
| G18  | ✅ **passed 2026-07-28** | **The trim tells the truth about what it keeps** (criterion amended — the premise it was filed on was false): a lossless trim's first presented frame is **byte-identical** to the source at the in-point in AVFoundation *and* ffmpeg, while `ffprobe -ignore_editlist 1` shows **13.56 s inside a 10.00 s clip**; the window states `Starts exactly at 0:02 · keeps 0.8 s before it inside the file`, and a **re-encoding trim holds only the kept range** (edit-list segment `0.000..5.000`, 4112×2570 hvc1, both audio tracks — ADR-004 intact). **An MP4 export honours a chosen size:** the real Settings picker set to `Largest (3686 × 2304)` → persisted → menu export → **3686 × 2304, High, Level 5.2**, yuv420p + faststart; four CLI sizes measured at **L3.2 / L5.0 / L5.0 / L5.2**, none crossing the decoder ceiling. **The idle menu is materially shorter and no slower:** **20 → 17 rows** (32 → 23 worst case) by `menudriver dump`, every action still present, open time **0.57–0.60 s** against a **0.57–0.59 s** baseline (5 runs each). **The count-in is cancellable:** Esc during the beat returned to idle **twice in a row** with no file written and Start immediately reusable — via a bare-Esc Carbon hotkey, since the click-through overlay never becomes key and a global monitor would need a TCC grant this product has never required. **A region pick can be adjusted:** the overlay re-opened with `800 × 500 pt · 1600 × 1000 px` drawn, two ⇧→ moved it to **x 120** with the size untouched, ⌥⇧ resized to **810 × 510**, Esc discarded, a 956 × 543 drag snapped to **`1920 × 1080 px · snapped`**, and the adjusted region **recorded 1620 × 1020 px** (M11 unaffected). **No capture-path change:** `git diff v1.9.0..HEAD -- RecorderCore/Capture RecorderCore/Recording` is **empty**; a regression capture is 4112×2570 hvc1 + 2 audio tracks. Also in the milestone: Settings **1137 → 437 pt** (90% → 35% of usable height), and four small honesties (a bounded take states `Stops at 2:35 PM`, the disk row subtracts the fail-stop reserve, dead rows say so). **530 tests.** |
| G17  | ✅ **passed 2026-07-27** | **A window-scoped recording captures exactly the chosen window** — including the case per-app capture structurally cannot exclude: an overlapping window of the SAME app, in front, is absent from every checked frame (**0.000%** of its measured green) while the target fills **92.6%**, both via the CLI (T1) and menu-driven (T2). A whole-screen capture of the same moment reads **10.7%** — the positive control, without which a broken detector reads as a pass (it did once). **Dimensions:** `SCWindow.frame` × scale, titlebar included, no shadow gutter (900×528 pt → 1800×1056 px; TextEdit 586×476 → 1172×952). **Armed replay** scoped to a window: 10.93 s clip, 1800×1056, hvc1 + AAC. **Mid-recording resize and close behave as T1 measured:** a resize does not change the output size (SCK scales into the pinned buffer, frames uninterrupted at 20/s); a close ends the session with a playable file and an honest `windowClosed`, by both routes (a real app closing its window, and the app quitting). A minimised window delivers nothing and recovers unaided — no stream error, no StallWatchdog. **The pick never silently falls back:** a gone window fails loud, and a **reused id is refused** by the owner check (ids are not durable — measured 1498 → 1512 across an app relaunch); live, a relaunched TextEdit left the new window selectable and the stale pick `(closed)`. **The other three modes are unaffected, re-verified through the menu after T2:** whole-screen 4112×2570, `--app` 4112×2570 (display-sized per §1a), region 1600×1200. 495 tests. |
| G16  | ✅ **passed 2026-07-27** | **No stream misreports itself:** the deployed app's assertion reads `Instant replay is armed` (T1; the original "an armed Mac idle-sleeps" criterion was replaced by ADR-018 — measurement showed SCK's own audio tap keeps the Mac awake regardless of `SleepGuard`). **The armed cost is stated where it's chosen:** Settings caption + menu row, live on Franco's own settings — `4:30 buffer · ≈800 MB · Mac stays awake` (T2). **System audio off:** probe shows video + 1ch mic, **no empty track**; on: 3 tracks, no regression vs G2 §3.1; all-off: playable video-only (T3). **Muted mic:** exactly one notice at ~10 s, recording ran to completion, file playable with a full-length silent mic track; unmute → the paired recovery notice; control run → neither (T4). **Menu-bar level measurably tracks audio:** four distinct rendered states by pixel diff (0/89/153/189 px, all inside the meter's columns), and a live capture lit it and returned to the silent bitmap (T5). **Setup proves capture and names the build:** `✓ screen · 4112 × 2570 / ✓ system audio / ✓ microphone · AirPods Pro`, muted → `! microphone · silent`, None → `— microphone · not selected`, scratch cleaned, footers match `VERSION` (T6). **No regression in the other capture modes:** region → 1600×1200 3-track, app-scoped → display-sized 3-track; export/trim/GIF encode suites green in the release gate. 470 tests. |
| G15  | ✅ **passed 2026-07-24** | T1: `swift test` 20 runs green, none over 10 s (baseline 8/10 failed at ~123 s). T3: `kill -9` mid-export leaves nothing at the final name (A/B measured; before, a torn `.mp4` survived). T4: no stale comment or dead `EndReason` arm remains; 429 tests. T5: STATUS.md 2,769 → 237 lines, rotation verified lossless, all doc references resolve. T2 closed "won't do". |


## Where the rest lives

| What | Where |
|---|---|
| Measured platform behaviour and gotchas (the most re-read artefact here) | `docs/07-field-notes.md` |
| Closed session logs — M0–M22 per-task detail, the v1 status write-up, calibration tables | `docs/history/2026-07-sessions.md` |
| Per-task specs, rulings and tick boxes | `docs/03-milestones.md` |

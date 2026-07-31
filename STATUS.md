# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

- **✅ M26-T1 SHIPPED (2026-07-31) — the exporter takes a source rect. Next: M26-T2 (crop in the
  Trim window).** `--crop x,y,w,h` on `screenrec-cli export --to-mp4`, and a `crop:` parameter beside
  `range:` on `Exporter.exportToMP4`. **664 tests.** Plan artifact:
  `claude.ai/code/artifact/dd785060-1f81-488a-a763-48bf10ae9bbd`.
  ✅ **RULED (Franco, 2026-07-31): source pixels, not a fraction; the Size cap measures the cropped
  rect.** So a 3600×2200 crop capped at 1280 lands at **1280×782** — the crop's aspect, not the
  source's — and "≈46 MB per minute" stays true because the rate model sees what is really encoded.
  🔴 **The seam docs/03 named does not exist.** The MP4 path never had an `AVVideoComposition`: it
  declares a smaller size on the writer input and the *encoder* scales. The composition it meant is
  `VideoFrameReader`'s, one file over. **Measured before implementing** (docs/07): `420v` accepted so
  no BGRA round-trip, **one frame per source frame** so VFR survives, the transform's origin is
  **top-left**, crop and fit ride one transform. Cost: 2 s of 4112×2570 in 0.30–0.40 s against 0.91 s
  for the uncropped export of the same 2 s.
  ✅ **An uncropped export runs exactly the code it ran yesterday** — the composition branch is
  reached only when a crop is set, the discipline `range` already uses.
  ✅ **Three smaller calls, decided rather than drifted into:** an out-of-bounds crop is **refused,
  not clamped**; crop dimensions round **down** to even, so the fit never upscales; naming is
  unchanged, and a " cropped" suffix is T2's to decide.
  ✅ **The content leg has a negative control:** the exported pixels differ from the same rect cut out
  of a source frame by **0.36%** (tolerance 6), while the bottom-left reading differs by **29.86% at
  delta 255**. Without that control a wrong-but-plausible crop passes.
  🔴 **`loadTracks(withMediaType:)` segfaults from `RecorderCoreTests`** — deterministic, on any file,
  with no export code involved, while the same call from production is fine. It surfaces as
  `Exited with unexpected signal code 11` naming no test. Use `load(.tracks)` there (docs/07).
  ⚠️ **The VERSION bump is still pending** — 1.13.0 rides with T2, the first half a user of the app
  can reach, and M25's deferred patch rides in that cut.

- **✅ M26-T4 SHIPPED (2026-07-31) — a precise trim can crop too.** From Franco's question, *"why
  can't we trim and crop at the same time?"* The honest answer had two halves: **`Export & Copy`
  already does both** in one pass, and a **lossless** trim never can — it copies encoded frames and a
  crop must decode them. **Precise** mode already re-encodes through a composition, so a crop rides
  it and produces what the MP4 export can't: **the source's codec and scale, both audio tracks
  separate**. **673 tests.** Verified headlessly through the CLI (`trim --precise --crop`), unlike T2.
  🔴 **The measurement that shaped it, and it is a trap:** an `AVAssetExportSession` **honours** the
  composition's `frameDuration`, where the reader path (T1) ignores it. Hand-building one resampled a
  19.4 fps capture to a constant 60 and cost **2.9× the bytes**. Derive from
  `videoComposition(withPropertiesOf:)` — it carries `sourceTrackIDForFrameTiming` — then override
  only `renderSize`/`instructions` (docs/07).
  ✅ **One transform now serves both paths:** `CropComposition`, extracted from T1's exporter.
  ⚠️ **No plan artifact for this one** — Franco chose it from an option whose preview showed the
  states and the output, and the shape didn't move once measured.

- **✅ M26-T2's live leg PASSED (2026-07-31, Franco at the keyboard).** He cropped a 4112 × 2570 take
  in the Trim window and exported: `Recording 2026-07-28 at 17.19.30 trimmed.mp4`, **`avc1`
  1920 × 812**, 129.12 s, 56 MB, one export receipt in the menu. **The crop reached the encoder and
  the cap measured it** — an uncropped export of that take is 1920 × 1200, so the height followed the
  *crop's* aspect (2.36), not the source's (1.60). The source `.mov` still probes 4112 × 2570 /
  129.11 s. ⚠️ **One number still unconfirmed:** what the window's caption read at the moment he
  pressed it. The caption and the exporter both compute through `Exporter.fittedSize` from the same
  `crop` state, so they cannot disagree structurally — but "the window is honest" is the task's own
  criterion and deserves his eyes, not my inference.

- **🟡 M26-T2 BUILT (2026-07-31), awaiting Franco's live leg — then M26-T3.** The Trim window can
  draw a crop: tick **Crop**, drag on the preview, read `1600 × 1000 px at 400,300`, `Reset` clears
  it. **671 tests** (+6 `CropGeometry`, +1 wiring). `VERSION` → **1.13.0**, carrying M25's deferred
  patch. Dev loop green; **not yet deployed** — the running app is still 1.12.0.
  ✅ **Rulings, all as recommended in the artifact** (`claude.ai/code/artifact/1f4eb109-09a3-4cac-82b5-81f30da6a844`):
  drag only, no numeric fields; **no persistence** between opens; the caption quotes the **cropped**
  size live; **`Trim & Save` disabled while a crop is set**, saying why — a trim has no crop, so it
  could only ignore one.
  ⚠️ **Crop is a mode, not an always-on overlay** — `AVPlayerView`'s inline transport controls sit
  underneath one. Off by default, so the window is unchanged until asked.
  ✅ **The untestable part was made small:** `CropGeometry` (AppCore) is pure — drag rect in a
  letterboxed preview → source pixels — with a round-trip test and a drag-in-any-direction test.
  The crop is held in **source pixels** and converted back for drawing, never the reverse.
  ⚠️ **`PlayerObservers` gained `@unchecked Sendable`** with its confinement stated. The diagnostic
  was always true of that closure (a non-`Sendable` class captured in a `@Sendable` one) and my diff
  surfaced it; it is main-queue confined, which is what `startPlayheadObserver` already relies on.
  🔴 **Still Franco's:** deploy + drag + ⌘↩, then check the caption's size against `probe`.

- **🗓️ M26-T2 planned (2026-07-31) — four rulings, all taken.** Artifact:
  `claude.ai/code/artifact/1f4eb109-09a3-4cac-82b5-81f30da6a844`, with a real capture of today's Trim
  window (preview blanked — it held Franco's own recording) beside the proposal. **Recommended:** drag
  to draw with a live read-out and Reset, no numeric fields; the crop does **not** persist between
  opens; the caption quotes the **cropped** size live; and **`Trim & Save` goes quiet while a crop is
  set** and says why — a trim is `AVAssetExportSession`, it has no crop, and silently ignoring one is
  the lie this project keeps refusing. ⚠️ **Crop drawing has to be a mode:** `AVPlayerView`'s inline
  controls sit under any always-on overlay, so the toggle is off by default and today's window is
  unchanged until it's asked for.
  🔴 **The drag is a human leg** — synthetic input can't activate an `LSUIElement` app, and its
  windows sit behind everything (docs/07). ⚠️ **The Trim window I opened for the screenshot is still
  open** behind Discord/Slack — ⌘W it. A click I aimed at its close button landed in Discord.

- **✅ G25 PASSED (2026-07-31) — M25 complete. Swift 6 is on for everything that ships.** Evidence
  in the gate table. ✅ **RULED (Franco): no v1.12.1** — M25 has zero user-facing change, so there is
  nothing to download; the bump rides into **M26's cut**. `VERSION` stays **1.12.0**. Recorded in
  docs/03 too, so a later session doesn't "correct" it with a stray tag.
  **Next: Franco's call.** M26 (crop on export) is the natural one — it has a named user, a measured
  pain, and its ruling is already taken; M27 (Core Audio taps) and M28 (`NSMenu`) are the other two
  encoded milestones.

- **✅ M25-T3 SHIPPED (2026-07-31) — every shipping target compiles in Swift 6. M25 done; G25 next.**
  `RecorderCore`, `AppCore`, `ScreenRecApp`, `screenrec-cli` and `AppCoreTests` are all v6. **660
  tests**, release build and signed bundle green. Plan artifact:
  `claude.ai/code/artifact/884dad3b-36bf-4197-9ca0-27cd03c8fa4d`.
  ✅ **34 sites, and ~30 were one sentence:** these AppKit types were always main-actor-only and
  nothing said so. `@MainActor` on `RegionSelectionController` (19 sites alone), `ShareActions`,
  `QuickLookController`, `Relaunch`, `HotkeyCenter`, the meter's ticker. ⚠️ Unlike T1's
  `@preconcurrency`, this **adds** checking — a future background-thread caller now fails to compile.
  **No ripple into AppCore**, which was the risk the plan flagged.
  ✅ **The stragglers took real answers, two by reusing what exists:** `TrimView` now calls
  `MediaFile.dimensions` instead of loading tracks itself (deleting duplicated code); `OnboardingView`
  crosses the `Sendable` status enum, not `UNNotificationSettings`; QuickLook crosses only the `URL`;
  `CountInOverlay` uses `MainActor.assumeIsolated`, a pattern that file already had.
  🔴 **RULED (Franco): `RecorderCoreTests` stays at v5, documented in `Package.swift`.** Its 8 sites
  include three `DispatchGroup.wait(timeout:)` calls M15-T1 added **so a drain that never leaves
  fails instead of hanging**; Swift 6 bans blocking waits in async contexts. Against this project's
  two prior vacuous-test incidents, a uniform setting wasn't worth the risk.
  ⚠️ **G25's criterion was amended before being run**, not quietly passed: it asked for zero `.v5`.
  The amendment and its reason are in docs/03.
  ✅ **Live on the v6 build:** menu Ready and armed, the **region overlay opened full-screen and
  cancelled on Esc** (19 of the 34 sites, the least-exercised path), a 0:06 recording with its
  receipt row, and a menu export probing `avc1` 1920×1200 + AAC. Test files cleaned up; replay still
  armed. ⚠️ One screenshot of the overlay caught Franco's terminal content through the transparent
  region and was **deleted**, not kept as evidence.

- **✅ M25-T2 SHIPPED (2026-07-31) — `AppCore` compiles in Swift 6. Next: M25-T3.**
  Five explicit-`self` lines in the replay-save closure, plus two `nonisolated` keywords on a test
  fixture. **660 tests.** Verified live where it counts: a real replay save rendered
  **`Replay saved · 27 s`** — that row *is* the closure that changed.
  🔴 **`AppCore` cannot flip without `AppCoreTests`.** v6 mangles `@MainActor` into closure-property
  types, so the v5 test target failed to **link** — `symbol(s) not found` for `copyToPasteboard`,
  `notify`, `reportFailure`, `notifier`. ⚠️ It surfaces as a bare `error: fatalError` from
  `swift test`, which reads like a crash and isn't one (docs/07).
  🔴 **That flip breaks `@Test(arguments:)` on a `@MainActor` suite** — five declarations — because
  the macro evaluates the argument closure outside the actor. Fixed with `nonisolated` on the shared
  `endReasons` fixture. ✅ **RULED (Franco): the test edit is fine** — an isolation keyword, no
  assertion or fixture value touched. ⚠️ But **M25-T1's "no test edited" property does not carry
  forward**, by necessity rather than choice.
  ⚠️ **The cluster was a double `[weak self]`** — outer closure *and* inner `Task`. Both kept (the
  inner one stops the Task extending `AppState`'s lifetime across the hop) and made explicit; a
  future reader should not "simplify" it away.
  ⚠️ **Franco's replay disarmed itself during one redeploy and I re-armed it.** Not the Swift 6
  build: a clean quit+relaunch of the same binary kept it armed. It is the **known transient
  self-disarm** already recorded under G6 (bundle replaced mid-quit on a busy machine).

- **✅ M25-T1 SHIPPED (2026-07-31) — `RecorderCore` compiles in Swift 6. Next: M25-T2.**
  **660 tests, and no test file was edited** — that was the whole claim of a task whose point is
  that nothing changes except who checks the rules. Real capture (3 tracks, hvc1 4112×2570), ranged
  export and GIF all re-run, since three of the fixes are on the export path. Plan artifact:
  `claude.ai/code/artifact/c1efcd9e-316d-4867-b1a6-d4ed4393078a`.
  🔴 **The measured "7 sites" was a floor.** Fixing the first batch revealed **5 more** — 1 in
  `MicrophoneRescue`, 4 `SCStream` sites in `CaptureEngine` — for **12 sites, 8 edits**. The
  compiler stops after the first batch, so each fix unblocks the next wave. **T2's "5" and T3's
  "unmeasured" are floors too**, and both now say so in docs/03.
  🔴 **My plan was wrong about the mechanism, and the fix reversed twice.** I said I would not reach
  for `nonisolated(unsafe)` in `CaptureEngine`; it turned out **not to work there at all** — that
  diagnostic is region analysis on the *call's result*, not the binding's isolation. A narrow
  `@unchecked Sendable` box worked for `forCapture()`, then four `SCStream` sites appeared behind
  it. The real finding: **SCK carries no `Sendable` annotations at all**, so this was never one
  value needing an assertion.
  ✅ **RULED (Franco, 2026-07-31): `@preconcurrency import ScreenCaptureKit` in `CaptureEngine`** —
  one true statement about an un-annotated SDK, rather than hand-written hatches scattered through
  the capture path. ⚠️ It is file-wide, so future SCK-originated `Sendable` diagnostics there are
  warnings; **our own types stay fully checked**, which is the milestone's whole value.
  ✅ **The plan's per-site calls that survived contact:** `Exporter:411` was a real over-capture (the
  drain closure held the whole `TranscodePlan` for three values) and got a real fix;
  `ByteCountFormatter` is built per call rather than asserted safe — its thread-safety is
  undocumented, and the pinned strings (`"1,8 GB"`, `"900 MB"`) stayed green; `AVAudioFormat` took
  `nonisolated(unsafe)` because its immutability is real. `MicrophoneRescue` took **`sending`** —
  a genuine ownership hand-off, and the one fix that needed no concession at all.

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

- **M24's per-task detail and G24's run are in `docs/history/2026-07-sessions.md`** (rotated 2026-07-31). G24's evidence stays in the gate table below.

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
| G25  | ✅ **passed 2026-07-31** (criterion amended before the run — see below) | All criteria re-run against **one release build** (`e4a4372`, deployed, signature valid, plist 1.12.0). **Every shipping target builds and tests in Swift 6:** `RecorderCore`, `screenrec-cli`, `AppCore`, `ScreenRecApp` and `AppCoreTests` all `.v6`; **660 tests**, release build and signed bundle green. ⚠️ **The criterion was amended before being run, not after:** as filed it required *no `.v5` in `Package.swift`*. One remains — `RecorderCoreTests` — because converting it rewrites three `DispatchGroup.wait(timeout:)` calls that M15-T1 added **so a drain that never leaves fails the test instead of hanging it**, and this project has twice shipped tests that silently stopped testing (Franco's ruling; the reason sits beside the setting in `Package.swift`, so it reads as a decision). **A real recording, replay and export still work:** the **v6 CLI** captured **8.01 s, three tracks** (hvc1 4112×2570 + 2×AAC, 0 dropped frames); through the deployed app, a take produced `Recording saved · 0:06` and a menu export probed **`avc1` 1920×1200 + AAC**; a **replay save** rendered `Replay saved · 21 s` (20 MB) — the path whose closure T2 changed. **The region overlay** — 19 of T3's 34 sites and the least-exercised path — **opened full-screen and cancelled on Esc**. **Nothing changed except who checks the rules:** no behaviour change was found at any point, and T1 landed with **no test file edited at all**. ⚠️ T2 and T3 did edit tests, of necessity: flipping `AppCore` forces `AppCoreTests` (v6 mangles `@MainActor` into closure-property types, so a v5 test target fails to *link*), and that flip breaks `@Test(arguments:)` on a `@MainActor` suite. |
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

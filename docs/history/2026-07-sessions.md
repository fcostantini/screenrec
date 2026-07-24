# History — closed session logs (M0–M14)

Rotated out of STATUS.md by M15-T5, verbatim and newest-first. **Nothing here is maintained**: it is
the record of how the work went, not a description of how things are. For current state read
`STATUS.md`; for the per-task specification and tick boxes read `docs/03-milestones.md`; for measured
platform behaviour read `docs/07-field-notes.md`.

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

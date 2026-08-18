# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

- **✅ M37 COMPLETE and G37 PASSED (2026-08-18) — the windows behave like windows. 🚢 v1.20.0.**
  **821 tests** (807 → 821). Three tasks from Franco's own use of the app, all verified **headlessly**
  on the deployed build — the "needs Franco" legs turned out not to, since an AX probe reads
  `activationPolicy`, the app's `AXMenuBar` and the Window menu's rows. **MINOR as filed (ADR-013):**
  T1 is a capability the app never had. **Not released — not tagged, not pushed.**
  ✅ **T1:** `accessory` → `regular` → `accessory` with `menu bar: none` either side; a minimized Trim
  shows as **`◆Trim`** in Window ▸ and the row restores it; ⌘V pastes into `Rename…`.
  ✅ **T2:** at 1100 × 800 the picture goes **480 × 300 → ~905 × 535**; the size persists; shrinking
  clamps at **500 × 653**, the size it used to be fixed at.
  ✅ **T3:** crop ON, the window's `Play` moved the clock **0:00 → 0:02** where the same press moved
  the timeline by *nothing* before; `Pause` held at 0:11; no transport is drawn while cropping.
  🔴 **Two defects this milestone nearly shipped, both caught by looking rather than by tests.**
  A bar installed at launch made ⌘H live, and hiding the app with the region overlay open then refused
  **every later `Select Region…`** silently — found by the review, then reproduced and fixed. And T2's
  first build resized the window while `TrimView` still pinned its column to `.frame(width: 500)`, so
  the content sat stranded in a 500 pt strip — Franco caught that in one screenshot.
  🔴 **One claim of mine was simply wrong:** "ScreenRec would list itself in its own Source
  picker". `SourcesModel.refreshApps` has self-excluded since M7. Corrected in the plan artifact, the
  milestone and ADR-023; the code written for it was deleted.
  ⚠️ **Needs Franco:** whether to tag and release v1.20.0.

- **✅ M37-T2 DONE (2026-08-18) — the Trim window resizes and the preview grows with it.**
  **819 tests** (818 → 819). Measured on the deployed build: at 1100 × 800 the picture goes
  **480 × 300 → ~905 × 535**, the crop dim lands on the picture rather than the box, close/reopen
  restores 1100 × 800, and shrinking clamps at **500 × 653** — the size the window used to be fixed
  at. **Next: M37-T3** (playback reachable while cropping).
  🔴 **The style mask was never the ceiling.** `TrimView` pinned its column to
  `.frame(width: 500)`, so the first build resized the *window* and left the content stranded in a
  500 pt strip with dead space either side. Franco caught it in one screenshot; both the column and
  the preview follow the window now.
  ⚠️ **`.overlay` must precede the flexible `.frame`** or the crop dim covers the box instead of the
  picture — in 07.

- **✅ M37-T1 DONE (2026-08-18) — a window open now means a Dock icon, ⌘-Tab and a menu bar.**
  **818 tests** (807 → 818). Verified headlessly on the deployed build: 0 windows → `accessory`,
  `menu bar: none`; Settings open → `regular`, `Apple · ScreenRec · Edit · Window`, `✓ScreenRec
  Settings` listed by AppKit; Trim minimized → **`◆Trim`**, and the row restores it; ⌘V pastes into
  `Rename…`; last window closed → `accessory`, no bar. **Next: M37-T2.**
  🔴 **The bar is removed, not just undrawn — a live run proved it matters.** A menu answers
  its key equivalents whether or not macOS draws it, so ⌘H went live; hiding the app with the region
  overlay open then refused **every later `Select Region…`** silently. Fixed in `present()`, and
  re-measured.
  🔴 **My "ScreenRec would list itself" trap was wrong** — `SourcesModel.refreshApps` has
  self-excluded since M7. Corrected in the artifact, the milestone and ADR-023; the code written for
  it was deleted.
  ⚠️ **Not committed until this line says so** — see the commit below.

- **📋 M37 FILED from Franco's own use (2026-08-18) — three tasks, nothing implemented. Next: M37-T1.**
  Plan artifact: `claude.ai/code/artifact/d4c0110d-199a-4d3e-a26c-0e55768677ce`. A `docs:` commit — no
  code changed, no VERSION bump yet (**MINOR at the gate**, ADR-013: T1 is a capability, not a fix).
  🔴 **All three reports are the same window being less than a window.** Minimizing Trim is a
  **one-way door**: `LSUIElement` removes the Dock tile, the ⌘-Tab entry and the menu bar — every route
  back — and `WindowPresenter` hands out a minimize button anyway, with **no `deminiaturize` anywhere in
  the source**, so even re-picking the menu row can't recover it. Settings and Onboarding carry the same
  button.
  ✅ **Ruled by Franco before filing:** all three windows flip the activation policy (not Trim alone),
  and the Edit menu's ⌘V fix is folded into T1.
  ✅ **Measured on the deployed v1.19.0, same click at one fixed pixel:** crop **off** → play/pause
  0→1, clock 00:00→00:02; crop **on** → timeline **20.421912393162 s, unchanged to twelve digits**.
  The overlay eats the transport and keeps drawing it dimmed underneath.
  ⚠️ **What narrows T3:** crop mode is *not* fully dead — the filmstrip still seeks (measured) and the
  arrow keys still step, because both are the app's own, not `AVPlayerView`'s.
  ✅ **T2 is plumbing, not geometry:** `CropGeometry` already derives the video rect from the view size
  it is handed and holds the crop in **source pixels**, so resizing cannot drift a crop. The ceiling is
  `TrimView.previewSize = 480 × 300`, not the style mask. Franco's clip was **1920 × 790** → the video
  filled **480 × 197** of a 300-pt box.
  🔴 **The trap T1 named was already handled, and the real one was worse.** `SourcesModel
  .refreshApps` self-excludes before `recordableAppsFilter` runs, so the Source picker was never at
  risk — that claim is wrong in the plan artifact, the milestone and ADR-023, and is corrected in all
  three. What *is* real: **a menu bar answers its key equivalents whether or not macOS draws it**, so
  a bar installed at launch made ⌘H over the region-selection overlay hide that window without closing
  it, wedging `Select Region…` permanently. The bar is installed and removed with the Dock icon.
  ⚠️ **Needs Franco:** the T3 spacebar call (recommend button-only — space fights the focus ring), and
  T1's live legs (⌘-Tab, Window menu restore, Dock tile appearing/going, ⌘V in the Rename field).

- **📎 README demo GIF added (2026-08-07) — a `docs:` commit, no VERSION bump (ADR-013).**
  17.6 s, 720×684, 20 fps, 1.6 MB at `docs/assets/demo.gif`, shot against the deployed v1.19.0: menu
  opens → Instant Replay armed (cost row and all) → Start → the clock ticking in the bar → Stop & Save
  → `✓ Saved` **and** the banner. Plan artifact:
  `claude.ai/code/artifact/4724df6a-6eba-4626-8f26-10cde3bc5060`.
  🔴 **Found a real defect in `Save as GIF`, not fixed:** it stamps a uniform `1/fps` delay on
  every frame, but SCK only emits frames where the screen changed, so any recording of a mostly-still
  screen comes out **time-compressed** — this clip would have played **2.2× fast** (112 frames × 0.08 s
  = 8.96 s for a 19.70 s take). Worked around with an `ffmpeg -vf fps=20` constant-rate pass before the
  export. **Filed in 07 with a fix direction** (per-frame delays from presentation timestamps).
  ⚠️ **A stop while replay was armed DID raise its notification banner** — against docs/06's claim that
  macOS suppresses banners *whenever* replay is armed, since an armed stream holds the display
  captured. Both confirmations fired here, measured on macOS 15.6.1. **The claim appears in the M35-T2
  status-item row and in M5-T5's reasoning; it should be re-checked before anything else leans on it.**
  ⚠️ **Two planned beats were cut after measuring:** `Recordings ▸` is **503 pt wide, 23 rows** and
  lists real filenames; `Source ▸` reaches to x=1650, far enough left to pull other apps' menu-bar
  icons into frame. The clip stays in the root menu.

- **✅ M36 COMPLETE and G36 PASSED (2026-08-06) — the surfaces state facts, not configurations.**
  Three tasks from the UI/UX audit: the fourth banner caption, the armed row's real holding, and a cap
  on window titles. **807 tests** (791 → 807), **13 breaks applied, 12 red**. Evidence in the gate table.
  🚢 **v1.19.0 — MINOR (ADR-013)**, decided at the gate as the milestone said it would be: T2 put a
  figure in the menu that was never there. **Not yet released.**
  🔴 **What this milestone was for, in one line:** three surfaces stated a *configuration* as though it
  were a *fact* — what macOS would do, how much was buffered, what a window was called — and this app's
  whole distinguishing feature is that it doesn't do that.
  🔴 **T1 was a miss in M35, and the fix is a guard rather than a caption:** docs/06 said "three
  touches", M35 audited the enumeration, and a fourth surface asserted suppression unconditionally for a
  day. A test now scans the source instead of trusting a list.
  ⚠️ **The sweeps found four holes in my own tests before finding any in the code** — the single most
  useful thing that happened across the three tasks, and all four are recorded in the gate row.
  ⚠️ **Two audit findings deliberately still not filed** (the recents date repetition, the Trim
  window's closing prose) and one needing an ADR if ever wanted (release notes in the update row). The
  recents one is now the menu's widest row.

- **📋 UI/UX AUDIT FILED as M36 (2026-08-06) — three tasks. Next: M36-T1.** Artifact:
  `claude.ai/code/artifact/bfb2f778-4be2-4e2a-b982-95f32d50ef3e`. Every surface driven on the deployed
  v1.18.0: both menus, all four Settings panes, onboarding, Trim. **No code changed** — a `docs:` commit.
  🔴 **The two leading findings are the same failure twice: a surface stating a *configuration* as if it
  were a *fact*.** A Settings caption asserts that macOS hides banners **without asking** — false
  whenever the sharing toggle is on, i.e. on Franco's own machine — and the armed row asserts
  `2 min buffer` **without asking what is held**, which after a display-sleep death is near zero.
  🔴 **T1 is a miss in M35, and mine.** docs/06 records M12-T5 as "three touches"; M35 fixed those three
  and G35's "every surface" criterion was assessed against that enumeration rather than a `grep`. There
  is a fourth. **T1 therefore also adds a guard against enumeration drift**, not just the fix.
  ⚠️ **Filed PATCH, MINOR decided at the gate** (M30's precedent): T2 may land as a new figure in the
  menu, which is arguably a capability.
  ⚠️ **Three findings reviewed and NOT filed** (Franco): the recents date repetition, the Trim window's
  closing prose, and whether the update row could say what changed (needs an ADR-020 amendment). They
  live in the artifact; don't re-file without a ruling.
  ⚠️ **One thing deliberately not claimed:** the Trim window's two action buttons *read* as both being
  default-styled, but the code says only `Trim & Save` is — recorded as an impression, not a finding.
  ✅ **Two tooling improvements fell out of driving the app:** `alertdriver.swift` now matches
  `AXDescription` (SwiftUI buttons often carry no `AXTitle`) and presses radio buttons and checkboxes —
  which is what made Settings' other panes reachable headlessly at all.

- **▶️ STATE OF PLAY (2026-08-06): every milestone through M36 is complete and gated. No filed work.**
  Both audits' roadmaps are shipped: the 2026-08-05 code-health one (M30–M33) and the 2026-08-06 UI/UX
  one (M36), plus everything filed from the sessions between (M34, M35).
  🚢 **`VERSION` is `1.19.0` and NOT released** — `Scripts/release.sh` will cut it, and its changelog
  preflight passes because 1.19.0's notes are written.
  🚢 **v1.18.0 is CUT and PUBLISHED** (2026-08-06) — full gate, tagged, signed zip live at
  `github.com/fcostantini/screenrec/releases/tag/v1.18.0`. Its notes come from `CHANGELOG.md`, and the
  M32-T5 preflight has now gated two consecutive releases.
  ✅ **The display-sleep question is measured and closed** (docs/07): armed replay does **not** wake a
  slept display, and the ring refills unaided to its full cap. Nothing is owed to Franco but the two
  standing items below, neither blocking.
  ⚠️ **A last audit was 2026-08-05 and the tree has moved a lot since** — public repo, a network read,
  release tooling that depends on `CHANGELOG.md`, `AppShellTests` covering both menu states, and
  `ADR-022`'s private-preference read. A fresh review is the natural next generator of work.

- **M28–M33's per-task detail, and M34/M35's, are in `docs/history/2026-08-sessions.md`** (rotated 2026-08-06, when "Now" reached 607 lines). Their milestone summaries and **all** gate
  evidence stay below. Read the history only to answer "why did we".


- **✅ M35 COMPLETE and G35 PASSED (2026-08-06) — the replay save is visible without a settings
  dance.** Three tasks: the copy stops hedging, the flash becomes a word, and onboarding confirms the
  fix. **791 tests** (777 → 791), **14 breaks across the three, 14 red**. Evidence in the gate table.
  🚢 **v1.18.0 — MINOR (ADR-013): new user-facing capability.** Not yet released.
  🔴 **What this milestone was for, in one line:** the flagship feature's only confirmation was a
  1.5 px tick worth **4 %** of the status item, on a machine where macOS suppresses the notification
  that would otherwise say so — and the app hedged about that suppression because nobody had checked
  whether it was readable. It was.
  🔴 **`ADR-022` is the decision it rests on:** the app may read a private macOS preference to tell the
  truth, because a failed read degrades to the old hedge rather than to a claim.
  ⚠️ **Two things it does not claim:** the first-arm alert's new copy was never seen live (once-ever
  flag already spent here), and the live "it took" moment is **unobservable on one screen** — going to
  System Settings buries the window, so the confirmation lands on the next open.
  ⚠️ **Franco's own reservation, kept in the record:** he expected the onboarding tick to move rather
  than the sentence. Left as chosen; two lines to change.

- **✅ M34 COMPLETE and G34 PASSED (2026-08-06) — what happens while recording is tested now.** Four
  tasks, one of them closed as unnecessary: a spike that disproved the milestone's premise, the two
  menus asserted, and the silent guard made catchable. **777 tests** (769 → 777), and **not one
  production file changed** in the whole milestone. Evidence in the gate table.
  ⚠️ **`VERSION` stays 1.17.1 — nothing changed for a user**, so there is nothing to cut. M34 was
  filed PATCH on the assumption of a fix; like M29, it turned out to contain none.
  🔴 **What this milestone was for, in one line:** the defects M28 shipped and the guard M33-T3
  removed were unreachable by every test that existed; they are now one `swift test` away.
  ⚠️ **Two of its four tasks were filed on premises that were already false** — no test could build a
  `RecordingSession` (one had since M22-T2) and `finishTake` was unreachable (six tests reach it).
  Filed impossibilities deserve one grep.

- **M27's per-task detail, the v1.14.0 cut and G26's run are in `docs/history/2026-08-sessions.md`** (rotated 2026-08-04, when "Now" reached 264 lines). Gate evidence for G26–G28 stays in the gate table below.


- **M25's and M26's per-task detail, and G25's run, are in `docs/history/2026-07-sessions.md`** (rotated 2026-08-03, when "Now" reached 295 lines). Gate evidence for G25 and G26 stays in the gate table below. Per-task logs for M15–M24 are in the same file; per-task specs and tick boxes are in `docs/03-milestones.md`.

- **⚠️ Franco's settings are his — read them live, never "restore" them.** `replayArmed` moved three
  times on 2026-08-04 alone, all by him. **This entry deliberately no longer states its value**: an
  entry that names one invites the next session to correct reality to match the file, which is
  exactly the mistake made twice — the second time (M28-T1) by reading his own disarm as a known bug
  reproducing. `defaults read dev.fcostantini.screenrec.app <key>` is the only source of truth, and
  a value that changed while you weren't looking means **he changed it**.
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


## Needs Franco (human-only items)

**Open:**


- [x] **The replay-save confirmation — RULED and encoded as M35** (Franco, 2026-08-06): (b) the flash
      is the **floor**, (a) onboarding-verify is the **improvement on top**, and the honest-copy fix
      (M35-T1) lands regardless. What remains from you is **one toggle flip** per verify leg, not a
      decision.
      ✅ **The measurement is PAID (2026-08-06) — nothing is owed to you now but the choice.** The
      setting has **no public API** (13 `UNNotificationSettings` properties, none about mirroring) but
      **is readable**: `com.apple.ncprefs` → `dnd_prefs` → **`dndMirrored`**, and the toggle you see is
      `!dndMirrored` — measured by flipping it on your machine, banner present with it on and **absent
      at 1 s / 3 s / 6 s** with it off. **(a) is buildable with a real checkmark**, at the cost of a
      private undocumented key that degrades to today's hedged copy if it ever disappears.
      🔴 **(b) is the floor, not an alternative:** the notification is **delivered in both states**, so
      no app can ever learn whether a human saw it — the "did you see it?" self-test I expected to be
      the fallback **cannot exist**. ⚠️ **Cheap and independent of the ruling:** the copy can stop
      saying banners *"may"* be hidden and say whether they **will** be (~15 lines).

- [x] **G4 §5.4's folder-error leg — RUN 2026-08-06**, after being owed since 2026-07-15. Choosing an
      unwritable folder now provably renders the documented error, keeps `~/Movies`, and persists
      nothing. 🔴 **Desktop itself is writable for the deployed app** (accepted, `outputDirectory`
      became `~/Desktop`, restored at once), so §5.4's literal wording is untestable on this machine —
      the substitute is a `chmod 555` directory, and `chmod 000` tests nothing because the panel cannot
      even enter it. **The panel is drivable headlessly now** (docs/07 has the recipe); nothing here
      needs you.

- [x] **Display-sleep lever — MEASURED AND CLOSED 2026-08-06** (declined 2026-07-27, attempted and
      abandoned earlier the same day, then run properly with Franco away from the keyboard for 90 s).
      ✅ **Both questions answered.** The retry loop does **not** wake a slept display — 34 failed
      capture-start attempts, display dark throughout — because this Mac locks when the display sleeps,
      which is 02 §7's *locked AND slept ⇒ zero displays* row, so SCK cannot start a capture at all.
      And the ring **refills unaided**: +64 s after the wake it held **63.31 s**, +165 s it held the full
      **120.50 s** cap.
      🔴 **The one thing worth knowing: pre-sleep content is discarded** — the ring restarts empty, so
      "the last two minutes" after you return spans your return, never your absence.
      ⚠️ Unreachable on this machine unprompted (`displaysleep 0`); it is a recipient's scenario.
      Detail in docs/07.

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
| G36  | ✅ **passed 2026-08-06** — all three criteria; one break green with its reason recorded | Against the deployed build (`1.19.0`, signed). **Each of the three surfaces states a fact, proven by breaking it:** T1 **4 breaks, 4 red** (polarity, a failed read turned into a claim, the caveat shown when banners work, the once-ever flag spent on nothing); T2 **5 applied, 4 red**; T3 **4 breaks, 4 red**. 🔴 **The sweeps found more holes in my tests than in the code — three in T2, one in T3.** T2: a spy overrides `heldSeconds()` wholesale so the real max-of-rings policy had **no coverage** (extracted as a pure function and pinned); NaN could not exercise the `isFinite` guard because every NaN comparison is false (±infinity cases added); and my ring test passed for the wrong reason — `evictLocked`'s own `CMTimeCompare` **drops an invalid-pts entry**, so no NaN span can form. T3: with an `"ab "` pattern the cut landed on a letter and the space-dropping never ran (the title is built from the cap now). ⚠️ **One break stays GREEN deliberately and the test file says why:** `RingBuffer`'s NaN guard is unreachable through `append` for the eviction reason above. **The menu's widest row is bounded:** measured in *characters* (⚠️ `awk` counts bytes and `— ⠐ …` are 3 each) — **zero window rows over 56**, the previously-171-character row now exactly **56**, breaking on a word boundary. ⚠️ The widest row of *any* kind is now a recents row at 63, which is the date-repetition finding Franco reviewed and chose not to file. **A planted suppression claim fails a test:** the guard scans `Sources/` and requires every claim to sit in a file that reads the setting — and it caught its own false positive first (`MenuBuilder` calls `state.bannerVisibility()` without naming the type). **Observed live for all three:** the Instant Replay caption in both states *and rewriting itself across a flip with the window untouched*; the armed row climbing `0:03 → 0:26 → 0:35 → 0:44 of 2 min held` and then returning to `2 min buffer` when full; the capped window row in `menudriver dump`. **807 tests**, `swift build` **0 warnings**, release and signed bundle green. |
| G35  | ✅ **passed 2026-08-06** — all three criteria; ⚠️ two claims narrowed rather than waived | Against **one release build** (deployed, signed, `1.18.0`). **A save is unmistakable with no banner possible:** with the sharing toggle **off**, Franco watched a replay save and confirmed the menu bar's **`✓ Saved`** carries it — *"I saw it, and it feels fine"*. 🔴 **His one reservation is recorded, not buried: he expected the onboarding checkmark to move rather than the text**, which is the exact objection M35-T2/T3's plan raised against the option he chose; left as chosen, and switching is two lines. **Every surface states the actual state:** the armed menu row reads **`Notification banners are hidden while armed`** with the toggle off and **disappears entirely** with it on (both observed in the deployed app); the onboarding row rewrote itself from *"…including while replay is armed"* to *"Banners are hidden while replay is armed. Turn on …"* **while the window sat untouched**, on the 1 s poll that already existed. ⚠️ **The first-arm alert's copy was NOT seen live** — it fires once ever and `hasSeenReplayBannerWarning` is already true on this machine; unit-tested only, and stated rather than implied. **A failed read degrades to the hedge, proven by breaking it:** `unknown` reproduces the pre-M35 wording, and turning that branch into a claim turns `anUnreadableSettingKeepsTheHedge` / `everyUnreadableShapeIsUnknownRatherThanAGuess` red. **Measured, not eyeballed** (M4-T1): the confirmation occupies **~32 %** of the item's area against the armed baseline where the old tick occupied **4 %**, present within **0.4 s**, gone by **3.2 s**. **791 tests**, `swift build` **0 warnings**, release and signed bundle green. **14 breaks across the three tasks, 14 red.** 🔴 **The one thing the milestone could not deliver, stated plainly:** the live "it took" moment is **unobservable on a single screen** — going to System Settings is what buries the onboarding window — so in practice the confirmation is seen on the *next* open. A property of the flow, not of the row. |
| G34  | ✅ **passed 2026-08-06** — all three criteria; the third proven by git rather than by a dump, and the reason stated | **The recording and paused menus each fail a test when broken, proven by breaking them:** **6 breaks, 6 reds**, one per test — the pause branch inverted (`Pause` shown while paused), a source picker left visible mid-recording, the scoped-take row dropped, the active-mic row dropped, the update row made idle-only, and `Discard Recording…` hoisted next to the Stop rows. ⚠️ **One patch did not compile and the harness said so** — `INCONCLUSIVE`, not "not caught" — which is the M32-T4 field note's guard working on its first outing. **The silent guard M33-T3 removed is catchable:** re-adding `guard exports.exportInProgress == nil else { return }` to `stopAndShare` turns **`stopAndShareQueuesBehindARunningExportRatherThanDroppingIt`** red (`queuedExportCount → 0` vs `1`); M33-T3's own sweep left the suite green on this exact break. **`menudriver dump` is unchanged:** proven by `git diff b4f16f1..HEAD -- Sources/` being **empty** — the milestone changed **no production file at all**, so the menu cannot differ. ⚠️ **Deliberately not confirmed by a live dump:** with the production diff empty, a dump would confirm a tautology and would open Franco's menu to do it. The stronger claim (no production change) is the one M29-T2 also made. **777 tests** (769 → 777), `swift build` **0 warnings**, release and signed bundle green. ⚠️ **The limit, recorded in the test file rather than implied:** a never-started session has `recordedDuration` NaN, so the header row is asserted at `00:00:00 — Zero KB · HEVC` and the clock and byte count are **not** assertable at all. |
| G32  | ✅ **passed 2026-08-05** — all four criteria; ⚠️ the "behind" leg necessarily uses a temporarily-patched build, stated not hidden | Re-run against **one release build** (`16d744d`, deployed, v1.16.0, signature valid). **A decision is recorded:** `ADR-020` (a read is allowed, and its bounds) and `ADR-021` (the repo is public; signing and distribution unchanged; the notarization friction accepted knowingly). **A build behind the latest says so:** the deployed menu rendered **`1.16.0 is available  (disabled)`** immediately above `Settings…`. ⚠️ **Method note:** a current build cannot be behind, so this leg ran with `CoreInfo.version` temporarily faked to `1.0.0` and rebuilt — CLAUDE.md's patch-observe-revert — then reverted, redeployed and re-checked showing **no row**. **A current build says nothing:** 0 rows on the real build, which is also the common case. **An offline machine is indistinguishable from a current one:** with the endpoint pointed at an unroutable host so the request hangs to its full 10 s timeout, the menu carried **0 update rows** and **no error notification** — silence, not a failure surface. **The check never blocks anything, measured against that same hanging request:** the menu was answerable **0.9 s after launch** while the check still had ~9 s to run; a recording **started, ran and saved** (`5.09 s`, hvc1 4112×2570 + AAC) inside the hang window; and an export **started and completed** inside it too. **767 tests**, clean-scratch build **0 warnings**, release and signed bundle green. ⚠️ **The row is deliberately dimmed** — ADR-020 forbids downloading, so it is news rather than an action; making it open the Releases page is one line and was left as filed rather than widened unasked. |
| G33  | ✅ **passed 2026-08-05** — all four criteria against one release build; one element observed only by unit test, recorded not waived | Re-run against **one release build** (`a1ba0a4`, deployed, v1.15.1, signature valid). **Three exports requested in quick succession all land, in order:** three `.mp4`s written at **12:57:08 / :09 / :10** — one second apart, so they ran **sequentially**, and the single-runner invariant held while none was dropped. A second round produced four more (6 → 10 files). Before M33-T1 every request after the first was refused. **The derive rows stay enabled while an export runs** — visible in `menudriver dump`, and the whole point of the change. **Quitting waits for work in flight:** an export at **12%**, then Quit → the app took **24 s to exit** and the `.mp4` was on disk before it went. **An export can be produced without the microphone, proven by LEVEL not by track count** (G21's trap): on a real 15 s take with AirPods, music in a windowed app and speech throughout — ⚠️ **the control first**, both source tracks audible (system mean −32.4 / max **−12.5** dB; mic mean −32.0 / max **−8.0**) — the normal export peaks at **−8.0 = exactly the mic's peak**, and `--no-microphone` drops it to **−12.6** against the system's **−12.5** with the mean back to **−32.4** = the system's exact mean. **The voice is gone and the music is not**, which is the half a silence-everything bug would also have passed. **The default export is unchanged:** `h264 1280×800 + aac 2ch`. **749 tests**, clean-scratch build **0 warnings**, release and signed bundle green. ⚠️ **Not observed live, and unit-tested instead: the `· N waiting` row.** A `menudriver` round-trip takes ~2–3 s and the export window is shorter, so the backlog drains before the menu can be read — an **instrument limit, not a product gap**; the string is pinned by `MenuHeaderTests` and a break turns it red. ⚠️ **Also not test-reachable:** re-adding `stopAndShare`'s silent guard leaves the suite green (needs a real `RecordingSession` — the M23-T3 shape). |
| G30  | ✅ **passed 2026-08-05** — all six criteria against one release build; ⚠️ the criterion found a defect of its own before passing | Re-run against **one release build** (`36bbd60`, deployed, signature valid). **A clean-scratch `swift build` emits 0 warnings and 0 errors** — M30 opened with **5 sites and 48 warning lines**. **A muted take ended by a real stream death leaves no tap behind:** `finished (windowClosed)` → `✓ no system-audio tap survived`, against a control take stopped normally that reports the same on both binaries — and the **pre-fix** binary reported `✗ 1 tap device(s) still alive` on the identical command. ⚠️ The check must run **in-process**: the aggregate is `kAudioAggregateDeviceIsPrivateKey`, so no external scan can see the leak, and two other probes are unusable (docs/07). **The filmstrip fills and terminates:** 16 requested, 16 distinct indices, stream finished, bounded at 20 s so a regression fails rather than hangs; and `--crop detect` — a second consumer, on G26's path — still reports **3088 × 2314 at 512,128 → 1920×1438**, its recorded figures exactly. **Two launches leave one app:** a plain second `open -n` yielded (1 instance), one carrying `--relaunching` did not (2) — the branch that would otherwise strand a first-run user, since `Relaunch.now()` spawns its replacement deliberately. **The grant poll backs off** 1 s → 5 s past two minutes, both arms unit-tested. **739 tests**, release and signed bundle green. 🔴 **The gate caught a defect M30-T4 missed:** four comments in `StatusIconImage` still justified compositing by a `MenuBarExtra` constraint M28 deleted — T4's sweep grepped the removed *target* name and never the removed *API*. Fixed before the gate passed (`36bbd60`). ⚠️ **Two things are NOT claimed:** the end-to-end TCC grant→relaunch flow (it needs an ungranted state, i.e. revoking Franco's own grant), and that any unit test can catch the tap leak returning — it cannot, which is why `--audit-tap` ships as the standing instrument and the test file says so. |
| G29  | ✅ **passed 2026-08-04** — proven by breaking things, not asserted | **Every rule fails a test when broken: 18 breaks applied, 18 turned the named test red**, tree clean after each. Ten over the menu's structure (a row deleted, a checkmark dropped, a dimming removed, a group reordered, a view detached), five over the status item's rules, three over the row geometry. ⚠️ **The sweep caught a flaw in itself first:** one break left unbalanced braces, so the build failed and no test ran — which the harness reported as "nothing went red". A non-compiling break now raises instead of counting, because a broken build reading as a passing check is the exact shape of the problem the exercise exists to find. **Both of M28's real defects are re-introducible and red** — dropping the observation flag, dropping `autoresizingMask` — so the two that shipped and needed a reviewer would now fail `swift test`. **The menu never moved:** byte-identical dump across 199 rows at T1; **no production file changed at all** at T2 (a stronger claim than a matching dump); 198 rows identical at T3, the only difference being `Mute ▸` tracking what was playing. **The pulse still runs and still stops**, measured: 1 distinct bitmap in 6 samples while idle, **6 of 6** while recording. **728 tests**, release and signed bundle green (`44bc2c9`, deployed). ⚠️ **Two tests assert only that a flag is set** and say so in the file — they pin measured facts (the selection material matched AppKit's own to delta (0,0,0)) against silent removal, and cannot prove how anything looks. The screenshot stays that instrument. ⚠️ **The recording and paused menus are still not unit-reachable** — they need a real `RecordingSession` — so `menudriver dump` keeps a job rather than being retired. |
| G28  | ✅ **passed 2026-08-04** — all four criteria, the first banked at T2 before any new capability landed | **The menu does everything it did:** T2's `menudriver dump` was **byte-identical** to the SwiftUI build across **both layouts and four states** — idle (160 rows), idle+armed, recording and paused — with the only differences being live values (bytes written, the `Stop & Copy` figure) and the `Mute ▸` list tracking what was actually playing. Verified in three separate audio states. **A thumbnail on every recents row:** decoded 10% into each clip, cached until the file changes, and **the dump is still identical** — all 98 rows of `Recordings ▸` — because a view-based item keeps its `AXTitle`. **A progress row that advances while the menu is open:** one menu open, eight samples, **eight distinct values** (`Exporting… 2% → 26%`) read off `AXTitle` with the menu held open throughout; the percentage is in the title as well as the bar, so VoiceOver gets the same row. **A recents list longer than five that is still readable:** ten recordings and five exports under day headers, **98 → 138 rows accounted for exactly** (4 headers + 3 files × 12), the submenu measuring **503 × 472 pt with 788 pt of headroom** and opening in **0.40 s** against T3's 0.39–0.40. **707 tests**, release and signed bundle green (`e71d6e2`, deployed, signature valid, satisfies its designated requirement). ⚠️ **Two defects were found by looking, not by testing:** the recents chevrons did not line up (a row's view keeps its created width), and the hover highlight was the *table* blue — the menu's selection is a **vibrancy material**, measured to **delta (0, 0, 0)** once corrected. Neither is visible in a dump; the second was caught only because Franco asked what the highlight was. ⚠️ **`ScreenRecApp` has no test target**, so the status-item controller, the menu builder and both row views are covered by live probes and screenshots alone. |
| G27  | ✅ **passed 2026-08-03** — mechanism (CLI) and **the shipped app**, once `NSAudioCaptureUsageDescription` was added and granted: a menu-driven take carried the muted app at −67.7 dBFS and the rest at −12.2, full-length. ⚠️ An earlier app run recorded silence and an earlier gate attempt had a silent control; both are recorded above rather than waived | Re-run against **one release build** (`5ad0811`, deployed, signature valid, plist 1.13.0). **A windowless app's audio is absent while the rest of the system is present:** QuickTime playing a 440 Hz tone and **hidden — 0 on-screen windows**, the case SCK structurally cannot exclude, muted by bundle ID through the tap. Its tone reads **−18.3 dBFS in the control take and −70.8 dBFS in the muted one (52 dB down)**, while Franco's **Spotify — a real windowed app — survives in both** (peak −12.1 → −18.2, the difference being the removed tone). ⚠️ **The control is the load-bearing half:** an earlier run of this gate was **discarded, not counted**, because neither source was actually producing sound and a silent control proves nothing — the G21 trap. ⚠️ **Not `afplay`**, per the criterion. **687 tests**, dev loop clean. 🔴 **Caveat 1 — an open defect ahead of the milestone, not a gate failure:** a muted take on a **quiet** Mac lands with **no audio track at all**, because the tap only delivers when something plays where SCK always delivers silence. The file's shape depends on whether anything happened to be playing; Franco's ruling pending. 🔴 **Caveat 2 — unmeasured:** the aggregate device disappearing mid-take (AirPods connecting, a default-output change). Both were known before the run and neither is hidden by it. |
| G26  | ✅ **passed 2026-08-03** | All four criteria re-run against **one release build** (`74ac1dc`, deployed, signature valid, plist 1.13.0, replay still armed). **An export can be cropped from the Trim window and from the CLI:** Franco pressed `Find bars` on a real letterboxed take, took the rect it offered and ⌘↩ — `Recording 2026-08-03 at 10.22.08 trimmed.mp4`, **`avc1` 1920 × 1438**, `public.mpeg-4`; the CLI took an explicit rect the same day. **The output's dimensions are what the UI promised and the Size cap measures the crop:** the window's caption read **`H.264 1920 × 1438`** and `probe` reads exactly that; a CLI crop of 3600 × 2200 capped at 1280 lands **1280 × 782** — the *crop's* 1.636 aspect, not the source's 1.600 (uncropped, that take exports 1920 × 1200). **The original is untouched:** md5 identical before and after on every source used, and the letterboxed take still probes `hvc1` 4112 × 2570 / 10.04 s. **A letterboxed capture's bars are found without anyone typing a rectangle:** `--crop detect` returned **3088 × 2314 at 512,128** against a true 513/512 by independent column scan, and a column scan of the *exported* frames finds no flat edge left at all — the pillars are gone, not merely reported. **Four real negatives stayed silent** (two screen recordings, two music-video clips). **681 tests**, release and signed bundle green; no `.partial` or `.sb-` anywhere. ⚠️ **The sample is one capture, made for the gate:** a 16:9 video fullscreen on a 16:10 display, recorded headlessly by the CLI. It is real letterboxing with real compression and a real watermark inside the bar — and it broke the detector twice before it passed (docs/07) — but the calibration rests on one clip, not a corpus. |
| G25  | ✅ **passed 2026-07-31** (criterion amended before the run — see below) | All criteria re-run against **one release build** (`e4a4372`, deployed, signature valid, plist 1.12.0). **Every shipping target builds and tests in Swift 6:** `RecorderCore`, `screenrec-cli`, `AppCore`, `ScreenRecApp` and `AppCoreTests` all `.v6`; **660 tests**, release build and signed bundle green. ⚠️ **The criterion was amended before being run, not after:** as filed it required *no `.v5` in `Package.swift`*. One remains — `RecorderCoreTests` — because converting it rewrites three `DispatchGroup.wait(timeout:)` calls that M15-T1 added **so a drain that never leaves fails the test instead of hanging it**, and this project has twice shipped tests that silently stopped testing (Franco's ruling; the reason sits beside the setting in `Package.swift`, so it reads as a decision). **A real recording, replay and export still work:** the **v6 CLI** captured **8.01 s, three tracks** (hvc1 4112×2570 + 2×AAC, 0 dropped frames); through the deployed app, a take produced `Recording saved · 0:06` and a menu export probed **`avc1` 1920×1200 + AAC**; a **replay save** rendered `Replay saved · 21 s` (20 MB) — the path whose closure T2 changed. **The region overlay** — 19 of T3's 34 sites and the least-exercised path — **opened full-screen and cancelled on Esc**. **Nothing changed except who checks the rules:** no behaviour change was found at any point, and T1 landed with **no test file edited at all**. ⚠️ T2 and T3 did edit tests, of necessity: flipping `AppCore` forces `AppCoreTests` (v6 mangles `@MainActor` into closure-property types, so a v5 test target fails to *link*), and that flip breaks `@Test(arguments:)` on a `@MainActor` suite. |
| G24  | ✅ **passed 2026-07-31** | All four criteria re-run against **one release build** (`625488b`, deployed, signature valid). **A chosen range reaches the clipboard in one action without the mouse:** in the Trim window, ←/→ to navigate, `O` to set the out-point and **⌘↩** — driven entirely from the keyboard by Franco — replaced a `SENTINEL-G24` clipboard with `Recording 2026-07-28 at 17.19.30 trimmed.mp4`: **5.19 s out of a 129 s source**, `avc1` 1920×1200 + AAC, `kMDItemContentType = public.mpeg-4`, window dismissed, **one** notice (`Copied — ⌘V to paste`, delivered list). ⚠️ The button had **no key equivalent** until this run — the gate found it, and ⌘↩ was added before re-running (`625488b`). **The take you just recorded is actionable from the top of the menu:** a take stopped **while replay is armed** — the case that was silent on every channel — produced `Recording saved · 0:07` as the first receipt row with the full `fileActions` submenu. **The Trim window can find a moment without blind scrubbing:** 16/16 filmstrip thumbnails on the 2:09 take, first at ~80 ms; arrow stepping walks the **sample table** and lands **0.000000 s** off the source's presentation times (`AVPlayerItem.step(byCount:)` moved 0.25 s and missed every frame — docs/07); ←/→ and click-to-seek confirmed live by Franco. **Deriving from an export never silently re-encodes it:** the export receipt's submenu offers `Save as GIF` and `Trim…` but **no `Export as MP4`** (the source `.mov` keeps all three), and trimming that `.mp4` through the Trim window landed `… trimmed.mp4` at **`public.mpeg-4`**, passthrough — while a `.gif` row loses all three derives, because `AVURLAsset` cannot read one at all. **660 tests.** ⚠️ Method note: the keyboard legs are **Franco's** — `LSUIElement` plus synthetic input cannot confer activation, so no agent can press a key into this app (docs/07). |
| G23  | ✅ **passed 2026-07-30** | All four criteria re-run against **one release build** (`c7509ec`, deployed, signature valid). **A recording that cannot be written stops itself and keeps what it wrote:** 500 MB APFS image, ballast to ~20 MB, the take fills the rest → **`✓ finished (writeFailed)` at 27 s** leaving **26.03 s** playable (hvc1 4112×2570 + AAC). The pre-fix binary on the identical rig ran the **full 60 s** — 38 s of it after the writer was already dead — and offered nothing. **An export that cannot fit refuses before it starts and names the disk:** 15.2 MB free against a 34.7 MB export → `Not enough room to export / This needs about 35 MB and SCRECFIT has 16 MB free. The recording is untouched.`, with **zero bytes written** (no `.mp4`, no `.partial`, no `.sb-`) and no receipt row. **An export in flight is visible without opening the menu:** the top-trailing dot, captured with the export confirmed in flight; and **armed + exporting shows both dots** without collision, meter intact. **A take that stops while replay is armed is never silent:** the tick renders beside the armed badge (item 39 → 51 pt, back to 39 after the window) — ⚠️ **the first time that flash has ever appeared**, since M9-T3 shipped it as a second `Image` a `MenuBarExtra` never draws. **Both extracted models fail when broken:** **12 breaks applied, 12 turned red**, each naming `SessionModelTests`/`ExportModelTests` rather than `AppStateTests`; tree clean after. **636 tests.** ⚠️ Method note: the icon states are evidenced by **magnified capture, not pixel count** — pixel-diffing this menu bar is unreliable (docs/07). |
| G0   | ✅ passed 2026-07-14 | build+test(23)+bundle green; Identifier=dev.fcostantini.screenrec.app, Authority=screenrec-dev, designated requirement stable across rebuilds |
| M1   | ✅ complete 2026-07-14 | all 5 tasks done; capture engine + router + probe + sleep guard, 41 tests |
| G1   | ✅ passed 2026-07-14 | probe-stream: all 3 sources flowing. video 4112×2570 420v (PTS Δ 0.008–0.09s, frame-on-change); system audio 48kHz/2ch/32-bit (Δ 0.02s); mic native format device-dependent — AirPods 24kHz/1ch, built-in 48kHz/1ch (both differ from system audio → separate tracks required, M2) |
| G2   | ✅ passed 2026-07-14 | §3.1 tracks hvc1+2×aac ✅; §3.2 kill-9 ✅ (kill@6s→5.04s playable AFTER fragment fix 10s→1s — 10s was unparseable if killed <10s); §3.3 sync-clap ✅ (Franco); §3.4 static-tail ✅ (14s static→14.4s @7.9fps, tail patch holds); §3.5 30-min drift ✅ (Franco ran real 30-min record + beepflash; per-track dur match 50ms; flash↔beep offset constant ~−67ms±10 from min 5→29 = no drift) |
| G3   | ✅ **PASSED 2026-07-15** | §4.1 pause-math: scripted `rec10,pause5,rec10` (--no-mic). Calm box → 4 runs 19.86–19.98s, all ∈ [19.8,20.2], tracks match ≤40ms. Loaded box (post code-review workflow, load ~2.6) → mean 20.05s over 8 runs (25s wall→20s file ⇒ 5s pause exactly removed), 5/8 strictly in-window; the 3 outliers are load jitter (audio starvation stretches the video tail; a load-delayed resume frame), NOT pause-math error. All runs probe monotonic-clean. §4.2 mic-disappears ✅ PASSED 2026-07-15 (Franco, post-M3-T6, per the ADR-012 definition): AirPods cased at ~22s of a 60s run → CLI printed `⚠️ microphone disconnected — still recording` at ~25s (≈3.2s latency = 3s timeout + ≤1s poll), recording ran to the end, `finished (userStopped)`, file playable, mic track 21.82s vs video 59.83s. First run (pre-M3-T6) disproved the gate's premise — no takeover, buffers just stop → docs/02 §4 corrected, ADR-012 written. Also proved: a reconnected device NEVER resumes (mic gone for the session). §4.4 disk-guard ✅ PASSED: `--test-disk-floor 500000` (GB) vs 676 GiB free → `finished (diskAlmostFull)`, file playable (2.25s); negative verified on a real non-boot volume (4 GB HFS+ image, importantUsage reads 0 → records the full 8s, `userStopped`) after /code-review caught that the recommended capacity key reads 0 on every external volume. §4.1 cross-seam clap-sync ✅ (Franco — sync holds across the seam). §4.3 ✅ both ways in: display sleep (headless via `pmset`) → playable 3.3s, and lid-close/system sleep (Franco) → `finished (displayDisconnected)` + playable 11.2s file finalized on wake, confirming lid-close is the same -3815 and that `.systemSleep` is genuinely unreachable. §4.3 monitor-unplug N/A — built-in display only. |
| G4   | ✅ **PASSED 2026-07-16** (§5.4 fresh-account rerun waived by Franco); ✅ **§5.4's folder-error leg finally run 2026-08-06** — see the M4-T4 note in docs/03 | §5.2 ✅ headless: DR byte-identical across A→B rebuild + `--verify --strict` + rebuilt app `Ready` → menu-driven 19.43 s playable file, no re-grant. §5.3 ✅ headless (delivery) + ✅ live (Franco: banner renders + click reveals). §5.1 ✅ live (Franco: auto-relaunch on grant transition, forced the ungranted state). §5.4 ❌→**FIXED + verified** (unit + headless forced-failure integration: no wedge, clean "Couldn't write…"; preflight probes the real AVAssetWriter API → Desktop rejected at selection); the fresh-account end-to-end rerun was **discarded by Franco 2026-07-16** — the waiver, not a pass, is the record. |
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

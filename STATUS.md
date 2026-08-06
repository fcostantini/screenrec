# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

- **📋 M35 FILED (2026-08-06) — the replay save becomes visible without a settings dance. Next:
  M35-T1.** Franco's ruling on the audit's one parked finding, taken after the measurement rather than
  before it. Three tasks: the copy stops hedging (needs no ruling), the flash is promoted (**the
  floor** — it is the only signal for someone who never touches the setting), and onboarding verifies
  the toggle took (**the improvement**, buildable only because `dndMirrored` turned out readable).
  🔴 **T1's hard constraint is three states, not two:** allowed / suppressed / **unknown**. A private
  undocumented key can vanish in any macOS release, and a caveat row that confidently says the wrong
  thing is worse than one that hedges — so a failed read must degrade to today's copy.
  ⚠️ **What M35 needs from Franco: one 10-second toggle flip per verify leg** (T1 and T3 share it), and
  **a taste call on T2's shape**, which gets a plan artifact with the options shown rather than
  described. No fresh account required.

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

- **✅ M34-T1 + M34-T3 SHIPPED, M34-T2 CLOSED (2026-08-06) — the recording and paused menus are
  tests now.** **775 tests** (769 → 775), **no production file changed**.
  Spike artifact: `claude.ai/code/artifact/a79d6ebc-cec4-4008-b407-f00fe24cbffd`.
  🔴 **M34's premise was false, and a test in this repo had already disproved it.** The milestone says
  no test can build a `RecordingSession`; `SessionModelTests` has been building one since **M22-T2**.
  Everything needing SCK or the disk lives in `start()` — `CaptureEngine.init` makes no `SCStream`,
  `AVAssetWriter` makes no file until `startWriting()` (0 stray `.partial` files), `DiskSpaceMonitor`
  is timer-free. **An impossibility claim is worth one grep before it becomes a milestone.**
  🔴 **T2 is closed, not done: there is no seam to build.** `attach` and `apply` are already
  `internal`. The 10-member protocol was rejected for T2's *own* M22 reason — it cannot be narrowed to
  the two members `SessionModel` reads, because `AppState` reaches the rest through `session.capture`
  at 11 sites, so narrowing forces a second owner of one object. The backdoor was rejected as
  unnecessary.
  ✅ **6 tests, 6 breaks, 6 reds** — including **the update row proven to ride the recording menu**,
  the half of M32-T3's "shared tail" claim that had never been checked.
  ✅ **The sweep guard I added yesterday paid for itself on its first outing:** a patch that didn't
  compile was reported **INCONCLUSIVE** instead of the false "not caught" the M32-T4 harness printed.
  ⚠️ **The limit, written into the test file rather than left implied:** a never-started session has
  `recordedDuration` NaN, so the header row reads `00:00:00 — Zero KB · HEVC` and always will.
  Structure is assertable; the clock and byte count are not.
  ⚠️ **T4 is reachable but has a dependency:** `stopAndShare`'s tail calls `exportAndCopy`, a **real**
  export, so it must go through the injection seam M33's queue tests already use.

- **✅ M32-T5 SHIPPED (2026-08-05) — the release notes say what changed, and all 8 published releases
  are rewritten. Next: M34-T1 (the recording-path spike), or Franco's pick.** `CHANGELOG.md` is the
  source; `release.sh` no longer runs `git log`. **769 tests.**
  🔴 **The commit list is gone, not collapsed — Franco's call, and my plan was wrong.** I proposed a
  `<details>` block "for the audit trail"; the audit trail is **git**, which the tag already links, and
  a list that is only honest when unreadable does not belong on a page meant to be read.
  🔴 **Dropping it deleted the fallback, so two guards replace it:** a test pinning a **non-empty**
  `## <VERSION>` section (red when missing *and* when empty — both proven), and a **preflight in
  `release.sh`** that refuses the release beside the existing `CoreInfo.version` check — **before
  anything is tagged, pushed or uploaded**, so it cannot half-publish. Measured with `VERSION=9.9.9`.
  ✅ **All 8 rewritten and verified live: 0 commit-style lines across every published release**
  (v1.17.0 was 9 bullets, four of them `docs:`). The **Install block was byte-identical across all
  eight**, so the Gatekeeper *Open Anyway* steps survive untouched.
  ✅ **CLAUDE.md now asks a commit subject to name the user-visible effect**, not an internal noun
  (Franco's question). The `Mx-Ty:`/`docs:` prefixes stay — they map a commit to its task, which is a
  job release notes never had.
  ⚠️ **The copy came from docs/03's task lists, not from using the app.** Two entries are deliberate
  anticlimaxes (v1.10.2 "No user-facing changes"; v1.15.1's tap fix qualified to `Mute ▸`), and
  `CHANGELOG.md` covers the **8 published releases + 1.17.1 only** — 25 tags exist, the rest were never
  published, stated in the file so it doesn't read as an oversight.

- **✅ M32-T4 SHIPPED (2026-08-05) — the update row goes somewhere.** The row opened as news and closed as a door: `MenuRow.link` +
  `UpdateCheck.releasesPageURL`. Copy unchanged, Franco's call. **768 tests.**
  🚢 **v1.17.1 — PATCH (ADR-013): the row existed and now works.**
  ✅ **The click is proven, not inferred.** Patch-observe-revert with `CoreInfo.version` faked to
  1.0.0: the dump read **`1.17.0 is available` with no `(disabled)`** (M32-T3's read
  `1.16.0 is available  (disabled)`), and `menudriver click` put Firefox on
  **`github.com/fcostantini/screenrec/releases`**. Both controls hold — the real 1.17.1 build shows
  **no row** before and after, scaffolding reverted.
  ✅ **4 breaks, 4 reds — but only because the seam changed mid-task.** The plan's inline
  `NSWorkspace` closure made "the row opens the **wrong** page" uncatchable; `MenuRow.link` carries the
  URL on **`representedObject`**, so a wrong destination is now a red test. A closure is a black box
  and firing it opens a browser.
  🔴 **Two doc gaps closed that the task hadn't catalogued:** ADR-020 specified a **dimmed** row (so
  shipping a clickable one silently would contradict a ✅ ADR — amended), and **docs/06 never recorded
  this row at all** — M32-T3 shipped a menu row with no spec line, now item 11b.
  🔴 **The sweep found a crash-prone existing test:** the slot assertion indexed `after[index + 1]`, so
  a row moved to the end of the menu **killed the entire run** with `Fatal error: Index out of range`
  — 700+ results lost, nothing attributed. Now `dropFirst(index + 1).first`. Both this and a
  build-failure-read-as-green are in docs/07.
  ⚠️ **Franco's finding, and it is the real remaining gap: the destination is worse than the row was.**
  The Releases page is raw `git log` — `docs:` commits, task IDs, agent-facing subjects. **Filed as
  M32-T5**, including that `gh release edit` can fix the 7 already-published releases in place.
  ⚠️ **Asked and answered, not built: could the app do the download/install itself?** The fetch is
  ~30 lines and `Relaunch.now()` (M30-T5) is already the right seam — but **an unnotarized download
  gets quarantined**, so the recipient still hits *Open Anyway* and the feature buys nothing; the only
  way out is the app stripping Gatekeeper's flag off its own replacement. Gated on notarization
  ($99/yr, declined 2026-08-05), an ADR-020 reversal, and a path no test can reach without destroying
  the binary under test. **Not filed as a milestone** — say so if it should be.

- **📋 FOLLOW-UPS FILED (2026-08-05) — M32-T4 and M34; one parked. Next: Franco's pick.** None came
  from the audit; all three are things the work itself turned up.
  **M32-T4 — the update row goes somewhere.** It says `1.17.0 is available` and does nothing. 🔴 **The
  person M32 was built for is the one who cannot act on it** — handed a `.app`, no reason to know a
  repo exists. One line (`MenuRow.action` + `NSWorkspace.open`); ADR-020 forbids downloading, not
  linking. **G32 unaffected** — no criterion mentions the row's clickability.
  **M34 — what happens while recording is untested.** 🔴 **The largest untested surface left, and
  where the defects actually come from:** M28 shipped two that only *looking* caught, M29 recorded the
  recording/paused menus as its own remaining gap, M23-T3 made `finishTake` internal because no test
  could reach it, and M33-T3's sweep proved a **silent** `return` can be re-added with the suite still
  green. Everything downstream of `session.isActive` needs a real `RecordingSession`. **T1 is a spike**
  because the obvious seam — a protocol over `RecordingSession` — is a large surface invented for
  tests and used by one caller. ⚠️ **T2 touches gate-verified ownership**, and M22 is the precedent for
  how that goes wrong.
  **Parked — label the audio tracks at write time.** `--no-microphone` identifies the mic by channel
  count, which is an inference. 🔴 Its failure mode is **silent and inverted**: a contract change would
  strip the *system audio* instead. ⚠️ A label helps only new files, so both paths coexist until old
  ones age out. **Trigger:** the first time export-without-mic is used in anger.

- **✅ M32 COMPLETE and G32 PASSED (2026-08-05) — a build can tell it's out of date.** Three tasks:
  the ruling (`ADR-020`), the check, and a dimmed row with an off switch. **767 tests.** Evidence in
  the gate table.
  🚢 **v1.17.0 — MINOR (ADR-013): a new user-facing capability.**
  🔴 **The milestone changed the project, not just the app.** T2 was blocked because the releases API
  404s on a private repo — and because **recipients of a handed-over `.app` have no GitHub access at
  all**, so even a link 404s for them. Franco made the repo **public** (`ADR-021`), which also fired
  ADR-014's own revisit trigger and settled it: **the notarization friction is accepted, not paid
  for**, and the README now leads with the block rather than burying it.
  ⚠️ **What it deliberately does not do:** never downloads, never writes, never blocks — all three
  measured against a request hanging its full 10 s timeout — and it can be switched off entirely,
  which is the only honest answer to a daily request that reveals an IP.

- **✅ M32-T3 SHIPPED (2026-08-05) — a build says when it's behind, and you can tell it not to look.
  M32's three tasks are done; G32 is ready to run.** A dimmed row above `Settings…`, reading state the
  launch check left behind — the menu is stamped at open and must never wait on a network (M6-T10).
  **767 tests.**
  🔴 **ADR-020's deferred ruling is taken: the check has an off switch.** `Settings ▸ Check for new
  versions`, default on, and its caption names the cost rather than hiding it — *"the request tells
  GitHub your IP address — turn this off and the app makes no network requests at all."* Off means
  **no request**, not a discarded answer, and it clears a row already showing.
  ✅ **Both states seen in the deployed app:** current build → **no row**; then with `CoreInfo.version`
  temporarily faked to 1.0.0 (patch-observe-revert), the real menu rendered
  **`1.16.0 is available  (disabled)`** exactly where specified. Scaffolding reverted, real build
  redeployed and re-checked.
  ✅ **6 breaks, 6 reds.**
  ⚠️ **The row is dimmed, which is a real trade:** ADR-020 forbids downloading, so it is news rather
  than an action — you still go to Releases yourself. Making it *open* that page downloads nothing and
  is one line; **left as filed rather than widened without asking.**

- **✅ M32-T2 SHIPPED (2026-08-05) — a build can tell it's out of date. Next: M32-T3 (the menu row).**
  🔴 **The repo is now PUBLIC** (Franco, 2026-08-05) — recorded as **`ADR-021`**, which amends
  ADR-014's "never public". Signing and distribution are **unchanged**: still self-signed, still not
  notarized, still handed over directly or built from source.
  🔴 **Why it moved:** T2 was blocked because the releases API 404s on a private repo — and worse,
  **recipients of a handed-over `.app` have no GitHub access at all**, so even a link to the releases
  page 404s for them. Token (never), separate manifest, drop it, or go public: Franco went public.
  ✅ **Measured against the real list:** **7 releases**, this build (1.16.0) told **nothing**, and a
  recipient still on **1.7.0 is offered v1.16.0** — the case the milestone exists for. Live leg gated
  behind `SCREENREC_LIVE_UPDATE_CHECK=1`; the default run stays offline. **760 tests.**
  ✅ **Notarization SETTLED (Franco, 2026-08-05): the friction is accepted, not paid for.** Going
  public fired ADR-014's own revisit trigger — release zips are downloadable by anyone, and macOS
  blocks an unnotarized app until **Open Anyway**. Reviewed and kept: $99/yr buys convenience for
  strangers, not capability. ⚠️ **The obligation that creates is saying so plainly**, so README's
  install section now **leads with the block** instead of burying it, and its old framing —
  *"not public distribution"* — is gone. Every release's notes already carried the steps.
  ⚠️ **Pre-publication scan, so nobody re-runs it in a panic:** no credentials/keys/tokens in the tree
  **or the full history**; no window titles or channel names ever reached the docs (M19-T5's
  discipline held in prose too); the one email is Franco's own in docs/00, deliberate. ~61
  `claude.ai/code/artifact/…` links are public but unreadable — dead links, not leaks.
  ✅ **Cadence ruled and shipped: daily** (Franco, 2026-08-05) — launch-only was wrong for an
  `LSUIElement` that sits in the menu bar for days.

- **✅ M33 COMPLETE and G33 PASSED (2026-08-05) — the share loop stops refusing work it can do.**
  Three tasks: a queue so a second export waits instead of being dropped, a Settings toggle that
  leaves your narration out of shared clips, and the collapse of the arm that withheld a copy it can
  now queue. **749 tests** (743 → 749). Evidence in the gate table.
  🚢 **v1.16.0 — MINOR (ADR-013): two new user-facing capabilities.**
  🔴 **What this milestone was for, in one line:** every one of its three changes removed a place
  where the app refused to do something it was perfectly capable of, and said so instead.
  ⚠️ **Two things are unit-tested rather than observed live**, both recorded in the gate row: the
  `· N waiting` menu row (the export drains faster than a `menudriver` round-trip can read it), and
  `stopAndShare`'s guard removal (needs a real `RecordingSession`).

- **✅ M33-T3 SHIPPED (2026-08-05) — the shortcut stops withholding a copy it can now queue.**
  Franco's ruling. M24-T2's `stopWithoutCopy` arm existed only because a second export would be
  dropped; T1 removed that reason. **749 tests.**
  🔴 **The trap: collapsing the arm alone would have been worse than leaving it.** `stopAndShare()`
  carried its own `exportInProgress == nil` guard with a **silent** `return` — so removing the arm
  without removing that guard would have made the shortcut stop and say *nothing*, which is exactly
  what M24-T2 was built to prevent. Four sites moved together: the arm, its `isExporting` parameter,
  the silent guard, and the menu row's disabled state. `stopCopySkipped` is deleted, callerless.
  ⚠️ **One removal is not unit-reachable, and the sweep proved it** — re-adding `stopAndShare`'s
  silent guard leaves the suite green, because that path needs a real `RecordingSession` (the M23-T3
  shape). Covered by the type system and the live leg, not by a test.

- **✅ M33 COMPLETE (2026-08-05) — an export queue, and an export that can leave you out of it.**
  T1: a second export waits its turn instead of being refused. T2: `Include the microphone` in
  Settings, off leaves your narration out of shared clips. **748 tests.** ⚠️ **G33 not yet run** —
  the milestone's own gate still needs its pass.
  ✅ **T2's level check is PAID, not waived** — the one leg I flagged as owed. On a real 15 s take
  (AirPods, music playing, Franco talking): both source tracks audible first (**the control**), then
  the normal export peaks at **−8.0 dB = exactly the mic's peak**, and `--no-microphone` drops it to
  **−12.6** against the system track's **−12.5**, mean back to **−32.4** = the system's exact mean.
  **The voice is gone; the music is not.**
  ⚠️ **A null test was tried and does not discriminate** (−27.7 vs −29.6 dB): the export is
  re-encoded, resampled and mixed with its own gain, so it never nulls against a raw source track.
  Recorded so it isn't rebuilt.
  🔴 **Identifying the mic track is an INFERENCE** — nothing in the container records a role. Mono
  ⇒ mic (system is always stereo, 02 §1; mics are normalised to 48 kHz mono, M8-T1). A stereo mic is
  **kept** rather than guessed at. **Follow-up worth filing: label the tracks at write time.**
  ⚠️ **Still open, both Franco's:** M32's ADR ruling (is a network read acceptable?), and whether
  `stopWithoutCopy` should collapse now that a second export queues rather than being dropped.

- **🔴 M31 CLOSED "won't do" (2026-08-05) — the premise was false, and the fault was mine.
  Next: M32 or M33, Franco's pick.** No code shipped; the T2 implementation was written, measured to
  change nothing, and reverted.
  🔴 **Retracting the audit's D2 and M31-T1's "GO" in full.** Recordings and exports have carried
  correct `ITU_R_709_2` tags all along. The audit's probe looked up extension keys named
  `"ColorPrimaries"` / `"TransferFunction"` / `"YCbCrMatrix"`; the real keys are
  **`"CVImageBufferColorPrimaries"`** and friends. A wrong key returns nil, so it reported "absent"
  for **every** file — and read as a measurement rather than a bug.
  ✅ **Confirmed on takes made *before* any change, by two independent tools:** `ffprobe` reads
  `bt709,bt709,bt709` on the `.mov` and both `.mp4` exports, and a corrected extensions dump agrees.
  ✅ **Why it works unasked:** SCK stamps all three on every buffer and `AVAssetWriter` propagates
  them. An explicit `AVVideoColorPropertiesKey` is a **measured no-op**.
  🔴 **The lesson, and it is the expensive one:** my synthetic "reproduction" encoded a pixel buffer
  carrying no colour attachments, so it produced a genuinely untagged file — it looked like it
  reproduced production and never touched it. **A reproduction that agrees with a broken probe is
  worth less than either alone.** docs/07 has the trap; the `kCMFormatDescriptionExtension_*`
  constants are the fix.
  ⚠️ **What survives and is worth keeping:** SCK's `colorSpaceName`/`colorMatrix` are nil by default,
  setting them changes nothing, and they **trap on use** if read as `String`.

- **✅ M30 COMPLETE and G30 PASSED (2026-08-05) — the signals nobody was hearing.** Six tasks: a
  leaked Core Audio tap, a data race with a hang behind it, four warning sites closed or explained,
  five stale references, and two launch guards. **739 tests** (728 → 739). Evidence in the gate table.
  🚢 **v1.15.1 — PATCH (ADR-013): fixes, no new capability.**
  ✅ **The headline number: 5 warning sites and 48 warning lines → ZERO.**
  🔴 **What this milestone was for, in one line:** every defect in it was something the machine was
  already reporting — a compiler diagnostic, a resource never released, a comment describing a
  framework that had been deleted — and nothing was reading them.
  ⚠️ **Two claims deliberately not made:** no unit test can catch the tap leak returning
  (`--audit-tap` is the standing instrument, and `SystemAudioTapTests` says so), and the end-to-end
  TCC grant→relaunch flow was not re-run, because producing an ungranted state means revoking
  Franco's own grant.
  🔴 **The gate earned its keep:** it caught four `MenuBarExtra` comments M30-T4's own sweep missed —
  T4 grepped the removed *target* name and never the removed *API*.

- **✅ M30-T5 + M30-T6 SHIPPED (2026-08-05) — one instance, and a poll that stops. M30's six tasks
  are done; G30 is ready to run.** `LaunchPolicy` (pure, the `StatusItemPolicy` pattern — building an
  `AppDelegate` installs a status item). **739 tests.**
  ✅ **T5's trap was the whole task, and both branches are proven against the deployed app.**
  `Relaunch.now()` runs `open -n`, which spawns a second copy **deliberately** and terminates the
  first only afterwards — so a naive guard would kill the replacement and strand a first-run user at
  onboarding the instant they granted Screen Recording. The relaunch carries `--relaunching`, and a
  copy holding it never yields. Measured with **Franco's own running instance as the incumbent,
  untouched throughout**: a plain `open -n` **yielded** (1 instance, still his pid), one with the flag
  **did not** (2), and only the copy this task created was killed.
  ✅ **T6 backs off rather than giving up** — 1 s for the first two minutes, 5 s after. Stopping
  entirely would mean a grant made later never relaunches, which is the flow the loop exists for; and
  G4 §5.1's immediate transition survives, because the fast window covers the whole time a first-run
  user is actually in it.
  ⚠️ **Neither T5's nor T6's end-to-end TCC leg was re-run, and neither is claimed.** Both need an
  ungranted state, which can only be produced by revoking Franco's own Screen Recording grant. What is
  proven is the discriminating half — a `--relaunching` copy survives the guard — which is the only
  thing these changes could have broken.
  ✅ **6 breaks, 6 reds** across the two tasks, including the relaunch trap.

- **✅ M30-T4 SHIPPED (2026-08-05) — the tree builds with ZERO warnings.**
  `capture.router` replaces the force-unwrap; the orphaned doc comment is gone; `LoginItem` names
  `AppShell`; `WindowPresenter` names `AppDelegate.init` / `.state` instead of `ScreenRecApp.init`
  and a SwiftUI `@State` M28 deleted; README reads **M0–M29**.
  ✅ **A full clean-scratch `swift build` emits 0 warnings and 0 errors.** M30 opened with **5 sites
  and 48 warning lines**. **733 tests**, release and signed bundle green, encode suites green one per
  invocation.
  ⚠️ **A fifth stale reference the task hadn't catalogued** — `WindowPresenter` also named
  `AppDelegate.appState`, which is `AppDelegate.state`. The grep that found the others searched for a
  *target* name; this was a *member* name, and only reading the line caught it.
  ⚠️ **No `VERSION` bump yet.** M30 is filed PATCH and T1/T2 are real fixes, so one is owed — but it
  belongs with G30, not mid-milestone (T5/T6 outstanding).

- **✅ M30-T3 SHIPPED (2026-08-05) — the warnings are closed or explained, one each.**
  Three sites, three answers, **no blanket `@preconcurrency import`**. **733 tests.** Plan artifact:
  `claude.ai/code/artifact/822e8092-b2cd-44ab-8bc6-ffe5ea86df66`.
  ✅ **One of them was a real fix, not a suppression.** `ReplayEncoder` was handing a whole
  `CMSampleBuffer` to `setupQueue` when bring-up reads only the format description — and SCK's
  IOSurface pool is `queueDepth` **(5)** deep, so that held one of five surfaces for the length of VT
  session creation, on the first frame of every arm. It passes `CMFormatDescription` now (measured
  **Sendable** in this SDK), so the warning goes by removing what it warned about.
  ✅ **`WriterDrain` keeps its invariant written down instead** — the block only ever runs on its
  serial queue — and `RecordingFileSentinel` drops the deprecated `String(cString:)`.
  ✅ **The bar is met: 1 warning site left, `AppState.swift:770`, which is T4's.** M30 opened with
  five.
  ✅ **Behaviour unchanged where it could have moved:** headless `replay-arm` → ring filled (10 kf,
  25 MB), save in **0.06 s** → `hvc1 4112×2570 + AAC, 8.26 s`.
  🔴 **Correction to the M30-T1 and M30-T2 entries below.** Both quote
  `SCREENREC_HW_ENCODE_TESTS=1 swift test` — the **whole suite at once** — as a green check. That
  form is the documented VT-oversubscription trap: it failed **2 of 2** today with 13 issues in 122 s,
  and **fails identically on an unmodified tree** (established by A/B, not assumed). Those runs
  passing was luck, not evidence. **The real check is one suite per invocation**, which
  `Scripts/hooks/pre-push` and `release.sh` already do — and all six affected suites pass that way.
  docs/07 has the detail.

- **✅ M30-T2 SHIPPED (2026-08-05) — the filmstrip's counter cannot lose a decrement.**
  `OSAllocatedUnfairLock<Int>` makes decrement-and-test one operation. **733 tests** (+1). Plan
  artifact: `claude.ai/code/artifact/9d40deee-65c0-47a4-bb1e-215e6aede97b`.
  🔴 **The task I filed was wrong about the blast radius:** `FilmstripThumbnails.stream` has **three**
  consumers, not just the Trim window — `BarDetector` via `--crop detect` is **on G26's verified
  path**, and `MenuThumbnails` is structurally immune (one thumbnail ⇒ one callback).
  ✅ **All three legs headless, so your desktop wasn't touched:** warnings gone from a clean-scratch
  build (**5 sites → 4**, the rest T3/T4's); a new gated test asks for 16, gets 16 distinct indices
  **and terminates**; `--crop detect` on the G26 sample still reports **3088 × 2314 at 512,128 →
  1920×1438**, its recorded figures exactly, source md5 unchanged.
  ⚠️ **2 of 3 breaks red, third green for a stated reason** — reverting the fix outright can't be
  caught, since nothing forces two callbacks to collide. 🔴 My first version of that third break was
  invalid (added a dead variable rather than reverting); redone properly before believing it.
  ⚠️ **The incremental-warning trap bit again** (M28-T3 recorded it): a second `swift build` against
  an already-populated scratch path re-emits nothing, which briefly read as "zero warnings
  everywhere". One clean build per inventory, or the number is fiction.
  ⚠️ **`OSAllocatedUnfairLock` is new here** — 24 `NSLock`s and none of these. Picked for
  correct-by-construction over idiom-consistency; the `NSLock` alternative is a 2-minute swap.

- **✅ M30-T1 SHIPPED (2026-08-05) — a terminated engine leaves no tap behind.**
  The teardown moved **into `cancelWatchdogs()`** — the one site both `stop()` and `terminate()`
  already call — rather than being copied into `terminate()`, plus `SystemAudioTap.deinit` for an
  engine released without terminating. **732 tests** (+4). Plan artifact:
  `claude.ai/code/artifact/162a0804-cadf-4585-9c4b-eac2e3cffb2f`.
  ✅ **Reproduced, then absent, same command on both binaries:** a window-close stream death
  (`finished (windowClosed)`) with `--mute-app` → **pre-fix `✗ 1 tap device(s) still alive`, post-fix
  `✓ none survived`**. ⚠️ **The control carries the claim:** a normally-stopped muted take reports
  none on *both* binaries, so the check isn't simply always clean.
  🔴 **The instrument nearly wasn't built.** The first probe said a private aggregate isn't
  enumerable in-process; that was a **false negative from a racy HAL cache** (3/5 without a settle
  delay, 5/5 with 0.5 s), and a weaker fallback was nearly adopted on that one run. Two other probes
  are genuinely unusable — see docs/07.
  ⚠️ **2 of 3 breaks go red, and the third is the point:** re-introducing the defect itself stays
  **green**, because no unit test can reach it. `screenrec-cli --audit-tap` ships as the standing
  instrument, and the test file says so rather than implying coverage it lacks.
  🔴 **My own error, cost real work:** the first break-sweep harness used `git checkout --` to
  restore, which reverted to **HEAD** and destroyed uncommitted edits — and detected "red" by
  grepping `✘`, which swift-testing also prints for **skipped** tests, so its first result was a
  false positive. Both fixed (scratchpad backups; classify on the `Test run with N tests failed`
  summary line). Worth knowing before writing the next sweep.

- **📋 AUDIT FILED (2026-08-05) — M30–M33 are the roadmap. Next: M30-T1.** A full read of the tree
  (code health + product), filed as four milestones in `docs/03`. Artifact:
  `claude.ai/code/artifact/5faea78f-6d9f-42f7-936e-8e1d6ad00c17`. **No code changed** — this is a
  `docs:` commit.
  ✅ **What held, checked rather than assumed:** module boundaries (RecorderCore/AppCore import no
  AppKit or SwiftUI, by grep), **zero** TODO/FIXME/HACK/XXX in Sources+tools+Scripts, Swift 6 on every
  shipping target, 728 tests green in **2.50 s** (3.07 s with `SCREENREC_HW_ENCODE_TESTS=1`), one
  stray `!` in 16,784 lines.
  🔴 **The two that cost something.** **(1) `CaptureEngine.terminate()` never stops the system-audio
  tap** and `SystemAudioTap` has no `deinit`, so any stream death that isn't a user Stop leaks a live
  process tap, a private aggregate device and two timers — reachable only with `Mute ▸` set, which is
  why G27 couldn't see it. **(2) Nothing sets colour tags anywhere:** three real files in `~/Movies`
  probe `ColorPrimaries=— TransferFunction=— YCbCrMatrix=—` on both `hvc1` and `avc1`, so every player
  guesses — and that lands on the `.mp4` share path ADR-016 exists for. Colour appears in **no** doc,
  field note or gate: an unexamined axis, not an accepted trade.
  ⚠️ **"One known warning" is five.** A clean-scratch build emits 10 lines over 5 sites; three are
  Swift 6 data-race **errors** downgraded because their types cross AVFoundation — i.e. where the
  compiler stopped checking docs/01 and said so. `FilmstripThumbnails:55/56` is a real race with a
  hang behind it.
  ⚠️ **`swift test` prints "728 tests passed" with 8 of them skipped** — the encode suites are gated
  behind `SCREENREC_HW_ENCODE_TESTS=1`. The pre-push hook and `release.sh` both run them, so nothing
  ships unverified, but the headline number is 720 in a normal loop.
  ✅ **The parked list was reviewed and endorsed unchanged** — nothing on this roadmap crosses
  ADR-015's line.

- **✅ M29 COMPLETE and G29 PASSED (2026-08-04) — the menu is testable, and the tests can fail.**
  Three tasks: a library target the menu code lives in, its structure asserted in-process, and the
  decisions that broke in M28 extracted from the widget that made them untestable. **728 tests**
  (707 → 728). Evidence in the gate table.
  ✅ **18 breaks, 18 reds**, including **both of M28's real defects put back**.
  🔴 **What this milestone was for, in one line:** the two defects M28 shipped were unreachable by
  every test that existed. They are now one `swift test` away.
  ⚠️ **`VERSION` stays 1.15.0 — nothing changed for a user**, so there is nothing to cut. The
  milestone was filed PATCH on the assumption of a fix; it turned out to contain none.
  ⚠️ **Still not unit-reachable: the recording and paused menus** (they need a real
  `RecordingSession`), and **how anything looks**. Both keep their existing instruments.

- **✅ M29-T2 SHIPPED (2026-08-04) — the menu's shape is now a test, not a deployment. Next: M29-T3.**
  11 tests build the real menu from a real `AppState` and assert it. **719 tests**, **no production
  file changed**. Plan artifact: `claude.ai/code/artifact/22a2996c-713d-4a87-9c2e-c050d6838ae7`.
  ✅ **10 breaks applied, 10 turned the named test red** — the only evidence that distinguishes a
  test from a decoration.
  ✅ **Ruled (Franco): these sit beside `menudriver dump`, they don't replace it.** The tests cannot
  reach the **recording or paused** menus — those need a real `RecordingSession` — so the dump keeps
  a job. ⚠️ `apply(.started)` moves the icon but not the session; a test written against it would
  have asserted the idle menu and passed.
  🔴 **Three defects the review caught, all mine:** a header assertion that read **live TCC** (green
  here, red on any ungranted machine), a predicate satisfied by a *filename*, and **256 stray
  preference plists** — the exact leak `TestDefaults` exists to prevent. Swept, and a run now leaves
  zero.

- **✅ M29-T1 SHIPPED (2026-08-04) — the menu code finally lives somewhere a test can reach.
  Next: M29-T2.** `Sources/ScreenRecApp` was an executable target, which SPM cannot link into a test
  target; its 17 files moved verbatim into an **`AppShell` library**, leaving `main.swift` plus the
  bundle's `Resources/`. **708 tests.** Plan artifact:
  `claude.ai/code/artifact/0ca0e2be-82a6-40b9-8ad7-61f3f7bf530b`.
  ✅ **Nothing moved but the files:** dump **byte-identical across 199 rows**, and
  `Scripts/bundle.sh` needed **no edit** — the product keeps its name, the payload stayed put.
  ✅ **One `public` symbol in the whole module** (`ScreenRec.run()`), verified by grep. `AppDelegate`
  moved too: leaving it in the executable would have forced a dozen types `public` to wire it.
  ✅ **The point, demonstrated:** `MenuBuilder.rows()` is asserted **in-process** — no app deployed,
  no menu open, no Accessibility. That is the loop M29-T2 turns into real coverage.

- **✅ M28 COMPLETE and G28 PASSED (2026-08-04) — the menu is AppKit's, and it does things the
  bridge never could.** Five tasks: the windows off the scene graph, the menu at parity, a thumbnail
  per recents row, an export row that advances while you watch it, and ten recents under day
  headers. **707 tests.** Evidence in the gate table.
  🚢 **v1.15.0 CUT (2026-08-04)** — `Scripts/release.sh` ran the full gate (707 tests plus all four
  hardware-encode suites), tagged, pushed and published the signed zip:
  `github.com/fcostantini/screenrec/releases/tag/v1.15.0`.
  ⚠️ **What this milestone cost, in one line:** two of its defects were found by *looking* — the
  chevrons that didn't line up, and a highlight in the wrong blue. Neither shows in a dump, and the
  second surfaced only because Franco asked what the highlight was.
  ⚠️ **`ScreenRecApp` still has no test target** — the controller, the builder and both row views are
  covered by live probes and screenshots only. **Filed as M29 (Franco, 2026-08-04): next up.**

- **✅ M28-T5 SHIPPED (2026-08-04) — ten recents, under the day they were made.** Day headers
  (`Today` / `Yesterday` / a weekday / `17 July`), caps 5 → 10 and 3 → 5. The dump changed by
  design: **98 → 138 rows, every one accounted for** (4 headers + 3 files × 12). Plan artifact:
  `claude.ai/code/artifact/6df5996f-f958-4c61-91e2-60de4c5710c5`.
  ⚠️ **Names stay exactly as on disk** — trimming the date from a row under a dated header would read
  better and would contradict docs/06's own copy rule. Deliberately left as a separate decision.

- **✅ M28-T4 SHIPPED (2026-08-04) — the export row advances while you watch it.** `ExportModel.exportProgress` + `ExportProgressRowView`. **700 tests.**
  Plan artifact: `claude.ai/code/artifact/29e741a2-701b-4a1a-98ad-7ffc9acd97df`.
  ✅ **Proven the only way that counts:** one menu open, eight samples, **six distinct values** —
  `Exporting… 1% → 6%` read off `AXTitle` with the menu held open throughout. M6-T10's constraint is
  dead for this row and, deliberately, no other.
  ✅ **The percentage is in the title, not only the bar** — the title is what VoiceOver reads, and a
  bar alone would have left that reader the frozen row this task exists to fix.
  ⚠️ **`Exporter` had been reporting progress to nobody since M10-T2** — the seam existed the whole
  time. GIF and trim still report nothing, so they keep the plain row rather than a fake figure.
  🔴 **Two defects the review caught, both mine:** stacked observer registrations (progress is nil
  almost always, so they never fired to clear themselves), and a generation stamp captured *before*
  the generation moved — which would have silently dropped every report.

- **✅ M28-T3 SHIPPED (2026-08-04) — the recents rows carry a frame each.**
  `MenuThumbnails` + `RecentRowView` (167 lines): a 36 × 22 pt well, the frame taken 10% into the
  clip, decoded off-main and cached until the file changes. **695 tests.** Plan artifact:
  `claude.ai/code/artifact/d2544888-a090-4389-93e7-c7184c2bd468`.
  ✅ **The dump is byte-identical** — all **98 rows** of `Recordings ▸`. A view-based row is invisible
  to `menudriver` as long as the item keeps its `title`.
  ✅ **No slower to open:** 0.39–0.40 s over five runs against G18's recorded 0.57–0.60 s (0.90 s on
  the first, cold). ⚠️ Historical baseline, not a same-session A/B.
  🔴 **A defect only a screenshot could catch:** the chevrons did not line up, because a row's view
  keeps its created width and the chevron tracked the title length. `autoresizingMask` fixed it.
  ⚠️ **The live-arrival path is unobservable in the app** — a probe file already had its frame by
  the time the row was visible. Implemented, and proven on the harness (docs/07); its value is T4.
  🔴 **Correction to the T2 entry below: "zero warnings" was wrong** — incremental builds don't
  re-emit warnings for unchanged files. A forced rebuild still shows the one known pre-existing
  warning, now at **`AppState.swift:766`** (this file said 753). Nothing new was added.

- **✅ M28-T2 SHIPPED (2026-08-04) — the menu is AppKit, and it is the same menu.**
  `MenuBarExtra` is gone: `StatusItemController` + `MenuBuilder` + `MenuRow` (756 lines) replace
  `MenuView` and the SwiftUI status-item label (829). The app's entry point is AppKit, and the seven
  launch jobs that hung off the status item's `.task` run in `applicationDidFinishLaunching`.
  **695 tests, no test edited, zero warnings.** Plan artifact:
  `claude.ai/code/artifact/4c5a7233-c222-48f5-bd31-b1930d5ac58d`.
  ✅ **The bar was met on all three menus.** Idle **byte-identical**, proven in both audio states
  (160 rows with an app playing; 157 + a matching `Mute ▸` block with none). Recording and paused
  identical row for row, the only differences being **live values** — bytes written and the
  `Stop & Copy` figure off sub-second elapsed. The recording legs are Franco's runs.
  🔴 **Measurement caught the one thing parity would have shipped broken:** the first open after
  launch had no app list, no window list and no recents detail — those come from async reads, and
  the SwiftUI menu filled them in **while open**, which is the M6-T10 corruption relied on as a
  feature. Caches are primed at launch instead. **A second dump would have hidden this.**
  ✅ **The gaps this entry first recorded as unevidenced are closed.** **Franco drove all three
  declared diffs himself (2026-08-04) and confirmed them** — the muted app's tick now sits in the
  checkmark gutter rather than typed into the label, and a picked-but-quit app's `(not running)` row
  genuinely dims. Those two are his visual check, not a dump. **The armed-replay block is dump
  evidence:** armed, the whole menu is **identical to the SwiftUI baseline** bar `Mute ▸` listing a
  playing app — checkmark, both dimmed rows and `Save Replay Now  [⌥⌘R]` byte for byte. ✅ **And the
  level meter composites in AppKit too:** the status item measures **39 × 24 armed against 27 × 24
  disarmed**, which is M16-T5's own figure for icon-plus-meter.
  ⚠️ The third declared diff turned out not to be one: `Source ▸`'s leading and trailing rules
  reproduce the inline `Picker`'s own separators exactly, so the dump shows no difference at all.
  ⚠️ **`M28` is a MINOR and `VERSION` is still 1.14.0** — T1 and T2 are no user-facing change, so the
  bump belongs with T3–T5, which are.

- **✅ M28-T1 SHIPPED (2026-08-04) — the windows no longer need a SwiftUI scene.**
  Settings, Onboarding and Trim are `NSWindow`s hosting the same views (`WindowPresenter`, 68 lines
  against 40 deleted). **695 tests**, dev loop clean. Plan artifact:
  `claude.ai/code/artifact/0b23f84a-32db-41e6-8afe-67c40efa9583`.
  ✅ **The bar was met exactly: `menudriver dump` is byte-identical across 161 rows** against a
  baseline captured before any code changed. A later dump differed in one place — `Mute ▸` listing
  Discord instead of `Nothing is playing` — because Discord had started playing; the same build had
  already produced an identical dump when nothing was.
  🔴 **M28-T1 exists because `openWindow` dies with the scene graph** (the ruling in the artifact,
  Franco's go-ahead 2026-08-04): the parity task was split so the windows move first and a dump diff
  has one candidate cause. **docs/03's M28 tasks are renumbered — the menu swap is now T2.**
  ✅ **Four scene behaviours measured, not assumed** (docs/07): content sizing survives via
  `sizingOptions`, and the Settings tabs still re-fit 292 → 372 → **437** → 327 pt — 437 being
  docs/06's own recorded tallest; **window position does not survive** and needed
  `setFrameAutosaveName`; `@Environment(\.dismiss)` is a **silent no-op** in a plain `NSWindow`.
  🔴 **RETRACTED, same day: `replayArmed` going to 0 was Franco disarming it, not the G6 relaunch
  bug.** I read a disarm I hadn't caused as a reproduction of a known defect, and **re-armed it on
  that inference — the exact move this file's standing warning exists to forbid**, for the second
  time in the project's history. The setting is his; a session that sees it change should assume he
  changed it. Live value now **0**, left alone.
  ⚠️ **Instrument trap worth knowing:** `CGWindowListCopyWindowInfo` races the order-in and reported
  no window for one that was on screen. AX is the authority; `CGWindowList` is only for getting an id
  to `screencapture -l`.

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

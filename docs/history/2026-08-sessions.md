# 2026-08 sessions — closed logs

Rotated out of `STATUS.md` when its "Now" section passed the ~250-line bound the working contract
sets. Gate evidence for G26, G27 and G28 stays in STATUS.md's gate table; per-task specs and their
tick boxes are in `docs/03-milestones.md`.

## M27 — audio-only per-app exclusion, and the v1.14.0 cut

- **🚢 v1.14.0 CUT (2026-08-03) — M27 ships: an app can be left out of a recording's audio while it
  stays in the picture.** `Mute ▸` in the menu, `--mute-app` in the CLI, a Core Audio process tap
  behind both. **695 tests**, release and signed bundle green, tagged and deployed.
  ✅ **What it does that SCK cannot:** silence an app with **no window at all** — the case
  `SCShareableContent` never lists, while its audio plays on at full level.
  ⚠️ **The bump also carries M25's deferred patch**, as ruled on 2026-07-31.
  ⚠️ **Known, recorded rather than fixed:** the pre-existing unused-value warning at
  `AppState.swift:753`; G26's letterbox calibration still rests on one clip; and the tap-silent
  notice's *positive* path can't be exercised without revoking a TCC grant.

- **✅ M27 WORKS IN THE APP (2026-08-03) — one plist key was the whole blocker.**
  `NSAudioCaptureUsageDescription` + the grant Franco clicked: a **menu-driven** take now carries
  full-length audio (697 344 samples / 14.5 s, continuous) with the muted app at **−67.7 dBFS** and
  the rest of the mix at −12.2. **No notarization and no entitlement needed** — the feasibility
  question is closed. ⚠️ The plist change is committed; **the menu path is now verified end to end**,
  which the CLI legs never covered.
  ⚠️ **A late-clicked prompt mimics a delivery bug:** the first run granted mid-take gave 1.3 s of
  audio in a 24 s file. Check for an unanswered prompt before chasing a stall.
  ✅ **Helpers now collapse onto their app (Franco's catch, 2026-08-03):** the menu shows **Discord**
  and muting it silences `com.hnc.Discord.helper.Renderer`, where the call audio actually is. ⚠️ The
  earlier framing was wrong twice over — the helper row was not noise to hide, and the plain Discord
  row would have silenced **nothing** (docs/07).
  ✅ **Armed replay does receive tap audio** (440 Hz at −22.1 dBFS in a saved clip) — the question
  M27-T2 left open.
  ✅ **The long take passed (5 min):** ~5.7% of one core, RSS 185 MB, **0 dropped frames**, 48 kHz
  throughout — closing both deferred questions (T2's IOProc allocation, T5's resampling).
  🔴 **It also caught a false positive no unit test could:** the silence notice fired because the
  **only app playing was the muted one**, so the tap was rightly silent while the cross-check said
  otherwise. `isAnythingPlaying` now excludes the silenced family; reproduced and confirmed fixed.
  ✅ **M27-T5 SHIPPED: the tap is normalised to 48 kHz stereo** through the mic path's own converter,
  now with an injectable target (the mic's default is untouched by construction). **694 tests.**
  ✅ **The leg with teeth passed (Franco, 2026-08-03):** AirPods disconnected mid-arm → the saved
  clip is 91.7 s with an **89 s audio track at 48000 Hz**, holding audio from *before* the switch.
  The ring kept its window; a format change would have emptied it. ✅ It also explains the
  "newest seconds are silent" anomaly logged twice: the **40 s tone fixture ending**, not a stall.
  ⚠️ The 24 kHz→48 kHz conversion itself stays unit-pinned — the device was back at 48 kHz by then.
  ⚠️ **Background: a tap's sample rate follows the output device (24 kHz measured, 48 kHz in T1) —
  SCK's is always 48 kHz.** So a muted take's audio quality now depends on the hardware. **Not the
  half-speed bug it was first written up as** — the track is correctly labelled and plays correctly;
  the retraction and the reasoning are in docs/07. **Open design question:** resample the tap to
  48 kHz (the `ResampledMicInput` precedent) or accept the device's rate — Franco's call.
  🔴 **Also still open:** a long take (T2's deferred real-time allocation). ⚠️ **Don't run one while
  Franco is on a call** — it captures the call.

- **🔴 (superseded) M27 DID NOT WORK IN THE APP (2026-08-03) — G27's pass covers the CLI only.** Measured at one
  moment, Spotify playing, mute set: **the app records −∞ dBFS** (silence) while **the CLI records
  −6.8 dBFS** with just the muted tone gone. **The tap needs a TCC grant the bundle doesn't have.**
  ⚠️ **M27-T1's Q5 answer was wrong and is retracted:** the probe ran the bundle's executable **from
  the Terminal**, and TCC attributes access to the **responsible process** — so it re-tested
  Terminal's grants. Launching a bundle's binary from a granted parent never tests that bundle.
  ✅ **`TapSilenceWatchdog` caught it unprompted, in the wild**, with a true sentence — the failure
  it was designed for, found by a human running the feature normally. Without T4 this ships as
  silent audio.
  ✅ **Feasibility is likely, and does not hinge on notarization:** TCC keys on a stable code
  identity, not on Gatekeeper — **this app already holds Screen Recording, Microphone and
  Notifications while self-signed** (M0-T3's stable designated requirement). The ladder, cheapest
  first: ① add **`NSAudioCaptureUsageDescription`** to the bundle plist, re-sign, **launch it as an
  app** (never from Terminal — that is what invalidated T1's probe) and create a tap; a missing usage
  string is the commonest cause of exactly this silent-zeros shape. ② If not, test whether an
  **entitlement** is needed — most audio entitlements are unrestricted and a self-signed build can
  carry them. ③ Only if both fail is "not without notarization" a real answer rather than a guess.
  ⚠️ **No TCC denial appears in the log**, consistent with silent zeros rather than a refusal.
  🔴 **Next: find what the app needs** (`NSAudioCaptureUsageDescription`? an entitlement? a grant
  that only a notarised build can hold?) — and if it can't have it, **M27 does not ship** and that is
  a product decision, not a bug fix. **No 1.14.0 cut until then.**

- **✅ G27 PASSED (2026-08-03) — M27's four tasks and its gate are in.** Evidence in the gate table.
  **Audio-only per-app exclusion ships:** a hidden app's tone fell **−18.3 → −70.8 dBFS** while a real
  windowed app survived. 🔴 **Two things stand between this and a release cut:** a muted take on a
  quiet Mac has **no audio track at all** (Franco's ruling pending), and the **aggregate device
  disappearing is unmeasured** (AirPods mid-take). ⚠️ **The first attempt at this gate was discarded**
  — both sound sources were silent, and a silent control proves nothing (the G21 trap).
  ⚠️ **`VERSION` is still 1.13.0**: M27 is a MINOR and wants 1.14.0, but not before those two close.

- **✅ M27-T4 SHIPPED (2026-08-03) — M27's four tasks are in. Next: G27.** `TapSilenceWatchdog`
  (6 tests) plus `audioTapSilent`. **687 tests**, dev loop clean. Plan artifact:
  `claude.ai/code/artifact/e15862e9-71c5-4af2-9ea8-b6338e74fd0f`.
  🔴 **Silence cannot be the signal:** an ungranted tap streams zeros with `OSStatus 0`, and so does
  a quiet Mac. The check is **something is playing AND the tap is silent for 5 s** — and the control
  that matters passed: **a genuinely quiet recording raises nothing**.
  ✅ **Ruled: no fallback to SCK audio** — it would restart the stream mid-take *and* silently undo
  the mute, since that path is the very filter which can't drop audio without dropping windows.
  ⚠️ **Two honest gaps:** the notice's positive path can't be exercised end to end without revoking
  Franco's TCC grants (decision unit-tested both ways instead), and **the aggregate device
  disappearing — AirPods connecting mid-take — is still unmeasured**. Both are G27's to weigh.

- **✅ M27-T2 and T3 SHIPPED (2026-08-03) — an app can be muted from the menu. Next: M27-T4.**
  `SystemAudioTap` routes tapped audio as `.systemAudio` through `PCMSampleBuffer` (its third
  caller), host-clock stamped so `TimestampRebaser` needs no special case — **no consumer changed**.
  `Mute ▸` sits beside `Everything Except ▸`, and the dimmed rows are one grammar: **`… won't be
  seen or heard`** against **`… will be seen but not heard`**. **681 tests.** Plan artifacts:
  `.../384bd51c-72d2-4f86-820a-2250378605b2` (T2), `.../55c6bd3a-d758-4e8c-9205-50c6eb429950` (T3).
  ✅ **Measured:** silencing QuickTime by bundle ID took its tone **−18.5 → −102.4 dBFS** while the
  rest of the mix held at −18.1; the no-exclusion control kept both; an ordinary take still lands
  **3 tracks**, because nothing muted means the SCK path is untouched code.
  🔴 **Two wrong assumptions, both caught by building:** the process object list is *every process
  the audio system knows* (`caphost`, `audiomxd`, accessibility daemons) — `IsRunningOutput` plus a
  resolvable-name filter took the menu from six daemons to one real app; and **one app owns several
  audio objects**, so T2's "silence the object" left a browser's other helpers audible.
  ⚠️ **T2's unplanned finding, which T4's copy must carry:** the tap *also* captures windowless
  processes SCK omits, so muting one app can make a take hold **more** sound, not less (docs/07).

- **✅ M27-T1 DONE (2026-08-03) — the premise holds; a tap does what SCK cannot. Next: M27-T2.**
  A spike, no shipped code, all five questions answered in docs/07. Plan artifact:
  `claude.ai/code/artifact/1af9516f-d319-482b-8493-0aeed7e2c18b`.
  ✅ **The one the milestone rested on:** a tap **excludes a windowless process**. Two `afplay` tones,
  the exclusion swapped between them as the control — the excluded one drops to **−106 / −97.8 dBFS**
  while the other holds at −18.2. That is the case SCK structurally cannot reach.
  ✅ **Format is SCK's own** (48 kHz, 2 ch, 32-bit float), 512-frame callbacks, and **tap and SCK run
  together without conflict**. Cost **~0.4% of one core**, 27.6 MB.
  🔴 **The finding that shapes T3/T4:** excluding a process with **no audio object** is a **silent
  no-op** — that app's audio lands in full. The excludable list is *processes the audio system
  knows*, not *running apps*. An excluded process quitting mid-take is graceful.
  ✅ **The permission question is closed, and M27 needs nothing new:** the deployed bundle's own
  identity read a tone through a tap at **−18.2 dBFS**. No new TCC grant, no new `Info.plist` key —
  Screen Recording and Microphone already carry it.
  🔴 **But an ungranted tap is SILENT, not an error.** A freshly signed `.app` with no grants
  reported `OSStatus 0`, a valid tap UID and **374 callbacks of pure zeros**. **A health check that
  reads status codes would pass a tap capturing nothing** — T4's failure modes must measure level.


- **✅ G26 PASSED (2026-08-03) — M26 is complete and v1.13.0 is tagged.** Crop on export ships:
  a rect from the CLI, a band drawn in the Trim window, a `Find bars` button that finds a real
  letterbox by itself, and a precise trim that crops while keeping HEVC and both audio tracks.
  Evidence in the gate table. **Next: Franco's call.** M27 (Core Audio process taps) is the proposed
  one, and its T1 is explicitly *measure before designing anything else*; M28 (`NSMenu`) is the other.
  ⚠️ **Two things left on the floor, both recorded rather than done:** the pre-existing unused-value
  warning at `AppState.swift:753`, and the fact that G26's calibration rests on **one** letterboxed
  clip — a second, from a different source, would be worth more than any amount of tuning.

## Rotated from STATUS.md on 2026-08-06 — M28–M33 per-task logs, and M34/M35's task detail

Their milestones' summaries and every gate row stay in STATUS.md; this is the per-task
narrative, moved because "Now" had reached 607 lines against CLAUDE.md's ~250 bar.

- **✅ M35-T3 SHIPPED (2026-08-06) — onboarding says whether banners will really appear. M35's three
  tasks are done; G35 needs Franco.** Option A: the tick stays, the sentence changes. **791 tests.**
  Plan artifact: `claude.ai/code/artifact/35f8f986-425c-4663-bfb2-0faee7d5c8f2`.
  ✅ **Observed live in both states, window never touched.** Allowed → *"…including while replay is
  armed"*; Franco flipped it off → the row rewrote itself to *"Banners are hidden while replay is
  armed. Turn on …"*. Toggle restored to on.
  ✅ **No new machinery** — `pollUntilSatisfied()` already re-reads every second *"because they're
  granted elsewhere, with no callback"*. ✅ **4 breaks, 4 reds.**
  🔴 **Franco expected the checkmark to move, not the text** — the exact objection the plan recorded
  against option A, confirmed on first use. Left as A on his call; **B or C is a two-line change.**
  🔴 **The live "it took" moment is unobservable on one screen:** going to System Settings is what
  buries the window, so a user sees the confirmation *next time they open it*. A property of the flow,
  not of the row — and the reason "walks them through it" promised more than any build could.
  ⚠️ **The first-arm alert's new copy was never seen live** (fires once ever;
  `hasSeenReplayBannerWarning` is already true here). Unit-tested only.

- **✅ M35-T2 SHIPPED (2026-08-06) — a saved replay says so, in words. Next: M35-T3, then G35.**
  Option A at 3 s, Franco's pick from four shown as sketches beside a real capture of the old flash.
  The item carries **`✓ Saved`** for 3 s, then nothing. **786 tests.** Plan artifact:
  `claude.ai/code/artifact/925e67a3-7388-41b3-a88d-40812cf9be45`.
  ✅ **Both sides measured, which is the point of capturing the "before" first:** the old tick changed
  **4 %** of the item's area — that was the entire receipt for a replay — and the word changes **~32 %**.
  Present within **0.4 s**, still there at **2.8 s**, gone by **3.2 s**, item back to the armed baseline
  (max delta **2**). Frames at 2.5 Hz on the deployed app.
  🔴 **Two corrections to my own plan.** (1) **The VoiceOver justification was wrong:**
  `accessibilityLabel` already appended `", saved"`, so no screen reader was ever left out — A's win is
  **visual only**, and the M28-T4 parallel I argued from does not hold. (2) **The sketch showed a blue
  pill; the build uses the menu bar's native text style**, which reads like `RAM 65%` beside it rather
  than fighting the template tinting. Judged better; overrule me if the look is wrong.
  ⚠️ **The item widens for 3 s and neighbours shift** — accepted knowingly (and the old tick already
  did it). Nothing animates, so `reduceMotion` is untouched.

- **✅ M35-T1 SHIPPED (2026-08-06) — the armed-replay caveat says what is true, or says nothing.
  Next: M35-T2 (the promoted flash) — a taste call, so it gets a plan artifact with options shown.**
  `ADR-022` records the ruling. **785 tests** (777 → 785).
  ✅ **Three states, all three seen where it matters.** Deployed app, one pass: banners allowed → the
  caveat row is **gone entirely**; suppressed → **`Notification banners are hidden while armed`**;
  `unknown` is unit-covered by injecting a failed read, since no machine produces it on demand.
  🔴 **The skip had to move into AppCore, and that is the only behaviour change in the task.**
  `isReplayArmed` spends the once-ever flag *before* AppShell sees it, so deciding in the alert would
  burn a user's single warning on nothing — and leave them unwarned if they later turned the setting
  off. A test covers exactly that sequence.
  ✅ **T3's blocker is cleared, which is why T1 went first:** the **running** app saw the toggle change
  **without a relaunch** — `CFPreferences` served no stale value. T3's design holds. ⚠️ One
  observation, not a guarantee.
  ✅ **4 breaks, 4 reds.** 🔴 **And two existing tests carried a defect this surfaced:**
  `ReplayWiringTests`' first-arm tests read the **live** system setting, so they asserted something
  about whoever ran them — passing here only because Franco's toggle is on. Both stub it now; same
  class as M29-T2's live-TCC assertion.
  ⚠️ **`VERSION` unchanged** — M30's precedent: the bump belongs with G35.

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

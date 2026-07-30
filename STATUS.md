# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

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
  ⚠️ **The strict ruling now has a price tag: A2's real export was 9.4 MB against its 35 MB
  estimate**, so A1 refused a job that would have fitted. That is the ~3.7× ceiling docs/07 predicted,
  arriving on a path where it *decides* rather than labels. **Franco may want to revisit strict.**
  ⚠️ Also found: an abandoned export leaves an `.sb-` temp nothing sweeps (pre-existing; `Quit Anyway`
  makes it one click) — cheap follow-up noted in docs/07.

- **🧹 The test suite had leaked 49,668 preference plists — 194 MB, 99.3% of `~/Library/Preferences`**
  (2026-07-30, found while reading the app's own settings). Deleted with Franco's OK: **50,027 → 359
  files, 302 MB → 109 MB**. Cause fixed by `TestDefaults`, which records every throwaway suite and
  sweeps on the way **in** as well as out. ⚠️ **The exit sweep cannot be made reliable** — it races
  `cfprefsd`, and a single clean run fooled me before two later runs leaked 154 each; the entry sweep
  is what bounds it. Residue is now one run's worth, self-healing, never cumulative.

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
  **Next: M23-T3** — work in flight visible from the menu bar; also owns the "a take that stops while
  replay is armed is completely silent" half. Plan artifact first, per the contract.

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

- **⚠️ Franco's current settings — do not "restore" these.** Instant replay is **OFF** because he
  turned it off (an earlier session re-armed it on a wrong inference and had to undo that);
  `Ask for a name when a recording stops` is **off**; Source is **Entire Screen**. If a session
  changes any of them for a test leg, change it back.

- **🚫 M20 (Marks) CLOSED "won't do" (Franco, 2026-07-28); M20-T1's code was reverted.**
  🔴 The measurement that ended it: **a sparse extra track disables fragmented writing, and with it
  crash safety.** `AVAssetWriter` emits a fragment only when *every* input has data up to the
  boundary, so a chapter track fed once per mark starves it — mid-write, the only state a crash sees:
  no track → 3 `moof` atoms, track present → **0**. Same build, same `kill -9`: marks off recovered a
  playable 10.99 s file, marks on was unreadable. Sidecar `.json` worked but Franco won't have a
  companion file beside every recording; movie metadata can't be set after writing starts.
  **Don't re-file without a new mechanism.** The generalised trap — measure any new
  `MovieRecorder` track *while writing*, by counting `moof` atoms — is in docs/07.

- **Parked, with triggers:** multi-display region capture (the week a second display is attached); an
  `NSMenu`-backed status item (the next feature needing custom row rendering); cursor emphasis /
  auto-zoom (behind ADR-015's render stage); and **audio-only per-app exclusion via Core Audio process
  taps** — the honest answer to review finding F3, since SCK's filter can't do it (docs/02 §1a-ii).

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

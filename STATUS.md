# STATUS — living state of the Tier-2 effort

> Agents: update this file every session. Newest session notes on top.
> Format discipline: keep "Now" brutally short. Measured platform behaviour goes to
> `docs/07-field-notes.md`; closed session logs rotate to `docs/history/`.

## Now

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

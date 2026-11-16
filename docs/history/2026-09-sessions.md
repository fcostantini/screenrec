# 2026-09 sessions — closed logs

Rotated out of `STATUS.md` on 2026-11-16, when its "Now" section had reached 338 lines against the
~250-line bound the working contract sets. These are the per-task logs of M37 (2026-08-18) and M38
(2026-09-07), moved verbatim. Both milestones' summaries and every gate row stay in STATUS.md;
per-task specs and their tick boxes are in `docs/03-milestones.md`.

## M38 — the preview keeps playing, and the sound can leave on its own

- **✅ M38-T3 DONE (2026-09-07) — the sound is reachable from the menu and from the Trim window.**
  **840 tests** (838 → 840). Driven on the deployed build: the recents submenu's `Export Audio` wrote
  **5.6 MB / 300.77 s / one AAC track**, and the Trim window's button — under the action row, with its
  caption — **dismissed the window** and wrote **27.82 s** for a 0:27 range. **M38 is code-complete;
  next is G38** (the gate, and the v1.21.0 bump with it).
  🔴 **Two defects only the real surface showed, both fixed before the commit.** The export receipt
  falls back to `Exported to MP4` for any extension it doesn't know, so an `.m4a` would have been
  announced as an MP4 — M36's sin in a new place. And `OutputLocation.exportExtensions` turns out to be
  **two rules in one list** — what Recent Exports lists, *and* which orphaned `.partial` the sweep may
  delete — so without `m4a` an abandoned audio export would have sat in the folder forever.
  ✅ **An `.m4a` row offers no derive at all** (measured in the menu): three of them need a picture and
  the fourth would hand back what you have.
  ⚠️ **The no-sound notice is unit-tested at both layers, never driven live** — no soundless recording
  exists here.
  ⚠️ **Instant Replay came back disarmed after this deploy** (it re-armed itself after the T1 one).
  Franco may want it back on.

- **✅ M38-T2 DONE (2026-09-07) — a take's sound can leave on its own, as an `.m4a`.**
  **834 tests** (826 → 834). `AudioExporter.exportAudio` + `screenrec-cli export --to-audio`, measured
  on the 5:01 replay: **one AAC track, no video track**, **300.77 s** against the source's 300.79,
  **5.6 MB in 1.78 s** from a 1.2 GB take; `--from 2 --to 5` → **3.00 s** named `… trimmed.m4a`.
  **Decoded rather than assumed** — peak 0.231 / rms 0.0145 over the first 20 s. **Next: M38-T3**
  (the menu row and the Trim window's button — and the three rulings in the plan artifact).
  🔴 **Two extractions rather than a copy:** `Exporter.mixedTracks` and
  `AudioEncodingSettings.mixedPCM` are shared with the MP4 path, so the two exports can't drift on
  which track is the microphone or what PCM the encoder is fed.
  ⚠️ **The audio fixtures carry no video**, so they run in the default suite; only the no-sound case
  needs the VT encoder and stays gated behind `SCREENREC_HW_ENCODE_TESTS=1` (run once, passing).
  ⚠️ **Franco's replays hold one stereo track, no mic** — so the real-file leg proves the
  keep-the-sound branch of M33-T2's rule, and the drop-the-mic branch is unit-tested on a fixture.
  🔴 **A later review found the two exports disagreeing about the same range** — this rebased from the
  earliest *sound* where `Exporter` rebases from the *picture*, so a late-starting mic made
  `Export Audio` and `Export & Copy` of one range write different lengths. Both rebase from the picture
  now; only the end is still the sound's. Re-measured: whole take **300.77 s**, a 2–5 s range **3.00 s**.
  🔴 **`/code-review medium` found two things my own pass didn't**, both fixed before the commit: the
  result reported the **asset's** length (video-driven) rather than the sound's — 300.79 against the
  file's 300.77, and the CLI divided bytes by it — and a test aimed its second export at the first
  one's path, leaving a stray `… 2.m4a` in `$TMPDIR` every run while still passing.

- **✅ M38-T1 DONE (2026-09-07) — the preview keeps playing while you move around in it.**
  **826 tests** (821 → 826). One AX probe run against both binaries, same button and same five keys on
  a 5:01 replay: **before**, `Play` took the clock 0:00 → 0:02 and five `→` froze it at 0:02 with the
  button back to `Play`; **after**, the same presses read 0:02 and **0:04** two seconds later, button
  still `Pause`. A filmstrip click while playing goes **3:47 → 3:49** instead of stopping, and five
  presses while paused start nothing. **Next: M38-T2.**
  🔴 **The fix is one `pause()` fewer, not a resume.** A seek preserves the rate on its own, so
  `seek(toSeconds:)` pauses only when `TrimSeek` says not to keep playing, and `step(byFrames:)`
  dropped its own pause — no completion handler, so a superseded seek can't restart a clip the next
  press already stopped.
  ⚠️ **The end-of-clip exception is unit-tested only** — 50 ms at the end of a 5-minute clip, where one
  filmstrip pixel is 0.18 s.
  ⚠️ **Driving that window needs `AXDescription`, not `AXTitle`**, and `AVPlayerView` publishes the
  video's Live Text as `AXTextArea` noise — both in docs/07.
  ⚠️ **The deploy discarded the armed replay buffer that was running** (Franco's call, taken before
  the rebuild); the relaunched build re-armed itself from settings.

- **📋 M38 FILED from Franco's own use (2026-09-07) — three tasks, nothing implemented. Next: M38-T1.**
  Plan artifact: `claude.ai/code/artifact/e2670924-062b-49d5-b8ef-34c3b33099f5`. A `docs:` commit — no code
  changed, no VERSION bump yet (**MINOR at the gate**, ADR-013: an audio derive is a capability the app
  has never had).
  🔴 **T1's pause is deliberate, not a side effect of seeking.** `TrimView.seek(toSeconds:)` calls
  `player.pause()` before every seek (`:405`) and `step(byFrames:)` pauses again on its own (`:385`),
  and ←/→, ⇧←/⇧→ and the filmstrip click all funnel through it — so all three stop playback.
  🔴 **MP3 cannot be written by this app, and that is measured rather than assumed.** Core Audio
  reports **0 encoders** for `kAudioFormatMPEGLayer3` (AAC, ALAC, FLAC and Opus report 1 each) and
  `afconvert -f MPG3` fails with `('fmt?')`. Shipping one means vendoring LAME — an ADR-010 exception.
  In docs/07 with the trap that `afconvert -hf` lists `.mp3` anyway.
  ✅ **Ruled by Franco before filing:** the export writes **`.m4a` (AAC)**, MP3 is not pursued; and
  "keep playing" covers the **filmstrip click as well as the arrows**, since both are the same `seek`.
  ⚠️ **Needs Franco:** the new row's placement and copy, whether `Export Audio` dismisses the Trim
  window (recommend yes, like its two neighbours), and the menu row's wording (`Export Audio` vs
  `Export as M4A`).
  ⚠️ **v1.20.0 is still unreleased** — the tag decision owed from M37 now covers M38's bump too.

## M37 — the windows behave like windows

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

## The README demo GIF (2026-08-07)

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

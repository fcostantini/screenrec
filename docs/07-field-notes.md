# 07 — Field notes

What ScreenCaptureKit, VideoToolbox, AVFoundation and the `.menu` MenuBarExtra **actually do**, as
opposed to what they document — measured, dated, and attributed to the task that found it. This is the
most re-read artefact in the repo: most entries exist because something cost hours to discover.

Append newest-first. Promoted out of STATUS.md by M15-T5, where it had grown to 1,229 lines inside a
file every session is required to read.

- 2026-07-30 (M23-T2, found while reading the app's own preferences): 🔴 **The test suites had
  leaked 49,668 preference plists — 194 MB, and 99.3% of every file in `~/Library/Preferences`.**
  The per-test `UserDefaults(suiteName: "screenrec-tests-\(UUID())")` idiom exists for a good reason
  (M4-T4 persists on `didSet`, so a bare `AppState()` scribbles on the real domain) — but a
  written-to suite **is a real plist on disk**, and nothing ever removed them. Three prefixes were
  accumulating: `screenrec-tests-` (42,663), `appstate-tests-` (6,449), `settings-window-` (556).
  Every `swift test` run added a few hundred more, and `defaults domains` on this machine returned
  2.2 MB of them. ⚠️ **A per-test teardown would not have held** — it has to be remembered by the
  author of every future test, which is exactly how it leaked in the first place; the fix is one
  `TestDefaults` helper that records each suite and sweeps them all from an `atexit` handler.
  🔴 **A suite cannot be reliably deleted at process exit at all.** `removePersistentDomain` alone
  leaves the file (`cfprefsd` owns it and writes back on its own schedule); adding
  `CFPreferencesAppSynchronize` + `unlink` cleaned a full run **once**, then leaked **154 of ~600**
  on the next two — it is a race with a daemon that outlives us, and one clean run is not evidence
  of a fix. ⚠️ **Don't trust a single green measurement on a race.** What actually works is giving
  up on winning it: sweep leftovers **on the way in** as well, with an age floor so a concurrent
  run's live suites are never touched. Measured across three runs — **154 → 308** growing before the
  entry sweep, then **308 → 308** holding, then **616 → 308** after a deliberate backlog. So it is
  self-correcting rather than merely bounded: the steady state is one run's residue (~150), and any
  backlog is reclaimed by the next run rather than needing a human with `rm`.

- 2026-07-30 (M23-T2, live): ⚠️ **The export's rate budget over-quoted a real take by 3.7×, and the
  strict fit check refused a job that would have fitted.** Measured through the deployed menu: a
  45.05 s take quoted **35 MB** (46.2 MB/min at the fitted 1920×1200) and the export it actually
  produced was **9.4 MB**. With 15.1 MB free the guard refused it — correctly by its own rule, and
  wrongly in fact. This is the same over-quote M21-T2 measured (~5× on a static desktop) arriving on
  a path where it *decides* something rather than just labelling a row. The ruling was strict on
  purpose (a false refusal is instantly recoverable; a false accept costs minutes and ends in the
  failure the check exists to remove) — but the number is now known, and it is the argument for
  revisiting it. ✅ The fitted size the estimate assumes was confirmed exact: the export probed
  `avc1 1920x1200`, matching the arithmetic.

- 2026-07-30 (M23-T2, leg B): ⚠️ **An abandoned export leaves an `AVAssetWriter` `.sb-` temp that
  nothing sweeps.** Measured by quitting through a live export: the `.mp4.partial` is litter the
  launch sweep already deletes (`isAbandonedExportPartial`, M15-T3 — verified here by a real abandon
  rather than a `kill -9`, and it took the file on the next launch), but the `.sb-<hex>` sibling
  survives, because M21-T1's `.sb-` sweep runs **after a successful finalize** and an abandoned
  export never reaches one. Pre-existing — the `M14T2 drain.mp4.sb-…` in `~/Movies` has sat there
  since July 23 — but `Quit Anyway` turns it from a rare race into a one-click path. Cheap follow-up:
  sweep the scratch prefix on launch too, beside the orphaned partials.

- 2026-07-30 (M23-T2): 🔴 **"Quit Anyway" would have waited, because every quit route funnels
  through `applicationShouldTerminate`.** The menu's `quit()` ends in `NSApplication.terminate(nil)`
  — which *runs the delegate*, which now returns `.terminateLater` whenever an export is in flight.
  So the abandon button and the wait button did the same thing, and only the label differed. Caught
  by reasoning through the leg before running it, not by the leg. The fix is that abandoning must
  clear `exportInProgress` **synchronously**, before `terminate` is called; a cancellation the
  delegate can't yet observe is not enough. Generalises: **on macOS an "are you sure?" alert in
  front of `terminate` cannot itself decide the outcome** — the delegate gets the last word, so any
  choice the alert offers has to be expressed as state the delegate reads.

- 2026-07-30 (M23-T1): what a dying `AVAssetWriter` actually does, and the one thing no unit test
  can reach.
  - 🔴 **`isReadyForMoreMediaData` stays `true` on a `.failed` writer, forever.** This is the whole
    reason the bug was invisible rather than merely unreported: the readiness guard does *not*
    short-circuit, so the append is reached, returns `false`, and — with the return value discarded —
    the recorder cheerfully accepts every frame for the rest of the take and writes none of them.
    Measured on a full volume: refusal and the `.failed` transition land on the **same call** (frame
    356), and `isReady` was still `true` on the next frame. So the append's `Bool` is the primary
    detector and the `writer.status` poll is only the backstop for when nothing is appending.
  - 🔴 **No synthetic sample buffer can fail a writer, so the mechanism is not unit-testable.**
    Tried and all four were **accepted** (`append` → `true`, status stayed `.writing`, `error` nil):
    mismatched dimensions (640×480 into a 320×240 input), PTS going backwards, PTS before the
    session start, and a wholly invalid PTS. `AVAssetWriterInput.append` validates almost nothing at
    call time — malformation surfaces at `finishWriting`, not here. Don't spend an hour trying to
    build a deterministic in-process failure; the unit tests cover the *decision* (`finalizePlan`'s
    priority, the notification copy, the naming-prompt policy) and a real volume covers the rest.
  - ✅ **The salvage is real, and it is the crash-recovery path.** ENOSPC at 11.87 s of a
    video-only take left a fragmented file that reads **11.07 s** — 0.8 s lost, exactly the 1 s
    `movieFragmentInterval`. Through the real CLI (video + system audio), a take killed at ~20 s
    probed **19.05 s**, hvc1 4112×2570 + AAC, both tracks within 80 ms.
  - **The A/B, same rig, M19-T1's standard** (500 MB APFS image, ballast leaving ~20 MB, the take
    fills the rest): **before**, the CLI ran the **full 60 s** — 38 s of it after the writer was
    already dead — and ended `✗ Couldn't finish saving the recording`, offering nothing; the
    `.partial` it abandoned probes **23.05 s** once renamed, so the content was always there.
    **After**, `✓ finished (writeFailed)` at **20 s** with a playable file handed back.
  - ⚠️ **The error is `AVFoundationErrorDomain -11807 "Disk Full"` wrapping `NSPOSIXErrorDomain 28`** —
    but don't key on it. A read-only remount or a detached volume arrives at the same `.failed`
    status by a different code, which is why the detection reads `status`, not `error`.
  - ⚠️ **On a volume that just hit ENOSPC the `.partial` → final rename can itself fail**, and it did
    in 2 of 4 runs (nondeterministic — it needs a metadata transaction the full volume may refuse).
    The `(try? finalizePartial) ?? partial` fallback then reports the `.partial` path, and **a
    `.partial` is unopenable — `AVURLAsset` can't infer a type from that extension**, so `probe`
    says "Cannot Open" over bytes that are perfectly good (copy to `X.mov` and it reads fine). The
    launch-recovery sweep renames it, so nothing is lost, but the reveal-on-click in that window
    lands on a file QuickTime won't open. Pre-existing behaviour of `finalizeNormal`; M23-T1 just
    makes it far more likely to be hit, since the volume is full by definition on this path.
  - ⚠️ Rig note: a quiet desktop encodes at **~0.4 MB/s**, ~5× under the rate budget, so a 500 MB
    volume never fills in a 60 s take. Ballast it to a few tens of MB free — and not *too* tight,
    or the writer dies before the first fragment flushes and there is genuinely nothing to salvage
    (11 MB free → dead at 1.5 s, unreadable file, which is correct behaviour but proves nothing).

- 2026-07-30 (M21-T4, live leg): ⚠️ **Excluding an app silences the system-audio track, not the
  room.** Under `Everything Except ▸ QuickTime`, the recorded system-audio track measured
  **−∞ dBFS** while the **microphone** track measured **−35.2 dBFS** — the mic hearing the tone
  through the speakers. No filter can fix that, and it is worth knowing before someone reports the
  exclusion as broken: with a mic in the take, an excluded app is inaudible only if the sound never
  leaves the machine (headphones, or the app muted). The menu's `won't be seen or heard` line is
  about what the app *captures*, which is the honest thing it can promise.

- 2026-07-29 (M21-T3):
  - 🔴 **A synthetic keystroke never reaches an `LSUIElement` app's modal alert — it goes to whatever
    is actually frontmost.** The alert renders and looks focused enough in a screenshot, but its
    buttons and text are drawn *inactive* (that greyed look is the tell). `NSApp.activate` inside the
    app doesn't help: a synthetic press confers no activation, which is menudriver's own documented
    caveat, one layer further along. My typed name and its Return went to the terminal instead, and —
    worse — **the un-answered alert left the app modal**, so the next run's `Start Recording` was
    queued behind it and the menu just sat idle. Drive an alert through AX instead:
    `AXUIElementSetAttributeValue(field, kAXValue…)` then `AXPress` the button by title. Unlike a
    SwiftUI window, an `NSAlert`'s controls *do* carry `AXTitle`.
  - ⚠️ The alert is a **layer-8** window (`NSModalPanelWindowLevel`), so a `CGWindowList` sweep
    filtered to layer 0 misses it entirely, and one that ignores layer grabs the open *menu* (101)
    instead.

- 2026-07-29 (M21-T2): 🔴 **The export's rate budget over-quotes a quiet screen by ~5×, so a row
  built on it must say `up to`, not `≈`.** `Stop & Copy MP4` first shipped its estimate as
  `≈11 MB` for a 14 s take; the file it wrote was **2.2 MB**. The model isn't wrong — it is
  `ExportConfiguration.bytesPerMinute`, whose own doc calls it a budget, and M19-T4 measured
  45.1 MB/min against 46 quoted **on busy content**. On a static desktop VideoToolbox spends a
  fraction of it (docs/07's earlier 12.9 vs 22.1 Mbps entry, same effect). The Settings picker can
  keep `≈` — it quotes what a minute *costs at these settings*, a comparison between picks — but a
  row promising what *this take* will weigh has to be a ceiling. Found by the live leg, which is
  the only place the two numbers meet.

- 2026-07-29 (M21-T1):
  - ✅ **`AVAssetReader.timeRange` clips exactly at the requested time, whatever the keyframes do.**
    In-point 30.000 s on a real capture whose preceding sync sample sits at 28.100 (1.900 s back):
    the first delivered video PTS is **30.000**, and the mixed audio's is **30.000** too. The reader
    decodes from the sync sample internally and hands back clipped samples, so a ranged export needs
    no retiming — and, unlike a lossless trim (02 §6a), the output holds **only** the range. This is
    why the MP4 export's range rides the reader rather than `AVAssetExportSession`, which is the
    trim's engine and would give up the mixed AAC track, the size fit and faststart.
  - 🔴 **A short export can outrun `AVAssetWriter`'s own cleanup and strand its `.sb-<hex>` temp** —
    the file M15-T3 recorded as a *hard-kill* leftover, here after a clean, successful export.
    Measured: a 5 s ranged export stranded one on the first run, then not in three repeats; a 110 s
    ranged export and a 5 s rangeless one never did. It is a race with process exit, not a property
    of the range — but a ranged export from the Trim window is short **by design**, so this went
    from rare to routine and is now swept after finalize (only names carrying our own scratch
    path's prefix; a miss is a no-op, since the convention is Apple's and undocumented).
  - ⚠️ **A real screen recording usually can't verify a frame-exact cut.** Comparing the export's
    first frame against source frames at 28.1 / 29.0 / 29.5 / 30.0 / 30.5 / 31.0 s scored
    **38.1–38.6 dB across all six** — the content (a mostly static browser window) barely changes,
    so the "right" frame won by 0.4 dB and the measurement proved nothing. A synthetic clip that
    burns its own timestamp into every frame, with keyframes 5 s apart, answers it outright:
    **52.4 dB** at the requested 27.30 s against **8.8 dB** at the keyframe 3.3 s earlier, and the
    frame simply reads `27.30 s`. Build the source that can fail the test, or the test is decoration.
  - ⚠️ **The Trim window's buttons carry no `AXTitle` — the label is in `AXDescription`.** A search
    for `role == .button && title == "Export as MP4"` finds *nothing* in that window, while its
    static texts read fine; the same walk shows `AXButton title= desc=Export as MP4`. `AVPlayerView`'s
    own controls behave the same way (`desc=mute/unmute`). Match on the description when driving a
    SwiftUI window, and keep a coordinate click as the fallback. The <kbd>I</kbd>/<kbd>O</kbd>
    shortcuts, by contrast, drive it perfectly once the window is key.
  - ⚠️ Pre-existing, untouched: the CLI's export line prints **`+ AAC` unconditionally**, so a
    recording made with both audio sources off (legal under ADR-019) reports an audio track it
    doesn't have. Fixing it means `ExportResult` carrying whether audio was written.

- 2026-07-28 (menu-bar clock alignment): 🔴 **the `.menu` MenuBarExtra hands a label's `Text` to the
  status item as its AppKit *title* and throws away every SwiftUI modifier on it.** Franco saw the
  elapsed clock sitting high beside the icon; measured, its ink centre was **22.0 against the icon's
  23.5** in a 48 px bar — 1.5 px at 2×, because digits carry no descenders while the line box
  reserves room for them. Three fixes were deployed and re-measured, and **none moved it a pixel**:
  `.offset(y: 0.75)`, `.offset(y: 5)` (deliberately huge — the decisive one), and `.padding(.top:)`.
  A `.font(.system(size: 6))` then rendered at **full size**, which is what proves the mechanism:
  the string is drawn by AppKit, not by us. Same family as this file's older note that a MenuBarExtra
  label renders only its **first** `Image`.
  - ⚠️ **Padding the icon's own canvas doesn't work either** — the status item **scales an
    oversized image back down** to the bar: a 0.75 pt taller canvas moved the ink up only 0.5 px
    *and* shrank the glyph from 26 to 25 px. Anything that changes the image's height trades
    alignment for size.
  - **What worked:** draw the clock *into* the image (`StatusIconImage.withClock`), centred on the
    font's **cap height** rather than its line box — the same reason the armed badge and the level
    meter composite instead of sitting beside the glyph. Digits went 22.0 → **23.0** against the
    icon's 23.5; the remaining 0.5 px is sub-pixel rounding of the baseline. The cost is owning the
    font and the ink colour: a non-template image can't be tinted by the menu bar, so the colour
    follows `NSApp.effectiveAppearance` (the trade the meter already makes).

- 2026-07-28 (M20-T2, the note that closed the milestone): 🔴 **a sparse extra track silently
  disables `AVAssetWriter`'s fragmented output — and with it, crash safety.**
  `movieFragmentInterval` emits a fragment only when **every** input has data up to the boundary,
  so an input that receives a sample rarely (a chapter track: once per mark) or never holds the
  boundary forever and **nothing is ever flushed**. The finished file looks perfect — fragments
  appear at `finishWriting` — so only a mid-write inspection shows it.
  **Measured mid-write, the only state a crash sees:** no extra track → **3** `moof` atoms · a
  chapter track never marked → **0** · a chapter track plus one mark → **0**. End to end through
  the app: two takes, same build, same `kill -9`, marks off recovered as a **playable 10.99 s
  file**, marks on was **unreadable** (`moov atom not found`, `mdat` length 0, no `moof`).
  ⚠️ **This applies to any future track**, not just chapters — timed metadata, captions, anything
  added to `MovieRecorder` that isn't fed continuously. If a track must be added, measure fragments
  *while writing* (count `moof` in the file on disk before finalize); a passing `finishWriting` and
  a readable output prove nothing about the crash case.
  - **What a chapter track needs, in case one is ever attempted again:** the association is owned
    by the **video** track (`video.addTrackAssociation(withTrackOf: text, type: .chapterList)`; the
    reverse throws); a bare `CMFormatDescriptionCreate` for `'text'` writes fine then fails
    `finishWriting` with **−12712**, and only a hand-assembled 59-byte big-endian QuickTime
    `TextDescription` works; and without `languageCode` on the track,
    `loadChapterMetadataGroups(bestMatchingPreferredLanguages:)` returns **0** chapters though the
    track is plainly present.
  - **Metadata is not an escape hatch:** `AVAssetWriter.setMetadata` throws once writing has begun
    ("Cannot call method when status is 1"), so a movie's metadata is fixed before the first frame.
  - **Portability, since it came up:** QuickTime and `ffprobe`/libavformat both read these chapters
    (`TAG:title=Mark 1` with exact ranges); **VLC 3.0.23 parses the `chap` box but emits no
    seekpoints**; and **our own MP4 export drops them entirely** — `Exporter` writes the video and
    audio tracks by name, so a text track never reaches a shared clip.

- 2026-07-28 (M20-T1): verifying a timestamp against the recording itself.
  - **A full-screen take records its own menu-bar clock**, so a mark's frame can be checked against
    the number the user was looking at when they pressed the key: the frame at the 0:05 mark read
    **00:00:05**, the one at 0:29 read **00:00:28**. That second reading is not an error — the label
    ticks at **1 Hz**, so expect up to a second of lag between the mark and what the frame shows.
    Cheapest timing evidence available for anything clock-shaped; M20-T3's seeks can reuse it.
  - ⚠️ **Do not reason about a driven sequence's timing from your own sleeps.** Every
    `swift tools/<x>.swift` invocation *compiles first*, several seconds each, so a scripted
    Start → Pause → dump run drifts far from the arithmetic. Reasoning that way produced a
    confident false bug report (that the header clock advanced during a pause — it had not; the
    pause simply landed later than assumed, and Franco knew because he was watching). **Read the
    app's own clock, not the wall clock you think you commanded.**

- 2026-07-28 (M22-T1): 🔴 **a python range-cut ate 190 lines of `AppState` and the build still had
  to tell me.** Extracting `SourcesModel` by `s[:a] + s[b:]`, the end marker for `regionLabel` was
  `// MARK: - Event folding` — which sits *below the whole Actions section*, so the cut removed
  `start()`, `stop()`, pause and the rest. Same failure as M18-T6's doc rewrite, now in code.
  **The rule that fixed it:** every range cut declares its expected line count and aborts if the
  range doesn't match, printing the first and last line removed. Six cuts, six size checks, and
  the two wrong markers surfaced as aborts instead of silent deletions.
  - **The forwarding surface costs more than it looks.** Predicted `AppState` at ~1,290 lines,
    landed at **1,391** (1,568 before): ~235 lines left, ~70 came back as forwards. Worth stating
    up front on the next extraction — the win is the seam, not the line count.

- 2026-07-28 (M22-T3): 🔴 **a test that looked right proved nothing, and only mutation said so.**
  Breaking each of the six units and re-running its new test caught `PollingTests`: swallowing
  cancellation (`try?` instead of `catch { return }`) costs **exactly one** extra tick — the loop
  wakes immediately because `Task.sleep` throws the instant it is cancelled, ticks, then exits on
  `!Task.isCancelled` — and the assertion tolerated one (`<= atCancel + 1`). The fix is a window
  *shorter than the interval*: tick every 300 ms, cancel, and check 80 ms later, where a correct
  loop cannot have ticked and a broken one already has. **Mutate before believing a new test.**
  - 🔴 **…and that fix then flaked the gate.** Asserting `atCancel == 1` after a fixed 400 ms sleep
    passed alone and failed inside the full suite (`atCancel → 0`): 557 tests run concurrently, and
    a 300 ms tick simply hadn't been scheduled yet. **A timing assertion must never come from a
    fixed sleep** — wait for the observation with a generous deadline (a broken loop never reaches
    it however long you wait), *then* measure the short window that distinguishes the bug. Third
    time this suite's reliability has been the thing at risk (M15-T1).
  - ⚠️ **`CMSampleBufferGetDuration` returns the buffer's TOTAL duration**, so
    `SampleTiming.retimed(duration:)` — which sets it per timing entry — reads back multiplied by
    the sample count on a multi-sample audio buffer (480 samples × 1/30 = 16 s). Assert it on a
    single-sample video buffer, which is the shape the tail patch actually retimes.
  - ⚠️ **CoreMedia refuses to create an audio sample buffer with an invalid PTS**
    (`CMAudioSampleBufferCreateReadyWithPacketDescriptions` fails), so the "no numeric timing" case
    can only be built from `makeMarkerBuffer()`.

- 2026-07-28 (M22-T5/T6): releasing, measured.
  - ⚠️ **`script -q /dev/null cmd <<< "y"` does NOT answer a prompt** — the heredoc feeds `script`'s
    own stdin, not the pty, so the program sees EOF and the answer echoes after it. Both a `y` and
    an `n` run "answered" the same way, which would have passed a broken decision. `expect -c
    'spawn …; expect "y/N"; send "y\r"; expect eof'` drives a real pty and distinguishes them.
  - **A `ditto` round trip preserves a bundle's signature; the quarantine flag rides along.**
    Downloaded `ScreenRec-1.10.1.zip` from GitHub, set `com.apple.quarantine` on the zip, and after
    `ditto -x -k` the **app inherited the same attribute** while `codesign --verify --strict` still
    read `valid on disk` + `satisfies its Designated Requirement`. `spctl -a -t exec` **rejects** it
    (`origin=screenrec-dev`) — which is ADR-014 working as designed, and exactly why the release
    notes lead with the Privacy & Security steps.
  - The signed 2.9 MB bundle compresses to **972 KB**.

- 2026-07-28 (M19-T5): 🔴 **a SwiftUI Picker tags its rows with a value, so any moving field in that
  value silently breaks the checkmark.** The menu tagged each window row with a `WindowSelection`
  built from the **live** window while the selection came from the **stored** pick — and the type
  was `Hashable` over `title`. Measured before the fix: `selection == rowTag` → **false** after a
  retitle, i.e. every browser tab switch left the picked window unmarked. It hid for two milestones
  because the `Source:` header is computed separately and stayed correct — there was even a passing
  test for the header. **The lesson generalises:** a tag value must carry identity only; if a field
  can change while the pick stays the same, it does not belong in the value the Picker compares.
  (Dropping `title` fixed the checkmark and took the window title off disk in the same edit.)

- 2026-07-28 (M19-T4): the Size picker had a decoy row, and the encoder does not spend its budget.
  - 🔴 **`1280 px` produced the same file as `1920 px`** — 6,764,917 vs 6,688,557 bytes from one
    7.47 s source, the smaller pick **1% heavier** for 2.25× fewer pixels. Structural, not
    content: M18-T2 floors the export rate at the 6 Mbps reference so a native-size region export
    can never get softer, and the floor keys off the **output** size, so every pick at or below
    1920×1200 asks for exactly 6 Mbps. Row dropped.
  - **The four picks, same source** (target → achieved, file): 1280×800 6.0 → 7.24 Mbps 6.76 MB ·
    1920×1200 6.0 → 7.16 Mbps 6.69 MB · 2560×1600 10.7 → 12.24 Mbps 11.43 MB · 3686×2304
    **22.1 → 12.86 Mbps** 12.02 MB. The largest is the one to note: VideoToolbox spends only what
    the content needs, and a static desktop cannot fill 22 Mbps — so a size label can state a
    *budget*, never a file size. (It also **overshoots** the target by ~20% at the smaller sizes.)
  - ⚠️ **`strings` cannot see a Swift literal ≤ 15 bytes** — they compile to immediate values, not
    data. Deploy-freshness checks in this repo use `strings <binary> | grep`, and `" per minute"`
    (11 bytes) returned **0 matches from a binary that contained it**. Grep a longer string.
  - **Filed, not done:** the floor could scale when an export *downscales* (keeping it only at
    native size), which would preserve M18-T2's guarantee and make a genuinely small pick possible.
    Measured here on static content only — it needs a busy-content measurement and its own task.

- 2026-07-28 (M19-T1): the guard fix, and two dead ends measured on the way.
  - **The live A/B, at the real 2 GB floor with no test hook** (4 GB APFS image, ~2 GiB of `dd`
    ballast landing 12 s into a 60 s take, free space crossing to 1.78 GiB): **before**, the take
    ran all 60 s and reported `finished (userStopped)` — the guard never spoke; **after**,
    `finished (diskAlmostFull)` at **15.3 s** wall clock, ~3 s after the crossing (2 s poll), and
    the file probes 14.89 s hvc1 4112×2570 + AAC. That is the whole bug and the whole fix, in two
    runs. It is now 04 §4.4's evidence; the `--test-disk-floor` hook stays only as a smoke check.
  - ⚠️ **`setTemporaryResourceValue` cannot poison the volume-capacity keys.** The obvious
    deterministic unit test — seed a `URL` with "1 byte free", assert the monitor ignores it —
    does not exist: a URL seeded that way still read the real 752,069,908,356. Don't spend an
    hour re-deriving it.
  - ⚠️ **`URL` value copies share one resource-value cache**, so the shipped `var probe = url;
    probe.removeAllCachedResourceValues()` idiom does not read "through a private copy": clearing
    the copy also unfroze the **original** (measured — it started returning fresh values too). It
    works, but it is a shared mutation, which is why the guard rebuilds from a path instead.
  - **What a unit test *can* see:** the boot volume moves by exactly the bytes you write —
    64 MiB → **67,108,864**, 5/5 trials, in 12–18 ms, on both capacity keys. So the regression
    test sets the floor 32 MB under a live reading, writes 64 MiB, and polls again; it fails on
    the held-`URL` code with "the volume fell below the floor and the guard stayed quiet"
    (verified by reinstating that code).

- 2026-07-28 (full review): 🔴 **The disk guard has never been able to see the disk filling.**
  `DiskSpaceMonitor(watching:)` captures one `URL` and polls
  `availableBytes(forVolumeContaining:)` on that same instance — and `URL` caches resource values
  per instance, so every poll after the first returns the free space as it was when the recording
  started. Measured on a 200 MB volume after writing 100 MB into it: the **held** instance still
  reported **204,754,944** bytes free while a **fresh** one reported **99,897,344**. So the 2 GB
  fail-stop floor only trips if the disk was already below it at Start, and ADR-007's "never
  fail-weird" is unmet for the most likely long-take failure.
  ⚠️ **The gate could not have caught it:** G3 §4.4 verifies the guard with
  `--test-disk-floor 500000` — a floor above the volume's free space, so it trips on the *first*
  poll, which a frozen reading satisfies. A test hook built to fire on demand says nothing about
  whether the thing it fires can observe change. Third instance of this `URL` gotcha in two days
  (M18-T3's recents, M18-T4's room figure), and the only one on a safety path.

- 2026-07-28 (M18-T6):
  - ⚠️ **`TabView` collapses macOS toolbar tabs into a `»` overflow menu when the window is
    narrow** — at 460 pt all four of ours hid behind a chevron, worse than the tall page it
    replaced. Nothing in the code said so and the AX dump looked healthy (`AXToolbar` present); the
    screenshot is what showed it, and Franco saw it before I did. A `Picker(.segmented)` over an
    enum can't collapse. After: 1137 pt → 437 pt at the tallest tab (90% → 35% of usable height).
  - ⚠️ **A SwiftUI segmented picker's buttons carry their label as the AX *description*, not the
    title** — a `menudriver`-style lookup by title finds nothing at all.
  - 🔴 **A python `s[:start] + new + s[end:]` rewrite silently ate a whole task entry.** M18-T5's
    doc update replaced everything from its own heading to `**Gate G18**:`, which spanned the
    already-filed M18-T6 — committed and pushed before anyone noticed. Third silent-replace
    casualty this session: prefer anchored single-string replaces, and check the surrounding
    headings after a range edit.

- 2026-07-28 (M18-T5):
  - ⚠️ **A deploy can report success and still be stale.** `swift build -c release` + `Scripts/bundle.sh`
    + `ditto` all succeeded, yet the running app showed the new hint line while missing the new badge
    suffix from the *same* build. A second round of exactly those three commands fixed it. Verify a
    deployed behaviour by re-running the leg; `strings` is only conclusive for long literals (Swift
    inlines short ones, so a missing 11-byte string proves nothing).
  - ⚠️ **A synthetic menu click doesn't activate the app, so synthetic keys go to whatever *is*
    frontmost.** Arrow keys aimed at the region overlay went to Firefox until the driver called
    `NSRunningApplication.activate` first — the overlay draws above everything at `.screenSaver`
    level, which makes it look focused when it isn't.
  - ✅ **The SCK↔view flip is its own inverse** (`sckRect(fromViewRect:displayHeightPoints:)`), so
    re-opening the overlay on a stored pick needs no second conversion — and no second place for a
    top-left/bottom-left error to hide.

- 2026-07-28 (M18-T4):
  - ✅ **A bare `Esc` works as a Carbon hotkey**, which is the only way to cancel the count-in: the
    overlay is `canBecomeKey = false` + `ignoresMouseEvents` on purpose, so no key event can reach
    it, and a global event monitor would need an Accessibility grant this product has never wanted.
    Measured registering (`status 0`) and *firing* in an accessory app that was not frontmost, with
    the screen locked. It swallows Esc system-wide while registered, so it lives only for the ~3 s
    of the count.
  - ⚠️ **`defaults write domain key 5` stores a STRING.** Without `-int`, the value comes back as
    `"5"`, so `object(forKey:) as? Int` yields nil while `integer(forKey:)` reads 5. A loader that
    used the former silently fell back to its default — and docs/06 documents these keys as
    user-inspectable, so a hand-written value is a real case, not just a test artefact.
  - ⚠️ **`BitrateModel` is honest but the *disk* is not all yours.** Predicted 4.16 MB/s at High
    60 fps vs **4.03 measured** on a real 23-minute take (3% conservative; 18–25% at Balanced). But
    a "room to record" figure must subtract the recording path's 2 GiB fail-stop reserve first:
    quoting raw free space promised 30 min on a 4 GiB volume for a take that stops at ~15. Measured
    after the fix: 2.7 GiB free → "about 2 min", 1.2 GiB → "Not enough room".
  - ⚠️ **Two harness mistakes worth not repeating.** A `swift script.swift` invocation pays a 1–2 s
    compile, so a "press Esc 1.2 s after clicking Start" test fired the key *before* the count began
    and recorded the screen instead — compile the drivers first (`swiftc -O`). And a `python`
    string-replace that doesn't match silently does nothing: a menu row I "added" was never in the
    file, which only the live dump revealed.

- 2026-07-28 (M18-T4, deploy hygiene): ⚠️ **Stop deploying with `kill -9`; quit through the app's
  own menu.** `swift tools/menudriver.swift click "Quit"` exits cleanly in ~2 s and **releases the
  SCK audio tap** (`pmset -g assertions` went 2 taps → 1 the moment it quit). A SIGKILL skips
  stream teardown entirely, which is precisely how a tap gets stranded — this machine is currently
  carrying an **18-hour-old** `AudioTap-…` assertion brokered by `replayd` for some earlier client.
  (That one predates this session, so it isn't ours, and Loom is a second SCK client here — but the
  mechanism is real and the clean path costs nothing.) The older note below is right that `killall`
  does *not* terminate the app; the fix is the menu's Quit, not a bigger hammer.

- 2026-07-27 (M18-T3):
  - ⚠️ **`URL` caches resource values per instance, and a menu holds its URLs across opens.** The
    recents cache keys on modification date, and a unit test that touched a file and re-read it
    still got the *old* date back — so a re-recorded or replaced file would have kept its first size
    and length forever. `removeAllCachedResourceValues()` before the read fixes it. Caught by the
    test, not by review or by reading the code.
  - **Out of scope, noticed:** three sites now open-code "load a URL's duration"
    (`Trimmer.trim`'s result, `TrimView.load`, `CaptureSelfTest`) and could adopt
    `MediaFile.duration`.
  - ✅ **A file's duration is a header read, not a scan.** 1–8 ms per file, and the **657 MB** file
    was the *fastest* of three (2.0 ms) while a 17 MB one took 7.8 — the first read pays for
    framework warm-up, not for bytes. Cheap enough for a menu row, still done off the open.

- 2026-07-27 (M18-T2):
  - 🔴 **"AVAssetWriter's H.264 path caps at 4096×2304" is false, and it had been load-bearing since
    M2.** The writer encodes 4112×2570 H.264 without complaint — it just moves to **Level 6.0**.
    Measured levels: 1280×800 → 3.2, 1920×1200 → 5.0, 2560×1600 → 5.0, 3686×2304 → **5.2**,
    4112×2570 → **6.0**. 4096×2304 is exactly Level 5.2's maximum frame size (36 864 macroblocks),
    so the number in docs was right for the wrong reason: it is a **decoder compatibility** ceiling,
    not an API limit, and nothing in the encode path tells you when you cross it. A "share" export
    that silently becomes Level 6.0 is the worst kind of regression — it writes, plays on the
    machine that made it, and fails on the phone you sent it to.
  - ⚠️ **"Scale the bitrate with the size" is only half a rule.** A symmetric scale looks obviously
    right and would have **softened every existing small export**: region and window recordings are
    usually below the 1920×1200 reference, so a 1280×800 clip would have gone 6 Mbps → 2.7 at the
    untouched default setting. Caught in review, not by the tests, which asserted the clamp I had
    written rather than the behaviour users had. Floored at the reference: rates rise, never fall.
  - ⚠️ **A re-encode's cost is not linear in pixels.** Same 14 s source: 1280 wide took 2.7 s,
    1920 → 2.1 s, 2560 → 2.6 s, but 3686 → **12.4 s** (5× the 2560 run for 2× the pixels). Worth
    knowing before quoting a progress estimate.

- 2026-07-27 (M18-T1, the second half — three of these correct the entry below, written hours
  earlier by the same task):
  - 🔴 **The defect the task was filed on does not exist. A lossless trim already cuts exactly where
    you ask.** `AVAssetExportSession` in passthrough writes an **edit list**: it stores from the
    preceding sync sample and maps presentation to start at the requested time. The trimmed file's
    first presented frame is **byte-identical** to the source frame at the in-point (md5, and ffmpeg
    agrees independently). Two milestones of copy, docs and a review finding said the in-point lands
    "up to two seconds early" — all of it inferred from "passthrough can only cut at a sync sample",
    and **nobody had opened a trimmed file and looked**. The real cost is that the cut frames stay
    *inside* the file (`ffprobe -ignore_editlist 1` → 13.56 s in a 10.00 s clip). Mechanism in 02 §6a.
  - 🔴 **`AVAssetExportPresetHEVCHighestQuality` + `timeRange` does not re-encode an HEVC source —
    it passes it through.** Same range, passthrough vs "highest quality": **23,578,074 bytes both
    ways**, 0.1 s, same 510 samples. Yesterday's entry below read that as "the preset *preserves*
    4112×2570, hvc1 and both audio tracks" — it preserved them because it never touched them, and
    `--precise` built on it would have written the lossless file while printing "precise re-encode".
    **Nothing about the output looked wrong; only a byte count said so.** Setting
    `session.videoComposition = AVVideoComposition(propertiesOf:)` forces the real encode, and a
    unit test now fails without that one line.
  - ✅ **The `non-monotonic timestamps` blocker was `probe`'s own bug, and never
    precise-mode-specific — every trim triggered it, lossless included.** Our capture emits B-frames
    (459 of 923 samples step back in PTS on a 20 s recording; DTS clean), and `probe` fell back to
    PTS for the four boundary samples that carry no DTS — comparing a PTS against neighbouring DTS.
    It now judges a track on one clock or the other, never both. The DTS pass still examines 919 of
    923 samples, so the check didn't go quiet; eight files re-probe clean.
  - ⚠️ **A re-encode is often the *larger* file.** Capture is frame-on-change; a re-encode emits
    constant frame rate. On a quiet 10 s range: lossless 2.2 MB / 0.6 s, precise **3.3 MB / 7.8 s**.
    "Re-encode = smaller" is a habit from camera footage and doesn't hold for screen recordings.
  - 🔴 **Closing a SwiftUI `Window` does not tear down its `@State`, so the Trim preview kept
    playing with no window to stop it** (Franco hit this in the deployed build; measured: playhead
    72.22 s → 85.51 s across a 10 s closed window). The only escape was opening the window on a
    *different* clip, because `load()` early-returns when the target is unchanged. `.onDisappear`
    **does** fire for a `Window` scene, so pausing and dropping the player there fixes it — verified
    after: play → close → 10 s → reopen reads `pos 0, playing 0`.
  - ⚠️ **Driving the Trim window needs one long-lived process: it closes when the app loses
    focus**, like the setup window (M16-T6). Each short-lived AX call activates the app, exits, and
    the window is gone before the next one runs. Also, an app with `LSUIElement` lists **no AX
    windows at all** until it is active — activate, then poll `kAXWindowsAttribute`.
  - ⚠️ **A seek from the player's scrubber lands on a keyframe**, so an in-point set by scrubbing has
    *no* lead-in and the window correctly says nothing. It cost a wrong conclusion here (the line
    looked broken); setting the in-point mid-playback, where the playhead is at an arbitrary time,
    showed it immediately. Users will see the line mostly when they set In while playing.
  - ⚠️ **An export receipt is validated only at launch.** `SettingsStore.loadLastExport` checks
    `fileExists`, but `expireStaleReceipt()` — the one that runs at every menu open — only checks
    *age*. Delete an exported file mid-session and the row stays, with every action in its submenu
    silently doing nothing (Franco, 2026-07-27). Same class as M18-T4 item (4), one row up.

- 2026-07-27 (M18-T1, measured before building — ⚠️ two of the four entries below are corrected
  above; kept unedited, because the correction is the lesson):
  - 🔴 **The lossless-trim keyframe gap is UNBOUNDED, not 2 s.** `AVVideoMaxKeyFrameIntervalDurationKey: 2`
    caps encoded frames; capture is frame-on-change, so a quiet stretch emits none and no keyframe
    lands. Measured on a 23-minute recording: in-point 61 s → real cut **57.63 s (3.37 s back)**;
    other probes gave 0.37–1.29 s. docs/03, docs/02 §3 and the trim window's caption all said
    "up to two seconds"; 02 §3 is corrected, the UI copy is M18-T1's job.
  - ✅ **Finding the real cut point is cheap.** `AVAssetTrack.makeSampleCursor(presentationTimeStamp:)`
    then `stepInDecodeOrder(byCount: -1)` until `currentSampleSyncInfo.sampleIsFullSync` — the walk is
    bounded by keyframe spacing, not file length: **0.0–0.9 ms, 20–116 steps** across a 23-minute file.
    Safe to call live while the user drags. ⚠️ `sampleIsFullSync` is an `ObjCBool` — `.boolValue`.
  - ⚠️ **Two assumptions of mine about `AVAssetExportSession` presets were wrong.** They do **not**
    flatten audio: a time-ranged export of a 3-track recording kept **both audio tracks separate**
    (2ch + 1ch) and cut frame-exactly (2→5 s requested, 3.00 s out). And `HighestQuality` is not the
    high-fidelity option — it **downscaled 4112×2570 → 3840×2400 and re-encoded hvc1 → avc1**.
    **`AVAssetExportPresetHEVCHighestQuality` preserves all of it**: 4112×2570, hvc1, both audio
    tracks, exact duration. So a precise trim is a **preset choice, not a reader/writer pipeline** —
    docs/03's "reuse `Exporter`" was the wrong mechanism (that path downscales to 1920 and mixes
    audio), but the right one is smaller than a pipeline, not bigger.
  - 🔴 **OPEN:** the re-encoded output makes `tools/probe.swift` warn **`non-monotonic timestamps:
    2 of 130 samples step backward`**, where the source is clean. Almost certainly B-frame reordering
    that `MovieRecorder` never emits, and harmless in a player — but every prior gate recorded
    "probe monotonic-clean", so it must be settled before precise mode ships.

- 2026-07-27 (v1.9.0 cut) — ✅ **FIXED by M22-T5; kept because the shape recurs.**
  `Scripts/release.sh` ended with an interactive `Push? [y/N]`, and the run-it-in-the-background rule
  (a foreground timeout SIGTERMs a cut mid-encode) meant stdin was never a terminal: it read N every
  time, printed `Not pushed`, and otherwise looked like a success while main and the tag stayed local.
  **The lesson that outlives it:** a prompt is a silent failure in any non-interactive path — decide
  by capability (`[ -t 0 ]` ⇒ ask, else act and say so), never by asking into the void.

- 2026-07-27 (M17-T2): **A fix can be green in tests, correct in review, and still inert — and the
  only thing that says so is running it.** The idle menu never rendered `lastFailure`, so a Start
  that failed looked like a no-op. Adding the row was necessary and **not sufficient**: `endSession()`
  clears `lastFailure`, and a start failure *does* have a session — the engine yields `.failed`
  through it and finishes the stream, so teardown lands right on top of the message microseconds
  later. The code even carried a comment asserting the opposite ("Start failures survive because they
  set this after the session is already over"); it had been wrong since it was written.
  - **Both of my new unit tests were vacuous and still passed.** They drove `apply(.finished)`, which
    never reaches `endSession()` — that only runs after the event stream drains. One passed for the
    wrong reason and one failed for the wrong reason; the failing one is what exposed it. **A test
    that cannot reach the code it names is worse than no test**, because it reports safety.
  - Found live only because **notification banners can be suppressed while replay is armed** — the
    backup channel for this message was silent at exactly the same time. The menu was literally
    displaying that caveat while I watched Start do nothing.
  - ✅ **A positive bridge finding, for once:** the `.menu` MenuBarExtra bridge **does** carry a
    `Menu` inside a `Menu` with its own inline `Picker`, checkmark and all, two levels deep. Most
    entries here are the bridge dropping something (a second `Image`, `.disabled` dimming), so this
    one is worth knowing before anyone assumes nesting is impossible.
  - ⚠️ **Cosmetic consequence of ruling (a):** after an app relaunches, its new window and the stale
    pick can render as two identically-labelled rows, one live and one `(closed)`. Honest, since the
    pick genuinely no longer points at anything, but it reads oddly.

- 2026-07-27 (M17-T1): **Two whole mechanisms were designed, built and deleted because the
  measurement arrived after the design.** Full platform detail is in 02 §1c; what belongs here is the
  process lesson, which cost most of the task:
  - The plan said "a window closing needs a presence watch, because `.app` proved SCK stays silent
    when its subject goes away" (§1a). Reasonable, precedent-backed, and **wrong**: a *window* filter
    ends the stream, immediately, for both a close and an app quit. `WindowPresenceWatch` — plus its
    46 ms poll, its interval justification, and a second `SCShareableContent` accessor — went in and
    came back out. **The `.app` precedent did not transfer, and nothing but a live run would have
    said so.**
  - Before that, the poll *interval* was tuned on a measurement (46 ms/probe ⇒ 5 s not 1 s) — good
    discipline spent on a mechanism that shouldn't have existed. **Measuring a design's parameters
    is not the same as measuring whether the design is needed**, and the cheap version of the second
    question (start a capture, close the window, see what happens) was available the whole time.
  - **A rig that cannot reach the state you need will happily report a wrong answer instead of an
    error.** Three attempts to destroy an AppKit window from the stimulus app left it in SCK's
    enumeration; each one looked like the platform saying "closes are undetectable". Driving a real
    app (TextEdit closing a document) took two minutes and gave the opposite answer.
  - **The positive control is not optional.** The same-app bystander assertion returned "0 matching
    pixels" — a clean pass — while the detector was simply looking for the wrong colour (see 02 §1c
    on the display-profile shift). Only running the same check against a capture that *should* match
    exposed it. Every content assertion needs its negative *and* its positive case.

- 2026-07-27 (M16-T5): **A `MenuBarExtra` label renders only its FIRST `Image`. A second one
  contributes nothing — not even width.** `Text` is fine; images are not. Measured on the live app by
  reading the status item's AX frame while swapping one view:

  | Label content | Status-item frame |
  |---|---|
  | icon only (baseline) | `27×24` |
  | icon + `Text("XX")` | **`51×24`** — text renders |
  | icon + `Image(systemName: "waveform")` | `27×24` — **second image dropped** |
  | icon + meter **composited into the same NSImage** | **`39×24`** ✅ |

  - This is why the armed badge was always drawn *into* the icon; M16-T5's meter had to follow. If a
    label needs a second glyph, composite it — an `HStack` will not do it.
  - ⚠️ **The same shape sits in `StatusIconView` for the replay-saved checkmark**
    (`if replaySavedFlash { Image(systemName: "checkmark.circle.fill") }`) — by this measurement it
    has **never rendered**. Not fixed here (out of M16-T5's scope); it wants the same compositing.
  - Locating the item for a screenshot: AppleScript's `position of menu bar item 1` returns `0,24`
    (useless), but the raw AX API on `kAXExtrasMenuBarAttribute` gives the real frame — see
    `scratchpad/itemframe.swift`. Without it you cannot crop a menu bar full of live third-party
    items, and diffing a wide strip is meaningless (CPU% and network counters change every second).
  - ⚠️ **`md5` of two `screencapture` PNGs is NOT a pixel comparison** — identical pixels can encode
    to different bytes. A first pass "measured" three distinct states that way; decoding and
    comparing pixels showed two. Compare decoded pixels (`scratchpad/pixdiff.swift`).

- 2026-07-27 (M16-T4): **Microphone levels, measured — two mics in the same quiet room are 23 dB
  apart, and a muted one is exactly zero.** Peak amplitude per 500 ms window, read through the real
  SCK mic path (`scratchpad/miclevels.swift`, kept out of the repo — it's a throwaway rig):

  | Source | Peak: median | Peak: quietest window | RMS: median |
  |---|---|---|---|
  | AirPods Pro, quiet room | −65.5 dBFS | **−78.9 dBFS** | −82.7 dBFS |
  | MacBook Pro Microphone, same room | −42.7 dBFS | −45.5 dBFS | −52.9 dBFS |
  | **Muted** (`set volume input volume 0`) | **−∞** | exactly `0.000000` | −∞ |

  - **A muted device delivers exact digital zeros** — all 16 windows, no dither. So the failure this
    task exists to catch is unambiguous at the sample level; the whole difficulty is not false-firing.
  - **The 23 dB spread between devices is why a threshold can't be eyeballed.** Anything tuned to the
    built-in's floor (−45) calls a live AirPods room silent. `MicrophoneSilence.floorDBFS = -90` sits
    ~11 dB below the quietest *real* window measured.
  - ⚠️ **SCK's first ~1 s of mic audio can be exact zeros** — two full 500 ms windows on a Bluetooth
    route, none at all on the built-in, so it is route-dependent. Any silence detector must judge a
    *run* (10 s here), never a buffer, or every AirPods recording fires at start.
  - `AVCaptureDevice.default(for: .audio)` follows the system default, so a measurement rig silently
    changes device when AirPods connect mid-session. Name the device in the output, or you will
    compare two rooms and call it noise.

- 2026-07-27 (M16-T3): **An SCK stream with `capturesAudio = false` and no mic opens no audio tap —
  so nothing but our own assertion keeps the Mac awake.** Completes the M16-T1 note below. The tap
  assertions are attributed to `replayd` (pid 510), never to the client that asked for them, so they
  can't be attributed by pid — count them instead, A/B against a baseline:

  | State | `pmset -g assertions \| grep -c "Created for PID: 510"` |
  |---|---|
  | Deployed app armed, no CLI (baseline) | 3 |
  | \+ CLI armed, **all audio off** | **3** — added nothing |
  | \+ CLI armed, system audio on, no mic | 4 |
  | after both exited | 3 |

  - ⚠️ **Don't read a raw count as "our" taps** — a first attempt did, and the running menu-bar app's
    own armed stream was in the number. The baseline is the whole measurement.
  - Consequence for M16-T4/T5 and anything power-related: "no audio at all" is the only configuration
    where an armed Mac could idle-sleep — and ADR-018 keeps it awake there anyway, on purpose.
  - **UNFIXED edge, by ruling (Franco, 2026-07-27):** with both audio sources off, `ReplayMuxer`'s
    save window loses the clock it anchors on. Its own comment explains why audio is the anchor —
    "audio flows continuously … anchoring at the video ring alone would save old content" — and with
    no audio, a still screen (frame-on-change) can leave the newest video frame minutes old, so a save
    grabs that instead of the trigger moment. Inherent, not introduced; the configuration couldn't
    exist before M16-T3. Fix would be a wall-clock fallback anchor in the muxer.

- 2026-07-27 (M16-T2): **`CGDisplayPixelsWide/High` return POINTS, not pixels** — 2056×1285 on this
  display, where SCK captures 4112×2570. `CGDisplayCopyDisplayMode(id)` gives both honestly
  (`width`/`height` points, `pixelWidth`/`pixelHeight` pixels) and its pixel size is the one that
  matches the frames. Anything sizing a buffer or a bitrate off the `PixelsWide` name is off by the
  backing scale — 4× the pixel count on a Retina Mac. (`NSScreen.frame × backingScaleFactor` agrees
  with the mode's pixel size; that's the seam `DisplayOption` carries into AppCore.)
  - Related, same task: **replay always encodes Balanced** (`ReplayEncoder` hardcodes
    `preset: .balanced`, per docs/04 §6.1's 2026-07-16 amendment), so the Quality setting does
    **not** change what an armed ring costs. Any footprint math that takes the user's preset as an
    input is wrong — it would quote a High user ~1.6× the truth.

- 2026-07-27 (M16-T1): **An SCK stream keeps the Mac awake even if you release your own power
  assertion — `coreaudiod` holds one for the audio tap, on `replayd`'s behalf.** M16-T1 was filed as
  "drop `SleepGuard` while armed and the Mac idle-sleeps again"; that premise is false, and one
  `pmset` snapshot during a `replay-arm` run is all it takes to see it:
  - Alongside our own `PreventUserIdleSystemSleep` there is a second one — owner `pid 184(coreaudiod)`,
    named `com.apple.audio.AudioTap-<uuid>.context.preventuseridlesleep`, with `Created for PID: 510`.
    **Pid 510 is `/usr/libexec/replayd`, the ScreenCaptureKit daemon** — so it is attributed to SCK,
    not to us, and it will not appear in any search for your own bundle ID.
  - **`--no-mic` does not remove it**: the system-audio tap alone is enough, and `capturesAudio = true`
    is unconditional today (M16-T3's finding). It appears at the same age as our own assertion and
    disappears when the process exits, so it is per-stream and released at teardown — **the only lever
    that releases it is tearing the stream down**, not any flag on our side.
  - Consequence for anything power-related: `SleepGuard` controls what `pmset` *blames*, not whether
    the Mac sleeps. Decide power behaviour at the stream-lifetime level (ADR-018 chose not to).
  - Read the assertion picture with `pmset -g assertions` (per-process, with the `Created for PID`
    attribution) and `pmset -g` (one "sleep prevented by …" line, process names only). The latter is
    the fast check; the former tells you who really holds it.
  - **UNMEASURED, worth one run when a display-sleep lever is allowed** (out of scope for M16-T1, and
    invisible on this machine, which is set to `displaysleep 0`): nothing prevents *display* sleep
    while armed, and 02 §7 records that starting a capture against a slept display **wakes it**. If
    those compose, `ReplayController`'s 5 s retry loop would bounce the display back on every five
    seconds after it sleeps — louder than the assertion ever was. Two facts, no measurement joining
    them yet.

- 2026-07-24 (M15-T1): **`VTCompressionSessionCreate` BLOCKS — it does not fail — once the hardware
  encoder pool is exhausted, and the block is ~120 s.** This is the whole story behind the flaky
  suite, and it is not what the 2026-07-21 note assumed. Measured mechanics:
  - **14 tests can hold a live session at once** (`ReplayMuxerTests` 8/8 build a `ReplayEncoder`,
    `ReplayEncoderTests` 6/7). Swift Testing parallelises across suites, so they all race.
  - Under exhaustion the tests **still mostly pass — after ~122 s each**. Because they block in
    parallel on the same resource, the whole run lands at ~123 s, not 14×120 s. So **a green run is
    not proof of health; wall clock is the real signal.** Judge this suite by duration, not exit code.
  - The failures that do appear are downstream symptoms (`nothingBuffered`, `files.count == 0`), which
    is why the failing test names moved around run to run and never pointed at the cause.
  - `@Suite(.serialized)` on the two suites caps it at ~2 concurrent sessions: **8/10 runs failing →
    0/20, slowest 3 s.**
  - **`ReplayEncoder.deinit` already invalidates its session — nothing leaks and production was never
    affected.** This was purely a test-harness concurrency bug.
  - **Killing the leaked `VTEncoderXPCService` processes does NOT heal it.** Tried it: a fresh service
    is re-exhausted immediately by the same 14-way race. Encoder-service age is a symptom, not a lever.
  - ⚠️ **Don't run `swift test` under a short foreground timeout.** A 2-minute cap SIGTERMs it
    mid-encode — exactly the degrade-the-next-run trap the 2026-07-21 note warns about. Background it,
    or give it minutes. (Learned by doing it.)

- 2026-07-24 (M15-T3): **a hard kill mid-export leaves an AVFoundation temp we don't sweep.** With
  `shouldOptimizeForNetworkUse = true` (faststart), `AVAssetWriter` writes a companion
  `<name>.sb-<hex>` beside its output and rewrites the moov at finalize. A `kill -9` strands it. It
  doesn't end with `.partial`, so `recoverOrphanedPartials` ignores it, and its extension isn't `mov`/
  `mp4`/`gif`, so nothing lists it — harmless but real litter in the output folder. Deliberately not
  swept: matching an undocumented Apple naming convention is the kind of guess that breaks on an OS
  update. Revisit only if a user ever notices one.

- 2026-07-24 (M15-T1, out of scope — for a future task): `ReplayMuxerTests.swift:106` and `:128` call
  `DispatchSemaphore.wait()` from an async context — a warning today, **an error under Swift 6 language
  mode**, which the package will eventually want (it is pinned to `.v5` in `Package.swift`). Pre-existing,
  untouched here. Slot into a debt task alongside any future language-mode move.

- 2026-07-22 (M10-T4): **SwiftUI's `VideoPlayer` CRASHES the app in our build.** Opening the Trim
  window with `VideoPlayer(player:)` fatal-errored at launch — SIGABRT, `swift::fatalError` →
  `getSuperclassMetadata` inside `_AVKit_SwiftUI` while instantiating generic metadata. It's the
  Command-Line-Tools (no-Xcode) SPM build: SwiftUI's generic `VideoPlayer` can't resolve its metadata.
  Fix: wrap AppKit's concrete **`AVPlayerView` in an `NSViewRepresentable`** (`TrimView.PlayerView`) —
  no generics, no crash. Any future SwiftUI+AVKit view should assume `VideoPlayer` is off-limits here.
  Also: `AVAssetExportSession(.passthrough)` gives an **exact-duration** trim via an edit list (not a
  keyframe-snapped longer clip) while staying lossless (same codec) — cleaner than expected.

- 2026-07-22 (M10-T4 debt): **`LastExport.menuTitle` infers the verb from the output extension**
  (`.mp4`→"Exported to MP4", `.gif`→"Saved as GIF", `.mov`→"Trimmed"). Correct today — the three
  derive actions write distinct extensions and no other path routes a `.mov` through `performExport`
  (`lastReplay` is separate) — but the invariant is unenforced. If a future `.mov`→`.mov` derive
  appears, store the verb/kind in `LastExport` instead of inferring it.

- 2026-07-21 (M10-T3): **`AVAssetReaderVideoCompositionOutput` ignores the composition's
  `frameDuration` for the OUTPUT rate** — it emits one frame per SOURCE frame. Setting
  `composition.frameDuration = 1/15` on a 30 fps source still yields 30 output frames (measured:
  srcFrames=34 → gifFrames=30). `renderSize` DOES scale. So GIF fps capping is a **PTS subsample in
  the reader** (keep a frame only once ≥ 1/fps has passed since the last kept), not a composition
  setting. Also: a synthetic MovieRecorder fixture fed in an instant burst loses ~2/3 of frames to
  HEVC encoder warmup (30 fed → 11 kept) — pace the feed (`usleep`) so the fixture is dense enough to
  exercise the subsample (30 fed → 34 kept → 15 GIF frames).

- 2026-07-21 (M10-T2 review deferrals, Franco-approved): three low-severity edges left out of the
  T2 commit. **① Pre-existing doc bug:** in `RecordingNotification.swift` the "The armed stream's
  mic died…" comment is stranded above `loginItemFailed()` (whose real comment is the next two
  lines), and `replayMicrophoneLost()` has none — predates M10, fix in a separate `docs:` commit.
  **② Quit mid-export can leave a partial `.mp4`:** the export `Task` isn't awaited on `⌘Q` (unlike
  recordings' `stopAndWaitForFinalize`); the partial is a *derived* share copy (source untouched,
  re-doable), so accepted, not fixed. **③ Export during record+replay is best-effort:** reachable
  via the replay-receipt submenu while capturing; it adds encode/decode load onto the live encoders
  and can fault VT (-12912), but fails cleanly (notification + `exportInProgress` cleared, no wedge).

- 2026-07-21 (M10-T2, extends the M10-T1 VT note below): **the fix for the encoder-oversubscription
  flakiness is to GATE the one hardware-encode integration test out of the default parallel run.**
  Shrinking it (small source, few frames, tiny target) did NOT fix it — ANY added live encode layered
  onto the other encoder suites faults VideoToolbox (-12912) ~half the time; confirmed by
  bisection (suite is 3/3 green without the test, majority-fail with it). It runs reliably in
  isolation (`--filter`), so it's `@Test(.enabled(if: env["SCREENREC_HW_ENCODE_TESTS"] == "1"))` and
  exercised via `SCREENREC_HW_ENCODE_TESTS=1 swift test --filter ExporterTests`. The default
  `swift test` skips it and stays stable. Real transcode coverage = the CLI verify (ADR-011).

- 2026-07-21 (M10-T1 debt): **`Exporter.FailureBox` + the `drain` loop duplicate
  `ReplayMuxer.AppendFailure` + `append`** — the first-error box is line-for-line equal; the drain loops
  differ only in source (pull-from-`AVAssetReaderOutput` vs replay from an in-memory array). A shared
  `Support/FirstError` (and maybe a shared drain skeleton) would DRY both, but the extraction touches
  `ReplayMuxer`, so it was **deferred from M10-T1** as out-of-scope (code-review finding ⑦, Franco
  approved deferring). Slot into a debt task.

- 2026-07-21 (M10-T1 test infra): **VT hardware-encoder oversubscription makes encoder-heavy tests
  flaky.** swift-testing parallelizes across suites, so several tests each holding a
  `VTCompressionSession` run at once; Apple Silicon allows only a handful concurrently. Two
  hardware-encode-heavy integration tests (each: build an HEVC fixture *then* re-encode) pushed it over
  → the shared 4 s readiness precondition in `SyntheticBuffers` failed ("encoder session never became
  ready") and the export tests hung ~120 s. Fix applied: **one integration test per new encoder-heavy
  suite** (merged the 640 + 2400 cases into a single 2400×1500 test that proves codecs, the 2→1 audio
  mix, faststart, *and* the downscale). Also: **killing `swift test` mid-encode (SIGTERM) degrades the
  HW encoder for the *next* run** — don't loop-run tests in a killable wrapper; a lone `swift test` is
  ~1.3 s.

- 2026-07-21 (M9-T5): **retired `MicSwapSpike.swift`** (822 LOC, 8 modes) — completed research
  scaffolding. Its findings are recorded (02 §4 / M3-T7, ADR-012 / M6-T4) and the recovery it explored
  is shipped (M8-T1/T2); the **M8 G8 live gates are the standing regression** — mic recovery is
  re-verified live against the app if ever needed, not via a CLI spike. Removed the file, the
  `mic-swap-spike` dispatch, and the printUsage modes block. Recoverable from git (parent of the M9-T5
  commit) if a two-stream harness is ever wanted again.

- 2026-07-21 (deploy gotcha): **`killall ScreenRec` did NOT terminate the running menu-bar
  instance** (PID unchanged after `killall -w`), so the subsequent `open dist/.../ScreenRec.app`
  merely re-focused the stale instance — you end up with the new files on disk but the OLD binary
  running (and the change appears "missing"). Reliable redeploy: read the PID
  (`ps -Ao pid,comm | grep MacOS/ScreenRec`), `kill -9 <pid>`, confirm it's gone, replace the
  bundle (`rm -rf /Users/Shared/ScreenRec.app && ditto dist/ScreenRec.app /Users/Shared/ScreenRec.app`),
  `open`, then **verify the PID changed**. Sanity-check a change is really in the deployed binary
  with `strings <bundle>/Contents/MacOS/ScreenRec | grep '<a copy string from the change>'`. TCC
  grants persist across the swap (same DR + same path).

- 2026-07-20 (M8-T2 live-rig lessons):
  - **"Open the case" does NOT reconnect AirPods to a Mac as an input device — in-ear does.**
    The first leg-1 attempt cued lid-open and the device never rejoined the HAL during the
    window (the run looked like a rescue failure; it was a rig failure — the machinery passed
    untouched on the retry with an in-ear cue). Any future mic-reconnect leg: cue "put them in
    your ears", and poll `list-mics` before starting a leg that needs them bound.
  - **Voice cues via `say` beat clock-watching for human-in-the-loop legs**: schedule
    `(sleep N; say "…") &` beside the capture; the human just reacts. Bonus: the cue audio
    lands in the system-audio track as a timeline marker. (Also handy: `say` re-prompts +
    a `list-mics` poll loop to detect the human completing a step.)
  - `log show` hides `os.Logger` `.info` lines without `--info` — absence of rescue log lines
    proves nothing at default level.

- 2026-07-20 (M7-T2): four rig/platform finds.
  - **🔴 menudriver's `dismiss` posted a GLOBAL Escape (CGEvent)** — whenever the menu wasn't
    actually tracking, that Esc went to the *focused* app. With Franco using the machine, focus
    was often the driving terminal — and Esc there **interrupts the agent session**, which looked
    exactly like Franco cancelling tool calls (he wasn't; he caught it: "something is
    interrupting you and it's not me"). Fixed: `dismiss` now performs **AXCancel on the menu
    element** — targeted, no-op when nothing's open, can never hit a bystander app. Lesson for
    every AX tool here: never post global key/mouse events when a targeted AX action exists.
  - **The harness auto-rejects a verbatim retry of a command the user declined.** After Franco's
    deliberate "stop for a moment" rejection, resending the identical command string bounced
    twice with the same "user doesn't want to proceed" — reworded/split commands went through.
    Adjust the command after any rejection; never resend it byte-identical.
  - **`grep -cE "error|warning"` in a `&&` chain is a trap**: zero matches ⇒ exit 1 ⇒ the rest
    of the chain (bundle.sh, the deploy) silently skips — I "deployed" a stale dist twice while
    the release build had the fix. Pipe to `grep` for display only, never as a chain link.
  - **`.disabled(true)` on a Picker row doesn't survive the `.menu` MenuBarExtra bridge**
    (measured via AX: the not-running row reads enabled, renders undimmed) — same family as
    text color / destructive role (docs/06 "Menu text styling"). And `SCShareableContent`'s app
    list includes windowed system chrome (Dock, Control Center, SystemUIServer, Stats) — a
    picker over it needs the `activationPolicy == .regular` filter (view layer;
    NSRunningApplication is AppKit).

- 2026-07-20 (M7-T1 verification-rig traps — cost three false failures and one lingering window):
  - **zsh backgrounding: `(A && B &)` runs A in the FOREGROUND and backgrounds only B.** Every
    "app isn't running" failure in the M7-T1 quit-leg attempts was the detached
    `(sleep N && pkill -x TextEdit &)` — sleep blocked, then pkill fired *right before* the
    recording started. The engine was correct each time. Use `(A; B) &` to background a
    sequence. Corollary of the standing lesson: assert the precondition (is the app running
    *now*?) immediately before the measurement, not seconds before.
  - **Interpreted tool scripts run as `swift-frontend -interpret <file>`** — `pkill -f "swift
    foo.swift"` doesn't match; `pkill -f foo.swift` does. Franco had to point out the stimulus
    window was still up.
  - A freshly `open`ed app takes a few seconds to appear in `SCShareableContent.applications`
    (02 §1a) — settle ~5 s before asserting listability.

- 2026-07-20 (M7-T1 /simplify findings skipped, with rationale — future inputs, not debt to hide):
  - **`ContentSelection` shape:** the altitude reviewer argued `.app` vs `.display` conflates
    "what scope" with "which display" (an app filter is display-scoped; the `.app → main
    display` rule lives in the engine). Kept as-is: it's docs/03's prescribed seam and matches
    T2's single-axis picker (Entire Screen / apps in one list). Revisit only if multi-display
    app capture or window-level capture ever becomes real — then `.app(bundleID:, on:)`.
  - **StallWatchdog under app filters:** measured (02 §1a) that app filters deliver frames
    continuously even when static — so silence there may be *stronger* stall evidence, and the
    watchdog could arguably stay attached. Kept the approved don't-attach ruling (one 34 s
    measurement isn't enough to bet the premise on; cost is only a diagnostic log line).
  - **Test-latch consolidation:** five near-identical private `Flag`/latch helpers now exist
    across test files; candidates for a shared RecorderCoreTests support file if one ever
    appears.

- 2026-07-20 (Route 2 coherence spike — PASSED, the M6-T4 mic-recovery gate is green): extended
  `mic-swap-spike --two-streams-pts` — run recording stream A (video + system audio) and a mic-only
  stream B concurrently, sample each output's host-clock PTS every 5 s, fit the drift of (A's PTS −
  B's mic PTS) vs time. 90 s / 18 samples: **sysAudio↔mic slope +0.6 ms/min, video↔mic +4.3 ms/min**
  — essentially zero (the ~50 ms constant sysAudio−mic offset is fixed capture latency, not drift).
  So two SEPARATE `SCStream`s share a coherent host clock on macOS 15 (the docs/02 §5 "coherent by
  construction" prior, now measured *across streams*), settling ADR-001's cross-stream concern.
  **Route 2 is viable.** If built (a ~2-task M6-T4 feature): a fixed-format resampled mic input + a
  reconnect watchdog that rebuilds stream B, mic muxed against the shared epoch. Route 2 preserves the
  replay buffer — the reason Franco rejected the cheaper auto-re-arm alternative (proven live to wipe
  the last minutes of video+audio; see the armed-replay note below). **Phase B also PASSED
  (2026-07-20):** `mic-swap-spike --two-streams-record` muxes both streams into one real `MovieRecorder`
  `.mov`; recorded 70 s with beepflash, the mic (stream B) held a **constant ~16 ms offset** to system
  audio (stream A) with no drift over 62 s (the 16 ms is the test's acoustic speaker→mic delay, absent
  in the real feature). So both source coherence and the end-to-end mux are confirmed — Route 2 is
  viable, gate fully green.

- 2026-07-20 (armed-replay mic loss — MEASURED, informs M6-T4 mic recovery): Franco's worry
  confirmed live with clip evidence. Arm replay with the AirPods mic (Automatic → AirPods, 24 kHz),
  then case the AirPods: the mic ring stops filling (screen + system audio keep going), a "mic
  disconnected while armed" notification fires, no menu-level indicator. **Reconnecting the AirPods
  does NOT restore the mic** — same SCK rule as recording (bound once at arm, a died device is
  unbindable to that stream; `ReplayController`'s `.microphoneLost` only notifies, never rebuilds).
  Proof by three saved clips (30 s buffer): #1 armed+AirPods → mic track 24 kHz; #2 case → wait past
  the buffer → reconnect → save → **no mic track at all**; #3 after re-arm → mic track 24 kHz back.
  So the ONLY recovery today is **re-arm** (or any rebuild event: record start/stop, a settings
  change). This bites harder for armed replay than for recording (armed runs all day; AirPods
  case/reconnect constantly), which reframes the M6-T4 mic-recovery judgment toward "worth it" — and
  specifically toward **Route 2** (rebuild a mic-only stream on reconnect, the only route that
  handles reconnect). First step if built: the §3.5 PTS-coherence spike (the Route 2 gate).

- 2026-07-20 (M6-T4 distribution, deferred): how a self-signed build runs elsewhere, worked out for
  Franco's "share it without a paid Developer account" question. The shipped app is
  `Authority=screenrec-dev` (self-signed, TeamIdentifier not set, **no entitlements embedded** — so no
  AMFI launch block). On another Mac it is NOT double-click-runnable (Gatekeeper blocks an unidentified
  developer), but it DOES run after a **one-time override**: System Settings → Privacy & Security →
  "Open Anyway" (macOS 15/Sequoia dropped the old right-click→Open shortcut), or strip quarantine with
  `xattr -dr com.apple.quarantine <app>`. After that, TCC grants (screen/mic) work normally — grants
  attach to the stable designated requirement, which self-signed apps have. The "unverified developer"
  warning is unavoidable without Developer ID + notarization ($99/yr). Building from source elsewhere
  needs the recipient to create their own `screenrec-dev` cert first (devsign.sh stops otherwise) — a
  ~15-min developer task, not a non-technical one. **Open question for when this is built:** is ad-hoc
  signing (`codesign -s -`) more portable for a *downloaded* app than a cert the target doesn't trust?
  Untested — only one Mac here. Revisit at M6-T4 when Franco actually shares.

- 2026-07-20 (M6-T12 discard): two things worth keeping.
  - **Menu text styling in a `.menu` MenuBarExtra goes through AppKit, which keeps only the text.**
    SwiftUI `.foregroundStyle`/`.foregroundColor` and `Button(role: .destructive)` are dropped
    (measured — a destructive role rendered plain gray). An **attributed** label whose color is an
    `NSColor` IS honored: `Text(AttributedString(NSAttributedString(string:, attributes:
    [.foregroundColor: NSColor.systemRed])))`. The plain string still reaches Accessibility as the
    row title, so `menudriver` finds it. Same family as the frozen header clock and the un-two-toned
    folder path — style a `.menu` MenuBarExtra through AppKit, not SwiftUI modifiers. Documented in
    docs/06 "Menu text styling".
  - **Discard vs a concurrent fail-stop — two known edges left unfixed (Franco's call 2026-07-20).**
    /code-review found four ways a confirmed discard could still leave a file. B (`.failed` writer)
    and C (moved/`.strandedAt` path) are fixed by removing the file unconditionally + at the stranded
    path in the discard branch. A and D are timing races with a *fail-stop that already saved a
    playable file*: A — a fail-stop finalizes+saves while the confirmation alert is open, and the
    discard confirmed afterward no-ops on a now-nil session; D — an external move fires the sentinel's
    stop at the same instant as the discard click, so the loop can read `discardRequested` false and
    finalize at the moved path. Both need a hardware fail-stop in the exact discard-decision window
    (rare), and both leave a *complete* recording, not a corrupt one. The robust fix is an
    AppState-level "convert a concurrent finalize into a discard" (delete the finalized file), but its
    correctness hinges on whether the MainActor consume task runs during `NSAlert.runModal()` — verify
    that empirically before building it. Revisit if it bites.

- 2026-07-20 (M6-T11 live mic list): the enumerator and the resolver were two AVFoundation layers
  with *different* freshness. `AVCaptureDevice.DiscoverySession` caches its device list in a
  long-running process (the stale picker), but `AVCaptureDevice(uniqueID:)` — the capture-side
  existence check — is **live per device** (it bound Franco's hot-connected AirPods while the list
  still didn't show them; that's why replay had his voice). The fix leans on exactly this split:
  the CoreAudio HAL (`kAudioHardwarePropertyDevices`) is the live *enumerator*, `AVCaptureDevice`
  the live per-UID *validator/namer*. HAL device UIDs are byte-identical to AVCaptureDevice's and
  to what SCK binds (`BuiltInMicrophoneDevice`; AirPods `40-…:input` — both probe-verified). Lesson:
  when a list looks stale but a direct lookup works, they're different APIs — don't assume one
  framework keeps one cache. Also: a `.menu` MenuBarExtra re-reads sources on each open (M6-T10's
  `RefreshOnMenuOpen`), so a live enumerator surfaces hot-plugged devices on the very next open.

- 2026-07-16 (M6-T1 C3): two observations from the acceptance leg.
  - **The app has a live install at `/Users/Shared/ScreenRec.app`** (found running there;
    binary byte-identical to today's dist build). A stable path outside `dist/` — which
    `bundle.sh` deletes every run — is exactly what M6-T5's login item needs, but no doc or
    STATUS entry records who put it there or whether it's the intended permanent address.
    Settle at M6-T4/T5.
  - **The menu's recent-replay rows list files that no longer exist** (~/Movies had zero
    Replay files; the menu showed two — moved/deleted externally). Recents don't revalidate
    on menu open; what a click on a dead row does is unverified. Candidate for M6-T3's
    error-path audit, not fixed here.

- 2026-07-16 (M5-T5 follow-up — the banner that can't render): **macOS suppresses notification
  banners while the display is captured, and armed replay means the display is always captured.**
  Franco pressed ⌥⌘R from another app: file saved, notification delivered (in the Center's
  list), no banner — the first notification this app fires *mid-capture*, so the first time the
  suppression could show. Both remedies measured:
  - `.timeSensitive` **with** its entitlement, self-signed: AMFI refuses to launch the app
    (POSIX 153 spawn failure) — restricted entitlements need a provisioning profile.
  - `.timeSensitive` **without** the entitlement: silently downgraded, no break-through.
  So: `interruptionLevel` stays set (free once M6-T4's Developer ID signing carries the parked
  `Scripts/entitlements.plist`); until then the user-side fix is System Settings → Notifications
  → "Allow notifications when mirroring or sharing the display". docs/06 amended. Also settled:
  the capture indicator itself is OS-mandated for any SCK stream — no opt-out exists, armed
  replay always shows it.
  - **The likely wider blast radius — armed replay suppressing EVERY app's banners — is
    documented (docs/06 + 02 §9) but deliberately marked inferred:** the policy is global by
    design, our own banner's suppression is measured, third-party suppression is not yet
    observed (the osascript probe has no notification grant of its own, so the headless A/B
    was inconclusive — the confirmation is Franco arming and Slacking himself). Franco's call
    2026-07-16: document now, decide on remedies later.

- 2026-07-16 (M5-T5 app replay): the widest review haul yet (10 confirmed), and the pattern is
  worth naming: **every serious one was a second writer to state I'd only considered the user
  writing.**
  - 🔴 **`refreshSources` re-homes picks on every menu open — my source-change `didSet`s
    treated those writes as user intent and restarted the armed pipeline**, wiping the replay
    buffer on the first menu open after launch, and right after a mic vanished (the exact
    moment someone opens the menu to save). A suppression flag scopes the didSets to genuine
    picks; regression test pins it; verified live (53.9 s clip after two menu opens). **When
    adding a didSet to a property, grep for every existing writer first** — one of them is
    usually not the user.
  - 🔴 **"Restore persisted state at launch" must re-check the permissions the state assumes.**
    Armed + revoked screen grant would have spun a 5 s SCK retry loop forever behind a lying
    badge. Launch activation now requires the grant usable; the grant→relaunch flow re-arms.
  - **Carbon hotkey lessons:** `RegisterEventHotKey` fails silently for combos other apps own
    (now surfaced as a notification); a registered hotkey intercepts its own combo before any
    local NSEvent monitor (the recorder must suspend it while listening); and a recorder that
    accepts plain-⌘ combos lets one reflexive ⌘C hijack copy system-wide — combos now require
    ⌥ or ⌃. Also: hotkey ints from the plist feed trapping `UInt32()` — bounded at load
    (the M4-T4 "bad plist is forever" rule, again).
  - **Replay's own streams must resolve the mic ID the way `start()` does** — a stale picked ID
    fed raw to SCK is the opaque "invalid parameter" (02 §1), which under the armed retry loop
    becomes an infinite failing respawn. One resolver, both paths.
  - **docs/06 amendments:** two notification rows added (mic lost while armed — the docs table
    predates armed replay; shortcut unavailable). The armed badge shows on all icon states, not
    just idle ("armed is orthogonal to recording"); menudriver now renders shortcut modifiers
    (it printed plain ⌘ for everything — a dump-only artifact that mislabelled ⌥⌘R).

- 2026-07-16 (M5-T4 ReplayMuxer): instant replay produces files; two findings worth keeping.
  - 🔴 **The clip window must be anchored at the newest pts across ALL rings, never the video
    ring's own newest** — frame-on-change means a static screen's video ring can be minutes
    stale while audio tracks wall-clock. /code-review caught my first pass anchoring on video:
    a static-screen save would have written minutes-long files of *old* content. The fix is the
    same idea as MovieRecorder's tail patch (02 §5), applied at mux time: window ends at the
    audio clock, the last frame is re-appended at the clip end, and a fully-static window
    rebases audio from the window start with the stale GOP frozen at the top.
  - 🐞 **AVAssetWriter infers a track's LAST sample duration from the *previous* pts delta when
    durations are invalid** (VT compressed samples: we encode with `duration: .invalid`). A
    tail patch 9 s after the last real frame therefore got a 9 s duration and inflated the
    track — video 19 s in a 10 s clip. Only the *last* sample misbehaves (interior samples get
    their real delta, which is exactly the frozen-frame display we want). Fix: the patch copy
    carries an explicit duration (`SampleTiming.retimed(_:to:duration:)`). Caught by the
    fully-stale-window unit test before it ever reached a live run.
  - **Process note: findings presented to Franco before fixing** (his rule from M5-T3), batch
    approved incl. option (b) on the window anchor. One finding was refuted by a verifier that
    actually reproduced disk-full against a tiny APFS image — the writer keeps accepting and
    fails cleanly at `finishWriting`; the drain's writer-status escape stays as cheap insurance
    for any state where `requestMediaDataWhenReady` stops re-firing.

- 2026-07-16 (M5-T3 audio rings): the live run earned its keep twice in one afternoon.
  - **/code-review's theme was silent-failure observability, and it was right four ways at once:**
    a format change pinned a minute of stale audio forever (eviction only runs on append — a ring
    that stops appending stops evicting, and its stats freeze looking healthy); `.microphoneLost`
    hit `default: break` in replay-arm while record prints a warning for the same event; the
    system ring's trouble counter was computed but never printed; and the T3 ticker redesign had
    dropped the video sample count, the only signal separating "spans 60 s" from "spans 60 s
    holding half the frames". All fixed. **Policy call (Franco): on a format change the ring
    clears + re-latches** rather than dropping forever — replay self-heals across AirPods codec
    flips (the only realistic trigger; SCK never re-binds devices, M3-T7, and the stream config
    pins system audio's format) at the cost of a second policy besides MovieRecorder's fail-stop.
    Revisit if the wild shows format thrash (`format ×N` in the ticker is the tell).
  - **The "device switched" ASBD identity now lives in one place** (`AudioFormatIdentity`,
    Support/) and gained the layout fields (`mFormatFlags`, `mBitsPerChannel`) — same
    rate/channels in a different layout is just as unmixable. MovieRecorder's fail-stop uses it
    too, so recording and replay can't disagree on what "switched" means. Note this slightly
    widens M3-T2's fail-stop trigger (a pure layout flip now also stops); that's more correct —
    the welded mic input corrupts on layout changes exactly as on rate changes.
  - 🔴 **SCK's system audio is planar (non-interleaved) Float32 — and two APIs quietly mislead on
    planar buffers.** (1) `CMSampleBufferGetTotalSampleSize` returns **0** for them (the live
    symptom: system ring at 62 s span, "0.0 MB"); count payload via
    `CMBlockBufferGetDataLength` instead. (2) The ASBD's `mBytesPerFrame` is **per-plane** when
    `kAudioFormatFlagIsNonInterleaved` is set, so naive rate math is short by the channel count
    (187 vs 375 KB/s). The mic (mono) hid both bugs. G1's probe recorded "48kHz/2ch/32-bit" but
    not the interleave — **when a format has a layout dimension, record the layout.**
  - 🔁 **The fixture-blind-spot pattern again** (sixth occurrence, still the same shape): every
    unit test fed 16-bit *interleaved* PCM, the one family where the code was right, and passed.
    The fix ships with a planar Float32 fixture (`makeAudioFormat(planarFloat32:)`) and a test
    that reproduces the live bug. When a code path branches on a format flag, the suite needs a
    fixture on **each side of the flag**.
  - 📏 **Second data point on RSS attribution variance** (see M5-T2 note): identical binary, two
    2-min runs — buggy-run RSS climbed to ~536 MB tracking ring fill; post-fix run plateaued at
    ~147 MB with a similar-sized ring. Whatever governs whether VT/CM buffer memory lands in our
    `phys_footprint`, it isn't our code. Also: **§6.1's ≲ 200 MB target collides with the
    19 Mbps reality** (02 §9 estimated ~10) — a busy 60 s ring can't fit. Flagged in "Now" as a
    T6 decision: VT `DataRateLimits` is available on the replay session (we drive VT directly,
    so M2-T6's AVAssetWriter limitation doesn't bind here).
  - **Deep-copying the audio was the right call for an unexpected reason too:** the copy is where
    the planar byte-length truth lives (`CMBlockBufferGetDataLength` of what we allocated) — a
    retained SCK buffer would have left us trusting the same lying sample-size bookkeeping.

- 2026-07-16 (M5-T2 ReplayEncoder): the encoder went in clean; the surprises were measurements.
  - 🔴 **/code-review (high) caught VT session bring-up running on SCK's screen queue** —
    `VTCompressionSessionCreate` + `PrepareToEncodeFrames` allocates the hardware encoder
    (tens–hundreds of ms) and my first pass did it inside `consume()` under the lock, on the
    same serial queue MovieRecorder shares. With queueDepth 5 at 60 fps (~83 ms of headroom),
    arming replay during a live recording would have visibly stuttered it — invisible in every
    T2 verify because nothing else consumed the queue yet. Bring-up now runs on a dedicated
    setup queue; frames arriving before readiness are dropped (the ring just starts a beat
    later). **"Doesn't block the callback queue" has to be checked against the slowest call on
    the path, not the average one** — the same docs/01 rule, still finding new ways to break.
  - Also from the review, all applied: `replay-arm`'s encoder failure now routes through
    `engine.stop(reason: .streamError(…))` (the M3-T2 seam) instead of `exit(1)` from a VT
    thread; `ReplayEncoder.init` preconditions on a finite positive window (a negative/NaN
    ring capacity silently evicts everything); `frameRateCap` is passed from the engine's
    `CaptureConfiguration` instead of a duplicated default; the synthesized-frame fixture is
    consolidated into `SyntheticBuffers.swift` (MovieRecorderTests' copy deleted); the
    keyframe-cadence test asserts cadence against *retained* span rather than absolute counts
    (RealTime sessions may shed frames, and the old assertions contradicted each other's
    tolerance); a test's captured `var` in the `@Sendable` onFailure closure became a locked
    latch; `stats()` is single-pass; the `--seconds 600` cap comment now states the real cost
    (~1.4 GB, not 0.9).
  - 📏 **`phys_footprint` attribution of VT output varies run to run.** Same code, same 3-min
    verify: one run plateaued at 16–17 MB (with `ps` RSS at 33 MB), the next at 113–128 MB with
    a slow upward drift — while the ring's payload bytes sat flat at ~141 MB in both. Whatever
    memory the HW encoder's output block buffers land in, the task-level number is not a stable
    measure of it. For §6.1, treat "RSS ≲ 200 MB" as satisfied but weak evidence; M5-T6's
    30-min audit should watch the drift and system-wide pressure, not one instrument.
  - ⚠️ **`tools/busyscene.swift` takes over Franco's screen — never run it without asking him
    first** (his ruling, mid-verify). Future busy-screen verifies: name the run and its length,
    let him pick the moment.
  - **VideoToolbox needs no TCC grant — the replay encoder is fully unit-testable headlessly.**
    Real HEVC encodes against synthesized IOSurface-backed pixel buffers, in-process, no
    permissions: keyframe cadence, eviction and stats are all asserted against actual encoder
    output, not mocks. The suite runs in ~0.7 s. This generalizes: anything VT-only in M5 (the
    muxer's AAC encode at T4, likely) can be tested the same way.
  - 📏 **Compressed VT output is NOT attributed to our process's memory.** The 3-min run held
    ~141 MB of compressed payload in the ring (measured by `CMSampleBufferGetTotalSampleSize`,
    and it matches Balanced's 19 Mbps × 62 s math exactly) while in-process `phys_footprint`
    read 17 MB and external `ps` RSS read 33 MB — both flat. The HW encoder's output block
    buffers live in memory the kernel doesn't charge to the task. Two consequences: (1) §6.1's
    "RSS plateau ≲ 200 MB" will pass trivially and is therefore a *leak* check, not a *usage*
    check; (2) M5-T6's audit should also watch system-wide memory pressure, not just our RSS,
    or the ring's real cost is invisible. Both instruments agreeing on "flat" is the part that
    matters for T2.
  - **02 §9's "~80 MB video @ 60 s" estimate is ~2× low for this display.** It assumed ~10 Mbps;
    Balanced at 4112×2570@60 computes 19 Mbps → ~141 MB/62 s. Not a bug — the model is doing
    what M2-T6 calibrated — but worth knowing before anyone sizes a 120 s ring (docs/06 offers
    one: ~282 MB payload).
  - **`--seconds` is capped at 600** so a typo can't ask for a multi-GB ring; docs/06's largest
    offered buffer is 120 s, so the cap is generous.

- 2026-07-16 (G4 §5.4 — the wedge bug the gate caught, and its fix): the whole reason gates exist.
  - 🔴 **An unwritable output folder WEDGED the app — a live SCStream with no way out.** Choosing
    Desktop without Files & Folders (or any folder that becomes unwritable): `AVAssetWriter.
    startWriting()` returns `false`, `MovieRecorder.beginWriting()` **swallowed it**, `consume()`
    then `guard didStartWriting else { return }` on every frame, and the recorder had **no channel
    to report "I couldn't begin."** `RecordingSession`'s event loop only ends when `engine.events`
    finishes — but the engine happily keeps capturing — so **no `.failed`/`.finished` ever reached
    the app.** Symptoms Franco hit: idle icon (no first frame written) + a menu stuck on "Stop &
    Save" (session ≠ nil) + inert Stop + dead screenshot shortcut (live capture holding the display).
  - **Fix A (the wedge):** `MovieRecorder` gained `onWriteFailure` (mirrors `onMicrophoneFormatChange`);
    `beginWriting` latches the failure and fires once, outside the lock; `RecordingSession` stops
    the engine and yields `.failed("Couldn't write the recording to …")`. Any `startWriting()`
    failure now ends in a plain message + a live app.
  - **Fix B (catch it early):** `OutputLocation.preflight` probed with a POSIX `createFile`, which
    **succeeds on a TCC-protected Desktop where `AVAssetWriter` fails** (measured: createFile→true,
    startWriting→NSCocoa 513/-12204). Now it probes with a throwaway `AVAssetWriter.startWriting()`
    (one input, self-cleaning) — the exact call a recording makes — so Desktop is rejected at
    selection. **Check a preflight against the API that actually gets blocked, not a cheaper proxy.**
  - ⚠️ **`~/Movies` is safe for a fresh user** — it is NOT TCC-protected, so the default path needs
    no grant (the whole point of the M0-T4 default). Only *changing* the output to Desktop/Documents/
    Downloads triggers this.
  - 🐞 **I could not reproduce the unwritable-Desktop state on the dev account** — launching the app
    via `open` from the agent's Terminal appears to lend it Terminal's Desktop access (the app is in
    NEITHER Files & Folders NOR Full Disk Access, yet wrote to Desktop). Don't state the mechanism as
    fact, but the lesson stands: **the honest repro is a Finder-launched app on a fresh account.** I
    verified the *integration* headlessly instead via a temporary forced-`startWriting`-failure hook
    (reverted): Start → no wedge, back to Ready, "Couldn't write…" delivered.
  - **Two /code-review follow-ups (deferred, out of scope for the RecorderCore fix):**
    - **Finding 1 (confirmed, observed live):** the write-fail `.failed` fires *after* `.started`
      (StartedDetector on the first complete frame is writer-independent), so `AppState` computes
      `hadStarted = statusIcon != .idle = true` → notification titled **"Couldn't save the recording"**
      when nothing was ever written (should be "Couldn't start"). Body is clear, so low-harm. Fix
      touches M4-T5's title heuristic — a small AppCore follow-up.
    - **Finding 3 (plausible):** preflight now does `AVAssetWriter` I/O synchronously on the main
      thread in `SettingsView.chooseFolder`; on a slow/network volume the folder pick could briefly
      hang. One-time action already behind a modal panel; move off-main if it ever bites.

- 2026-07-16 (G4 headless prep): docs/04 §5 is labelled "human-driven", but **half of it isn't**.
  - **§5.2 grants-survive-rebuild is fully headless on this account.** Two-part proof: (1) the
    signing half — `codesign -d -r-` designated requirement is byte-identical across an A→B
    `bundle.sh` rebuild (diff the `designated =>` line), `--verify --strict` passes; (2) the
    behavioral half — after the rebuild, launch the app, confirm the menu header reads
    `ScreenRec — Ready` (readiness is a *live* TCC read, so `Ready` == grant still attached), then
    `menudriver` a real recording. A successful post-rebuild capture IS the proof the grant survived.
  - **The fail-stop notification IS deliverable headlessly — the seam already exists.** The app has
    no `--test-disk-floor` (that's the CLI's), but `RecordingSession.init(diskFloorBytes:)` is
    public and the app just passes `nil`. A ~4-line temporary launch-arg hook at `AppState.start()`
    (`--force-fail-stop` → `diskFloorBytes: 500_000 GB`) trips the disk guard right after the first
    frame → `finished(.diskAlmostFull)` → the app posts its real fail-stop copy. Verified the exact
    docs/06 string delivered live, then reverted (tree clean). No product change needed for the gate.
  - **`--print-delivered-notifications` stamps dates in UTC (`…Z`), not local.** For the "is this
    *this* run?" check (M4-T5's warning), convert: on this box local = UTC−3, so a 09:53 local run
    shows `12:53Z`. Assert against the converted time or the whole thing looks stale.
  - **What stays human, and why it can't be faked:** a *rendered banner* and a *click* (Notification
    Center draws them; delivery ≠ appearance), the fresh-account never-granted paths (this Mac holds
    every grant — the throwaway-bundle trick proves TCC *logic* but not the *onboarding UX*), and
    the `NSOpenPanel` Desktop-preflight (`menudriver` can't drive a system file panel). Those three
    are the whole of what's left, and they're in the walkthrough artifact.

- 2026-07-16 (M4-T6 bundle polish): small task, one honest miss.
  - **The icon is code-drawn, not a checked-in mystery PNG.** `tools/makeicon.swift` renders the
    1024 master; `Scripts/makeicns.sh` runs `sips` + `iconutil` to the 10-slot `.icns`. Same
    reproducible-not-binary reasoning as `busyscene.swift`. Candidate C — a display with a record
    dot — because the icon most needs telling apart in the Screen Recording permission list,
    where every neighbour is also a recorder.
  - **Version has one source now.** `Info.plist` carries `__VERSION__` placeholders; `bundle.sh`
    stamps them from `VERSION` and fails loud if `VERSION` or the icon is missing. The checked-in
    plist literally cannot disagree with the built bundle — you can't stamp what you didn't read.
  - 🐞 **"icon renders in Finder" ≠ "icon renders on the notification banner" — I conflated them.**
    `NSWorkspace.icon(forFile:)` resolves the icon from the assembled bundle immediately (docs/03's
    actual check, passing). But the notification banner still shows the generic placeholder:
    `usernoted` caches the icon per bundle-id, cached the icon-less earlier build, and `lsregister
    -f` doesn't flush that cache. The clean flush (`killall usernoted`) is restarting a system
    daemon, which the sandbox correctly refused on my own initiative. **Two different icon caches
    with different flush rules** — Finder/LaunchServices vs the notification daemon. The banner
    icon is expected to come good at M6 (app at a real path + notarized); until then it's a known
    gap, watched at G4, not a claimed pass. It was never a docs/03 requirement — it was my stretch
    goal in the T5/T6 plans, so no gate is blocked, but the plan overpromised.

- 2026-07-15 (M4-T5 notifications): mostly wiring; the value was in the copy.
  - 🔴 **docs/06's copy table covered four fewer cases than the engine emits**, and the gaps were
    invisible until the two were laid side by side. `streamError` (reachable — SCK dies for
    reasons we don't classify) had no copy; mic-loss had none though **ADR-012 promises a
    notification**; `failed` had none because the table assumes "always a playable file"; and
    `Mac went to sleep` was copy for `EndReason.systemSleep`, which M3-T4 measured as
    unreachable. **Check a copy table against the enum, not against the happy path** — a spec
    written before the code knows only the cases the author imagined.
  - **The notification needs a duration `.finished` doesn't carry.** `elapsedSeconds` only
    advances while the menu is open, so it's usually stale or zero at finish. The writer's
    `recordedDuration` is the only accurate source, and it's readable only *before* the session
    is torn down — hence `notify(about:)` runs at the top of `apply`, ahead of the fold.
  - **The notification delegate must be installed before launch completes** (hence
    `NSApplicationDelegateAdaptor`, not a view's `.task`): a click can *launch* the app, and a
    response delivered before a delegate exists is dropped — losing the one interaction docs/06
    specifies for notifications.
  - **`willPresent` must return `.banner`** or the notification is silently swallowed whenever
    ScreenRec happens to be frontmost (Settings or Onboarding open). Easy to miss: the app is an
    accessory and rarely frontmost, so it works in testing and fails in the one case a user is
    looking at the app.
  - 🔴 **The feature was dead for every normal install, and the live test passed anyway.**
    `requestAuthorization` was only reachable from onboarding's Notifications row — but that
    window opens when a permission *blocks*, notifications never block, and it stops auto-opening
    once the blocking rows go green. So: fresh install → grant screen → relaunch → the window
    never opens again → authorization stays `.notDetermined` → **every notification silently
    dropped, forever**, with the error discarded inside `add(request)`. The verify passed only
    because this machine had been granted by hand. /code-review found it. The app now asks once
    at launch; onboarding's row still shows the state and routes to Settings.
    **Whenever a permission gates a feature, ask where it gets requested on a machine that never
    saw the setup screen.**
  - 🐞 **`.failed` means two things and its own doc comment says one.** `EngineEvent.failed` is
    documented as "preflight/start failure", but `RecordingSession` also yields it from the
    `finish()` catch — a *finalize* failure after a full recording. The notification mapper
    trusted the doc, so losing a 90-minute capture at the last step announced "Couldn't start
    recording" over a body saying finalization failed. Only the caller can tell them apart
    (`statusIcon != .idle`). **A doc comment is not a contract; grep the emitters.**
  - 🐞 **Two start-failure paths posted nothing at all.** `start()`'s `reserveRecordingURL` and
    `RecordingSession.init` catches set `lastFailure` and returned — no session, so no event
    stream, so no notification; and `lastFailure` reaches no idle surface since the header shows
    readiness. Net effect: click Start with an unwritable folder, get *no banner and no visible
    change*, walk away believing you're recording. They now route through `apply(.failed(…))`.
  - **What `--print-delivered-notifications` proves, and what it can't.** It asserts real copy
    from a real delivery — docs/03's verify, no human needed. ⚠️ But it reads Notification
    Center's **persisted** list, not this run's: it happily prints week-old entries, so the gate
    could pass with nothing delivered. It now prints each notification's date — **assert on the
    date, not just the copy** (verified: run at 22:24:19, notification at 22:24:26). It still
    says nothing about whether a banner *appeared* or what a click does.
  - **Fail-stop copy is unit-tested but never delivered live** — the app has no
    `--test-disk-floor` (that's the CLI's), so provoking one needs a patch. G4 §5.3 covers it.

- 2026-07-15 (M4-T4 settings): the app finally remembers something. Two lessons, one of them
  the same one as always.
  - 🔴 **`tools/menudriver.swift` CANNOT verify window activation, and it took an hour and a
    design change to learn that.** A synthetic click doesn't confer activation the way a real one
    does, so after `click "Settings…"` the app stays un-frontmost and the window looks like it
    opened behind everything — *whatever the app does*. I read that as a bug, replaced
    `Settings` + `SettingsLink` with a plain `Window` chasing it, tried an AppKit selector,
    and wrote "verified — Terminal stayed frontmost" into the source as fact. Then **Franco said
    "the menu opens fine for me"** and the whole thing evaporated. **Third false negative from my
    own tooling in two tasks** (unopened submenus; `AXDescription` vs `AXTitle`; now this) — the
    warning is in the tool's header now. Trustworthy from it: structure, titles, checkmarks,
    enabled/disabled, that a click landed. Not trustworthy: anything about focus or z-order.
    **When a tool says the app is broken and a human says it isn't, the tool is the defendant.**
  - **The `Settings` scene buys an LSUIElement app nothing** — it exists to route ⌘, through the
    app menu, which an accessory doesn't have. ⌘, is bound on the menu item instead. That's why
    the plain `Window` stayed after the false alarm: one way of opening a window rather than two.
    But it is a *preference*, not a fix, and the source says so — `SettingsLink` is not known to
    be broken.
  - 🐞 **A setting that persists perfectly and reaches nothing.** `fpsCap` round-tripped through
    UserDefaults, showed in the UI, and never reached the capture: `captureConfiguration` didn't
    pass `frameRateCap`, so the engine used its own default. Persistence tests all passed. The
    test that catches it asserts the *configuration*, not the stored value — **a settings test
    that stops at the plist is testing a drawer, not a setting.**
  - 🐞 **Tests were writing to the real `UserDefaults`.** `AppState()` defaults to `.standard`,
    and settings persist on `didSet` since this task — so one test's `state.quality = .high`
    leaked into another test's launch, and onto disk between runs. Found because a test that had
    passed for hours suddenly failed. Every AppState in a test now gets a throwaway suite.
    **The moment state persists, "just construct one" stops being free in tests.**
  - **Persisted state is a different risk in kind, and this is the task where it starts.**
    In-memory state self-corrects on the next launch; a bad plist value is the app's problem at
    *every* launch until someone fixes it — and `defaults write dev.fcostantini.screenrec.app
    fpsCap 0` is one command. So the load validates rather than trusts: unknown preset → the
    default, fps not in {30,60} → the default (not clamped: 0 divides by zero downstream and
    "clamped to 30" is a value nobody chose), a folder that's gone → `~/Movies`. The realistic
    one isn't a hand-edited plist — it's the external drive that was mounted when they chose it.

- 2026-07-15 (M4-T3 onboarding): the TCC findings are in **02 §1/§2** (measured tables — read
  them before touching permissions). What belongs here is everything else.
  - 🔴 **The same question — "is this state current?" — has OPPOSITE answers for a menu and a
    window, and I got each one wrong once.**
    - A **menu** is rebuilt on every open, and SwiftUI decides `.disabled` *before* any `.task`
      on those rows runs ⇒ a stored-and-refreshed value is always one open behind ⇒ **compute
      live** (`readiness`). Shipped stale; the live run caught it.
    - A **window stays open** while the user walks to System Settings and back ⇒ computing live
      keeps the values right and **still never redraws**, because TCC changes outside the
      process and `@Observable` has nothing to observe ⇒ **store it and poll**
      (`onboardingRows`). Shipped broken; *Franco* caught it — he granted the microphone and
      watched the row sit on `○ Grant…`.
    The two look inconsistent side by side and are not. **Rule: ask whether the surface is
    rebuilt or persistent before deciding where the state lives.**
  - **`@Observable` publishes on every set, not every change** — so a 1 Hz poll that assigns
    unconditionally redraws the window every second forever. Assign only on a real change
    (`OnboardingRow` is Equatable for exactly this).
  - **Verification tooling: SwiftUI puts a button's label in `AXDescription`, not `AXTitle`.**
    Matching on title finds zero buttons and looks exactly like "the window has no buttons".
    `tools/menudriver.swift`-style helpers must match either. (Same false-negative family as the
    unopened-submenu bug from M4-T2 — twice in two tasks.)
  - **`osascript` + System Events needs an Automation grant** ("Terminal wants access to control
    System Events"). It prompts the human unannounced — warn Franco before running one. Dev
    tooling only; the product never needs it.
  - **The throwaway-bundle trick generalises and is now the house method for permission work**
    (recipe in 02 §1): same signing identity + a different bundle ID = a TCC subject macOS has
    never granted, on this account, with our own grants untouched. It settled a question the
    docs had called untestable-without-a-fresh-account since M3-T4, in ten minutes. Cleanup is
    `tccutil reset <service> <that bundle id>` — **always with the bundle ID**; the bare form
    would destroy our grant (02 §2).
  - ⚠️ **A probe bundle must be launched via `open`, not run from the shell.** A bare binary is
    attributed to the *responsible process* (Terminal), which holds every grant — it would have
    measured the exact opposite of what was intended, and looked like a clean result.
  - **I asserted something about Franco's screen I never verified, and it was wrong.** From run 1
    I concluded "-3801 says *user declined* although nobody was asked" — a nice finding, entirely
    false: a prompt *had* appeared and he *had* declined. He corrected it; otherwise it would
    have gone into 02 as measured fact. **Never narrate the user's screen.** The re-run in the
    genuinely-denied state is what actually earned the second row of that table.
  - **Two spec bugs found by building, both the same shape — a door that only opens outward:**
    1. docs/06's `Grant…`-only row is dead for anyone who ever declined (02 §2). Fixed: ask once,
       then offer System Settings forever after. It flips on *having asked*, not on *being
       denied*, because macOS won't tell us which state we're in — and the remedy is identical.
    2. The header was spec'd disabled-unless-blocked, which strands the *optional* Notifications
       row: it never blocks ⇒ `needsOnboarding` goes false ⇒ the window stops auto-opening ⇒ a
       user who dismissed the prompt has no route back from anywhere in the app. Franco hit this
       for real. Fixed: the header always opens Onboarding; only *auto*-opening is gated on a
       blocking row. **Auto-appearing and being reachable are different questions — docs/06
       conflated them, and so did I.**
  - 🔴 **`CGPreflightScreenCaptureAccess()` goes true the instant the switch lands — and the
    process still can't capture until it restarts (02 §2). Believing it is how you build an app
    that says `Ready` and fails every recording.** /code-review found this and it was the root of
    most of the task's defects: `readiness` trusted preflight, so Start enabled the moment the
    user toggled Settings, whether or not the restart had happened. **Only a launch-time snapshot
    can tell the difference** — permissions alone cannot, because "granted, usable" and "granted,
    needs restart" are the same TCC answer. `AppState.screenWasGrantedAtLaunch` +
    `needsRelaunchForScreenGrant` are that snapshot, and `readiness` now reports blocked until
    the relaunch happens.
  - **A promise the user can close is not a promise.** The relaunch first lived in the onboarding
    window's `.task`, so closing the window (or granting straight in System Settings without
    pressing our button) silently dropped the "we'll relaunch automatically" the row's own copy
    makes. It now lives on the status item's task, which lives as long as the app, and keys on
    the **grant transition** rather than on our button being pressed — the user may never touch
    the button, and that grant needs the same restart. **Rule: a background promise belongs on a
    surface the user can't dismiss.**
  - **My fix for Franco's header request quietly created a way to abandon a recording.** Making
    the header always-clickable broke the invariant the relaunch's safety argument rested on
    ("the window only exists while recording is blocked") — so a click on a *status readout* could
    silently quit and reopen the app, discarding every in-memory pick. Two lessons: **an
    invariant defended by a comment in another file is not defended**, and a small UI change can
    invalidate a safety argument three files away. `Relaunch.now()` is now guarded on
    `isSessionActive` even though `readiness` should already make it unreachable — "should be" is
    not a thing to abandon a live writer on.
  - **Copy has to follow the gate.** The mic row said "Only needed if you record a microphone"
    while Start was greyed out *because of that row* — telling the one person who is blocked that
    it isn't their problem. Detail text now depends on whether the row is actually blocking.

  - **The good news that reframes M4-T3: asking is the add button.** Neither the Microphone nor
    the Notifications pane has a "+", but neither needs one — *the request itself creates the
    row*, whatever the user answers. So there is exactly **one** unrecoverable state, **never
    having asked**, and it is the state the app was in before this task. That is the whole case
    for onboarding, and it's stronger than the spec's.

- 2026-07-15 (M4-T2 the menu): the task that made M4 verifiable — and the first task where a
  **live run found a bug the unit tests structurally could not**.
  - 🐞 **A stored `readiness` is always one menu-open behind.** SwiftUI builds a menu's rows —
    including which are `.disabled` — *before* any `.task` attached to them runs. So refreshing
    readiness from that task lands after the decision it was meant to inform, and the menu shows
    the answer from the **previous** open. Live symptom: pick a microphone, and the menu went on
    offering an enabled Start that silently did nothing (the ungranted mic flipped readiness, the
    stale menu didn't know). Now a **computed** property — both TCC queries are cheap local
    checks, so asking during body evaluation is affordable and cannot lag. **Rule: anything the
    menu's structure depends on must be readable at build time, not refreshed from `.task`.**
    `.task` is only good for things that change *while* the menu is open (the elapsed clock).
  - **`EngineEvent.fileProgress` is declared but nothing emits it** — a dead case, exactly like
    `.systemSleep` was before M3-T4. The CLI's ticker polls `recordedDuration` + the file size on
    disk; the menu now does the same. That suits docs/06 better anyway ("≤1 Hz, menu open only"):
    a pull happens exactly when someone is looking, which no push could arrange. Left dead rather
    than wired up — M4-T2 had no business changing RecorderCore. Whoever needs it should ask
    whether it should exist at all before implementing it.
  - **`isSessionActive` must be `session != nil`, NOT derived from the icon.** Between `start()`
    and the first complete frame the icon still reads `.idle` while a session exists. Keying the
    menu off the icon would offer "Start Recording" a second time in that window (a second
    session over the first) and let ⌘Q skip its confirm and abandon a live writer.
  - **A `Picker` in menu content already *is* docs/06's submenu-with-checkmark.** Wrapping it in
    an explicit `Menu` + `.pickerStyle(.inline)` reads closer to the spec's wording and renders
    further from it — it adds stray separators around the group. Verified with `menudriver dump`.
  - **RecorderCore stayed untouched, but only just.** `DisplaySelection`/`MicrophoneSelection`
    carry associated values and aren't `Hashable`, so they can't be SwiftUI picker tags. Rather
    than add conformances to a capture type to suit a menu, `AppState` stores the raw picked
    identifiers and builds a `CaptureConfiguration` at start. Better shape anyway — but note the
    pull: the UI *will* keep asking for small favours from RecorderCore. Refuse them.
  - **My own comment lied and a test caught it.** I claimed the recent-files filename tie-break
    "keeps the newer of two same-second files first". It does not — `Recording.mov` sorts above
    `Recording 2.mov` descending, though the suffixed one was written second. The tie-break buys
    *determinism* (`sorted(by:)` isn't stable), nothing more. The test now asserts stability
    rather than pinning the quirk as if it were intent.

- 2026-07-15 (M4-T2 verification — **the "(human)" tax on M4/M5 mostly evaporated**):
  - **`tools/menudriver.swift` + Franco's Accessibility grant = headless menu testing.** The
    whole T2 verify (open menu → pick sources → Start → wait → Stop → probe the file) ran with no
    human. `dump` prints the open menu as text — titles, checkmarks, shortcuts, disabled rows,
    submenus — so docs/06's structure is **assertable**, not a screenshot to squint at. Use it.
  - ⚠️ **`AXPress` on a menu-bar item returns `.success` and does nothing.** Menu tracking runs a
    modal event loop the action never enters. Third instance of this project's oldest trap (SCK's
    `updateConfiguration` OK-on-a-dead-device, 02 §4; the `--nil-follow` window). The menu opens
    via a synthetic `CGEvent` click at the item's own reported frame. Menu *items* do respond to
    AXPress once their menu is open.
  - 🔴 **A submenu's AX children don't exist until the submenu is opened — and I shipped that as a
    false negative into the very tool built to prevent false negatives.** `dump` read the children
    without opening, so the Microphone submenu printed as empty. It looked exactly like a real
    regression (the app "losing" its device list), I believed it, and I was one edit from
    "fixing" an app that was never broken — until **Franco sent a screenshot showing the two
    devices right there**. The tool now opens each submenu, retries, and prints
    `(unread — submenu never populated)` rather than printing nothing. **The rule this project
    keeps relearning, now in its fifth costume: an empty reading is not evidence of emptiness.
    Any instrument that can't distinguish "nothing there" from "didn't look" will eventually
    invent a bug for you.** Verified fixed: three consecutive dumps now identical and complete.
  - **The grant is on Terminal, not "Claude Code"** — Claude Code here is a CLI hosted by
    Terminal.app, so it never requests Accessibility and never appears in that list. It's a broad
    grant (anything run in Terminal can drive any app); revoke it after M4/M5 if desired.
  - 🔴 **The Microphone pane has NO "+" button** (verified by screenshot, 2026-07-15) — unlike
    Screen Recording / Accessibility / Full Disk Access. Apps appear there *only* after calling
    `requestAccess`. **Consequence: in M4-T2 the app is an unrecoverable dead-end the moment a mic
    is picked** — Start greys out, and neither the app nor the user can grant it. This is the
    strongest possible argument that M4-T3's onboarding is load-bearing, not polish. It also
    means: **any permission the app needs, the app must ask for — you cannot document your way
    around it.**
  - **Screen Recording CAN be granted by hand** (`+` → the .app), which is how T2 was tested at
    all. The grant survived a dozen `bundle.sh` rebuilds — M0-T3's stable designated requirement
    holding up in practice, exactly as promised.

- 2026-07-15 (M4-T1 menu-bar shell): the first UI task, and the headless-verification story is
  better than expected — **the agent does not have to hand the visual check to a human.**
  - **`screencapture -x -R x,y,w,h` works from this terminal** (same foreground-TCC rule as
    capture — see the M2-T5 note). `NSScreen.main.frame` is **2056×1285 points** at 2× on this
    machine; the menu bar is the top ~32 points. So any menu-bar state can be captured and read
    back. Combined with the next point, docs/03's `(human)` visual checks for M4 are mostly
    self-serviceable — leave the human the *judgement* calls (does it look right), not the
    *existence* ones (does it render at all).
  - **To photograph a state the UI can't reach yet, patch the app temporarily and revert.** T1
    has no Start button (that's T2), so `.recording`/`.paused` were unreachable. A throwaway
    `.task {}` in `App.swift` drove `state.apply(.started)` → `.paused` on a timer; captured;
    reverted. Cheaper than a debug launch argument and it ships nothing.
  - **Don't eyeball an animation — measure it.** Two pulse screenshots looked identical to me;
    the mean red channel said otherwise (redness 0.198→0.426 across phases, a 2.15× swing vs the
    2.22× the 0.45 alpha floor predicts). The pulse was working *and* the floor was right, but I
    could not have told you either from the pictures. Same lesson as the M3 field notes in a new
    costume: a check that can't fail for the intended reason is decoration.
  - **SwiftUI's implicit animations do NOT drive a `MenuBarExtra` label** — the status item is
    rendered to an `NSImage`, so `.animation`/`withAnimation` do nothing there. A `Timer.publish`
    + `onReceive` flipping `@State` *does* re-render it (verified above). That's why the pulse is
    hand-driven at 12 frames / 2 s cycle rather than declared.
  - **Menu-bar colour requires `isTemplate = false`.** The menu bar tints template images to
    match itself, which would flatten the red and amber — the two icons whose entire meaning is
    their colour — into the same monochrome as idle. Only `.idle` stays a template (it *should*
    follow the system). Colour is baked in via `NSImage.SymbolConfiguration(paletteColors:)`.
  - **`lsappinfo info -only ApplicationType <pid>` → `"UIElement"` is the headless proof of "no
    Dock icon"** — better than "I looked at the Dock", and scriptable for the G4 gate.
  - **Scope call worth knowing:** docs/06's status-item table has four states, but the fourth
    (replay-armed badge) has nothing that can set it until M4-T2's toggle, so `StatusIcon` has
    three. `AppState.statusIcon` is therefore currently a 1:1 image of the event fold with no
    second input — when T2 adds arming, that likely becomes a derived property over
    (activity, isReplayArmed). Deliberate: the badge design would have been improvised now.
  - 🐞 **UI has a whole class of bug the CLI never had: the invisible-to-sighted-testing kind.**
    /code-review found the pulse dropping the status item's accessible name on every faded frame
    (~92% of them) — `NSImage(size:flipped:)` returns a fresh image, and I copied `isTemplate`
    across but not `accessibilityDescription`. So VoiceOver announced an unnamed image in the one
    state where the icon is the app's only signal. **Two lessons.** (1) `Image(nsImage:)` does
    NOT adopt an `NSImage`'s `accessibilityDescription`, and a label-based `MenuBarExtra` has no
    title to fall back on — the accessible name must be applied in SwiftUI with
    `.accessibilityLabel()`, so that is where it now lives (one source of truth, in the layer
    that works). The old `MenuBarExtra("ScreenRec", systemImage:)` had been carrying the name for
    free; switching to a custom label silently dropped it. (2) Every screenshot I took was of a
    state that *looked* right — the a11y tree is not in the picture. For M4+, "I captured it" is
    not the same evidence it was for the CLI.
  - **I put a number in the audit trail that I never measured** (claimed 15 AppCore tests; there
    are 11) and it reached docs/03 AND STATUS before the review caught it. docs/03 + STATUS are
    the per-task audit trail, so an invented figure quietly devalues the measured ones beside it.
    `swift test --filter AppCoreTests` prints the count in one second. **Never write a count you
    didn't just read off the harness** — and note the count is @Test *declarations*, not expanded
    parameterized cases (11 here, not the 21 the arguments would suggest).
  - **The review is the only thing that catches cross-cutting scope drift.** It flagged an
    unrelated CLAUDE.md process change riding inside the M4-T1 diff (Franco had asked for it
    mid-session, so it was wanted — but it belonged in its own `docs:` commit, not smuggled into
    a task commit whose message claims to be a menu-bar shell). "One task, one commit" is
    enforced by nobody but the reviewer.

- 2026-07-15 (M3-T5 stall watchdog): the review caught a **logic bug in the one condition the
  class exists for**, and my tests could not have found it.
  - **`idle < silence` is NOT `the user was active`.** I wrote the guard as "did any input land
    after the last frame?". One inert keypress (a lone modifier changes nothing on screen, so no
    frame) leaves idle permanently 1 s behind silence — so it stays true *forever after the user
    walks away*, and every poll then reports a stall on an untouched machine. Exactly the
    coffee-break cry-wolf the class was written to prevent. Correct guard is **recent** activity:
    `idle < timeout`.
  - **My test harness structurally couldn't express the bug.** `advance(_:userActive:)` pins idle
    to 0 or grows it — so every test was "always active" or "always idle", never the realistic
    middle (active, *then* leave). Both extremes passed. Fifth blind-spot test today (see the
    boot-volume-only disk probe, the 400 MB image, the `--nil-follow` window, the lock-only
    repro). **The pattern is always the same: the fixture can only produce states where the code
    is right.** When a condition compares two quantities, test them *diverging*, not just each
    pinned.
  - **The refactor I deferred for safety introduced its own risk anyway.** Moving the mic poll
    onto the nonisolated `pollingTask` means `check()` no longer serializes against the actor, so
    a late `.microphoneLost` can in principle interleave between `.stopped` and
    `continuation.finish()` where the actor-isolated form made that structurally impossible.
    Mitigated by disarming both watchdogs *before* teardown; the residual window needs
    `terminate()` delayed ≥3 s past a stream death. Documented in Polling.swift rather than
    pretended away — if it ever shows up, revert the mic poll to an actor-isolated `Task {}`.
  - **`.hidSystemState`, not `.combinedSessionState`**, for the idle probe: the combined state
    counts *synthetic* events, so a mouse jiggler or keep-awake utility reads as "someone's here"
    on an unattended machine and manufactures the false stall the cross-check exists to prevent.
  - **Accepted false positive (documented, not faked): multiple displays.** The idle probe is
    machine-wide, capture is per-display — working on an uncaptured second display reads as
    active while the captured one is legitimately static. macOS exposes no per-display input
    signal. Costs log noise in a diagnostic, never a recording. Weigh it when reading a
    multi-display soak.
  - **The diff took the package from warning-clean to not** (a bare `@Sendable` method-reference
    default). With no CI the build loop is the only gate we have, so a standing warning is how
    the next real one gets scrolled past. Fixed; a clean build is back to **0 warnings** — worth
    checking that explicitly, since `grep error` won't show it.

- 2026-07-15 (M3-T4 display/sleep): the technical findings are in **02 §1/§7** (the -3815 code,
  the lock+sleep truth table). What belongs here is the process lesson:
  - **I mis-modelled this twice, and each wrong model produced a test that "passed" while
    testing nothing.** First guess: "a locked screen hides displays" → locked, captured fine
    (it records the login window). Second: "display sleep hides displays" → `pmset` slept it,
    captured fine (SCK wakes it). Only lock **AND** display-off does it. Both wrong runs looked
    like clean passes, not errors — that is the whole danger. Fourth time today (see the
    `--nil-follow` window and the 400 MB disk image) that a test's *setup* failed to create the
    state under test and quietly reported success.
    **Rule going forward: for any environment-dependent test, first prove the condition exists,
    then assert on it.** A test that cannot fail for the intended reason is decoration.
  - **`pmset displaysleepnow` is a genuine headless lever** for the mid-recording death
    (-3815 → `.displayDisconnected` → playable file) — that half of §4.3 no longer needs a human.
    The zero-display start path still needs a real lock (a shell keeps running while locked, so
    a human locks and the agent drives `pmset` + the capture).
  - **`EndReason.systemSleep` is unreachable** and was never wired up. SCK collapses sleep, lock
    and unplug into one code, so there is nothing to map it from. Left in place (docs/01 defines
    it, M5/M6 may find a source) but do not fake a distinction to justify it.
  - **The review found my fix only half-fixed the bug.** I gated the permission message on the
    preflight (`granted` → "no displays", else → "grant permission") — but
    `Permissions.screenRecordingState()` never returns `.denied`, so `.notDetermined` is the only
    other live value, and it's exactly what a freshly-built CLI binary reports *while capturing
    fine* (02 §10). So the original misdiagnosis survived on the only path the CLI can reach.
    The deeper point the review surfaced: **zero displays can never mean "ungranted"** — an
    ungranted process throws instead (02 §10) — so the preflight should not gate this at all.
    Now: zero displays ⇒ "no displays available", full stop. Lesson: a decision table looks
    complete until you check which cells the production caller can actually produce.
  - ⚠️ **02 §1 and §10 flatly contradicted each other** on ungranted behavior (empty results vs
    throws) and had done since the planning docs. §10 is measured, so it won. Untestable here
    (revoking TCC would destroy our own grant) → **M4-T3's fresh-account walkthrough settles it**,
    and the task now says so. If §1 turns out right, `startDecision` needs revisiting.
  - **-3817 `SCStreamErrorUserStopped` was landing on the fail-stop path.** macOS's screen-
    recording indicator lets a user stop the capture; that arrived as `.streamError`, which
    ADR-007 defines as fail-stop — so the most ordinary stop there is would have fired M4's
    "ended unexpectedly" notification. Now maps to `.userStopped`.

- 2026-07-15 (M3-T3 disk guard): the review caught a bug my gate **and** my unit test were both
  structurally blind to. Worth internalizing.
  - **`volumeAvailableCapacityForImportantUsage` returns 0 (not nil) on every non-boot volume.**
    Full detail + the fix now in 02 §7. Shipping impact would have been: every recording to an
    external SSD/USB/SD/disk-image self-terminates at ~2 s claiming "disk almost full".
  - **Why nothing I did could have caught it:** the unit test probed `temporaryDirectory` and the
    §4.4 gate wrote to `~/Movies` — *both the boot volume*, the one place the key works. A test
    named "reads real capacity" passed the whole time. Lesson: when an API's behavior is
    **environment-dependent**, testing one environment is testing nothing. The fix splits the
    volume-dependent reconciliation into a pure function over both keys, which IS testable, and
    keeps the live probe as a thin shell.
  - **Verified end-to-end after the fix**: a 4 GB HFS+ image (importantUsage 0, raw 3.7 GB) now
    records the full 8 s and finishes `userStopped`. Test that scenario with `hdiutil create
    -size 4g -type SPARSE` — and make the image **bigger than the floor**, or the guard fires for
    a legitimate reason and the test proves nothing (I did exactly that with a 400 MB image first).
  - **A wall-clock delay is not a startup guarantee.** The poll originally slept 2 s before its
    first check so it couldn't stop the engine pre-first-frame. But engine start can exceed 2 s
    (first launch, Bluetooth mic binding) — and a thrashing near-full volume is *precisely* when
    it does, so the guard's own trigger correlates with the race. Now it waits on
    `recordedDuration` leaving NaN (the writer session actually starting) instead.
  - **Deferred (rule of three):** the disk poll loop is verbatim-identical to CaptureEngine's mic
    watchdog loop. The review flagged the duplication; M3-T5's stall watchdog makes it three, so
    extract a shared `poll(every:)` helper there. Not done here because moving CaptureEngine's
    `Task {}` into a nonisolated helper would silently change its actor isolation — a real
    behavior change to ship as a side effect of a cleanup.
  - **Open design question for M3-T4/M6-T3:** we *guard* a filling disk but never *preflight*
    one — starting a recording with < 2 GB free stops it ~instantly with `.diskAlmostFull`
    (correct, but a refusal up front with "free some space" would be kinder than a 2-second file).

- 2026-07-15 (**free M3-T4 evidence, found by accident during M3-T3**): Franco's display went to
  sleep mid-session and handed us two display-handling findings for nothing.
  - ✅ **Display sleeping MID-recording behaves correctly**: SCK fired `didStopWithError`
    ("Failed to find any displays or windows to capture") → `finished(streamError(…))` → a
    **playable 1.81 s file**. That is ADR-007's fail-stop working in the wild, and it is most of
    what §4.3 asks for. M3-T4 should still do the deliberate lid-close run, but the mechanism is
    already observed.
  - 🐞 **BUG for M3-T4: a LOCKED screen is misreported as a permission failure.** Confirmed
    cause — Franco locked the screen on stepping away, so this is a 2-second repro, not a
    theory: **lock the screen → run `record` → "Screen Recording permission is needed"** while
    `CGPreflightScreenCaptureAccess()` says **granted**. `SCShareableContent` returns **0
    displays** for a locked screen, and `CaptureEngine.startDecision` maps *any* zero-display
    result to `permissionGuidance` — sending the user to System Settings to grant a permission
    they already hold. 02 §1's "empty results = permission missing" is **incomplete**: locked,
    asleep, and disconnected displays are indistinguishable from it. Fix in M3-T4 — gate the
    permission wording on the preflight actually disagreeing, else say "no displays available —
    the screen may be asleep, locked, or disconnected". `CaptureEngineTests.
    failsWhenNoDisplaysAvailable` encodes the conflation and must change with it. Deliberately
    NOT folded into M3-T3 (unrelated to the disk guard).
  - **Capture tests need the screen unlocked and awake.** Zero displays ⇒ nothing captures. If
    capture suddenly fails with a permission message mid-session while the preflight says
    granted, suspect a locked/sleeping screen before suspecting TCC — the message actively
    misleads you here until M3-T4 lands.

- 2026-07-15 (M3-T7 spike — mic device binding): full findings live in **02 §4** (experiment
  table + the two recovery routes) and **02 §1** (the nil correction). Meta-lessons worth keeping:
  - **The spike blew its time-box (30 min → ~2 h) and was worth it.** It killed a stale ⚠️ that
    had been shaping the design, produced a one-line root-cause model, and turned "can we ever
    recover the mic?" from a guess into two costed, de-risked routes. But log it honestly: a
    time-box that gets ignored should at least be noticed.
  - **My priors were 1-for-3.** I predicted leg 1 would fail (it worked), leg 2 would fail
    (right), leg 2b would fail (it worked). In this API, reason less and measure more.
  - **A test that never triggers its event reads exactly like a negative.** The first `--nil-follow`
    run "proved" nil doesn't follow — actually the AirPods never disconnected inside the fixed
    25 s window (buffer counts kept climbing). Fixed by watching for *either* outcome with a
    generous bound, plus an explicit INCONCLUSIVE verdict. Any future device spike should do the
    same rather than assume a duration.
  - **AirPods only disconnect when the case LID CLOSES** — an open case keeps them connected.
    That is what silently invalidated the first run; put it in any test instructions.
  - **`updateConfiguration` returns OK while doing nothing** when asked to bind a died device
    (8/8 attempts). No error path to detect it — you must watch for buffers.

- 2026-07-15 (M3-T6 mic-loss watchdog): what the live runs and the review taught.
  - **SCK keeps delivering mic buffers while paused** — proved by a 5 s scripted pause against
    a 3 s watchdog timeout that did NOT false-fire. That's why the watchdog needs no pause
    handling at all: it's a router-level consumer, and pause never stops the stream (M3-T1).
    If pause is ever changed to stop the stream, this watchdog WILL false-fire — read this first.
  - **Detection latency is timeout + poll interval** (3 s + ≤1 s). Live: mic died at 21.82 s,
    warning at ~25 s. Matches by construction; don't shrink the timeout without checking the
    load-jitter margin (M3-T1 saw ~0.9 s audio starvation under heavy load).
  - **Disarm the watchdog BEFORE `await stream.stopCapture()`, not after** (/code-review). Stop
    halts mic delivery and Bluetooth teardown can take seconds, so a watchdog still polling
    across that suspension reports a disconnect on a recording whose mic track is complete —
    "⚠️ disconnected" immediately followed by "✓ finished". Cancel-on-`terminate()` alone is
    too late. The same reasoning will apply to M3-T5's stall watchdog.
  - **`Task {}` inside an actor method INHERITS the actor's isolation** — it does not run off-
    actor (I had a comment claiming the opposite; the compiler disagrees). Fine here (the poll
    body is one lock-guarded compare) but don't assume a spawned Task escapes the actor.
  - **Dropping a `Task` reference does not cancel it.** An engine released while `.running`
    (never stopped, no error) left the 1 Hz poll waking forever — now cancelled in `deinit`.
  - **`start()` could resurrect a terminated engine**: a stream error can `terminate()`
    reentrantly during the `startCapture()` await, then `start()` resumed and set
    `state = .running` over it (pre-existing; M3-T6 made it worse by stranding an
    uncancellable Task). Now guarded with `guard state == .starting` on resume.

- 2026-07-15 (§4.2 LIVE — **docs/02 §4's mic-takeover claim is FALSE**): Franco recorded 60 s
  with AirPods, cased them at ~22 s. Result — the recording **continued to the full 60 s** and
  finished `userStopped`, dropped frames 0:
  ```
  duration: 59.85s
  track 1: audio aac  48000Hz 2ch  dur 59.79s   ← system audio, full
  track 2: video hvc1 4112x2570    dur 59.85s   ← video, full
  track 3: audio aac  24000Hz 1ch  dur 22.57s   ← mic (AirPods), STOPS at the disconnect
  ```
  - **The built-in mic did NOT take over. The mic buffers just stopped.** No format change, no
    error, no event. So M3-T2's format-compare detector correctly never fired — it is a valid
    guard for a *same-device* format change, but it is NOT the AirPods story it was written for.
  - **Root cause: we pin an explicit `microphoneCaptureDeviceID`** (forced by 02 §1 — nil throws
    "invalid parameter" on 15.6). SCK captures the device you named and won't substitute. With a
    pinned ID a device *switch* essentially cannot occur; only *loss* can. Corrected in 02 §4.
  - **This exposed a real ADR-007 violation in the status quo:** the mic died and nothing told
    the user — 37 s narrated into a void, exit 0, file looks healthy. "Silently degraded" is the
    exact failure ADR-007 forbids. Fix = a starvation watchdog (M3-T6) emitting `microphoneLost`.
  - **Policy decided: ADR-012** — mic loss notifies and KEEPS recording (ending a 90-min screen
    capture over a headphone battery is the worse outcome). Amends ADR-007 for that trigger only.
  - **Open (M3-T7 spike):** re-attaching to the built-in mic to keep recording *sound* needs
    (a) `SCStream.updateConfiguration` to accept a new mic device ID live — unverified, and
    (b) a fixed-format resampled mic input, since the writer input's format is welded to the
    first buffer's and cannot change after `startWriting()`. (a) is spike-able headlessly.

- 2026-07-15 (M3-T2 mic format-change): fail-stop wiring + a reusable seam.
  - **Detection = compare the mic buffer's ASBD to the input's established one** (sample rate,
    channel count, format ID). SCK mic buffers are LPCM and a given device's format is stable,
    so a device switch (AirPods 24 k mono → built-in 48 k mono/stereo) is the only thing that
    changes those fields — no false positives. `MovieRecorder` stores the ASBD when it builds
    the mic input and checks every later mic buffer; on a diff it fires a **one-shot** callback
    and drops the mismatched buffers (never feed a new format into the established input — it
    corrupts the track, docs/02 §4).
  - **New reusable seam: `CaptureEngine.stop(reason: EndReason = .userStopped)`.** A monitor that
    detects a fail-stop condition passes its reason; it flows through the existing `.stopped`→
    `.finished` path so the file finalizes as `.finished(reason:)`. M3-T3 (disk floor →
    `.diskAlmostFull`) and M3-T4 (display/sleep) reuse this — don't reinvent per-condition stops.
  - **The recorder signals OUT via an injected `@Sendable` callback; it never touches the engine.**
    `RecordingSession` builds the callback capturing the `engine` actor (no `self` capture, no
    retain cycle) and injects it at recorder init. The callback fires from a capture queue under
    the recorder lock but only spawns a `Task { await engine.stop(...) }` — non-blocking, and the
    later `recorder.finish()` runs off-lock via the event loop, so no re-entrancy/deadlock.
  - **Detection sits AFTER the writing gate, deliberately** (high-effort /code-review finding).
    Placed before it, a swap in the first frame-interval fail-stopped a recording with nothing
    written → `.failed(noFramesWritten)` + discarded output, while a swap a hair later gave a
    playable file — the outcome flipped on sub-frame timing. Pre-writing mic buffers are already
    dropped by the `guard didStartWriting`, so capture now just carries on until there's
    something worth saving. Two tests pin this (fires-once-and-finalizes / before-writing-
    doesn't-fail-stop) — note the mic-only test only passed originally *because* of the bug.
  - **The callback fires OUTSIDE the lock** (same review): `consume` registers the notify defer
    *before* the unlock defer, so LIFO runs unlock first. `lock` is non-reentrant — firing under
    it made any handler that touched the recorder a capture-queue deadlock waiting to happen.
  - **`stop(reason:)` carries the reason through the `.starting` path too** (same review): the
    branch used to keep only `stopRequested` and terminate as `.userStopped` on resume, so a
    swap during `startCapture()`'s suspension would misreport the cause. Now paired with
    `requestedStopReason`.

- 2026-07-14 (M3-T1 pause/resume): wiring + a timing lesson for future gate runs.
  - **Pause anchor = newest raw PTS across all tracks**, not the last video frame. The rebaser
    removes `resumeFrameRaw − pauseAnchor`; anchoring on the last *video* frame (which can be
    stale on a static screen) would over-remove. System audio flows continuously (~43/s) so
    the cross-track max stays within a buffer of real "now". `MovieRecorder.latestRawPTS`.
  - **Resume re-anchors on the next COMPLETE video frame** (docs/02 §5, for A/V sync). So the
    pause-math precision depends on a frame arriving promptly after resume — i.e. on the screen
    changing. With normal desktop activity (ticker repainting, cursor) frames flow at tens of
    fps and the resume frame lands within ~1 frame; on a truly static screen the resume frame
    can lag up to ~1 s and shorten the file. The gate must run with screen motion present.
  - **`--script` sleeps use a tight-tolerance ContinuousClock sleep, not `Task.sleep`.** Default
    `Task.sleep` grants the scheduler generous wake-up slack; under the capture's CPU load the
    two 10 s record segments overshot ~0.2–0.3 s total, pushing the file to ~20.25 s (just over
    the ±0.2 s gate). A 2 ms tolerance recentres warm runs on ~20.0 s (±0.05).
  - **First scripted run in a batch is a cold-start outlier** (saw both 20.46 s high and 19.04 s
    low). The SCK capture-start / first-frame path warms up after one run; warm runs then
    cluster tightly (19.86–20.03 across ~9 runs). Same cold-start caveat as the G2 §3.5 flasher.
    Gate protocol: do one warm-up capture, then measure on a CALM system. DO NOT drive the
    record segments off `recordedDuration` to "nail" 20 s — that would make the file 20 s *by
    construction* and stop the duration check from proving the pause was removed (the 25 s-wall→
    20 s-file delta is the whole point). Keep wall-clock sleeps. The `--script` first segment IS
    anchored to the first frame (waits for `recordedDuration` to leave NaN) so SCK startup
    latency doesn't shorten the file — that's a *measurement* anchor, the segments stay wall-timed.
  - **Under heavy background load the gate spread widens** (saw 19.2–20.85 with load ~2.6 right
    after the 17-agent code-review workflow), but the MEAN stays ~20.05 (math is exact). The
    high outliers are *audio starvation*: near stop, under load, system-audio delivery lags and
    the video tail-frame patch extends video ~0.5–0.9 s past where audio ended → total tracks
    the longer video. Not pause-specific (tail-patch × load; G2 §3.5's 30-min run matched tracks
    ≤50 ms under normal load). Measure §4.1 on a calm box.
  - **`.paused`/`.resumed` events are gated on the timeline actually toggling** (high-effort
    /code-review finding): `TimestampRebaser.pause/resume` now return whether they took effect,
    `MovieRecorder` propagates it, and `RecordingSession` emits the engine event only when true.
    Pausing in the startup window (engine `.running` but before the first frame / rebaser epoch)
    is a no-op and no longer emits a pause that didn't happen. Also fixed: interactive stop
    regressed to "only bare Return" — restored to "any non-p/r line stops"; `--duration` timer
    now uses the same `preciseSleep`.

- 2026-07-14 (G2 §3.5 drift): the 30-min A/V-sync check is fully automatable given a
  beepflash recording. Method (reusable for the M6 §7 soak sync check): find each flash via
  **AVAssetReader sequential decode** of the video track in a time window + sparse-pixel
  brightness (NOT AVAssetImageGenerator random-access — it decodes from a keyframe per seek,
  ~100× slower); find each beep via AVAssetReader LPCM peak amplitude in the same window;
  compare flash-time − beep-time across markers. Result: constant ~−67 ms offset (fixed
  pipeline latency), no drift over 30 min. GOTCHAS: (a) the flasher's FIRST invocation is a
  cold-start → first marker's flash renders ~400 ms late; use markers 2+ for sync. (b) beepflash
  markers are ~287 s apart (285 s sleep + ~2 s per marker), so estimated marker times drift
  ~12 s by 30 min — center the search on observed flash times, not the nominal interval.

- 2026-07-14 (M2-T6): calibration + tools. Big practical unlocks for future capture work:
  - **Foreground Bash captures WORK** (agent runtime holds the TCC grant); backgrounded/
    detached commands lose it and fail "permission needed". Keep capture commands foreground
    and short-ish (a 28 s 4-way calibration loop stayed foreground; a `swift tools/probe.swift`
    COMPILE inside a command can push it over the auto-background threshold — pre-compile).
  - **I can drive a full-screen scene myself**: a `.screenSaver`-level `NSWindow` from a
    swiftc-compiled CLI renders on the display and IS captured (verified via frame brightness:
    a white flash reads 1.00 vs 0.22 baseline). `tools/busyscene.swift` (animated scene) and
    `tools/beepflash.sh` (sync markers) both use this.
  - **AVVideoAverageBitRateKey is a SOFT cap in real-time HEVC.** The HW encoder floors at the
    content's "natural" bitrate and won't crush quality to hit a low target — so presets barely
    separate on busy content (efficient≈balanced) and Balanced can't be pushed below ~50% of
    Tier-1 on complex scenes. Hard control needs VideoToolbox `DataRateLimits` (a VTCompression
    path), not AVAssetWriter — note for M6 if stronger preset differentiation is wanted.
  - Comparison table + numbers are in the "M2-T6 calibration comparison" section above.

- 2026-07-14 (human-verified): Franco ran `record` in his OWN terminal (not the agent
  runtime) and it worked perfectly — real capture, plays back, produced file good. Confirms
  the record pipeline works for a real user outside the agent's TCC grant, and the documented
  first-run permission dance holds. NOT a formal G2 pass (kill-9 / sync-clap / static-tail /
  drift still unrun), but de-risks G2 §3.1 track layout.

- 2026-07-14 (M2-T5): full `record` CLI UX. Notes:
  - **Progress ticker** = `\r  ⏺ MM:SS  <size>` every 0.5 s to stdout, guarding
    `recordedDuration.seconds` with `.isFinite` (the recorder returns `.invalid`/NaN before
    the first frame — docs/02 §10). `RecordingSession.recordedDuration` exposes it.
  - **Positional `[path]`**: an existing directory → auto-named inside; else an exact output
    file (O_EXCL-reserved via `OutputLocation.reserveExact`, refuses to overwrite).
  - **Return-to-stop** only when `isatty(STDIN_FILENO)` — a piped/automated run must NOT be
    stopped by stdin EOF, so the reader is skipped there (`--duration` bounds those).
  - **Preset size ordering IS testable live** with generated motion: a background mouse-mover
    (`CGWarpMouseCursorPosition` in a loop — no Accessibility grant needed) gives enough
    consistent frame change that efficient<balanced<high holds. Ambient static screen won't.
  - **Backgrounded/detached Bash commands lose the Screen Recording TCC grant** → capture
    fails "permission needed". Run capture tests in the FOREGROUND. (The failure did confirm
    the placeholder cleanup: a failed record leaves no 0-byte litter.)
  - Review fix: keeping the O_EXCL placeholder (M2-T4 TOCTOU) leaked a 0-byte file on failure
    paths and blocked exact-path retry; `MovieRecorder` now removes it on cancel / no-frames.

- 2026-07-14 (M2-T4): `record` does real 3-track capture. Design + gotchas future agents need:
  - **MovieRecorder self-configures from buffers.** It's now a `SampleConsumer`; the video
    input is built lazily from the FIRST frame's format (dimensions), like the mic input from
    the first mic buffer. This removed all pixel-dimension plumbing (the CLI can't resolve the
    display size without capturing) — the recorder just needs fps + preset + mic on/off. Every
    buffer is rebased via `TimestampRebaser` and retimed with
    `CMSampleBufferCreateCopyWithNewTiming` before append, so the file is zero-based & monotonic.
  - **`RecordingSession`** (new, RecorderCore/Recording) composes engine+recorder and emits the
    unified event stream incl. `finished` — the CLI and (later) the app share it.
  - **Probe monotonic check must use DTS, not PTS.** HEVC B-frames make PRESENTATION timestamps
    legitimately non-monotonic in storage order (probe saw "61/122 out of order" — all false).
    DTS (decode order) is the real invariant. Also: encoders emit a benign equal-timestamp edit
    at the very start (priming) and an invalid (nan-PTS) trailing packet — flag only STRICTLY
    backward steps and skip non-numeric stamps, or the probe cries wolf on clean files.
  - **Synthetic-buffer tests can't verify the tail-frame patch's extension.** `expectsMedia
    DataInRealTime = true` (required so SCK callbacks never block) makes the writer DROP buffers
    fed faster than real time; a burst-fed test drops most frames so durations are unreliable.
    The tail-patch code runs in the live path; its EXTENSION behavior is a G2 §3.4 (static
    screen) gate item. Don't add synthetic duration-assert tests for it.
  - **OutputLocation.reserveRecordingURL** closes the TOCTOU by `O_EXCL`-creating each
    candidate name and KEEPING the placeholder (holds the name); `MovieRecorder.beginWriting`
    removes it in the same synchronous breath as `startWriting()` creates the real file
    (`AVAssetWriter` init is fine with a pre-existing file but `startWriting` fails on one —
    verified), so the name is free for microseconds, not the whole startup window.

- 2026-07-14 (M2-T4 review): high-effort /code-review found real bugs; all fixed this task:
  - **Mic-never-arrives no longer discards the recording.** A selected-but-silent mic used to
    block `startWriting` forever (whole capture lost). Now `MovieRecorder` gives the mic a
    0.75 s grace past the first video frame, then proceeds WITHOUT the mic track. (M3-T2 can
    refine — e.g. surface a "mic unavailable" event.)
  - **TOCTOU actually closed** — the first pass deleted the placeholder before returning,
    reopening the race; now the placeholder is held until the writer (see above).
  - **`--duration` capped at 86400 s** — `UInt64(seconds * 1e9)` trapped on huge values.
  - **CLI mic resolution made pure + deduped** (dry-run and capture share one resolver).
  - **probe monotonic check now single-pass** across all tracks (was one full file pass per
    track — slow on the 30-min gate files).
  - Left as-is (low value): the lazy video input can't throw a precise `cannotAddInput(.screen)`
    at init like the old eager path — a bad first-frame format would fail late with
    `noFramesWritten`. SCK always delivers a valid video format on this hardware.

- 2026-07-14 (M2-T2): MovieRecorder skeleton lands (3-track .mov, HEVC + 2×AAC).
  TWO things worth carrying forward:
  (1) **AAC bitrate must snap to the encoder's applicable set.** Apple's AAC encoder
      accepts only a discrete bitrate set that shrinks with the format — 24 kHz mono
      (AirPods!) tops out at 64 kbps: `[16,20,24,28,32,40,48,56,64]k`. Requesting the
      nominal 160 kbps → `AVAssetWriter` fails at finish with -11861 / OSStatus -12651
      "encoding parameters not supported." `MovieRecorder.supportedAACBitRate` now queries
      `AVAudioConverter.applicableEncodeBitRates` and picks the highest ≤ target. This is
      exactly the AirPods 24 kHz mono case from G1 — the docs/02 §4 "~160 kbps" is a target,
      not a literal. (docs/02 §4 could note the discrete-set constraint.)
  (2) **OPEN for M2-T4/M3-T2 — mic-enabled recording is hostage to the mic.** Because the
      mic input is built lazily from the first mic buffer and inputs can't be added after
      `startWriting()`, the writer defers `startWriting` until that first mic buffer. If a
      mic is selected but never produces a usable buffer (silent/failed device, or a first
      buffer with no ASBD), `startWriting` never fires, ALL video is dropped, and `finish()`
      throws `noFramesWritten` — the whole screen recording is lost over a mic glitch. M2-T4
      (readiness/robustness) or M3-T2 (mic handling) must add a fallback: e.g. after a short
      grace period with no mic buffer, start writing video+system without the mic track.
  Also: `MovieRecorder` needs the resolved PIXEL dimensions (not in CaptureConfiguration —
  the engine computes them at start). M2-T4 must pass the engine's resolved width/height +
  the clamped fps into the recorder.

- 2026-07-14 (M1-T4): probe-stream confirms all three sources flow through the router.
  KEY M2 INPUT — the mic's native format is device-dependent and differs from system
  audio: AirPods = 24000 Hz/1ch/32-bit float, built-in = 48000 Hz/1ch/32-bit, system
  audio = 48000 Hz/2ch/32-bit. Empirical proof the mic needs its own AVAssetWriterInput
  (can't share the system-audio input — DTS finding now confirmed live). Screen frames
  arrive as 4112×2570 `420v` (bi-planar YUV 4:2:0, NOT compressed — HEVC encode happens
  in the writer). Mic capture required Franco to grant Claude Code Microphone TCC.
- 2026-07-14 (M1-T2 review): xhigh code-review of the capture engine found real
  concurrency/robustness bugs — all fixed: (a) stop() during start()'s suspension was
  silently lost → added a state machine (idle/starting/running/terminated) + stopRequested
  honored on resume; (b) fail()/didStopWithError could both emit → single termination
  authority (failToStart/terminate, state-guarded; handler hops to the actor); (c) engine-
  smoke reported streamError / no-frame as OK → now requires .started + clean stop;
  (d) --duration nan/inf/neg trapped → validated; (e) unvalidated frameRateCap → clamped
  [1,240]; (f) raw TCC error → mapped to permissionGuidance (tested); per-instance sample
  queues; early-exit smoke on failure. Accepted as-is: startDecision.denied is defensive/
  unreachable in prod; minor guidance-string duplication with Permissions.swift.
- 2026-07-14 (M0 holistic review + M1-T1): Holistic M0 review passed from a fully clean
  state (`rm -rf .build dist` → build/test(23)/release/bundle all green; devsign
  idempotent; designated requirement stable across fresh rebuilds; CLI works). M0 is
  genuinely complete. M1-T1: CaptureConfiguration + QualityPreset/DisplaySelection/
  MicrophoneSelection value types + pixel math, 29 tests. CLI now parses presets via
  QualityPreset (placeholder array removed).
- 2026-07-14 (M0-T5): CLI dry-run + list-mics work. TWO things to watch in M1:
  (1) `CGPreflightScreenCaptureAccess()` returns false ("not determined") for the
  freshly-built Tier-2 CLI even though this terminal records fine via the Tier-1 PoC —
  TCC screen-recording grants attach to the responsible binary's code identity, so the
  new binary may need its own grant, or preflight is just conservative. M1-T2's
  engine-smoke will settle whether capture actually works from the terminal or needs a
  grant. (2) Desktop preflight now reports OK because this terminal currently CAN write
  there (the write-probe tests reality) — so the old "Desktop always fails" is
  environment-specific, not universal; ~/Movies default still stands as the no-grant-
  needed choice.
- 2026-07-14 (M0-T4): Permissions.swift + OutputLocation.swift in RecorderCore, 23
  tests green. Ran /code-review (xhigh workflow) on the diff; fixed 5 of 6 findings:
  preflight now probes WRITE access (opendir only proved read/execute) and distinguishes
  a missing folder from a permission denial; mic resolution rejects a stale/unplugged
  preferred ID and an empty default; timestamp/resolvedFileName made internal.
  **Deferred to M2 (open item):** newRecordingURL collision resolution is check-then-act
  (TOCTOU) — two recordings started in the same clock second could resolve to the same
  name. Real fix = the writer creating the file with `O_EXCL` and retrying the suffix on
  EEXIST. Low risk now (manual recording is single-instance; replay uses a "Replay"
  prefix). MovieRecorder (M2-T2/T4) MUST use exclusive create — add to that task's work.
- 2026-07-14 (M0-T3): bundle.sh assembles/signs dist/ScreenRec.app. Verified:
  Identifier=dev.fcostantini.screenrec.app, Authority=screenrec-dev; designated
  requirement byte-identical across two rebuilds (`identifier "…" and certificate leaf
  = H"62a8ac…"`) → TCC grants will survive rebuilds; `open` launches the LSUIElement
  app, process stays alive, quits cleanly. `spctl -a -t exec` fails (not notarized) —
  expected pre-M6, script reports it without failing. Info.plist lives at
  Sources/ScreenRecApp/Resources/Info.plist and is `exclude`d in Package.swift so SPM
  ignores it.
- 2026-07-14 (M0-T1): Command Line Tools have NO XCTest — `import XCTest` fails to
  compile. Swift Testing (`import Testing`) works and is now the mandated framework
  (docs/02 §10 updated). Verify evidence: `swift build` links all 3 targets;
  `swift test` → "1 test passed"; CLI prints skeleton banner with RecorderCore 0.1.0.

- 2026-07-13 (planning session): Tier-1 PoC (~/code/screenrec-poc) empirically verified:
  SCRecordingOutput survives kill -9 with sub-second loss; nil microphoneCaptureDeviceID
  throws "invalid parameter" on 15.6; Desktop output dir fails the same way when the
  terminal lacks the Files & Folders grant; recordedDuration is NaN pre-first-frame.
  All encoded in docs/02.

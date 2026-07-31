# 06 — UI Specification (menu-bar app, M4/M5)

The authoritative description of the app's UI. Visual mockups exist in the plan
artifact (Franco has the link); this doc is the buildable spec. Principle: every
control maps 1:1 to a RecorderCore capability that already passed its CLI gate —
the UI adds no behavior of its own.

## Shell

SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.menu)`. `LSUIElement = true` (no Dock
icon, no main window). Windows that exist: Settings (⌘,) and Onboarding (first launch /
missing permissions only).

## Status item (the menu-bar icon)

| State | Icon | Notes |
|---|---|---|
| idle | outline record circle (`record.circle`) | template image, adapts to menu bar |
| recording | filled red circle | subtle pulse; respect Reduce Motion (static red) |
| paused | half-filled circle, amber | |
| input level (M16-T5) | three rising bars right of the glyph, lit by peak level | **composited into the icon image** — a MenuBarExtra label renders only its first `Image` (measured, docs/07). Shown while recording or armed with a mic; opt-out `showsMenuBarLevel`. Lit/unlit by opacity, not colour: the idle icon is a template, where only alpha survives |
| elapsed clock (M9-T3) | `HH:MM:SS` right of the glyph while recording | **drawn into the icon image**, not carried as a `Text`: the `.menu` bridge renders a label's `Text` as the status item's AppKit *title* and discards SwiftUI layout and styling, leaving the digits 1.5 px high at 2× with no way to move them (measured, docs/07). Centred on the font's cap height, since digits have no descenders. Opt-out `showsMenuBarTimer` |
| replay armed (idle) | outline circle + small dot badge, **bottom-trailing** | armed is orthogonal to recording. **M5** — see the Settings amendment: the badge ships with the feature that can be armed, not before (it had been re-homed T1→T2→T4 before Franco ruled) |
| export in flight (M23-T3) | a second dot badge, **top-trailing** | orthogonal again — an export can run while idle *or* recording, so it is a flag composited in, never a fourth `StatusIcon` case. The corner is the only free one: armed keeps the one it has shipped in since M5 (Franco's ruling, 2026-07-30) |
| saved (M9-T3, fixed M23-T3) | a tick right of everything else, ~2 s | ⚠️ **had never rendered**: it was a second `Image` in the label's `HStack`, and a MenuBarExtra draws only the first (measured, docs/07). Now composited like the badge, meter and clock. Raised by a replay save, and by a take that stops **while replay is armed** — the case that was otherwise silent on every channel, since an armed stream keeps the display captured and macOS suppresses banners then (M5-T5). An ordinary stop does not flash: its banner works, and two confirmations of one event is noise. Not raised for `.writeFailed`, whose notice is a problem to read rather than a tick to glance at |

## Menu — idle state

Order and grouping (separators between groups):

1. Header row: `ScreenRec` — right-aligned status `Ready` (or blocking condition, e.g.
   `Permissions needed…`). ⚠️ **AMENDED 2026-07-15 (Franco): always clickable, never disabled —
   it always opens Onboarding, `Ready` or not.** As originally specified it was disabled unless
   blocked, which strands the optional Notifications row: notifications never block, so once
   the blocking rows go green the window stops auto-opening and a user who dismissed the
   notification prompt has no route back to it from anywhere in the app. Auto-opening is still
   gated on a *blocking* row (nobody gets nagged about an optional one) — this only keeps the
   door openable. Onboarding never *reappears* on its own once satisfied; it can always be
   *asked for*.
2. **Start Recording** — primary action, bold. **M12-T3: the first actionable row** — the export/replay
   receipts (below) sit *under* Start/Arm, never squatting above it. When the opt-in start/stop shortcut
   is enabled (`recordHotkey`), Start advertises the combo in the shortcut column (the `Save Replay Now`
   pattern), and while recording so does whichever Stop row the ending selects (item 3b, M24-T2).
   **A Start that fails carries its reason directly under this row (M17-T2).** Such a start produces no
   session, so the menu stays *idle* — where `lastFailure` used to render nowhere and Start looked like
   a no-op. The recording-state menu has always shown it; both surfaces now do. ⚠️ The notification is
   not a substitute: banners can be suppressed while replay is armed (item 3's own caveat), which is
   exactly when this was found.
3. **Instant Replay armed** — checkmark toggle; right hint `⌥⌘R saves`. Persisted.
   **M5** (Franco, 2026-07-15): a toggle that arms nothing is a lie for a whole milestone.
   When armed, a dimmed cost row follows it (M16-T2): `4:30 buffer · ≈800 MB · Mac stays awake`
   — the Settings caption's short form, **stamped at open, never ticking** (M6-T10). Without
   screen geometry it degrades to `Mac stays awake while armed`.
4. — separator —
5. `Source ▸` submenu (M7-T2; was `Display ▸`): what gets captured. **Entire Screen** (one row
   per `NSScreen` when several — "Entire Screen (<name>)"), a divider, then the **running apps**
   (name-sorted; ScreenRec excludes itself; filtered to `activationPolicy == .regular` so system
   chrome — Dock, Control Center — never lists). Checkmark on current. Apps enumerate via
   `CapturableApps` — the same `SCShareableContent` read the engine binds against, so a listed
   app is always bindable; fetched async at menu open (the rows can land a beat late on the
   first open, like the recents). **A picked app that isn't running stays listed** as
   `<name> (not running)` with the checkmark — the pick survives absence (the mic rule), Start
   then fails loud (never a silent whole-screen fallback), and an armed replay retries until the
   app returns (measured: quit → relaunch re-arms unaided). ⚠️ `.disabled(true)` on a Picker row
   does not survive the `.menu` bridge (measured M7-T2) — the not-running row renders undimmed;
   accepted. Hidden while recording (see recording item 7).
   **System audio (M16-T3, ADR-019):** below `Microphone ▸`, a checkmark row **`Capture System
   Audio`** — a boolean gets a checkmark, not a submenu, and the menu is already under M18-T3's
   diet. Persisted (`capturesSystemAudio`, absent ⇒ on). Changing it while armed restarts the armed
   stream, like the mic and source picks (SCK binds audio sources per stream). When it is off **and**
   the mic reads None, one dimmed row follows: **`This recording will have no audio`** — a silent
   recording is legitimate, but it must not be a surprise discovered afterwards. Zero extra rows in
   every other configuration.
   **Window (M17-T2):** below the app rows, a single **`Window ▸`** row whose submenu lists the
   on-screen windows as `<App> — <Title>`, app-then-title sorted, ScreenRec's own excluded. It nests
   deliberately: a dozen-plus windows is normal (12 measured on the dev machine), and Source is the
   longest submenu already — M18-T3 is shortening it. Verified live that the `.menu` bridge carries a
   `Menu` inside a `Menu` with its own inline `Picker`, checkmark and all. The pick is
   **persisted with its owning bundle id** (`captureWindow`), and capture refuses a window whose owner
   doesn't match: window ids are **reused**, so a restored bare id could bind a different app's window
   — recording the wrong thing while looking like it worked (docs/02 §1c). ⚠️ **The pick stores the
   id and the bundle id, and nothing else (M19-T5)**: a window title is another app's content —
   a private-browsing window, a DM — and it has no business in the preferences plist. Rows label
   themselves from the *live* window, so a retitled window (every browser tab switch) stays the pick
   and simply relabels. It also has to be that way for the checkmark: the menu tags each row with
   the selection value, so a stored title that no longer matched the live one left the picked row
   unmarked (measured, M19-T5). A picked window that is gone stays listed and checkmarked as
   **`<App> (closed)`** — the app is all that can be said without a title, and the marker is what
   keeps it distinct from an app-scoped pick, in the row and in the `Source:` header alike. The
   `(not running)` app rule; Start then fails loud.
   **Everything Except (M21-T4):** a nested `Everything Except ▸` row (the `Window ▸` pattern, for
   the same reason — it must not lengthen the idle menu) listing the same on-screen apps, plus
   **`Nothing`** to undo it. The pick reads in the header as `Source: Entire Screen except Slack`, and
   one dimmed row follows the Source row: **`Slack won't be seen or heard`** — the exclusion takes the
   picture as well as the sound (SCK has no audio-only exclusion, docs/02 §1a-ii), and nobody should
   discover that by watching the file. Zero extra rows when nothing is excluded. A picked app with
   nothing on screen **cannot be excluded** (docs/02 §1a-ii): it stays listed as
   `<name> (not on screen)`, and the recording starts anyway with a notice — *"Recording started ·
   nothing left out"* — because losing the take over it would be worse. An excluded app quitting
   mid-recording is a non-event: there is simply nothing left to leave out.
   **Region (M11-T2):** below the app rows, when a region is set, a checkmarked `Region <w>×<h>`
   row (point size) shows the current pick — re-selectable, and it survives its display's absence
   like the app pick (a start against a vanished display fails loud, M11-T1). **M12-T4** moved
   **`Select Region…` *inside* `Source ▸`** (below the checkmarked region tag), so all three capture
   modes are entered from the one submenu — implemented as a `Menu` wrapping an inline `Picker` (the
   Picker keeps SwiftUI's reliable checkmark; the `.menu` bridge can't check hand-built rows) plus the
   action Button. The overlay opens full-screen (crosshair, Return confirms, Esc cancels); on confirm the
   rect (flipped from AppKit bottom-left to SCK top-left points, docs/02 §1b) becomes the Source. Persisted
   (display + rect); **main display only** in v1 — **M12-T4** makes that honest: the overlay's size badge
   reads **`<w> × <h> pt · <W> × <H> px`** (points × the display's backing scale, so a power user can frame
   exactly 1920×1080 px), and on a **multi-display** Mac a top-center caveat pill says *"Region capture
   uses the main display only"* (`RegionSelection.badgeText`/`mainDisplayHint`, pure + tested).
6. `Microphone ▸` submenu: `None`, **`Automatic (System Default)`**, a divider, then the input-device
   list. Checkmark on current. Disabled while recording. Devices enumerated **live** via the CoreAudio
   HAL (`AudioInputs.available`), not `AVCaptureDevice.DiscoverySession` — the latter caches and misses
   devices hot-plugged into a long-running app (M6-T11). Each HAL device is validated through
   `AVCaptureDevice`, so the list holds exactly what the recorder can bind: resolvable virtual/aggregate
   devices included, un-bindable ones filtered (Franco, 2026-07-20).
   **Automatic (M6-T13):** an opt-in mode that follows the system default input — resolved at
   record/arm start only (SCK binds the mic once, 02 §4), so a running capture never hot-switches to a
   mid-session device (that's M6-T4). A specific device pick is never overridden by a connecting
   device. The recording menu's active-mic line names the *resolved* device, so the menu doesn't lie.
   (A `.menu` Picker honors a `Divider()`, though not text color — see "Menu text styling".)
7. `Quality ▸` submenu: Efficient / Balanced / High (docs/02 §3 presets).

   **M12-T3 — the titles carry the current pick.** These three submenu rows read `Source: <pick>` /
   `Microphone: <pick>` / `Quality: <pick>` (e.g. `Source: Region 820×512`, `Microphone: None`,
   `Quality: High`), so a glance tells the truth without opening the submenu (the `.menu` bridge keeps
   the title text). The Source value mirrors the checkmarked row (whole screen — named only when there's
   a display choice — / app name / `Region <w>×<h>`); Microphone reads through `presentMicrophonePreference`,
   so an away device shows `None`, and Automatic shortens to `Automatic`; a picked-but-closed app shows
   its name (the `(not running)` detail stays on the submenu row). Pure `sourceMenuLabel`/`microphoneMenuLabel`.
8. — separator —
9. **`Recordings ▸`** (M18-T3) — the whole file browser, one level down. It was nine top-level rows
   (the folder, five recents, the `Recent Exports` label and three exports) out of a menu that
   measured 20 rows with three files and 32 at worst; folding it leaves 17 and 23. First row is
   **`Open Folder — <~/path>`**, which reveals the output dir in Finder and **shows the current
   destination** as a home-relative path (e.g. `~/Movies`) so it's visible without opening (Franco,
   2026-07-16). One title string — a SwiftUI `.menu` can't two-tone the path.
10. Recent recordings: up to 5 most-recent files from the output dir, inside `Recordings ▸` under a
    divider — until M18-T3 they were top-level rows **faked** one level in, since a SwiftUI menu
    exposes no `NSMenuItem.indentationLevel`; nesting them makes the indent real and the
    leading-space titles (and their accessibility labels) go away. Each row carries **what
    distinguishes takes**: `<name> — 23:04 · 5.5 GB` (M18-T3; name exactly as on disk, size through
    `ByteCountFormatter`, length `M:SS` growing to `H:MM:SS`). The read is **off the open and cached
    by modification date** (M6-T10): a row shows its name the first time a file is seen and gains
    its length and size when the read lands — measured 1–8 ms per file, and a repeat open re-reads
    nothing. ⚠️ `URL` caches resource values per instance and the menu holds its URLs across opens,
    so the cache check clears them first or a re-recorded file keeps a stale size forever.
    (Franco, 2026-07-15: they read as the folder's contents rather than as more commands.) **M10-T2/T3/T4 made each a submenu**, then **M12-T1 added the share/preview
    row** — `<name> ▸ { Reveal in Finder · Quick Look · Share… · Copy | Export as MP4 · Save as GIF ·
    Trim… }` (the `|` is a divider: act-on-this-file above, derive-a-new-file below) — so the
    export/share/edit actions have a home; the old direct click-to-reveal moved into the submenu.
    **Quick Look** opens the system preview panel (`QLPreviewPanel`, space toggles); **Share…** the OS
    share sheet (`NSSharingServicePicker` — AirDrop/Messages/Mail, no screenrec-hosted anything);
    **Copy** writes the file to the pasteboard so ⌘V drops it into Slack/Finder. `Trim…` opens the Trim
    window (below). An export shows an `Exporting <name>…` row while it runs (stamped at open, not ticking
    — the M6-T10 constraint) and an `Exported to MP4 · <name>` receipt — **M12-T1 made it a submenu too**,
    so the exported `.mp4`/`.gif` gets the same actions. **M12-T3** sits these receipts **below Start/Arm**
    (Start is the first actionable row) and **expires a stale one**: a persisted receipt older than one hour
    (`LastExport.date`, checked at menu open) is dropped, so it can't reappear as fresh from an earlier
    session — the file still lives in Recent Exports. **M12-T2** gave exports a
    real home: a **`Recent Exports`** group below the recordings (up to 3 most-recent `.mp4`/`.gif` in the
    output dir, same submenu), and the receipt now **survives relaunch** (persisted `lastExportPath`,
    validated — a receipt whose file was moved/trashed is dropped). The submenu also gained a third,
    **manage** group: **`Rename…`** (an `NSAlert` text field, extension preserved, collisions → ` 2`) and
    **`Move to Trash`** (reversible → no confirmation, red attributed title). Both act on the row's own file
    only — trashing/renaming a derived `.mp4` never touches its `.mov` source. The saved-replay receipt
    (M9-T2) shares the same submenu.
    **M24-T3 gave the take that just stopped the same receipt**: `Recording saved · 0:22`, first in the
    receipt group (a take precedes anything derived from it, so Stop & Copy MP4 shows both rows, each
    pointing at its own file). Titled by **length, not filename** — the timestamped name is exactly what
    makes `Recordings ▸` hard to scan, so repeating it would move the problem. It appears after **every**
    stop that leaves a file (`.writeFailed` is already withheld by `SessionModel.finishedRecording`), is
    **not persisted** — a recording already lives in `Recordings ▸`, so the row is prominence, not access —
    and expires at menu open on the export receipt's own one-hour clock, or when its file goes, or when the
    next take starts. A rename re-points it keeping its original date; a trash clears it. ⚠️
    Implementation notes from M4-T2: a SwiftUI `.menu`
    `MenuBarExtra` exposes neither `NSMenuItem.indentationLevel` (the indent is leading
    whitespace in the title, with an explicit accessibility label so VoiceOver reads the
    filename) nor a dimmed-but-clickable style — "dimmed style" is **not** currently met and
    can't be without dropping to a hand-built NSMenu. Revisit in M6 polish if it matters.
11. — separator —
12. `Settings…` (⌘,) · `Quit` (⌘Q). Quit while recording → confirm, then clean
    finalize before exit (never abandon a writer). **Every OTHER quit route while recording**
    (logout, shutdown, software update, `⌘Q` from a window) also finalizes — `applicationShouldTerminate`
    returns `.terminateLater`, saves the take, then exits (M13-T2). That path is **silent** (no confirm
    modal — one could stall a logout); only the explicit menu Quit confirms. Idle / armed-replay quit
    immediately (nothing on disk to save).

## Menu — recording state

1. Header row: pulsing red dot + elapsed `HH:MM:SS` (tabular numerals) + right-aligned
   `<size> · HEVC`. Values stamp at menu open (`NSMenu.didBeginTracking`) and hold while
   the menu stays open; every reopen is fresh. *Amended 2026-07-17 from "updates ≤ 1 Hz"
   (M6-T10, measured): any state publish rebuilds the OPEN menu's AppKit rows and garbles
   hover/highlight — a per-second tick corrupted rows under the cursor — and
   `Text(timerInterval:)` doesn't animate through the menu bridge, so a live clock in a
   `.menu` MenuBarExtra is not implementable without the corruption.* **M9-T3:** the *menu-bar
   label* (the status item itself, not the menu) DOES show a live ticking `HH:MM:SS` — it isn't
   subject to the bridge (it already redraws for the pulse), so the always-visible clock lives
   there; the in-menu header stays stamped-at-open. Opt-out via `showsMenuBarTimer`.
2. **Pause** / **Resume** (swaps by state).
3. **Stop & Save** — primary.
3b. **Stop & Copy MP4 · up to 95 MB** (M21-T2) — stops, finalizes, exports at the Settings size and puts
   the `.mp4` on the pasteboard, so the next keystroke is ⌘V. Sits *beside* Stop & Save, never
   replacing it: Stop & Save keeps the bold primary, and muscle memory must not start an encode.
   **The shortcut column follows `stopHotkeyCopies`** (M24-T2): exactly one of the two Stop rows
   prints the combo, and it is the one the key performs — the setting is opt-in, so this is a
   chosen ending rather than a surprise. **Not called "Stop & Share"** — `Share…` means the macOS share sheet everywhere else in
   this app. The figure is the Size picker's rate budget (M19-T4) over the elapsed minutes, stamped
   at open (M6-T10) and **omitted** without display geometry (M16-T2). It says **`up to`**, not `≈`:
   the encoder undershoots the budget badly on a quiet screen (11 MB quoted, 2.2 MB written — docs/07). **Disabled while an export
   runs** — `performExport` would drop the second one, and the `Exporting …` row immediately above
   says why (M17-T2: a dropped action must be visible). Ends in **one** notice — `Copied — ⌘V to
   paste`, which still reveals on click — not an export receipt plus a copy. The `.mov` is kept
   (ADR-004).
4. — separator —
5. Dimmed info rows: when app-scoped, `Recording <app> only` (M7-T2 — the recording menu names
   its subject); when region-scoped, `Recording region <w>×<h>` (M11-T2); active mic +
   `separate track`. Then the **Arm Instant Replay toggle
   — live mid-recording** (amended 2026-07-17, M6-T8: arming attaches replay to the live
   stream, disarming detaches; the recording is unaffected either way) and, when armed,
   **Save Replay Now** with the shortcut column carrying the combo (this replaces the old
   `Replay still armed · ⌥⌘R` info row — the checkmark and shortcut column say the same
   thing interactively).
6. — separator —
7. Dimmed: `Sources locked while recording` (pickers hidden, not disabled-but-present).
8. — separator —
9. **Discard Recording…** (M6-T12) — throw the take away. Subordinate to Stop & Save and set
   apart from it (two separators + the replay/sources block between them): the one irreversible
   action must not sit under Stop's muscle memory. **Red** title (see "Menu text styling"). Ellipsis
   ⇒ it confirms first, and the confirmation's **safe** choice is the default so a reflexive Return
   can't destroy a take. On confirm: the file is removed (no `.mov`, no `.partial`) and the app
   returns to Ready, **silently** — the alert was the acknowledgement, so no notification fires.
   *Known edge (documented, not fixed for v1): a hardware fail-stop (mic/disk/display) landing in
   the few seconds the alert is open finalizes and saves the take (ADR-007), and a discard confirmed
   after that keeps the resulting playable file — the recording had already completed. See STATUS
   field notes.*
10. Settings/Quit remain.

Paused state: header dot goes amber, timer freezes, `Resume` primary.

### Menu text styling (`.menu` MenuBarExtra bridge)

The `.menu`-style `MenuBarExtra` renders rows through AppKit and keeps only their text: SwiftUI
`.foregroundStyle`/`.foregroundColor` and `Button(role: .destructive)` are **dropped** (measured,
M6-T12 — a destructive role rendered plain gray). To color a row, give the `Button` an
**attributed** label whose color is an `NSColor`, which the bridge *does* honor:

```swift
Button(role: .destructive) { … } label: { Text(discardTitle) }
// discardTitle = AttributedString(NSAttributedString(
//     string: "Discard Recording…", attributes: [.foregroundColor: NSColor.systemRed]))
```

**Quitting with work in flight (M23-T2).** A recording confirms (`Stop recording and quit?`) and is
finalized first. An **export** confirms too — `An export is still running.` / `Quitting now throws it
away. The recording it came from is untouched.` — with **`Wait for Export` as the default button**,
so a reflexive Return can't discard it (the `Discard Recording…` rule). ⚠️ `Quit Anyway` must clear
the in-flight state *synchronously*: every quit route ends in `NSApplication.terminate`, whose
delegate waits for an export, so an abandon the delegate can't observe becomes a wait (docs/07).
Logout and shutdown reach `applicationShouldTerminate` directly, where a modal could stall the
system — that route waits silently, and asks nothing.

The plain string still reaches Accessibility as the row's title, so `menudriver` finds and clicks
it. Same family of limitation as the header's frozen clock (item 1) and the un-two-toned folder
path (item 10): for a `.menu` MenuBarExtra, style through AppKit, not SwiftUI modifiers.

## Notifications (UserNotifications; click always reveals the file in Finder)

Copy pattern — **outcome first, cause second, always a playable file** (ADR-007 in UI
form). Never the word "error" for a fail-stop.

| Event | Title | Body | Click |
|---|---|---|---|
| Manual stop | `Recording saved · 00:12:34` | `Recording 2026-07-14 at 10.12.mov` | reveal |
| Fail-stop (any cause) | `Recording saved · 00:12:34` | `Ended: <cause>. File is playable.` | reveal |
| Microphone lost mid-recording | `Still recording · microphone disconnected` | `The recording has no microphone until it reconnects.` | — |
| Microphone recovered mid-recording — **M8-T2** | `Still recording · microphone reconnected` | `The microphone track resumed.` | — |
| Microphone silent mid-recording — **M16-T4** | `Still recording · microphone is silent` | `No sound has reached it for 10 seconds. Check that it isn't muted.` | — |
| Microphone audible again — **M16-T4** | `Still recording · microphone is picking up sound` | `The microphone is working again.` | — |
| Write failed mid-take — **M23-T1** | `Recording saved · 00:03:07` | `Ended: couldn't keep writing to disk. File is playable.` | reveal |
| Write failed, file gone with the volume — **M23-T1** | `Couldn't save the recording` | `Couldn't keep writing the recording, and the file is no longer where it was being saved. The disk it was saving to may have been disconnected.` | — |
| Never started | `Couldn't start recording` | the engine's own message, e.g. `No displays available — the screen may be asleep or locked.` | — |
| Replay saved — **M5** | `Replay saved` | `Replay … .mov — last 60 s. Click to reveal.` | reveal |
| Replay save failed — **M5** | `Couldn't save replay` | one-line cause + what to do | — |
| Exported to MP4 — **M10-T2** | `Exported to MP4` | `<name>.mp4 — ready to share. Click to reveal.` | reveal |
| Export won't fit — **M23-T2** | `Not enough room to export` | `This needs about 1,8 GB and Macintosh HD has 900 MB free. The recording is untouched.` | — |
| Export failed — **M10-T2** | `Couldn't export to MP4` | `The original recording is untouched. Try again, or check the output folder is writable.` | — |
| Saved as GIF — **M10-T3** | `Saved as GIF` | `<name>.gif — ready to share. Click to reveal.` | reveal |
| GIF failed — **M10-T3** | `Couldn't save GIF` | `The original recording is untouched. Try again, or check the output folder is writable.` | — |
| Recording file moved — **M6-T7** | `Still recording · file moved back` | `The recording file was moved while recording, so it was moved back.` | — |
| Recording file deleted — **M6-T7** | via `failed`: | `The recording file was deleted while recording, so the video couldn't be saved.` | — |
| Recovered interrupted recording — **M6-T7** | `Recovered an interrupted recording` | `Recording … .mov is ready to play.` | reveal |
| Replay mic lost while armed — **M5, amended M8-T2** | `Replay still armed · microphone disconnected` | `Replays saved while it's away have no microphone.` | — |
| Replay mic silent while armed — **M16-T4** | `Replay still armed · microphone is silent` | `Replays saved now have no sound from it. Check that it isn't muted.` | — |
| Replay mic audible again — **M16-T4** | `Replay still armed · microphone is picking up sound` | `Replays saved from now on include it again.` | — |
| Replay mic recovered while armed — **M8-T2** | `Replay still armed · microphone reconnected` | `Replays saved from now on include the microphone again.` | — |

Fail-stop causes, one per reachable `EndReason`:
`display disconnected` · `the recorded app quit` · `the recorded window closed` ·
`disk almost full` · `screen capture stopped unexpectedly` (an unclassified `streamError` — say
what happened, never the raw SCK string, never the word "error")

⚠️ **AMENDED 2026-07-15 (M4-T5): the table didn't cover what the engine emits.** Four fixes:
- **`streamError` had no copy** and is reachable — SCK can die for a reason we don't classify.
- **Microphone lost had no row**, though ADR-012 promises a notification: the recording
  *continues*, so this is the one notification that isn't about an ending. Outcome-first means
  leading with "still recording" — the question it answers is "did my 90-minute capture die?".
- **`failed` had no row.** The rest of the table assumes a playable file; this is the case where
  there isn't one, so it's the one place "Couldn't" is right (as in "Couldn't save replay").
- **`Mac went to sleep` is deleted — it was copy for a state that cannot occur.** M3-T4 measured
  that SCK reports sleep, lock and unplug as the same code (-3815 → `displayDisconnected`), so
  `EndReason.systemSleep` is unreachable. M5/M6 never found a source, so the case was **deleted**
  in M15-T4 along with `microphoneChanged`.

**M6-T7 — the in-progress file defends itself.** The active recording is written as
`Recording ….mov.partial` (renamed to `.mov` at finalize, so the recents rows never list an
unfinished file); a vnode sentinel on the writer's descriptor renames a moved/trashed partial
straight back (same-volume rename — a cross-volume move arrives as delete), and an unlink
fail-stops the session immediately instead of writing an hour into a doomed inode. Launch
scans the output folder for orphaned partials and renames them back to playable `.mov`s.

⚠️ **AMENDED 2026-07-16 (M5-T5 follow-up): banners are suppressed while the screen is captured —
which is whenever replay is armed.** macOS hides ordinary banners when the display is shared or
captured ("Allow notifications when mirroring or sharing the display", off by default), and the
replay-saved notification fires exactly then; it lands in Notification Center's list but never
renders. Measured live (Franco, 2026-07-16). Every earlier banner check passed because those
notifications fire after capture ends. Remedies, in order:
- **Now:** the user enables *System Settings → Notifications → Allow notifications when
  mirroring or sharing the display* — **measured working 2026-07-16 (Franco): with the toggle
  on, the replay-saved banner renders while armed, and so do third-party banners (Slack) —
  the remedy is system-wide.** The suppression side (toggle OFF + armed ⇒ Slack silenced?)
  remains inferred; the A/B needs a toggle-off run. Candidate onboarding copy for the
  Notifications row (deferred by Franco, same day).
- **M6-T4:** `interruptionLevel = .timeSensitive` is already set on every notification, but the
  required entitlement (`Scripts/entitlements.plist`, parked) needs a provisioning profile —
  AMFI refuses to launch a self-signed app carrying it (POSIX 153), and without the entitlement
  the level is silently downgraded (measured, both ways).

⚠️ **The wider consequence (2026-07-16, partly inferred — see the caveat): armed replay likely
suppresses EVERY app's banners, not just ours.** The suppression state is Notification Center's
global "display is being shared" policy — the same one a Zoom screen-share trips — so while
replay is armed, Slack/Messages/calendar banners should all land silently in the list. Users
will blame Slack or macOS, never the dot badge. **Measured:** our own banner is suppressed while
armed. **Inferred, not yet observed:** third-party banners (the toggle's design is global; the
30-second confirmation is "arm, then Slack yourself" — pending, Franco). Remedies are the same
two above, but note the asymmetry: the M6 time-sensitive entitlement fixes only OUR banners;
the user-side toggle un-suppresses everything, including during genuine screen-shares — a
privacy trade to make knowingly. Decision deferred (Franco, 2026-07-16): document now, act
later — candidates are onboarding copy, a product-brief honesty note, or nothing until users
hit it.

✅ **RESOLVED — M12-T5 surfaces it (2026-07-23), three touches:** (1) a **one-time alert on the
first arm ever** ("Notifications may be hidden while replay is armed"; OK + **Open Notification
Settings…** routing to the M9-T2 fix), gated on a persisted `seenReplayBannerWarning` flag so it fires
exactly once; (2) a **standing dimmed menu row** under the Arm toggle while armed — `Notification
banners may be hidden while armed` — cleared on disarm; (3) a **line in onboarding's Notifications
copy** (granted + not-yet-asked states) so the caveat is seen at setup. **All three say "may"
deliberately** (Franco, 2026-07-23): the global "Allow notifications when mirroring or sharing the
display" toggle that actually governs suppression **isn't readable via any public API** (`UNNotification­Settings`
exposes per-app auth/alert/preview, not this global switch), so an unconditional "are hidden" would lie
to anyone who's enabled it — the copy names that exact toggle and stays true either way. The M9-T2
Settings caption + deep-link stay as the durable reference. No change to the OS suppression itself.

## Onboarding window (first launch, or any missing permission)

Single window, checklist of two rows, each with live status (✓ green / ○ pending) and
one button:

1. **Screen & System Audio Recording** — button `Grant…` → `CGRequestScreenCaptureAccess()`
   + explainer: "macOS requires quitting and reopening ScreenRec after granting —
   we'll relaunch automatically." (Relaunch helper: spawn detached
   `/usr/bin/open -n` on self after grant detected.)
2. **Microphone** — button `Grant…` → standard prompt; instant, no relaunch.
3. **Check that recording works (M16-T6)** — below the rows, a `Run a test` button:
   *"Records five seconds and throws it away."* It records into a **scratch directory — never the
   output folder** — reads the finished file's tracks and deletes it, then reports one line per
   source. Four states, because "you turned it off" and "it's broken" must not read alike:
   `✓ screen · 4112 × 2570` / `— system audio · turned off` / `! microphone · silent — check that
   it isn't muted` (**M16-T4's words and its measured floor — one vocabulary per condition**) /
   `✗ screen · nothing was recorded`. Green ticks above only prove TCC said yes; this proves capture.
   It runs its own session, so an armed replay keeps its ring. Re-runnable; the menu header already
   opens this window, so it needs no menu row of its own.
4. **Version footer (M16-T6)** — `ScreenRec <CoreInfo.version>`, here and in the Settings footer.
   ADR-014 hands people a signed `.app` directly, so *"am I on the build with the fix?"* has to be
   answerable from inside the app.

⚠️ **AMENDED 2026-07-15 (M4-T3 spike): a `Grant…` button alone is not enough, and shipping only
one would strand exactly the users who need help.** macOS prompts **once, ever** — after a
decline, the request call is an instant no-op (02 §2), so the button does nothing and says
nothing. Both rows therefore need a second state:

- Row 1 (screen): the app can't distinguish "never asked" from "declined" (preflight is false
  for both — 02 §2), so it must find out **by asking**: press `Grant…`, and if the permission
  still hasn't landed, the row switches — permanently, for that launch — to
  **`Open System Settings…`** with the copy: *"ScreenRec was denied screen recording. Turn it on
  in System Settings, then reopen ScreenRec."* Deep link:
  `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`.
- Row 2 (microphone): `AVCaptureDevice.authorizationStatus` reports a real `.denied`, so the row
  can show `Open System Settings…` immediately, with no guessing.
  Link: `…?Privacy_Microphone`.

Per the copy rules: name the fix, not the API. Never say "denied" as an accusation — the user
often clicked the wrong button once, months ago, and has no idea that's why.
3. **Notifications** (optional, never blocks): `UNUserNotificationCenter` authorization
   request; row shows `✓` / `○ Skipped`; the app is fully functional without it.

Recording controls stay disabled until rows 1–2 green (mic optional if user picks
`None`; notifications never gate anything).
Window never *reappears* on its own once satisfied — but it stays openable from the menu header
(item 1 above). No marketing copy, no multi-step wizard.

⚠️ **AMENDED 2026-07-15 (Franco): a granted row links to its System Settings pane too.** Once the
window became always-openable it stopped being onboarding-only and became the app's permissions
screen — and a granted row with no button left no route *out* of a permission once given, which
is a poor answer from a screen recorder to "how do I turn this off?". Granted rows get a plain
**link** (`System Settings`), not a bordered button: three call-to-action buttons on an all-green
checklist read as unfinished work. **Bordered = something to do; link = something to review.**
The intro line follows the same split: it states what's needed while anything blocks, and reads
"ScreenRec has everything it needs. You can change any of these at any time." once nothing does —
the old line is simply false above three green ticks.

## Settings window (SwiftUI Form, UserDefaults-backed)

**Four tabs since M18-T6** — a segmented control, not `TabView`: at this window's width SwiftUI
collapses toolbar tabs into a `»` overflow menu, hiding three of the four pages behind a chevron.
**General** (output folder, launch at login, the menu-bar toggles, the version footer) ·
**Recording** (quality, frame rate, count-in, the two global shortcuts) · **Instant Replay** ·
**Sharing** (MP4 + GIF). The window sizes to the current tab — tallest measured **437 pt**, against
**1137 pt** as one page (90% of a 1260 pt usable screen).

- Output folder (choose → `opendir` preflight immediately, friendly error per 02 §2)
- Quality preset · Frame-rate cap (30/60)
- **Show recording time in the menu bar** (M9-T3) — top-level toggle, on by default; off ⇒ the
  status item shows the icon only. Backed by `showsMenuBarTimer`.
- **Global start/stop shortcut** (M9-T4) — opt-in toggle (off by default — an always-live combo the
  user didn't choose can clash); enabling seeds ⌥⌘S and shows the recorder pill. Fires
  `AppState.toggleRecording` (active session ⇒ Stop & Save; idle+ready ⇒ Start; blocked ⇒ notify).
  Backed by `recordHotkey`.
  - **When it stops — `Save` · `Save and copy`** (M24-T2), a segmented picker below the pill, visible
    only while the shortcut is on. `Save and copy` ends in `AppState.stopAndShare` instead of `stop`,
    so the take is kept *and* an `.mp4` lands on the clipboard. A picker rather than a second
    shortcut: `Save and copy` keeps the `.mov` too (ADR-004), so there is nothing to trade per-take,
    and the menu keeps both endings as rows. Backed by `stopHotkeyCopies`; absent ⇒ `Save`, so an
    existing install's combo is unchanged. The caption gains a sentence when it copies.
  - **An export already running** ⇒ it still stops and saves, then posts *"Saved — the copy had to
    wait"*: `performExport` takes one job at a time, stopping is the combo's primary contract, and a
    hotkey cannot grey itself out the way the menu row does (M17-T2).
- **Global pause/resume shortcut** (M12-T6) — the start/stop twin: opt-in toggle, seeds ⌥⌘P, recorder
  pill. Fires `AppState.togglePause` (recording ⇒ Pause; paused ⇒ Resume; **idle ⇒ silent no-op** — a
  notification there would be noise, unlike the record hotkey's real "blocked" failure). Lets a demo be
  paused without opening the menu (which is itself captured). Backed by `pauseHotkey`; a third
  `HotkeyCenter` id beside replay=1, record=2.
- **Count in before recording (3-2-1)** (M12-T6) — opt-in toggle, off by default. When on, Start shows a
  3→2→1 count-in overlay (a big translucent number on the main display, **click-through and not a veil**,
  so the target window can be brought forward during the beat), **then** begins capture — the countdown
  itself isn't recorded, and the file starts ~3 s after Start. Backed by `countInEnabled`; the count-in
  runs on both menu-Start and the ⌥⌘S hotkey (it's in `AppState.start`).
- Instant replay: buffer length — **a slider that snaps to 15 s (5 s–15 min), plus a typed `M:SS`
  field for exact values (M9-T8;** slider is continuous/tick-free, applied on release; was a 30 s /
  60 s / 2 min picker) · hotkey recorder (default ⌥⌘R) — **M5**
  - Changing the length while armed resizes the buffer **in place** (M6-T6): grow keeps
    everything and fills to the new length; shrink drops the excess immediately. Quality/
    fps/source changes still restart the armed stream (SCK binds sources per stream, 02 §4).
  - **What it costs, under the slider (M16-T2):** `A 4:30 buffer holds about 800 MB in memory.
    While armed, ScreenRec keeps your Mac awake.` Memory first — it's what the slider changes;
    the second sentence is ADR-018's deliberate wakefulness. The figure tracks the **in-progress**
    drag, not the commit-on-release, and is rounded to two significant figures (`≈`-grade, not a
    measurement). With no screen geometry yet, only the wakefulness sentence shows — **never
    quote a number that can't be computed**. Quality is absent on purpose: replay always encodes
    Balanced (`ReplayEncoder`), so the preset doesn't change the ring.
- Launch at login (`SMAppService`) — **M6 ✅ shipped M6-T5.** A top-level toggle between
  Frame rate and Instant Replay. `SMAppService.mainApp.register()`/`unregister()`; its
  `.status` is the source of truth (self-persisting), seeded into the toggle at launch. The
  `.requiresApproval` status (user disabled it in System Settings) counts as on, with a
  notification pointing them there; a failed register reverts the toggle and notifies.
  **Works for the self-signed dev build — no notarization needed (measured M6-T5).**
- **Stop After** (M18-T4) — a menu submenu beside Quality, not a Settings row: Off (default) / 5 /
  15 / 30 / 60 min, persisted `stopAfterMinutes`. Bounds the *next* take; changing it mid-recording
  would move a deadline the menu has already stated. Wall clock from Start (a long pause eats into
  it), stopping through the shipped `.userStopped` path. While recording, one row states the
  deadline as an absolute, locale-formatted clock time — `Stops at 2:35 PM` — never a countdown
  (M6-T10).
- **Room to record** (M18-T4) — under Start, and only when it is news: below two hours the menu
  reads `Room for about 40 min at High`, or `Not enough room to record at High` when the free space
  is already under the recording path's fail-stop reserve. Above that it says nothing, because
  "about 50 hours" is noise. The figure counts only space *above* the 2 GiB reserve, since capture
  stops itself there (02 §7), and `BitrateModel` errs high on cost so it never over-promises.
- **MP4** (M18-T2) — a section above GIF (the menu orders them that way), one Picker steering
  `Export as MP4`: **Size** — 1920 / 2560 px, plus a ceiling row that names what it would
  really produce for the current source, `Largest (3686 × 2304)`. Default 1920, i.e. every export
  before this was a setting. Sizes stop at H.264 Level 5.2's frame size, because past it the
  encoder moves to Level 6.0 and phones stop decoding (docs/02 §3) — "Original" is deliberately not
  offered. Bitrate is not a picker: it rises with the output's pixel count from 6 Mbps at
  1920×1200 and never falls below it, so a smaller output is never softer than it used to be. The CLI (`export --to-mp4 --width`) has its own flag and does not read these prefs.
  - **Each row states what a minute of it weighs (M19-T4)** — `1920 px · ≈46 MB per minute`,
    `2560 px · ≈81`, `Largest (3686 × 2304) · ≈170`. Since every pick already plays anywhere, weight
    is the thing that decides between them; destination words (`Message / web`) would promise an
    acceptance that clip *length* governs, not the row. `≈`-grade through `ApproximateBytes`, like
    the replay buffer's memory figure, and withheld entirely when no source geometry is known.
  - **1280 px was removed in M19-T4**: the bitrate floor above gave it the same 6 Mbps as 1920, so
    it measured 1% *heavier* for 2.25× fewer pixels — a decoy row. A stored 1280 snaps to 1920 on
    load; `--width 1280` on the CLI still works.
- **GIF** (M10-T3 follow-up) — a section below it, three Pickers steering `Save as GIF`:
  **Frames per second** (12/15/20/24) · **Width** (320/480/640/800 px; caps height too) · **Maximum
  length** (10/15/30/60 s). Defaults 15 / 480 / 30. The CLI (`export --to-gif`) has its own
  `--fps/--width/--seconds` flags and does not read these prefs.

⚠️ **AMENDED 2026-07-15 (Franco): the last two rows do not ship with M4-T4.**
- **Instant replay settings move to M5, with the feature.** M4-T4 was going to store the keys
  for M5-T5 to read later, which sounds harmless — but it means shipping controls for a feature
  that does not exist for a whole milestone. Nothing about replay appears in the UI until the
  ring buffer behind it does. (This toggle had been re-homed three times — T1→T2→T4 — before
  Franco ruled: it belongs to the feature.)
- **Launch at login moved to M6 — shipped M6-T5.** The path-stability worry (a login item aimed
  at `dist/`, which `bundle.sh` deletes) resolved once the app lived at a stable path; the toggle
  registers wherever the app actually runs from. The feared notarization dependency didn't
  materialize either — `SMAppService.register()` works for the self-signed build (measured).

UserDefaults keys (contractual — **do not rename**; the names are fixed even where the writer
moved):
| Key | Type | Written by |
|---|---|---|
| `outputDirectory` | String path | M4-T4 |
| `qualityPreset` | `efficient`\|`balanced`\|`high` | M4-T4 |
| `fpsCap` | Int 30\|60 | M4-T4 |
| `microphoneID` | String uniqueID; absent ⇒ None (or Automatic — see below). **Never cleared by device absence** — the pick survives the AirPods sitting in their case; the menu's checkmark sits on None while the device is away (Franco, 2026-07-16). A specific pick resolves device-or-nothing (no default fallback, or the menu would lie) | M5 follow-up |
| `microphoneAutomatic` | Bool; true ⇒ **Automatic (System Default)**, and it wins over any `microphoneID` in the plist. Resolution follows the system default at capture start (M6-T13) | M6-T13 |
| `captureAppBundleID` | String bundle ID; absent ⇒ entire screen. **Never cleared by the app not running** — the pick survives (mic rule); a start while it's away fails loud, armed replay retries until it returns | M7-T2 |
| `capturesSystemAudio` | Bool; **absent ⇒ on** (M16-T3, ADR-019) — system audio is opt-out, so existing installs keep capturing it. Off ⇒ no system-audio track is written at all (never an empty one) | M16-T3 |
| `replayArmed` | Bool | **M5** |
| `replaySeconds` | Int seconds; **M9-T8 slider range 5–900** (clamped on load — a positive out-of-range value snaps to the nearest bound, absent/≤0 ⇒ 60). Was 30\|60\|120 | **M5** |
| `replayHotkey` | Dict: keyCode Int, modifiers Int | **M5** |
| `recordHotkey` | Dict: keyCode Int, modifiers Int; **absent ⇒ off** (M9-T4, opt-in global start/stop) | M9-T4 |
| `pauseHotkey` | Dict: keyCode Int, modifiers Int; **absent ⇒ off** (M12-T6, opt-in global pause/resume) | M12-T6 |
| `countInEnabled` | Bool; **absent ⇒ off** (M12-T6). Start runs a 3-2-1 count-in before capture | M12-T6 |
| `stopHotkeyCopies` | Bool; **absent ⇒ off** (`Save`). The start/stop shortcut's ending — on ⇒ it also leaves an `.mp4` on the clipboard (M24-T2) | M24-T2 |
| `showsMenuBarTimer` | Bool; **absent ⇒ on** (opt-out). The status-item label's live elapsed clock while recording (M9-T3) | M9-T3 |
| `showsMenuBarLevel` | Bool; **absent ⇒ on** (opt-out). The status-item input meter while recording or armed (M16-T5) | M16-T5 |
| `seenReplayBannerWarning` | Bool; **absent ⇒ false** (not seen). Once true the first-arm banner-suppression alert never fires again (M12-T5) | M12-T5 |
| `gifFPS` · `gifWidth` · `gifMaxSeconds` | Int; each snaps to its nearest picker choice on load, absent ⇒ 15 / 480 / 30. The `Save as GIF` caps (M10-T3 follow-up) | M10-T3 follow-up |
| `stopAfterMinutes` | Int; snaps to its nearest picker choice on load, absent ⇒ 0 (Off). Bounds a take (M18-T4) | M18-T4 |
| `mp4Width` | Int; snaps to its nearest picker choice on load, absent ⇒ 1920. The `Export as MP4` width cap; 4096 means "largest the source allows inside Level 5.2" (M18-T2) | M18-T2 |
| `lastExportPath` · `lastExportDate` | String path + Date (M12-T2/T3); **absent ⇒ no receipt**. The last export, so its menu receipt survives relaunch — dropped on load if the file is gone (moved/trashed) **or has no date** (a pre-T3 entry), and expired at menu open once the date is **older than one hour** (M12-T3). Not part of `Settings` — a transient pointer, not user config; its own load/save | M12-T2/T3 |

⚠️ **`launchAtLogin` is NOT a UserDefaults key (amended M6-T5).** The spec originally listed
one, but `SMAppService` persists the login-item registration itself, so a stored bool would be
a redundant second source of truth that can drift. The toggle reads `SMAppService.mainApp.status`
live and writes through `register()`/`unregister()`. No key.

## Trim window (M10-T4 — the first editing surface, ADR-015)

Opened from a recent recording's `Trim…` submenu row; a plain `Window` (id `trim`) reading
`AppState.trimTarget`, like Settings (an LSUIElement app can't spawn document windows). Spare by
design — one in/out, no timeline scrubbing-to-frame, no multi-clip:
- An **`AVPlayerView`** preview (AppKit via `NSViewRepresentable` — SwiftUI's generic `VideoPlayer`
  fatal-errors in the Command-Line-Tools SPM build; field note).
- A **filmstrip** under the player (M24-T4): **16 thumbnails** across the take, one row, no scrolling,
  filling **progressively** as they decode (first at ~80 ms, all 16 in ~785 ms on a recording —
  docs/07). A click seeks proportionally to where you clicked, not to the thumbnail; a white marker
  tracks the playhead. Caption: *"Click to seek · ←/→ a frame · ⇧←/⇧→ a second"*. Navigation, not
  editing — no zoom, no waveform, no multi-track; the window stays spare.
- **←/→ step one real frame**, ⇧ makes it a second. The frame comes from the sample table
  (`FrameStep`), not `AVPlayerItem.step(byCount:)`, which assumes a cadence frame-on-change capture
  doesn't have. The keys are claimed by a local `NSEvent` monitor scoped to this window, because a
  bare arrow isn't a key equivalent and `AVPlayerView` would otherwise scrub with it (docs/07).
- **Set In** / **Set Out** grab the playhead; `In M:SS` / `Out M:SS` readouts; `Trimmed length ≈`.
  <kbd>I</kbd> and <kbd>O</kbd> are their shortcuts (M18-T1).
- **▶ Play range** plays `[in, out]` and pauses at the out-point (a boundary time observer, removed
  when it fires — the player retains the closure).
- **Trim & Save** runs the trim (`AppState.trim`, off-main via `performExport`, the
  one-at-a-time/receipt/notification path) and dismisses. Disabled for a <0.1 s range or while an
  export runs.
- **Export & Copy** (M21-T1; copies since M24-T1) writes the shareable `.mp4` of that range directly
  — no `.mov` in between — leaves it on the pasteboard, and dismisses; same disabled rule.
  `Trim & Save` keeps the Return key (ADR-015: lossless is the default). The file is the ` trimmed`
  sibling's `.mp4`, so a clip can't be mistaken for an export of the whole take. One notice, the
  `Stop & Copy MP4` one: *"Copied — ⌘V to paste"*. One button, not an `Export` / `Export & Copy`
  pair: the row has 39.5 pt of slack and a fourth button needs ~112 pt. The title names the copy
  because the clipboard is taken either way. A caption states what it will produce:
  *"Export & Copy writes only the range — H.264 1920 × 1200 — and puts it on the clipboard. ⌘V pastes
  it."* The size is this recording's own fitted through the Settings width, and is omitted until the
  source's geometry has loaded (M16-T2). Unlike a lossless trim, this holds only the range: a ranged
  read clips at the in-point (docs/07), so no lead-in caveat applies.
- **Re-encode** (M18-T1, unchecked by default — ADR-015 keeps lossless the default): *"Re-encode —
  the clip will contain only M:SS – M:SS"*. Both modes start exactly at the in-point; lossless also
  keeps the frames back to the previous keyframe inside the file (docs/02 §6a), which the window
  states above the buttons when there are any: *"Starts exactly at 1:01 · keeps 3.4 s before it
  inside the file"*. That line is absent when the in-point already sits on a keyframe — a caveat
  with nothing to warn about is noise.
- Copy states the ruling: *"Both start exactly where you set them. Lossless copies the streams, so
  the clip also keeps the frames back to the previous keyframe inside the file; re-encoding drops
  them, takes longer and can produce a larger file. The original is kept either way; this saves a
  new ' trimmed' file."*

## Naming a take (M21-T3)

Opt-in, off by default: **Settings → Recording → `Ask for a name when a recording stops`**, beside
`Count in before recording` — its sibling, another beat the user chooses to add. When on, a finished
take raises the `Rename…` alert with take-time copy: **`Name this recording`** over
**`0:10 · Esc keeps the date name. The extension stays the same.`**, the field pre-filled with the
date name and selected, buttons **`Name`** / `Cancel`.

- It runs **after the session has torn down** — the stop timer is cancelled and an armed replay has
  re-armed — so an alert left on screen can't hold the app's next state. The file is already safe
  on disk before anything is asked; naming is decoration on top of that.
- It runs **before the share export**, so `Stop & Copy MP4` puts the *named* `.mp4` on the clipboard
  rather than a date-named sibling.
- Esc, Cancel, a blank field and an unchanged name all keep the date name (`RenameTarget`'s existing
  rules); a collision steps to ` 2` exactly as `Rename…` does.
- Nothing is asked when there's nothing to name: a discarded take, a start that failed, a fail-stop
  that left no file, and — **M23-T1** — a take whose writer failed. That one *does* leave a file, but
  renaming or exporting it means writing to the volume that just refused a write; the same rule
  keeps `Stop & Copy MP4` from trying. `SessionModel.leavesAnActionableFile` is exhaustive over
  `EndReason`, so a new reason has to state its answer rather than defaulting to "ask".
- Replay clips are never named this way — the save happens mid-take, and a modal there would
  interrupt what is being recorded.

## Copy rules

- Verbs on buttons: `Start Recording`, `Stop & Save`, `Pause`, `Grant…`. No "OK".
- File names shown exactly as on disk; durations `HH:MM:SS`; sizes via
  `ByteCountFormatter`.
- Blocking problems name the fix, not the API: "Your terminal has the permission but
  ScreenRec doesn't" — never "TCC error -60005".

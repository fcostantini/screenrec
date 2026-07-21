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
| replay armed (idle) | outline circle + small dot badge | armed is orthogonal to recording. **M5** — see the Settings amendment: the badge ships with the feature that can be armed, not before (it had been re-homed T1→T2→T4 before Franco ruled) |

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
2. **Start Recording** — primary action, bold.
3. **Instant Replay armed** — checkmark toggle; right hint `⌥⌘R saves`. Persisted.
   **M5** (Franco, 2026-07-15): a toggle that arms nothing is a lie for a whole milestone.
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
8. — separator —
9. `Open Recordings Folder — <~/path>` — reveals the output dir in Finder, and **shows the current
   destination** as a home-relative path (e.g. `~/Movies`) so it's visible without opening (Franco,
   2026-07-16). One title string — a SwiftUI `.menu` can't two-tone the path (same limitation as
   item 10).
10. Recent recordings: up to 5 most-recent files from the output dir, **indented one level**
    under `Open Recordings Folder` so they read as its contents rather than as more commands
    (Franco, 2026-07-15 — inline rows, not a submenu, settling this against 03's wording);
    click reveals in Finder. ⚠️ Implementation notes from M4-T2: a SwiftUI `.menu`
    `MenuBarExtra` exposes neither `NSMenuItem.indentationLevel` (the indent is leading
    whitespace in the title, with an explicit accessibility label so VoiceOver reads the
    filename) nor a dimmed-but-clickable style — "dimmed style" is **not** currently met and
    can't be without dropping to a hand-built NSMenu. Revisit in M6 polish if it matters.
11. — separator —
12. `Settings…` (⌘,) · `Quit` (⌘Q). Quit while recording → confirm, then clean
    finalize before exit (never abandon a writer).

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
4. — separator —
5. Dimmed info rows: when app-scoped, `Recording <app> only` (M7-T2 — the recording menu names
   its subject); active mic + `separate track`. Then the **Arm Instant Replay toggle
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
| Never started | `Couldn't start recording` | the engine's own message, e.g. `No displays available — the screen may be asleep or locked.` | — |
| Replay saved — **M5** | `Replay saved` | `Replay … .mov — last 60 s. Click to reveal.` | reveal |
| Replay save failed — **M5** | `Couldn't save replay` | one-line cause + what to do | — |
| Recording file moved — **M6-T7** | `Still recording · file moved back` | `The recording file was moved while recording, so it was moved back.` | — |
| Recording file deleted — **M6-T7** | via `failed`: | `The recording file was deleted while recording, so the video couldn't be saved.` | — |
| Recovered interrupted recording — **M6-T7** | `Recovered an interrupted recording` | `Recording … .mov is ready to play.` | reveal |
| Replay mic lost while armed — **M5, amended M8-T2** | `Replay still armed · microphone disconnected` | `Replays saved while it's away have no microphone.` | — |
| Replay mic recovered while armed — **M8-T2** | `Replay still armed · microphone reconnected` | `Replays saved from now on include the microphone again.` | — |

Fail-stop causes, one per reachable `EndReason`:
`display disconnected` · `microphone changed` · `disk almost full` ·
`screen capture stopped unexpectedly` (an unclassified `streamError` — say what happened, never
the raw SCK string, never the word "error")

⚠️ **AMENDED 2026-07-15 (M4-T5): the table didn't cover what the engine emits.** Four fixes:
- **`streamError` had no copy** and is reachable — SCK can die for a reason we don't classify.
- **Microphone lost had no row**, though ADR-012 promises a notification: the recording
  *continues*, so this is the one notification that isn't about an ending. Outcome-first means
  leading with "still recording" — the question it answers is "did my 90-minute capture die?".
- **`failed` had no row.** The rest of the table assumes a playable file; this is the case where
  there isn't one, so it's the one place "Couldn't" is right (as in "Couldn't save replay").
- **`Mac went to sleep` is deleted — it was copy for a state that cannot occur.** M3-T4 measured
  that SCK reports sleep, lock and unplug as the same code (-3815 → `displayDisconnected`), so
  `EndReason.systemSleep` is unreachable. The enum case stays (docs/01 defines it; M5/M6 may find
  a source) but nothing renders it.

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

## Onboarding window (first launch, or any missing permission)

Single window, checklist of two rows, each with live status (✓ green / ○ pending) and
one button:

1. **Screen & System Audio Recording** — button `Grant…` → `CGRequestScreenCaptureAccess()`
   + explainer: "macOS requires quitting and reopening ScreenRec after granting —
   we'll relaunch automatically." (Relaunch helper: spawn detached
   `/usr/bin/open -n` on self after grant detected.)
2. **Microphone** — button `Grant…` → standard prompt; instant, no relaunch.

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

- Output folder (choose → `opendir` preflight immediately, friendly error per 02 §2)
- Quality preset · Frame-rate cap (30/60)
- **Show recording time in the menu bar** (M9-T3) — top-level toggle, on by default; off ⇒ the
  status item shows the icon only. Backed by `showsMenuBarTimer`.
- **Global start/stop shortcut** (M9-T4) — opt-in toggle (off by default — an always-live combo the
  user didn't choose can clash); enabling seeds ⌥⌘S and shows the recorder pill. Fires
  `AppState.toggleRecording` (active session ⇒ Stop & Save; idle+ready ⇒ Start; blocked ⇒ notify).
  Backed by `recordHotkey`.
- Instant replay: buffer length — **a slider that snaps to 15 s (5 s–15 min), plus a typed `M:SS`
  field for exact values (M9-T8;** slider is continuous/tick-free, applied on release; was a 30 s /
  60 s / 2 min picker) · hotkey recorder (default ⌥⌘R) — **M5**
  - Changing the length while armed resizes the buffer **in place** (M6-T6): grow keeps
    everything and fills to the new length; shrink drops the excess immediately. Quality/
    fps/source changes still restart the armed stream (SCK binds sources per stream, 02 §4).
- Launch at login (`SMAppService`) — **M6 ✅ shipped M6-T5.** A top-level toggle between
  Frame rate and Instant Replay. `SMAppService.mainApp.register()`/`unregister()`; its
  `.status` is the source of truth (self-persisting), seeded into the toggle at launch. The
  `.requiresApproval` status (user disabled it in System Settings) counts as on, with a
  notification pointing them there; a failed register reverts the toggle and notifies.
  **Works for the self-signed dev build — no notarization needed (measured M6-T5).**

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
| `replayArmed` | Bool | **M5** |
| `replaySeconds` | Int seconds; **M9-T8 slider range 5–900** (clamped on load — a positive out-of-range value snaps to the nearest bound, absent/≤0 ⇒ 60). Was 30\|60\|120 | **M5** |
| `replayHotkey` | Dict: keyCode Int, modifiers Int | **M5** |
| `recordHotkey` | Dict: keyCode Int, modifiers Int; **absent ⇒ off** (M9-T4, opt-in global start/stop) | M9-T4 |
| `showsMenuBarTimer` | Bool; **absent ⇒ on** (opt-out). The status-item label's live elapsed clock while recording (M9-T3) | M9-T3 |

⚠️ **`launchAtLogin` is NOT a UserDefaults key (amended M6-T5).** The spec originally listed
one, but `SMAppService` persists the login-item registration itself, so a stored bool would be
a redundant second source of truth that can drift. The toggle reads `SMAppService.mainApp.status`
live and writes through `register()`/`unregister()`. No key.

## Copy rules

- Verbs on buttons: `Start Recording`, `Stop & Save`, `Pause`, `Grant…`. No "OK".
- File names shown exactly as on disk; durations `HH:MM:SS`; sizes via
  `ByteCountFormatter`.
- Blocking problems name the fix, not the API: "Your terminal has the permission but
  ScreenRec doesn't" — never "TCC error -60005".

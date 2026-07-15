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
| replay armed (idle) | outline circle + small dot badge | armed is orthogonal to recording |

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
4. — separator —
5. `Display ▸` submenu: one entry per `NSScreen`, checkmark on current. Disabled while
   recording.
6. `Microphone ▸` submenu: AVCaptureDevice list + `None`. Checkmark on current.
   Disabled while recording.
7. `Quality ▸` submenu: Efficient / Balanced / High (docs/02 §3 presets).
8. — separator —
9. `Open Recordings Folder` — reveals output dir in Finder.
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
   `<size> · HEVC`. Updates ≤ 1 Hz (menu open only; no timers while closed).
2. **Pause** / **Resume** (swaps by state).
3. **Stop & Save** — primary.
4. — separator —
5. Dimmed info rows: active mic + `separate track`; `Replay still armed · ⌥⌘R` when
   armed.
6. — separator —
7. Dimmed: `Sources locked while recording` (pickers hidden, not disabled-but-present).
8. Settings/Quit remain.

Paused state: header dot goes amber, timer freezes, `Resume` primary.

## Notifications (UserNotifications; click always reveals the file in Finder)

Copy pattern — **outcome first, cause second, always a playable file** (ADR-007 in UI
form). Never the word "error" for a fail-stop.

| Event | Title | Body |
|---|---|---|
| Manual stop | `Recording saved · 00:12:34` | `Recording 2026-07-14 at 10.12.mov` |
| Fail-stop (any cause) | `Recording saved · 00:12:34` | `Ended: <cause>. File is playable.` — causes: `display disconnected`, `microphone changed`, `disk almost full`, `Mac went to sleep` |
| Replay saved | `Replay saved` | `Replay … .mov — last 60 s. Click to reveal.` |
| Replay save failed | `Couldn't save replay` | one-line cause + what to do |

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
Window never reappears once satisfied. No marketing copy, no multi-step wizard.

## Settings window (SwiftUI Form, UserDefaults-backed)

- Output folder (choose → `opendir` preflight immediately, friendly error per 02 §2)
- Quality preset · Frame-rate cap (30/60)
- Instant replay: buffer length 30 s / 60 s / 2 min · hotkey recorder (default ⌥⌘R)
- Launch at login (`SMAppService`)

UserDefaults keys (contractual — M4-T4 writes them, M5-T5 reads them; do not rename):
`outputDirectory` (String path), `qualityPreset` (`efficient`|`balanced`|`high`),
`fpsCap` (Int 30|60), `replayArmed` (Bool), `replaySeconds` (Int 30|60|120),
`replayHotkey` (Dict: keyCode Int, modifiers Int), `launchAtLogin` (Bool).

## Copy rules

- Verbs on buttons: `Start Recording`, `Stop & Save`, `Pause`, `Grant…`. No "OK".
- File names shown exactly as on disk; durations `HH:MM:SS`; sizes via
  `ByteCountFormatter`.
- Blocking problems name the fix, not the API: "Your terminal has the permission but
  ScreenRec doesn't" — never "TCC error -60005".

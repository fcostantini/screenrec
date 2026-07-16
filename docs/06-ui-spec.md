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
5. `Display ▸` submenu: one entry per `NSScreen`, checkmark on current. Disabled while
   recording.
6. `Microphone ▸` submenu: AVCaptureDevice list + `None`. Checkmark on current.
   Disabled while recording.
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

| Event | Title | Body | Click |
|---|---|---|---|
| Manual stop | `Recording saved · 00:12:34` | `Recording 2026-07-14 at 10.12.mov` | reveal |
| Fail-stop (any cause) | `Recording saved · 00:12:34` | `Ended: <cause>. File is playable.` | reveal |
| Microphone lost mid-recording | `Still recording · microphone disconnected` | `The rest of the recording has no microphone track.` | — |
| Never started | `Couldn't start recording` | the engine's own message, e.g. `No displays available — the screen may be asleep or locked.` | — |
| Replay saved — **M5** | `Replay saved` | `Replay … .mov — last 60 s. Click to reveal.` | reveal |
| Replay save failed — **M5** | `Couldn't save replay` | one-line cause + what to do | — |

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
- Instant replay: buffer length 30 s / 60 s / 2 min · hotkey recorder (default ⌥⌘R) — **M5**
- Launch at login (`SMAppService`) — **M6**

⚠️ **AMENDED 2026-07-15 (Franco): the last two rows do not ship with M4-T4.**
- **Instant replay settings move to M5, with the feature.** M4-T4 was going to store the keys
  for M5-T5 to read later, which sounds harmless — but it means shipping controls for a feature
  that does not exist for a whole milestone. Nothing about replay appears in the UI until the
  ring buffer behind it does. (This toggle had been re-homed three times — T1→T2→T4 — before
  Franco ruled: it belongs to the feature.)
- **Launch at login moves to M6.** `SMAppService` registers a login item pointing at the
  bundle's *current path*, and until M6 the app has no permanent address — `dist/ScreenRec.app`
  is a build directory `bundle.sh` deletes on every run. Registering it now aims a login item at
  a folder that will not exist. It belongs with notarization and installability, which are the
  same problem: the app needs somewhere to live.

UserDefaults keys (contractual — **do not rename**; the names are fixed even where the writer
moved):
| Key | Type | Written by |
|---|---|---|
| `outputDirectory` | String path | M4-T4 |
| `qualityPreset` | `efficient`\|`balanced`\|`high` | M4-T4 |
| `fpsCap` | Int 30\|60 | M4-T4 |
| `microphoneID` | String uniqueID; absent ⇒ None. **Never cleared by device absence** — the pick survives the AirPods sitting in their case; every stream start resolves picked-device-or-nothing (no default-mic fallback, or the menu would lie), and the menu's checkmark sits on None while the device is away (Franco, 2026-07-16) | M5 follow-up |
| `replayArmed` | Bool | **M5** |
| `replaySeconds` | Int 30\|60\|120 | **M5** |
| `replayHotkey` | Dict: keyCode Int, modifiers Int | **M5** |
| `launchAtLogin` | Bool | **M6** |

## Copy rules

- Verbs on buttons: `Start Recording`, `Stop & Save`, `Pause`, `Grant…`. No "OK".
- File names shown exactly as on disk; durations `HH:MM:SS`; sizes via
  `ByteCountFormatter`.
- Blocking problems name the fix, not the API: "Your terminal has the permission but
  ScreenRec doesn't" — never "TCC error -60005".

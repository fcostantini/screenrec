# 02 — Technical Reference (hard-won knowledge — READ BEFORE CODING)

Everything below was verified either empirically on this machine (macOS 15.6.1, Apple
Silicon, terminal already granted Screen Recording + Microphone TCC) or via primary
sources during the 2026-07 research pass. Items marked ⚠️ were live bugs we actually hit.

## 1. ScreenCaptureKit stream setup

- One `SCStream` delivers all three sources. Register three outputs via
  `addStreamOutput(_:type:sampleHandlerQueue:)`: `.screen`, `.audio`, `.microphone`
  (mic type is macOS 15+).
- Pixel-true dimensions: `SCContentFilter.contentRect` is in **points**; multiply by
  `filter.pointPixelScale`. On the dev machine that yields 4112×2570. Never hardcode.
- `capturesAudio` (**the user's choice since M16-T3/ADR-019, default on**), `sampleRate = 48_000`,
  `channelCount = 2`, `excludesCurrentProcessAudio = true`. `capturesAudio` and the mic are
  independent switches: either, both, or neither. **With both off, SCK opens no audio tap at all** —
  measured 2026-07-27 by assertion count (see docs/07), which matters because that tap is what keeps
  the Mac awake regardless of our own `SleepGuard` (§7).
- **`microphoneCaptureDeviceID`: pass an explicit id.** Resolve
  `AVCaptureDevice.default(for: .audio)?.uniqueID` and pass it.
  ⚠️ **Correction (2026-07-15, M3-T7):** the old claim here — "on 15.6 nil makes `startCapture`
  throw invalid parameter" — is **stale on 15.6.1**: nil is accepted and delivers the default
  mic fine. It buys nothing, though: nil **resolves the default once at `startCapture` and then
  pins it** — measured, AirPods → built-in default switch mid-stream is NOT followed (the mic
  just dies). So nil is equivalent to naming the device, minus knowing which device you got.
  Keep passing the explicit id. Do not "fix" this by dropping to nil hoping for auto-fallback.
- `minimumFrameInterval = CMTime(value: 1, timescale: fps)` is a **cap** — SCK is
  frame-on-change. A static screen delivers no frames (see §5 tail-frame patch).
- `queueDepth = 5`. Do not retain sample buffers beyond the callback except by design
  (ring buffer holds *compressed* video, not SCK surfaces; PCM copies for audio).
- `showsCursor = true` for v1 (cursor-as-data is ADR-008, deferred).
- Content enumeration: `SCShareableContent.excludingDesktopWindows(false,
  onScreenWindowsOnly: true)`.
  ✅ **SETTLED (2026-07-15, M4-T3 spike) — an ungranted process THROWS. It never enumerates
  zero.** Measured directly, both TCC states, on this machine:

  | TCC state of the calling app | `SCShareableContent` |
  |---|---|
  | not determined | macOS **prompts**; on decline → throws **-3801** `SCStreamError.userDeclined` |
  | denied | throws **-3801** immediately, no prompt |

  §10 was right and this section's old "returns empty results" claim was research, never
  observation. It is now deleted rather than merely doubted.
  **Consequence: zero displays NEVER means "ungranted".** If enumeration returned at all you are
  authorized; zero displays means the screen is locked **and** slept (§7's table).
  `startDecision` therefore reports "no displays available" for zero and never blames
  permission — **confirmed correct**, no change needed. The ungranted path is the thrown -3801,
  which `startErrorMessage` already maps (it matches `SCStreamError.Code.userDeclined`, and
  -3801 is exactly that constant; -3815 `noCaptureSource` is the display-gone code from §7 —
  the two are cleanly distinct).
  ⚠️ Do **not** "fix" this by consulting `CGPreflightScreenCaptureAccess()` — it false-negatives
  for freshly-built CLI binaries that capture fine (§10), so trusting it re-creates the very
  misdiagnosis (users sent to grant a permission they already hold).

  **How it was measured, since the old note said it was impossible here** (it claimed only a
  fresh account could do it, because revoking TCC would destroy our own grant): **TCC keys on
  code identity, not on the user.** A throwaway bundle signed with the *same* identity but a
  different bundle ID (`dev.fcostantini.screenrec.tccprobe`) is a subject macOS has never
  granted anything — its designated requirement differs only in the identifier. It measures the
  ungranted path on this account, changing nothing about ours. Cleanup afterwards is
  `tccutil reset ScreenCapture dev.fcostantini.screenrec.tccprobe` — **note the bundle ID
  argument; a bare `tccutil reset ScreenCapture` would destroy this machine's grant (§2).**
  Reusable for any future "what does an unprivileged copy of us see?" question.
  ⚠️ The bundle must be launched via `open` to get its own identity — a bare binary run from the
  shell is attributed to the *responsible process* (Terminal), which holds the grant, so it
  would have measured the opposite of what was intended.
- Sample handler queues must do minimal work. Video buffers: check
  `SCStreamFrameInfo.status == .complete` via attachments; `.idle`/incomplete frames are
  skipped (but see tail-frame patch).

## 1a-ii. Per-app *exclusion* (`SCContentFilter(display:excludingApplications:)`) — measured 2026-07-29, M21-T4

- **The excluded app's audio is digital silence**, through the identical path: a 440 Hz tone at
  −9 dBFS playing in QuickTime read **peak 0.3500 / −9.1 dBFS** on a plain display filter and
  **peak 0.0000 / −∞ dBFS** when that app was excluded. Audio buffers keep arriving (426 in 8 s), so
  the stream is healthy — it is silent, not stalled.
- 🔴 **Exclusion is not audio-only: the app's windows leave the frame too.** The filter defines
  *content*; SCK has no audio-scoped exclusion. Measured by comparing the same screen region across
  both runs — QuickTime's window is present in one, absent in the other, with what's behind it
  showing through.
- 🔴 **An app with nothing on screen cannot be excluded at all.** Minimise it and it disappears from
  `SCShareableContent.applications` (the §1a listing rule, from the other direction) — while its
  audio still lands in a normal capture at full level (measured: −9.1 dBFS, minimised). So the
  "background music" case, which is the one worth excluding, is the one the API can't reach. The app
  records without the exclusion and reports `excludedAppUnavailable` rather than implying otherwise.
- **Frame delivery is the display path's** (frame-on-change), not `.app`'s continuous rate — an
  excluding filter is a display capture with a hole in it, so it keeps the StallWatchdog.
- ⚠️ **"System audio" is not literally every process — and the rule isn't established.** A tone played
  by `afplay` (a bare CLI binary, no bundle, no window) **never appeared** in the captured track:
  −∞ dBFS with no exclusion at all, and again with an unrelated app excluded. Yet a **minimised**
  QuickTime — also windowless on screen — *was* captured at −9.0 dBFS. So it is not "windows on
  screen" that decides it; the distinguishing factor (bundled app vs bare process, audio API used,
  something else) is **unmeasured**. Consequence for tests: verify system audio with a real windowed
  app, never with `afplay`, or a passing measurement can mean nothing was playing (G21 nearly
  recorded a false negative this way).
- For true audio-only exclusion the route is Core Audio process taps
  (`AudioHardwareCreateProcessTap` + `CATapDescription(excludeProcesses:)`, macOS 14.2+), which is a
  separate system-audio source, not a filter change. Parked, not attempted.

## 1a. Per-app capture (`SCContentFilter(display:including:)`) — measured 2026-07-20, M7-T1

- **Geometry:** an `including:` filter's `contentRect`/`pointPixelScale` are the *display's*
  (2056×1285 pts @2× → 4112×2570 here), not the app's windows. Frames arrive display-sized
  with the app's windows composited on black, so bitrate/timing math is content-independent.
- **System audio IS scoped to the included app.** Measured with the same afplay stimulus:
  whole-screen control peaked 0.29 (float sample) / −10.6 dB in the recorded track;
  app-scoped peaked 0.0000 / −91 dB (digital silence).
- **The included app quitting fires NO stream error** — the stream keeps running and
  delivering frames of the now-empty filter, indefinitely. Ending the session takes process
  watching: `AppTerminationWatch` (`DispatchSourceProcess`/`NOTE_EXIT`, no polling) →
  `stop(reason: .appQuit)`. A source armed against an already-dead pid never signals, hence
  the watch's before-and-after liveness probes.
- **Zero windows (app alive) is likewise silent-healthy:** no error, stream keeps delivering.
- **An app filter delivers frames continuously at ~the fps cap even when the content is
  static** (measured 35 fps avg over a static TextEdit window) — unlike whole-display
  capture's frame-on-change. Expect no VFR size savings for static app content.
- `SCShareableContent.applications` lists only apps with on-screen windows, and a freshly
  launched app can take a few seconds to appear — "running" (pgrep-alive) does not imply
  resolvable yet. `CapturableApps`/`list-apps` read the same enumeration the engine resolves
  against, so a listed app is always bindable.

## 1b. Region capture (`SCStreamConfiguration.sourceRect`) — measured 2026-07-22, M11-T1

Record an arbitrary rectangle of one display. Mechanism: a plain **whole-display** filter
(`SCContentFilter(display:excludingWindows:[])`) plus `sourceRect` to crop it, and `width`/`height`
sized to the region (not the display). `resolveRegion` (CaptureEngine) is the pure seam.

- **Coordinate space & origin — MEASURED top-left, in display points.** `sourceRect` is in the
  same space as `filter.contentRect`: **points, origin top-left** — NOT AppKit's bottom-left screen
  points. Verified conclusively: a `record --region 0,0,1200,120` frame matched `screencapture -R
  0,0,1200,120` (the menu bar — a known top-left-points shot) at a normalized image diff of 0.019,
  and did NOT match the same-size bottom strip (diff 0.170, ≈ the top-vs-bottom difference itself).
  A bottom-left origin would have captured the bottom strip at `y=0`; it captured the menu bar.
- **Retina → pixels:** output `width`/`height` = region points × `filter.pointPixelScale`, same as
  the whole-display path (§1). On this display that's ×2 (800×500 pt → 1600×1000 px, live-probed).
- **Even-dimension snap:** encoders want even chroma dims, so pixels are **floored to even**, and
  `sourceRect` is trimmed to `evenPx / scale`. The floor (not round) matters: rounding up could push
  `sourceRect.maxX` a sub-pixel past the display edge on a fractional straddle — floor keeps
  `sourceRect ⊆ clamped ⊆ display`. The point→pixel map then stays exact 1:1.
- **Edge-straddle → clamp; off-screen → fail loud.** A rect that overruns an edge is clamped to the
  display (`rect.intersection`); one that doesn't overlap at all (or is zero-area / non-finite /
  rounds under 2 px) **fails to start** with actionable copy — never a silent whole-screen fallback
  (the M7 `.app`-gone precedent).
- **`destinationRect` is left default (omitted).** docs/03 M11 floated setting it; in practice the
  default (fill the full region-sized output) places the cropped source 1:1 with no letterbox —
  live-verified exact. Setting it is unnecessary.
- **Audio has NO region.** Region uses the plain display filter, so system audio is whole-machine —
  unlike an `.app` filter, which scopes system audio to the app (§1a). The mic path is unaffected.
- **Frame delivery is the display path's** (frame-on-change from the whole display), not `.app`'s
  continuous ~fps (§1a). So `.region` attaches the StallWatchdog exactly as whole-display does.
- **One display only.** `sourceRect` is per-display; a region spanning two monitors is out of scope
  (M11 non-goal). The CLI region targets `.main`; the enum carries a `DisplaySelection` for M11-T2.
- **The drag overlay (M11-T2) flips coordinate spaces.** Its `NSView` is AppKit points, **bottom-left**
  origin; SCK's `sourceRect` is **top-left**. `RegionSelection.sckRect` does the one flip:
  `sck.y = displayHeightPoints − (viewRect.y + viewRect.height)`, `x`/`w`/`h` unchanged. On the main
  display the overlay window sits at frame origin `(0,0)`, so view-local points are display-local —
  the flip's assumption. Live-verified end-to-end (a centered drag → a centered SCK rect that records
  exactly that screen region); the direction is unit-tested against the menu-bar-at-top case.

## 1c. Window capture (`SCContentFilter(desktopIndependentWindow:)`) — measured 2026-07-27, M17-T1

Record one window, and follow it as it moves. Mechanism: a **desktop-independent** filter built from
an `SCWindow` — unlike `.app` (which composites an app's windows onto a *display* filter, §1a) this
one has no display at all, so `CaptureEngine.resolveScope` resolves no `SCDisplay` for it and
`filter.contentRect` is the **window's** rect rather than a display's.

- **Listing must use the on-screen enumeration.** `SCShareableContent.forCapture()`
  (`onScreenWindowsOnly: true`) returned **32 windows, 9 of them at `windowLayer == 0`**; the full
  enumeration (`onScreenWindowsOnly: false`) returned **97 windows, 52 at layer 0**. The extra 43
  layer-0 entries are invisible untitled helper windows — Discord, Slack, Firefox and Spotify each
  carry several, plus service processes (`CursorUIViewService`, `ThemeWidgetControlViewService`).
  So `CapturableWindows.available()` reads the on-screen list, keeping *listed ⇒ bindable*
  structural exactly as `CapturableApps` does (§1a).
- **`windowLayer == 0` is the "real user window" filter**, and it is load-bearing: of the 32
  on-screen windows, **23 are chrome** — menu-bar extras (layer 25), the Desktop and the Dock's
  wallpaper (large negatives), the screen-recording status indicator (large positive) — and one of
  them is ScreenRec's own status item. This is the analogue of M7-T2's `activationPolicy == .regular`
  app filter, except `windowLayer` is on `SCWindow`, so it stays a pure function in RecorderCore
  instead of needing the view layer.
- ✅ **A window going away ENDS THE STREAM — no watch needed.** This is the opposite of `.app`,
  where the included app quitting fires no error at all and needs `AppTerminationWatch` (§1a).
  Measured both routes, each ending a live recording at the second it happened:

  | What happened | SCK stream | Reported |
  |---|---|---|
  | TextEdit closed its document window, app still running | **errors** | `.windowClosed` |
  | The owning app was killed outright | **errors** | `.windowClosed` |
  | Window minimised, then restored | keeps running | — (frames stop and resume) |

  So window scope arms **no** `AppTerminationWatch` and **no** presence poll: SCK is immediate,
  free, and beats any watch. Both routes report `.windowClosed`, deterministically — racing a
  process watch against the stream error would make the reported reason a coin toss, and "the
  recorded window closed" is true either way.
- 🔴 **The error code is the SAME one a disconnected display uses**, so `endReason` must be told
  what was being captured: `noCaptureSource` means *the display* went away under a display filter
  and *the window* went away under a window filter. Mapping it blind reports a closed window as a
  disconnected display — which sends the user to check their monitor cable. Measured: before the
  fix, killing the recorded app produced `finished (displayDisconnected)`.
- ⚠️ **Do not try to detect "window gone" by polling — it cannot work.** Measured, against a
  minimised window and a closed-but-retained one:

  | Probe | Live | Minimised | Closed, app retains it | App killed | Cost (median) |
  |---|---|---|---|---|---|
  | `CGWindowListCopyWindowInfo([.optionIncludingWindow], id)` | found | **gone** | **gone** | gone | 0.077 ms |
  | `CGWindowListCreateDescriptionFromArray([id])` | **not found** | — | — | — | 0.061 ms |
  | `SCShareableContent` full enumeration | found | **found** | **found** | gone | **46.3 ms** |

  `CGWindowListCreateDescriptionFromArray` can't even find a live window. The cheap
  `CGWindowListCopyWindowInfo` reports minimised as gone — a poll on it would end a recording every
  time the user minimised. And the full enumeration keeps listing a window the app has closed but
  not deallocated, so it cannot see a close either — besides costing 46 ms a poll (a 1 s poll is
  ~4.6% of a core for the whole recording, more than the entire app at rest in the G6 soak, §7).
- **Window output is snapped down to even pixels.** A window can be an odd number of points wide,
  and at scale 1 that yields an odd pixel width an encoder's 4:2:0 chroma can't take. Displays are
  even already and regions floor in `resolveRegion` (§1b), so the snap is window-only.
- **A window id is not a durable handle** — it does not survive a relaunch of the owning app (stated
  in docs/03 M17; whether a pick persists at all is **M17-T2's ruling (a)**, not settled here).

### The four rulings docs/03 M17-T1 asked for

- **(a) A mid-recording resize does NOT change the output size.** The window grew 900×528 → 1200×728
  pt at t+4.5 of a live capture; frames kept arriving at 20/s and the output stayed **pinned at
  1800×1056 px for the whole run** — one dimension line, never a second. SCK scales the window into
  the size `SCStreamConfiguration` was given. So pinning `width`/`height` from `filter.contentRect`
  at start is correct and sufficient, and the writer's welded video input never sees a change
  (§3). ⚠️ The consequence for the user is that a window resized mid-take is **scaled**, not
  re-framed — the recording keeps the aspect and pixel size it started with.
- **(b) A minimised window delivers nothing, and recovers by itself.** Frames stopped within the
  same second as `miniaturize` and resumed within the same second as `deminiaturize` — exactly 8
  seconds of zero frames against an 8.4 s minimise, with no stream error. So `.window` attaches
  **no StallWatchdog**: "user active ⇒ frames expected" is false for a window the user has put
  away, exactly as it is under an app filter (§7).
- **(c) System audio IS scoped to the window's owning application** — the `.app` behaviour (§1a),
  not the `.region` behaviour (§1b). Measured three ways through one code path: a tone from
  *another* app read **0.0000 (−inf dBFS)** — exact digital silence; the same tone played *by the
  window's own app* read **0.3589 (−8.9 dBFS)**; the whole-screen control read the same **0.3589
  (−8.9 dBFS)**. ⚠️ Note it is scoped to the **app, not the window**: a second window of the same
  app making noise is still recorded, because SCK has no per-window audio.
- **(d) The frame is the window's `frame`, titlebar included, with no shadow gutter.** A window
  asked for a 900×**500** content size reports `SCWindow.frame` 900×**528** pt — the 28 pt titlebar
  — and `filter.contentRect` equals `frame` exactly. Output was 1800×1056 px = frame × 2. In the
  captured frame the titlebar renders as a grey strip above the content, and the **corners are
  opaque black** (the rounded-corner fill), not transparent — there is no alpha to preserve and no
  margin to subtract.

### Rig traps that cost real time (2026-07-27)

- ⚠️ **`SCContentFilter(desktopIndependentWindow:)` traps with `CGS_REQUIRE_INIT`** in a process
  that has never talked to the window server — i.e. a plain CLI binary, which is exactly the
  headless verify surface (ADR-011). `screenrec-cli record --window` died on it. Enumeration and
  `SCWindow.frame` are fine; only filter construction trips it. Any CoreGraphics display call fixes
  it (`CaptureEngine.connectToWindowServer`); AppKit is not needed, which matters because
  RecorderCore may never import it. A GUI host already has the connection.
- ⚠️ **Captured colours are NOT the colours you asked `NSColor` for.** The display profile transform
  shifted a pure magenta fill to rgb(232,51,244) and an `NSColor(red:0, green:0.85, blue:0.2)` green
  to **rgb(93,213,76)** — 93 counts off in the red channel alone. A content assertion written
  against the nominal colour finds **0 matching pixels and looks like a pass**. Always sample the
  recorded colour first, and always run the positive control (the same check against a capture that
  *should* contain it) — here that control was what caught the error.
- ⚠️ **A stimulus window must be animating.** Window capture is frame-on-change, so a static window
  delivers ~nothing: a first pass at ruling (b) measured 16 s of zero frames across both a resize
  and a minimise and could not tell which caused it, because the window was a static fill.
- ⚠️ **An AppKit window is hard to genuinely destroy from a test rig** — with `isReleasedWhenClosed`
  either way, `close()` left the window in SCK's full enumeration while the app lived. Three
  attempts failed; the answer came from driving a **real** app (TextEdit closing a document window)
  instead. When a rig can't reach a state, reach for a real app before concluding anything about
  the platform.

## 2. TCC / permissions (both PoC field bugs lived here)

- **Screen & System Audio Recording** (`kTCCServiceScreenCapture`): covers system audio
  too. Preflight `CGPreflightScreenCaptureAccess()`; request
  `CGRequestScreenCaptureAccess()`. Grant is per code-signing identity; the granted app
  must be **fully restarted** (all processes) to pick it up.
- 🔴 **A decline is FINAL — `CGRequestScreenCaptureAccess()` never asks twice** (measured
  2026-07-15, M4-T3 spike, on a genuinely denied bundle):
  ```
  preflight BEFORE request: false
  CGRequestScreenCaptureAccess() -> false   (returned in 0.00s — no prompt shown)
  preflight AFTER request:  false
  ```
  macOS prompts **once, ever**. After that the request call is a no-op returning false, so a
  `Grant…` button wired straight to it is **dead** for any user who ever clicked "Don't Allow" —
  and they are the exact users who need it. Onboarding must offer a **route to System Settings**
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`), not just a
  request call.
  ⚠️ And the app **cannot tell "never asked" from "declined" up front**: preflight returns false
  for both, and `Permissions.screenRecordingState()` collapses both to `.notDetermined` (which
  is why its `.denied` case, and `recordingReadiness`'s `.blocked`, were unreachable for
  screen). The only way to distinguish them is **empirically**: call request, and if the grant
  still hasn't landed, treat it as declined and show the System Settings route. That is a
  one-way door — once shown, don't go back to `Grant…`.
- **Microphone: same one-prompt rule, but the state IS legible and a decline IS recoverable.**
  Measured 2026-07-15 (M4-T3 spike, throwaway `…screenrec.micprobe` bundle):

  | state | `AVCaptureDevice.requestAccess` | prompt? | row in the Microphone pane |
  |---|---|---|---|
  | notDetermined | `false` after 2.11 s | **yes** (declined) | **created** by the decline, toggled off |
  | denied | `false` in 0.00 s | no | already there, toggled off |

  Two consequences, and they point opposite ways from the screen case:
  - ✅ **A declined microphone is recoverable.** The pane has **no "+"** (M4-T2, screenshot) —
    but it doesn't need one, because *asking* is what creates the row. Once the app has asked
    even once, the user has a permanent toggle, whatever they answered. So the only
    unrecoverable state is **never having asked** — which is precisely M4-T2's dead end and
    precisely what M4-T3 removes. **Any permission the app needs, the app must ask for; you
    cannot document your way around it.**
  - ✅ **No empiricism needed here**, unlike screen: `authorizationStatus(for: .audio)` returns a
    real `.denied`, so the row can offer the System Settings route immediately.
  ⚠️ `NSMicrophoneUsageDescription` in Info.plist is **mandatory** — the process is killed
  without it (this bit the spike's probe bundle before it was added).
- **Microphone**: `AVCaptureDevice.requestAccess(for: .audio)`;
  `NSMicrophoneUsageDescription` in Info.plist is MANDATORY (process is killed without
  it). Takes effect immediately, no restart.
- ⚠️ **Output directory TCC**: Desktop/Documents/Downloads are protected. SCK/AVFoundation
  surfaces an unreadable output dir as **"invalid parameter"**. Always preflight with
  `opendir()` on the target directory and emit a human explanation. Default output:
  `~/Movies` (unprotected). The app bundle will eventually get its own Files & Folders
  prompts; preflight anyway.
- ⚠️ **Stable signing identity or you re-grant TCC every rebuild.** Ad-hoc signatures
  change per build. `Scripts/devsign.sh` must establish a stable identity: use an
  "Apple Development" cert if one exists, else create a self-signed code-signing cert
  ("screenrec-dev") in the login keychain and sign every build with it. This is M0 work
  and a prerequisite for sane development.
- Sequoia's monthly re-approval nag: mostly relaxed since 15.1 for regularly-used apps.
  Nothing to do in code.
- macOS 26.1+ reportedly requires a real `.app` bundle for the Screen Recording pane —
  another reason the app (not the CLI) is the shipping artifact. CLI remains dev-only,
  runs under the terminal's grant.

## 3. Video encoding (MovieRecorder)

- **HEVC (`hvc1`) is the default codec.** H.264 is only used by the share export (M10-T1), fitted
  to a width cap.
  ⚠️ **The "AVAssetWriter's H.264 path caps at 4096×2304" claim was wrong** (measured 2026-07-27,
  M18-T2): the writer encodes 4112×2570 H.264 without complaint. What changes is the **level** —
  1280×800 → 3.2, 1920×1200 → 5.0, 2560×1600 → 5.0, **3686×2304 → 5.2**, **4112×2570 → 6.0**.
  4096×2304 is exactly **Level 5.2's** maximum frame size (36 864 macroblocks), and Level 6.0 is a
  2016 addition for 8K that most phone decoders refuse. So the ceiling is real but it is a
  *compatibility* ceiling: a share export must stay at or below 4096×2304, and there is no honest
  "original size" MP4 of a 4112×2570 recording — the largest safe output is 3686×2304.
- Bitrate model (`BitrateModel`): `bits = width × height × fps × BPP`, with H.264-class
  BPP ≈ 0.05 and an HEVC discount ≈ 0.6. Presets (CLI literals: `efficient` |
  `balanced` | `high`, lowercase):
  - Efficient: ×0.5 → ~5 Mbps @ 4112×2570×30
  - Balanced (default): ×1.0 → ~19 Mbps @ 60 fps (≈8.5 GB/h worst case; VFR means far
    less in practice — PoC measured ~0.5 MB/s light use)
  - High: ×1.75
  - Compare-and-tune in M2 against Tier-1 output quality.
- Writer settings: `AVVideoCodecKey: .hevc`, width/height, `AVVideoCompressionPropertiesKey:
  [AVVideoAverageBitRateKey: n, AVVideoExpectedSourceFrameRateKey: fps,
  AVVideoMaxKeyFrameIntervalDurationKey: 2]`.
  ⚠️ **This caps ENCODED FRAMES, not wall clock — the real keyframe gap is unbounded**
  (measured 2026-07-27, M18-T1). Capture is frame-on-change, so a static stretch emits no
  frames and therefore no keyframes: on a 23-minute recording the sync sample before a 61 s
  point sat **3.43 s** back, well past the 2 s the setting implies, and it is worst when the
  screen was quiet. What that gap costs is in §6a — not a moved in-point.
- **The encoder emits B-frames**, so PTS is legitimately non-monotonic in storage (measured:
  459 of 923 samples step back on a 20 s recording; DTS is clean). Anything checking timestamp
  order must judge DTS and PTS separately and never compare one against the other — the first
  and last few samples of a track carry no DTS at all.
- `expectsMediaDataInRealTime = true` on **all** inputs. If `isReadyForMoreMediaData`
  is false, **drop the buffer** — never block the SCK callback queue.
- Hardware encode is automatic (Media Engine). Do not touch VideoToolbox directly for
  file recording — only the replay path uses VTCompressionSession (because it needs
  compressed frames in memory, not in a file).
- ProRes 422 is a valid AVAssetWriter codec if a "mezzanine" mode is ever wanted —
  park it; enormous files.

## 4. Audio tracks (MovieRecorder)

- **Three `AVAssetWriterInput`s total; NEVER feed `.audio` and `.microphone` buffers into
  one input** — they have different `CMFormatDescription`s and it corrupts the container
  (Apple DTS-confirmed, forums thread 805892). Two AAC audio inputs:
  - system: 48 kHz stereo, AAC ~192 kbps
  - mic: build input lazily from the **first mic buffer's format description** (device-
    native format varies: AirPods mono 24 kHz vs studio interface 96 kHz), AAC ~160 kbps.
- Mic device notes: AirPods drop system playback quality while their mic is active
  (HFP/A2DP limitation, not our bug — surface in UI copy).
- ⚠️ **A lost mic device does NOT hand over to another one — its buffers simply stop.**
  Verified 2026-07-15 (§4.2, AirPods → case mid-recording): video and system audio ran the
  full 60 s while the mic track just ended at 22.6 s. No takeover, no format change, no
  error, no event. The cause is §1's forced explicit `microphoneCaptureDeviceID`: SCK
  captures the device you *named* and will not substitute another. An earlier draft of this
  section claimed "AirPods die → built-in mic takes over" — that is **FALSE**; do not design
  against it. Detecting mic loss therefore needs a **starvation watchdog** (was delivering,
  then stopped), not a format comparison — M3-T6, policy in ADR-012.
- ⚠️ **A lost mic never comes back *to the stream that lost it*** — reconnecting the device
  does NOT resume delivery on the original `SCStream` (verified 2026-07-15: mic track ended at
  21.8 s of a 59.8 s file despite a reconnect). **Since M8-T2 recovery IS built**: on loss,
  `MicrophoneRescue` waits for the rebind target via a HAL device-list listener
  (`kAudioHardwarePropertyDevices`), then splices a fresh mic-only `SCStream` into the same
  router through its own `ResampledMicInput` — the track/ring resumes after a silent gap;
  `MicrophoneWatchdog.rearm()` restarts the loss cycle so repeated case/uncase works. Policy
  honors the pick (`MicrophoneRecovery`): `.sameDevice` for a specific pick, `.systemDefault`
  for Automatic (which may recover onto a *different* device — the current default).

### The one rule behind all mic-device behavior (M3-T7 spike, 2026-07-15)

> **SCK binds the mic device ONCE at `startCapture` and never re-resolves it** — whether you
> name a device or pass nil. Everything below follows from that.

Six experiments (`screenrec-cli mic-swap-spike`, modes `--reconnect` / `--fallback` /
`--nil-device` / `--nil-follow` / `--two-streams`):

| Experiment | Result |
|---|---|
| `updateConfiguration` re-point between two **live** devices | ✅ works (48k→24k, buffers follow) |
| **Passive** reconnect of a died device | ❌ never resumes |
| Re-point to a **died-and-returned** device (same uniqueID) | ❌ dead — and `updateConfiguration` **returns OK while doing nothing** |
| Re-point to a device **alive throughout**, after the mic died | ✅ works, first attempt |
| nil device id at start | ✅ accepted, delivers the default (see §1 — the old "nil throws" is stale) |
| Does nil **follow** the default when it changes? | ❌ no — resolves once, then pins; the mic dies with its device |

Consequences for anyone designing mic recovery:
- **The stream's mic path is NOT poisoned when its device dies** — a live device binds to it
  fine. What is permanently unbindable is *any device that disappeared during that stream's
  life*, even back under the same uniqueID.
- **The poisoning is per-STREAM.** A fresh `SCStream` binds a previously-died device normally.
- ⚠️ **`updateConfiguration` gives no error signal for this** — it returned OK on all 8 attempts
  while delivering nothing. Never trust its return value; watch for buffers.
- Two viable recovery routes, both verified, neither built (ADR-012):
  1. **Re-point to a live device** — enables "AirPods die → built-in". One-way (can never go
     back to the AirPods) and needs a fixed-format/resampled mic input (48k into a 24k input).
  2. **Rebuild a mic-only second stream** — two `SCStream`s were verified to coexist and both
     deliver, so the recording stream never blinks. Handles fallback *and* reconnect (a
     returning AirPod rebinds at the same 24 kHz → no resampling). PTS coherence across the two
     streams — ADR-001's whole concern — **verified 2026-07-20** (`mic-swap-spike --two-streams-pts`:
     sysAudio↔mic drift +0.6 ms/min over 90 s, i.e. the same host clock with no relative drift;
     the ~50 ms sysAudio−mic offset is constant capture latency, not drift), and confirmed
     end-to-end (`--two-streams-record` muxes both streams into one `.mov`: mic held a constant
     ~16 ms offset to system audio, no drift over 62 s). This is the preferred recovery route (and
     the only one that handles reconnect without wiping the replay buffer).
- **Format changes mid-stream are absorbed since M8-T1**: every mic buffer is normalized to
  ONE fixed format — 48 kHz mono Float32 (`ResampledMicInput`, `AVAudioConverter`, primeless,
  output PTS = input PTS) — in the engine's mic path *before* `SampleRouter` fan-out, so no
  consumer ever sees a device format. M3-T2's fail-stop-on-flip is retired
  (`EndReason.microphoneChanged` deleted outright in M15-T4; ADR-007 amended); the ring's
  re-latch still guards system audio only. Measured live (`mic-swap-spike --record-repoint`):
  a recording rode an AirPods→built-in `updateConfiguration` re-point with one continuous
  31 s mic track spanning the swap, signal on both sides.
  ⚠️ Consequence: **the mic track no longer reveals the source device's rate** — it is always
  48 kHz mono, so M6-T13's "verify the Automatic pick by track sample rate" method is dead;
  verify via the active-mic menu line (or volume fingerprinting) instead.
- Default track layout: system + mic as two separate tracks (the whole point of Tier 2).
  Optional third "mixed" track is out — players play all tracks simultaneously anyway,
  which IS the mixed experience.

## 5. Timing, sync, session lifecycle (MovieRecorder + TimestampRebaser)

- All three SCK outputs deliver host-clock PTS — coherent by construction on macOS 15.
  This is why we require 15+ (ADR-001).
- **Session start**: `startSession(atSourceTime: .zero)` and rebase every buffer by
  subtracting the epoch = PTS of the **first complete video frame**. Buffers (audio)
  arriving before the epoch: drop them. Audio must never lead video.
- **Pause/resume** (`TimestampRebaser`): on pause, note `pauseStartPTS`; while paused,
  drop everything; on resume (at next complete video frame), add
  `resumePTS - pauseStartPTS` to a cumulative `pausedOffset`; every appended buffer's
  PTS = `raw - epoch - pausedOffset`. Enforce **strictly monotonic** output PTS per
  input (drop violators; QuickRecorder's frameQueue exists because SCK occasionally
  reorders/dupes).
- **Tail-frame patch**: SCK sends nothing while the screen is static, so a recording
  stopped after 30 static seconds would lose them. On stop, re-append the last video
  frame with PTS = stop time (fatbobman's fix). Keep (don't release) a reference to the
  most recent pixel buffer for this purpose only.
- **Crash safety**: `writer.movieFragmentInterval = CMTime(seconds: 1)` on `.mov`. A fragment
  is flushed to disk each second, so a `kill -9` loses at most ~1 s and the file is playable
  from the first flush on. ⚠️ **The interval directly bounds worst-case loss** — this was 10 s
  originally, but the §3.2 kill test (M2/G2) proved that anything killed before the first
  10 s flush was completely unparseable (media on disk, no fragment index). 1 s matches the
  PoC's sub-second-loss behavior; the overhead (one small `moof` per second) is negligible.
  `shouldOptimizeForNetworkUse` is NOT crash safety (moov placement at finalize only).

## 6. File output

- Container: `.mov` (required for fragment intervals). Name: `Recording yyyy-MM-dd at
  HH.mm.ss.mov`; replays `Replay yyyy-MM-dd at HH.mm.ss.mov`. Default dir `~/Movies`
  (§2). User-configurable dir must pass the `opendir` preflight at selection time AND at
  record time. Name collision (two recordings started the same second): append ` 2`,
  ` 3`, … before the extension.

## 6a. Trimming (`Trimmer`) — measured 2026-07-27, M18-T1

- **A passthrough trim already starts exactly at the in-point.** `AVAssetExportSession` writes an
  **edit list**: it stores from the preceding sync sample but maps presentation to begin at the
  requested time. Measured — the trim's first presented frame is byte-identical to the source at
  the in-point, in AVFoundation *and* in ffmpeg. "The in-point snaps back to a keyframe" describes
  what is stored, not what plays; it was in our copy and docs for two milestones as if it were the
  latter.
- **What it does cost: the file keeps the lead-in.** Everything between the sync sample and the
  in-point stays inside the file, hidden — `ffprobe -ignore_editlist 1` reports 13.56 s for a
  10.00 s clip and decodes the frame 3.43 s before the in-point. Video only: every audio packet is
  a sync sample, so audio's lead-in is ~0.02 s. `KeyframeIndex.leadInStart` finds it in 0.0–0.9 ms
  on a 23-minute file (an `AVSampleCursor` stepped back in decode order; the walk is bounded by
  keyframe spacing, not file length). ⚠️ `sampleIsFullSync` is an `ObjCBool` — `.boolValue`.
- **A re-encoding preset alone does NOT re-encode.** `AVAssetExportPresetHEVCHighestQuality` +
  `timeRange` on an HEVC source passes it straight through: byte-identical output (23,578,074
  bytes both ways), 0.1 s. Setting `session.videoComposition =
  AVVideoComposition(propertiesOf: asset)` forces the real encode — that is what `.precise` does.
  ⚠️ Plain `AVAssetExportPresetHighestQuality` re-encodes but **downscales 4112×2570 → 3840×2400
  and converts hvc1 → avc1**; the HEVC preset preserves size, codec and both audio tracks (ADR-004
  holds through the re-encode).
- **Precise is slower and often larger.** A re-encode emits constant-frame-rate video where
  capture emitted almost nothing: on a quiet 10 s range, lossless = 2.2 MB / 0.6 s, precise =
  3.3 MB / 7.8 s. It buys one thing — a file that contains only the kept range.

## 7. Long-recording robustness

- `SleepGuard`: `ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled,
  .userInitiated], reason:)` for the life of **any** stream — recording, armed replay, or a CLI
  diagnostic (ADR-018) — ended at teardown. The reason comes from `CaptureEngine.Purpose` and is
  user-visible in `pmset -g assertions`, so each purpose states its own: an armed stream must not
  claim to be recording. Display sleep still ends the stream — that's a clean finalize, acceptable.
- ⚠️ **Releasing our assertion would not let an armed Mac idle-sleep anyway.** Measured 2026-07-27:
  any SCK stream that captures audio also carries a `PreventUserIdleSystemSleep` held by
  `coreaudiod` on behalf of `/usr/libexec/replayd`, for the audio tap — present with the mic off
  too (the system-audio tap alone does it), and released only when the stream is torn down. Don't
  plan power behaviour around dropping `SleepGuard` alone (docs/07, M16-T1).
- Display unplug / resolution change / user lock → `didStopWithError` → finalize + notify.
  Never attempt hot re-attach in v1 (ADR-007).
- **The display-gone error is `SCStreamErrorNoCaptureSource` (-3815)**, "Failed to find any
  displays or windows to capture" (measured 2026-07-15: `pmset displaysleepnow` mid-recording →
  -3815 → `finished(.displayDisconnected)` → playable file). ⚠️ SCK reports display **sleep**,
  screen **lock**, and **lid-close / system sleep** identically as -3815 — lid-close confirmed
  2026-07-15 (§4.3: the machine slept mid-recording, the process was suspended, and it finalized
  `displayDisconnected` + a playable 11.2 s file on wake). So **`EndReason.systemSleep` was
  confirmed dead, not merely unused** (and deleted in M15-T4): there is no signal to map it from, and every guess at
  wiring it up would have been wrong. Do not invent a distinction the API doesn't give you.
  (Monitor unplug stays untested — this machine has only a built-in display.)
  `CaptureEngine.endReason(forStreamError:)` maps it; unmapped SCK errors keep their code in the
  message, which is how -3815 was identified rather than guessed.
- **The recording file itself is guarded (M6-T7).** The active file is `….mov.partial`
  (finalize renames it; `OutputLocation` owns the lifecycle) and `RecordingFileSentinel`
  watches it via a private `O_EVTONLY` fd: a rename is reversed in place (the writer's fd
  follows the inode, so moves — the Trash included — never hurt the data), an unlink ends the
  session as `.failed` (no relink API exists; the bytes die at close). Two traps encoded there:
  the sentinel must attach only from `MovieRecorder.onDidBeginWriting` — earlier attachment
  races `startWriting()` and can watch the reservation placeholder's replaced inode (a false
  delete on a healthy start, caught live) — and path comparison must use `realpath(3)`, because
  `F_GETPATH` resolves `/private` while Foundation's `resolvingSymlinksInPath` strips it.
  Teardown uses `cancelAndWait()` (drains an in-flight rename-back so finalize can't race it)
  and a torn-down latch (a late `onDidBeginWriting` must not install an uncancellable
  sentinel). Recovery sweeps only partials untouched for 60 s — a live writer touches its
  file about once a second, and in-process "no recording running" can't see other processes.
  Accepted trade-off: the final `.mov` name is NOT held during a recording (the claim sits on
  the partial), so a collision at finalize steps to `… 2.mov` — timestamped names make that
  cosmetic. A `movedAndUnrestorable` file is finalized in place via the writer's fd and
  reported *saved* at its new location, never "deleted".
- ⚠️ **Zero displays needs lock AND display-off — neither alone does it** (measured 2026-07-15,
  after getting this wrong twice by testing one condition at a time):

  | State | `SCShareableContent` | Starting a capture |
  |---|---|---|
  | Unlocked, display slept (`pmset displaysleepnow`) | displays listed | **works** — SCK wakes the display |
  | **Locked**, display on | displays listed | **works** — records the login window |
  | **Locked AND display slept** | **zero displays** | fails (this is the only zero-display state) |

  The model: SCK will wake a sleeping display to capture it, but it cannot while the session is
  locked. So the real-world trigger is "walked away" — locking, then the idle timer powering the
  display off. Reproduce it headlessly-ish: have a human lock, then `pmset displaysleepnow` from
  a shell (the shell keeps running while locked). A running stream is separate: display sleep
  alone kills it with -3815 regardless of lock state.
- Disk-full: stop cleanly at < 2 GB free with notification (`DiskSpaceMonitor`, M3-T3).
- ⚠️ **Read the free space through a path, never a held `URL`.** `URL` caches resource values per
  instance, so a monitor that keeps one polls its own first answer forever — measured 2026-07-28 on
  a filling 300 MB volume: 312,950,784 held vs 208,093,184 fresh. That shipped: from M3-T3 to
  M19-T1 the floor could only trip on a disk that was *already* too full at Start. The guard now
  builds its `URL` inside `availableBytes(forVolumeAtPath:)` on every poll, so no caller can hold
  one (M19-T1). ⚠️ Injected-probe tests cannot see this class of bug — 04 §4.4 names what can.
- ⚠️ **Do NOT read `volumeAvailableCapacityForImportantUsage` alone** — an earlier draft of this
  line recommended exactly that, and it is a trap. Measured 2026-07-15 (HFS+/exFAT/FAT32/APFS
  disk images): **every non-boot volume reports it as `0` — not nil — while the volume has
  plenty free** (0 vs 102 MB real). Any `< floor` test then reads every external SSD, USB stick,
  SD card, disk image and network share as full and kills the recording on the first poll. It is
  still the *better* key on the boot volume (it counts purgeable space: 764 GB vs 726 GB raw), so
  read **both** `volumeAvailableCapacityForImportantUsage` and `volumeAvailableCapacity` and take
  the **larger**. A genuinely full volume reports ~0 from both, so the guard still fires.
  ⚠️ Note `0` is a *successfully read* value, so no nil-guard catches this — and tests probing
  only `temporaryDirectory`/`~/Movies` (the boot volume) will pass while the guard is broken
  everywhere else. Test the reconciliation as a pure function over both keys.
- Probe the output **directory**, not the output file: `resourceValues` throws for a path that
  doesn't exist yet, which returns nil forever and silently disables the guard.
- OBS reports rare SCK stalls on multi-hour Sequoia sessions; our watchdog (`StallWatchdog`,
  M3-T5): if no video buffer arrives for 30 s AND the user isn't idle — input activity via
  `CGEventSource.secondsSinceLastEventType(_:eventType:)` (CoreGraphics,
  RecorderCore-safe; NSEvent monitors are AppKit and permission-gated) — log it; do not
  auto-restart in v1.
  ⚠️ **The idle cross-check is the whole design, not a refinement.** SCK is frame-on-change, so
  an idle user's static screen delivers nothing for minutes and that is *healthy* (§5's
  tail-frame patch exists for exactly that; G2 §3.4 measured 14 s of it). "No frames" alone
  would cry wolf on every coffee break. Silence is evidence only when the user was demonstrably
  active during it — i.e. `secondsSinceLastEventType < the silence`.
- **Reading the stall log.** It goes to the unified log (`os.Logger`, subsystem
  `dev.fcostantini.screenrec`, category `capture`) — **not** to the CLI's stdout, so it is
  invisible unless you look for it. A stall can't be forced (SCK has to genuinely wedge), so the
  M6-T2 soak is the realistic place it would ever fire. Check with:
  ```sh
  log show --predicate 'subsystem == "dev.fcostantini.screenrec"' --last 2h
  log stream --predicate 'subsystem == "dev.fcostantini.screenrec"'   # live
  ```

## 8. Echo cancellation — explicitly out (v1)

SCK provides none. Speakers + mic = the mic hears the speakers. v1 stance: UI hint
("wear headphones for narration over sound"). Do NOT reach for the voice-processing
AudioUnit: VPIO globally ducks SCK's system-audio capture to near-silence (~-51 dB,
vendor-reported) — worse than the problem. Revisit post-v1 with AECAudioStream-style
approaches if it matters.

## 9. Instant replay specifics (ReplayEncoder / RingBuffer / ReplayMuxer)

- `VTCompressionSession` (HEVC): `kVTCompressionPropertyKey_RealTime = true`,
  `AllowFrameReordering = false` (no B-frames: PTS==DTS, monotone ring, passthrough mux
  without decode-order headaches), `MaxKeyFrameIntervalDuration = 1 s`,
  `AverageBitRate` from BitrateModel (Balanced), `ProfileLevel` HEVC Main AutoLevel.
- Feed it `CVPixelBuffer`s from `.screen` callbacks (same SampleRouter tap as recording).
  Output callback pushes compressed `CMSampleBuffer` + keyframe flag (from attachments,
  `kCMSampleAttachmentKey_NotSync` absent ⇒ keyframe) into the video ring.
- Rings are duration-bounded (target N + 2 s slack). Keyframe every 1 s bounds clip
  start error to ≤ 1 s. Memory at 60 s, measured: video ≈ Balanced bitrate × 62 s
  (~145 MB busy at 4112×2570 — the original ~80 MB assumed ~10 Mbps) + ~29 MB PCM audio.
  Accepted uncapped (Franco 2026-07-16): replay quality stays at recording parity;
  VT `DataRateLimits` is the ready lever if a cap is ever wanted (unavailable through
  AVAssetWriter, available here — M2-T6).
- Mux on demand: snapshot under lock → oldest keyframe ≥ N s back → rebase PTS → one
  AVAssetWriter: video input `outputSettings: nil` + `sourceFormatHint` (passthrough);
  two AAC audio inputs encoded from PCM at mux time. Write on a utility queue; the ring
  keeps rolling. Duplicate-hotkey during mux: coalesce (ignore while mux in flight).
- Hotkey: Carbon `RegisterEventHotKey` (works without Accessibility/Input-Monitoring
  permission, unlike `NSEvent.addGlobalMonitor`). Default ⌥⌘R, configurable in the
  Settings window (M4-T4; keys in docs/06).
- OS note: Apple ships `SCClipBufferingOutput` (native rolling buffer) in the macOS 27
  beta cycle — our design keeps `ReplayEncoder+RingBuffer` behind a small interface so it
  can be swapped for the OS implementation later (ADR-005).
- ⚠️ **Armed = a live SCK stream, and macOS treats any live stream as "display being shared":**
  the capture indicator is mandatory (no API opts out; the OS rolling-buffer API won't either),
  and Notification Center suppresses banners under its global mirroring/sharing policy —
  measured for our own notifications (delivered, never drawn); by that policy's design this
  should suppress every app's banners while armed (not yet directly observed — docs/06 has the
  full write-up and remedies).

## 10. CLI/dev environment gotchas (bit us in the PoC)

- ⚠️ `recordedDuration`/CMTime can be **invalid → `.seconds` = NaN → `Int(NaN)` traps**.
  Guard every CMTime→display conversion with `.isFinite`.
- stdout is block-buffered when not a TTY: `setvbuf(stdout, nil, _IONBF, 0)` in the CLI
  so crashes can't eat diagnostics.
- Bare executables get TCC attribution from the parent terminal; granting Screen
  Recording requires **quitting the whole terminal app** (all tabs = one process).
- ⚠️ **Capture tests run via an agent's shell are attributed to the AGENT's runtime**,
  not the terminal or the binary. When Claude Code runs `engine-smoke`/`record`, the
  Screen Recording prompt names the Claude Code process (e.g. "2.1.209") — that process
  must be granted, and the grant applied immediately (no restart needed, verified
  2026-07-14). A different terminal/runtime = a separate grant. `SCShareableContent`
  throws "The user declined TCCs…" when ungranted (not empty displays) — CaptureEngine
  catches it and emits `.failed`.
- Embed Info.plist into CLI binaries via `-sectcreate __TEXT __info_plist` (see PoC's
  Package.swift) for the mic usage description.
- Swift 6 toolchain: use `swiftLanguageMode(.v5)` (PoC precedent) to avoid strict-
  concurrency fights in delegate-heavy SCK/AVF code. Revisit post-v1.
- ⚠️ **No XCTest under Command Line Tools** — `import XCTest` fails to compile (XCTest
  ships with Xcode only). All tests use **Swift Testing**: `import Testing`, `@Test`,
  `#expect`. Verified working with CLT's Swift 6.1 (M0-T1).
- DRM video (Netflix, TV app) captures black. By OS design. Not a bug.

## Reference implementations (read before writing MovieRecorder)

- `~/code/screenrec-poc` — our Tier-1: stream config, permissions flow, CLI UX patterns.
- QuickRecorder `RecordEngine.swift` (github.com/lihaoyun6/QuickRecorder) — production
  AVAssetWriter pipeline incl. pause timestamp math. GPL — **read for patterns, do not
  copy code** (license; also we can do cleaner).
- Azayaka (github.com/Mnpn/Azayaka) — dual SCRecordingOutput/AVAssetWriter engines.
- nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit — canonical timing
  writeup (session start, retiming).
- Apple forums thread 805892 — DTS on the two-audio-inputs requirement.

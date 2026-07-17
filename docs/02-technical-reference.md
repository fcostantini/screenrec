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
- `capturesAudio = true`, `sampleRate = 48_000`, `channelCount = 2`,
  `excludesCurrentProcessAudio = true`.
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

- **HEVC (`hvc1`) is the default codec.** Hard constraint: AVAssetWriter's H.264 path
  caps at 4096×2304 — the dev display (4112×2570) already exceeds it. Offer H.264 only
  with a downscale, or not at all in v1.
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
- ⚠️ **A lost mic never comes back — reconnecting the device does NOT resume delivery.**
  Verified 2026-07-15: AirPods cased mid-recording and then reconnected ~20 s later produced
  no further mic buffers at all (mic track ended at 21.8 s of a 59.8 s file; the recording ran
  to the end). Mic loss is therefore one-shot per session — nothing to re-arm or recover, which
  is why `MicrophoneWatchdog` fires once.

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
     returning AirPod rebinds at the same 24 kHz → no resampling). Unverified assumption to
     settle first: whether a second stream's mic PTS stays coherent with the main stream's
     video (ADR-001's whole concern — use the §3.5 drift method).
- **Format changes mid-stream** remain possible for the *same* device (e.g. an AirPods
  HFP/A2DP codec flip), so `MovieRecorder` compares each mic buffer's ASBD (sample rate /
  channels / format ID) against the input's and fail-stops on a diff (M3-T2). With a pinned
  device ID that is a defensive guard, not the common path. Do not attempt live format
  switching in v1 (ADR-007): the input's format is welded to the first buffer's, so *any*
  device swap would first require normalizing the mic into a fixed-format input (ADR-012).
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

## 7. Long-recording robustness

- `SleepGuard`: `ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled,
  .userInitiated], reason: "Recording")` while recording or replay-armed; end it after.
  Display sleep still ends the stream — that's a clean finalize, acceptable.
- Display unplug / resolution change / user lock → `didStopWithError` → finalize + notify.
  Never attempt hot re-attach in v1 (ADR-007).
- **The display-gone error is `SCStreamErrorNoCaptureSource` (-3815)**, "Failed to find any
  displays or windows to capture" (measured 2026-07-15: `pmset displaysleepnow` mid-recording →
  -3815 → `finished(.displayDisconnected)` → playable file). ⚠️ SCK reports display **sleep**,
  screen **lock**, and **lid-close / system sleep** identically as -3815 — lid-close confirmed
  2026-07-15 (§4.3: the machine slept mid-recording, the process was suspended, and it finalized
  `displayDisconnected` + a playable 11.2 s file on wake). So **`EndReason.systemSleep` is
  confirmed dead, not merely unused**: there is no signal to map it from, and every guess at
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

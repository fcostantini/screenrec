# 01 — Architecture

## Package layout (SPM, no Xcode project — see ADR-002)

```
screenrec-app/
├── Package.swift
├── Sources/
│   ├── RecorderCore/          # Library. ALL capture/encode/write logic. No UI imports.
│   │   ├── Capture/          # CaptureEngine (owns the one SCStream), CaptureConfiguration,
│   │   │                     #   SampleRouter (fan-out), CapturableApp, Permissions,
│   │   │                     #   MicrophoneWatchdog + MicrophoneRescue (M8), StallWatchdog,
│   │   │                     #   AppTerminationWatch (M7), EngineEvent
│   │   ├── Recording/        # RecordingSession (engine+recorder seam), MovieRecorder,
│   │   │                     #   TimestampRebaser, BitrateModel, AudioEncodingSettings
│   │   ├── Replay/           # ReplayEncoder (VTCompressionSession), RingBuffer,
│   │   │                     #   ReplayAudioRing, ReplayMuxer (passthrough)
│   │   ├── Export/           # Exporter (H.264 MP4), GifExporter, Trimmer, VideoFrameReader (M10)
│   │   └── Support/          # OutputLocation, DiskSpaceMonitor, Polling, SleepGuard,
│   │   │                     #   RecordingFileSentinel (M6), ResampledMicInput (M8), CoreInfo
│   ├── screenrec-cli/         # Dev harness (ADR-011). main + Export/Trim/ReplayArm/ProbeStream
│   ├── AppCore/               # Library. App state + view models. No AppKit/SwiftUI (M4-T1).
│   │   │                     #   AppState (@Observable, MainActor; folds EngineEvents),
│   │   │                     #   Settings (+ Hotkey), PermissionsModel, OnboardingModel,
│   │   │                     #   ReplayController, RecordingNotification, RecordingClock,
│   │   │                     #   StatusIcon, DisplayOption, LoginItem, MenuHeader,
│   │   │                     #   LastExport, LastReplay, RecentRecordings
│   └── ScreenRecApp/          # Menu-bar app. SwiftUI + AppKit. Depends on AppCore.
│       │                     #   App (@main, MenuBarExtra + AppDelegate), Notifier, Relaunch,
│       │                     #   HotkeyCenter (Carbon), RegionSelectionOverlay (M11),
│       └── Views/            #   StatusIconView, MenuView, SettingsView, OnboardingView, TrimView
├── Scripts/                   # bundle.sh, devsign.sh, release.sh, smoke.sh (M13), hooks/pre-push
├── Tests/                     # RecorderCoreTests + AppCoreTests (pure-decision + integration)
├── tools/                     # probe, frames, menudriver, settingsdriver, hoverprobe, axdump
└── docs/                      # you are here
```

**Rule for agents:** `RecorderCore` must never import AppKit/SwiftUI (CoreGraphics is
fine). Everything testable lives there. The CLI is the primary dev/verification surface
until M4 — build UI last.

## Runtime dataflow

```
                    ┌──────────────────────── CaptureEngine ───────────────────────┐
                    │  SCStream (one per session)                                   │
                    │  outputs: .screen  .audio  .microphone                        │
                    └──────┬──────────────┬──────────────┬─────────────────────────┘
                           │ CMSampleBuffers on 3 serial queues (SCK requirement)
                           ▼              ▼              ▼
                    ┌──────────────── SampleRouter ────────────────┐
                    │ fan-out; consumers attach/detach at runtime  │
                    └──────┬───────────────────────────┬───────────┘
                           │                           │
              (recording active)              (replay armed)
                           ▼                           ▼
                  ┌─ MovieRecorder ─┐        ┌─ ReplayEncoder ──────────────┐
                  │ AVAssetWriter   │        │ video → VTCompressionSession │
                  │  in: video HEVC │        │        → RingBuffer (60 s)   │
                  │  in: sysaudio   │        │ sysaudio → RingBuffer (PCM)  │
                  │  in: mic        │        │ mic      → RingBuffer (PCM)  │
                  │ fragments @10 s │        └──────────┬───────────────────┘
                  └───────┬─────────┘                   │ hotkey
                          ▼                             ▼
                    ~/Movies/*.mov              ReplayMuxer (passthrough)
                                                        ▼
                                               ~/Movies/Replay *.mov
```

Key property: **recording and replay are independent consumers of the same stream.**
Both can run at once (recording a meeting AND able to clip the last minute). SampleRouter
is the seam that makes this trivial.

## Concurrency model

- `CaptureEngine` is an **actor** owning stream lifecycle (start/stop/reconfigure).
  **One exception (M8-T2):** `MicrophoneRescue`, a lock-based satellite owned by the engine,
  runs a second, mic-only `SCStream` after a mic loss and splices its (fixed-format) buffers
  into the same `SampleRouter`. Its lifecycle is callback-driven (HAL device events, SCK
  delegate) rather than actor-hosted; the engine creates it per session and cancels it in
  `terminate()`. "One stream per session" elsewhere in this doc means the *primary* stream.
- Sample delivery happens on **dedicated serial `DispatchQueue`s** passed to
  `addStreamOutput` (one per output type). Handlers must be allocation-light: no async
  hops, no lock contention; append to writer / push to ring and return. SCK's IOSurface
  pool == `queueDepth` (we use 5) — retaining buffers stalls capture.
- `MovieRecorder` and `RingBuffer` guard state with `NSLock`/`os_unfair_lock`, not actors
  — actor hops are too slow/jittery for the per-frame path.
- UI state flows: RecorderCore exposes an `AsyncStream<EngineEvent>`; `AppState`
  consumes it on the MainActor. This is the definitive event surface (M1-T2, M3-T2,
  M4, and docs/06 notification copy all consume it — extend here, never fork):

  ```swift
  enum EndReason: Sendable {
      case userStopped, displayDisconnected, appQuit, windowClosed, diskAlmostFull
      case streamError(String)
  }
  enum EngineEvent: Sendable {
      case started                                   // first complete video frame
      case paused, resumed
      case microphoneLost                            // mic stopped delivering; recording CONTINUES (M3-T6, ADR-012)
      case fileProgress(seconds: Double, bytes: Int64)
      case stopped(EndReason)                        // engine ran with no writer (e.g. engine-smoke)
      case finished(url: URL, reason: EndReason, droppedFrames: Int)  // file finalized, playable
      case failed(message: String)                   // nothing playable exists (preflight/start)
  }
  ```
  Fail-stop (ADR-007) is ALWAYS `finished` with a non-`userStopped` reason — a playable
  file plus a cause. `failed` is reserved for failures before any media was written.
  `microphoneLost` is the one mid-recording problem that does NOT end the session (ADR-012):
  it is a notification, not a termination, and the mic track simply ends at that point.

## Recorder state machine (enforced in CaptureEngine)

```
 idle ──start──▶ preparing ──firstCompleteFrame──▶ recording ◀──resume── paused
   ▲                │ error                            │ pause ────────────▲
   │                ▼                                  │ stop
   └── finalizing ◀────────────────────────────────────┘
        (writer.finishWriting; also entered on stream death / display unplug)
```

- `preparing`: stream started, writer built, session NOT started. Session starts at the
  first VIDEO frame with `SCFrameStatus.complete` (audio arriving earlier is buffered or
  dropped — never let audio lead video; see 02 §5).
- Stream death (`didStopWithError`, e.g. display unplugged, sleep) from any state →
  `finalizing` → clean file. This mirrors what the PoC proved: end early, never corrupt.

## Instant replay design (M5, details in 02 §9)

- `ReplayEncoder`: one `VTCompressionSession`, HEVC, `RealTime=true`,
  `AllowFrameReordering=false` (no B-frames ⇒ PTS==DTS ⇒ ring trimming and passthrough
  muxing stay simple), `MaxKeyFrameIntervalDuration=1s`.
- `RingBuffer`: append-only circular store of (CMSampleBuffer, isKeyframe, pts); evicts
  from the head while `newest.pts - oldest.pts > capacity + 2 s`. Video ring holds
  compressed samples (~10 Mbps ⇒ ~80 MB/60 s). Audio rings hold raw PCM
  (48 kHz stereo Float32 ⇒ ~23 MB/60 s each) — raw PCM avoids an AAC encoder in the hot
  path; AAC encoding happens once, at mux time.
- `ReplayMuxer` on hotkey: snapshot ring contents (copy the array under lock — cheap,
  buffers are refcounted), find oldest keyframe ≥ N seconds back, rebase PTS to zero,
  write via AVAssetWriter with `outputSettings: nil` + `sourceFormatHint` for video
  (passthrough — no re-encode) and AAC settings for the audio inputs. Target < 1 s.

## Error philosophy

Every failure ends in one of exactly two user-visible outcomes: (a) a clear pre-flight
message BEFORE recording starts (permissions, output dir, no mic), or (b) a finalized
playable file plus a notification saying why recording ended. There is no outcome
"recording silently broken" and no outcome "file corrupted." The PoC's TCC lessons
(02 §2) exist because SCK errors are opaque — preflight everything we can.

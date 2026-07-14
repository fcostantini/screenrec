# 01 — Architecture

## Package layout (SPM, no Xcode project — see ADR-002)

```
screenrec-app/
├── Package.swift
├── Sources/
│   ├── RecorderCore/          # Library. ALL capture/encode/write logic. No UI imports.
│   │   ├── Capture/
│   │   │   ├── CaptureEngine.swift        # SCStream lifecycle, owns the one stream
│   │   │   ├── CaptureConfiguration.swift # value type: display, mic, fps, quality…
│   │   │   ├── SampleRouter.swift         # SCStreamOutput → fan-out to consumers
│   │   │   └── Permissions.swift          # TCC preflight/request, onboarding state
│   │   ├── Recording/
│   │   │   ├── MovieRecorder.swift        # AVAssetWriter session (3 inputs)
│   │   │   ├── TimestampRebaser.swift     # epoch rebase + pause offset accounting
│   │   │   └── BitrateModel.swift         # quality preset → bitrate math
│   │   ├── Replay/
│   │   │   ├── ReplayEncoder.swift        # VTCompressionSession wrapper
│   │   │   ├── RingBuffer.swift           # generic timed ring of CMSampleBuffers
│   │   │   └── ReplayMuxer.swift          # ring → passthrough AVAssetWriter → file
│   │   └── Support/
│   │       ├── OutputLocation.swift       # dir preflight (TCC!), naming, ~/Movies
│   │       └── SleepGuard.swift           # ProcessInfo activity assertion
│   ├── screenrec-cli/         # Dev harness. Thin CLI over RecorderCore.
│   │   └── main.swift
│   └── ScreenRecApp/          # Menu-bar app. SwiftUI. Depends on RecorderCore only.
│       ├── App.swift                      # @main, MenuBarExtra
│       ├── AppState.swift                 # ObservableObject bridging RecorderCore
│       ├── Views/ (MenuView, SettingsView, OnboardingView)
│       ├── Hotkey.swift                   # Carbon RegisterEventHotKey wrapper
│       └── Resources/Info.plist, AppIcon
├── Scripts/
│   ├── bundle.sh              # assembles ScreenRec.app from SPM build output + signs
│   └── devsign.sh             # one-time: create/find stable signing identity
├── Tests/RecorderCoreTests/   # unit tests (RingBuffer, TimestampRebaser, BitrateModel)
├── tools/probe.swift          # file inspector (tracks/codecs/duration) — already works
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
- Sample delivery happens on **dedicated serial `DispatchQueue`s** passed to
  `addStreamOutput` (one per output type). Handlers must be allocation-light: no async
  hops, no lock contention; append to writer / push to ring and return. SCK's IOSurface
  pool == `queueDepth` (we use 5) — retaining buffers stalls capture.
- `MovieRecorder` and `RingBuffer` guard state with `NSLock`/`os_unfair_lock`, not actors
  — actor hops are too slow/jittery for the per-frame path.
- UI state flows: RecorderCore exposes an `AsyncStream<EngineEvent>` (started, paused,
  fileProgress(duration,bytes), finished(URL), failed(Error)). `AppState` consumes it on
  the MainActor.

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

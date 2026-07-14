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
- ⚠️ **`microphoneCaptureDeviceID` must be set explicitly.** Docs say nil = default mic;
  on 15.6 nil makes `startCapture` throw "invalid parameter". Resolve
  `AVCaptureDevice.default(for: .audio)?.uniqueID` and pass it. (PoC commit has the fix.)
- `minimumFrameInterval = CMTime(value: 1, timescale: fps)` is a **cap** — SCK is
  frame-on-change. A static screen delivers no frames (see §5 tail-frame patch).
- `queueDepth = 5`. Do not retain sample buffers beyond the callback except by design
  (ring buffer holds *compressed* video, not SCK surfaces; PCM copies for audio).
- `showsCursor = true` for v1 (cursor-as-data is ADR-008, deferred).
- Content enumeration: `SCShareableContent.excludingDesktopWindows(false,
  onScreenWindowsOnly: true)`. Returns **empty results, not an error**, when Screen
  Recording permission is missing.
- Sample handler queues must do minimal work. Video buffers: check
  `SCStreamFrameInfo.status == .complete` via attachments; `.idle`/incomplete frames are
  skipped (but see tail-frame patch).

## 2. TCC / permissions (both PoC field bugs lived here)

- **Screen & System Audio Recording** (`kTCCServiceScreenCapture`): covers system audio
  too. Preflight `CGPreflightScreenCaptureAccess()`; request
  `CGRequestScreenCaptureAccess()`. Grant is per code-signing identity; the granted app
  must be **fully restarted** (all processes) to pick it up.
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
  BPP ≈ 0.05 and an HEVC discount ≈ 0.6. Presets:
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
  (HFP/A2DP limitation, not our bug — surface in UI copy). Watch for **format changes
  mid-stream** (device switch, e.g. AirPods die → built-in mic takes over): compare
  `CMSampleBufferGetFormatDescription` against the input's; on change, v1 policy is
  end-recording-cleanly with a notification (ADR-007). Do not attempt live format
  switching in v1.
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
- **Crash safety**: `writer.movieFragmentInterval = CMTime(seconds: 10)` on `.mov`.
  Empirically (PoC, `kill -9`): SCRecordingOutput survived with sub-second loss; our
  writer must match — the kill test in 04-testing is a **required** M2 acceptance gate.
  `shouldOptimizeForNetworkUse` is NOT crash safety (moov placement at finalize only).

## 6. File output

- Container: `.mov` (required for fragment intervals). Name: `Recording yyyy-MM-dd at
  HH.mm.ss.mov`; replays `Replay yyyy-MM-dd at HH.mm.ss.mov`. Default dir `~/Movies`
  (§2). User-configurable dir must pass the `opendir` preflight at selection time AND at
  record time.

## 7. Long-recording robustness

- `SleepGuard`: `ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled,
  .userInitiated], reason: "Recording")` while recording or replay-armed; end it after.
  Display sleep still ends the stream — that's a clean finalize, acceptable.
- Display unplug / resolution change / user lock → `didStopWithError` → finalize + notify.
  Never attempt hot re-attach in v1 (ADR-007).
- Disk-full: watch `recordedFileSize` growth vs `volumeAvailableCapacityForImportantUsage`;
  stop cleanly at < 2 GB free with notification.
- OBS reports rare SCK stalls on multi-hour Sequoia sessions; our watchdog: if no video
  buffer arrives for 30 s AND the screen isn't static (heuristic: any input event seen),
  log it; do not auto-restart in v1.

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
  start error to ≤ 1 s. Memory at 60 s: ~80 MB video + ~46 MB PCM audio. Fine.
- Mux on demand: snapshot under lock → oldest keyframe ≥ N s back → rebase PTS → one
  AVAssetWriter: video input `outputSettings: nil` + `sourceFormatHint` (passthrough);
  two AAC audio inputs encoded from PCM at mux time. Write on a utility queue; the ring
  keeps rolling. Duplicate-hotkey during mux: coalesce (ignore while mux in flight).
- Hotkey: Carbon `RegisterEventHotKey` (works without Accessibility/Input-Monitoring
  permission, unlike `NSEvent.addGlobalMonitor`). Default ⌥⌘R, configurable in M6.
- OS note: Apple ships `SCClipBufferingOutput` (native rolling buffer) in the macOS 27
  beta cycle — our design keeps `ReplayEncoder+RingBuffer` behind a small interface so it
  can be swapped for the OS implementation later (ADR-005).

## 10. CLI/dev environment gotchas (bit us in the PoC)

- ⚠️ `recordedDuration`/CMTime can be **invalid → `.seconds` = NaN → `Int(NaN)` traps**.
  Guard every CMTime→display conversion with `.isFinite`.
- stdout is block-buffered when not a TTY: `setvbuf(stdout, nil, _IONBF, 0)` in the CLI
  so crashes can't eat diagnostics.
- Bare executables get TCC attribution from the parent terminal; granting Screen
  Recording requires **quitting the whole terminal app** (all tabs = one process).
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

import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import os

/// Owns the single `SCStream`'s lifecycle and publishes `EngineEvent`s. In M1-T2 it
/// detects the first complete video frame (`.started`) and clean/error termination;
/// sample fan-out to consumers arrives with `SampleRouter` (M1-T3).
public actor CaptureEngine {
    /// Event stream (unbounded-buffered, so events emitted before the caller starts
    /// iterating are still delivered). `nonisolated` + `let` so callers read it without
    /// `await` and background SCK callbacks can yield without hopping onto the actor.
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let continuation: AsyncStream<EngineEvent>.Continuation

    /// Fan-out for captured buffers. Consumers (MovieRecorder, ReplayEncoder) attach here;
    /// the engine attaches its own started-detector. Thread-safe, so `nonisolated`.
    public nonisolated let router: SampleRouter

    private let configuration: CaptureConfiguration
    private let sleepGuard = SleepGuard()
    private var stream: SCStream?
    private var handler: StreamHandler?

    /// Emits `.microphoneLost` if a selected mic stops delivering (docs/02 §4, ADR-012); nil
    /// when no mic was selected. Polled by `microphoneWatchdogTask` while capture runs.
    private let microphoneWatchdog: MicrophoneWatchdog?
    private var microphoneWatchdogTask: Task<Void, Never>?

    /// Logs a wedged capture — video silent while the user is active (docs/02 §7). Diagnostic
    /// only: v1 never auto-restarts, this exists so a soak can be explained afterwards.
    private let stallWatchdog: StallWatchdog
    private var stallWatchdogTask: Task<Void, Never>?

    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "capture")

    private enum State { case idle, starting, running, terminated }
    private var state: State = .idle
    /// Set if stop() arrives while start() is still suspended (actor reentrancy); start()
    /// honors it — with the requested reason — when it resumes, rather than bringing up an
    /// unstoppable stream.
    private var stopRequested = false
    private var requestedStopReason: EndReason = .userStopped
    /// Orthogonal to `state` (the stream stays `.running` while paused, still delivering
    /// buffers that the recorder drops); gates `pause`/`resume` so each event fires once.
    private var isPaused = false

    // One serial queue per output type per engine — SCK requires per-output sample-handler
    // queues, and handlers must stay light (docs/01 concurrency rules). Instance-scoped so
    // two engines (e.g. record + replay, M5) never serialize through shared globals.
    private let screenQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.screen")
    private let audioQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.audio")
    private let microphoneQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.microphone")

    public init(configuration: CaptureConfiguration) {
        self.configuration = configuration
        (self.events, self.continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        self.router = SampleRouter()
        // Only a mic that was actually selected can be lost.
        if case .device = configuration.microphone {
            let continuation = self.continuation
            microphoneWatchdog = MicrophoneWatchdog { continuation.yield(.microphoneLost) }
        } else {
            microphoneWatchdog = nil
        }
        stallWatchdog = StallWatchdog { seconds in
            Self.log.warning(
                """
                Capture stalled: no video for \(Int(seconds), privacy: .public)s while the user \
                was active. The stream is likely wedged (docs/02 §7). Not restarting — v1 policy.
                """)
        }
        // `.started` = first complete video frame. The router already drops incomplete
        // frames, so the first `.screen` buffer the detector sees is exactly that.
        router.attach(StartedDetector(continuation: continuation))
        if let microphoneWatchdog { router.attach(microphoneWatchdog) }
        router.attach(stallWatchdog)
    }

    public func start() async {
        guard state == .idle else { return }
        state = .starting
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if stopRequested { return terminate(requestedStopReason) }

            switch Self.startDecision(
                screenPermission: Permissions.screenRecordingState(),
                availableDisplays: content.displays.count
            ) {
            case .fail(let message):
                return failToStart(message)
            case .proceed:
                break
            }

            guard let display = resolveDisplay(from: content) else {
                return failToStart("No display matched the requested selection.")
            }

            let handler = StreamHandler(router: router) { [weak self] error in
                Task { await self?.terminate(Self.endReason(forStreamError: error)) }
            }
            let (filter, streamConfig) = makeStreamConfiguration(for: display)
            let stream = SCStream(filter: filter, configuration: streamConfig, delegate: handler)
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: screenQueue)
            try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: audioQueue)
            if case .device = configuration.microphone {
                try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: microphoneQueue)
            }
            try await stream.startCapture()

            if stopRequested {
                try? await stream.stopCapture()
                return terminate(requestedStopReason)
            }
            // `terminate()` can have run reentrantly while we were suspended (a stream error
            // hops onto the actor). Don't resurrect a dead engine — and don't arm a watchdog
            // that the already-finished `terminate()` will never cancel.
            guard state == .starting else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            self.handler = handler
            state = .running
            sleepGuard.begin(reason: "Recording the screen")
            startWatchdogs()
        } catch {
            failToStart(Self.startErrorMessage(error))
        }
    }

    /// Clean stop, carrying the end `reason` (default `.userStopped`; a monitor passes a
    /// fail-stop reason like `.microphoneChanged`). Safe at any point: during `start()`'s
    /// suspension it records the request *and its reason* for `start()` to honor on resume;
    /// while running it stops the stream; after termination it is a no-op.
    public func stop(reason: EndReason = .userStopped) async {
        switch state {
        case .idle, .terminated:
            return
        case .starting:
            stopRequested = true
            requestedStopReason = reason
        case .running:
            // Disarm BEFORE tearing the stream down. `stopCapture` halts delivery and can take
            // seconds (Bluetooth teardown), and a monitor still polling across that suspension
            // reports on a recording that is perfectly complete: the mic watchdog would call it
            // a disconnect, and the stall watchdog — with frames already stopped and the user's
            // just-pressed stop hotkey making them look "active" — would call it a wedge.
            cancelWatchdogs()
            if let stream {
                try? await stream.stopCapture()
            }
            terminate(reason)
        }
    }

    /// Pause the recording. The `SCStream` keeps running (SCK still delivers buffers, the
    /// recorder drops them) and the paused span is removed from the output timeline (docs/02
    /// §5). Emits `.paused`. No-op unless actively running and not already paused.
    public func pause() {
        guard state == .running, !isPaused else { return }
        isPaused = true
        continuation.yield(.paused)
    }

    /// Resume after `pause()`; the recorder re-anchors on the next complete video frame.
    /// Emits `.resumed`. No-op unless currently paused.
    public func resume() {
        guard state == .running, isPaused else { return }
        isPaused = false
        continuation.yield(.resumed)
    }

    // MARK: - Single termination authority (state-guarded, actor-isolated)

    private func failToStart(_ message: String) {
        guard state != .terminated else { return }
        state = .terminated
        sleepGuard.end()  // idempotent; failToStart precedes begin(), kept for symmetry
        continuation.yield(.failed(message: message))
        continuation.finish()
    }

    /// Starts the health monitors for as long as capture runs (see `pollingTask` for the
    /// cancellation and handle-retention rules these depend on).
    private func startWatchdogs() {
        if let microphoneWatchdog {
            microphoneWatchdogTask = pollingTask(every: MicrophoneWatchdog.checkInterval) {
                microphoneWatchdog.check()
            }
        }
        let stallWatchdog = self.stallWatchdog
        stallWatchdogTask = pollingTask(every: StallWatchdog.checkInterval) { stallWatchdog.check() }
    }

    private func cancelWatchdogs() {
        microphoneWatchdogTask?.cancel()
        microphoneWatchdogTask = nil
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
    }

    /// Dropping a `Task` reference does not cancel it, so an engine released while running —
    /// never stopped, no stream error — would otherwise leave the poll loops waking forever.
    deinit {
        microphoneWatchdogTask?.cancel()
        stallWatchdogTask?.cancel()
    }

    private func terminate(_ reason: EndReason) {
        guard state != .terminated else { return }
        state = .terminated
        cancelWatchdogs()
        sleepGuard.end()
        continuation.yield(.stopped(reason))
        continuation.finish()
        stream = nil
        handler = nil
    }

    private func resolveDisplay(from content: SCShareableContent) -> SCDisplay? {
        switch configuration.display {
        case .main:
            return content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
        case .id(let id):
            return content.displays.first { $0.displayID == id }
        }
    }

    private func makeStreamConfiguration(for display: SCDisplay) -> (SCContentFilter, SCStreamConfiguration) {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let (width, height) = CaptureConfiguration.pixelDimensions(
            pointSize: filter.contentRect.size,
            pointPixelScale: CGFloat(filter.pointPixelScale)
        )
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        // Clamp the public, unvalidated fps: 0/negative yields an invalid CMTime SCK
        // rejects, and a value above Int32.max would trap the CMTimeScale initializer.
        let fps = min(max(configuration.frameRateCap, 1), 240)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5
        config.showsCursor = true
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        if case .device(let id) = configuration.microphone {
            config.captureMicrophone = true
            config.microphoneCaptureDeviceID = id
        }
        return (filter, config)
    }

    // MARK: - Pure decisions (unit-tested with injected state)

    enum StartDecision: Equatable {
        case proceed
        case fail(String)
    }

    /// ⚠️ **Zero shareable displays never proves a missing grant.** An *ungranted* process does
    /// not enumerate zero — `SCShareableContent` **throws** "The user declined TCCs…" (docs/02
    /// §10, measured in M1-T2), which `start()`'s catch turns into `permissionGuidance` via
    /// `startErrorMessage`. So reaching this function at all means enumeration succeeded, i.e.
    /// we are authorized in fact; and the only measured zero-display state is a screen that is
    /// locked **and** slept (docs/02 §7). Blaming permission here sent users to System Settings
    /// to grant what they already held (verified live by locking the screen).
    ///
    /// Deliberately does NOT consult the preflight to decide: `CGPreflightScreenCaptureAccess()`
    /// is documented to false-negative for freshly-built CLI binaries that capture fine (docs/02
    /// §10), so trusting it would resurrect the same misdiagnosis on exactly that path.
    ///
    /// `.denied` is honored defensively though the public API cannot currently produce it —
    /// `Permissions.screenRecordingState()` only ever returns `.granted` or `.notDetermined`.
    static func startDecision(screenPermission: PermissionState, availableDisplays: Int) -> StartDecision {
        if screenPermission == .denied { return .fail(permissionGuidance) }
        guard availableDisplays > 0 else { return .fail(noDisplaysGuidance) }
        return .proceed
    }

    /// Maps a start-time error to a user-facing message. The ungranted-permission case
    /// arrives as a thrown SCK "user declined" error (docs/02 §2/§10) — translate it to
    /// actionable guidance instead of the raw TCC string. Matches by SCK domain+code with
    /// a message fallback so it holds even if the code constant shifts.
    static func startErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let isSCK = nsError.domain == SCStreamError.errorDomain
        let isDecline = (isSCK && nsError.code == SCStreamError.Code.userDeclined.rawValue)
            || error.localizedDescription.range(of: "declined", options: .caseInsensitive) != nil
        if isDecline { return permissionGuidance }
        // The display can also vanish *inside* the start window (enumeration succeeds, then
        // `startCapture` throws). Same condition as the two sibling paths — say the same thing
        // rather than leaking a raw SCK string on the one surface that missed it.
        if isSCK, nsError.code == SCStreamError.Code.noCaptureSource.rawValue { return noDisplaysGuidance }
        return error.localizedDescription
    }

    /// Classifies an unexpected stream death into the most specific `EndReason` we can (docs/01),
    /// so the file's stated cause is meaningful rather than a raw SCK string.
    ///
    /// Measured (2026-07-15, `pmset displaysleepnow` mid-recording): a display going away ends
    /// the stream with `.noCaptureSource`. ⚠️ **Lid-close and monitor-unplug are NOT yet
    /// observed** (STATUS → Needs Franco) — they may land on a different code, which is exactly
    /// why unmapped errors keep their raw code in the message. Carrying the code is how
    /// `.noCaptureSource` was identified rather than guessed; don't remove it.
    ///
    /// `.systemSleep` stays unreachable on purpose: nothing we have measured distinguishes it,
    /// and faking the distinction would be worse than leaving the case unused (docs/02 §7).
    static func endReason(forStreamError error: Error) -> EndReason {
        let nsError = error as NSError
        guard nsError.domain == SCStreamError.errorDomain else {
            return .streamError(error.localizedDescription)
        }
        switch nsError.code {
        case SCStreamError.Code.noCaptureSource.rawValue:  // measured: the display went away
            return .displayDisconnected
        case SCStreamError.Code.noDisplayList.rawValue:    // same family; unobserved, by kinship
            return .displayDisconnected
        case SCStreamError.Code.userStopped.rawValue:
            // The user stopped us from the system's screen-recording indicator. Ordinary, not a
            // failure — mapping it anywhere else makes ADR-007 treat the most normal stop there
            // is as a fail-stop, and M4 would fire an "ended unexpectedly" notification for it.
            return .userStopped
        default:
            return .streamError("\(error.localizedDescription) [SCStreamError \(nsError.code)]")
        }
    }

    static let noDisplaysGuidance =
        "No displays are available to capture — the screen is locked or asleep, or no display "
        + "is connected. Unlock and wake the screen, then try again."

    static let permissionGuidance =
        "Screen Recording permission is needed. Grant it in System Settings → Privacy & Security "
        + "→ Screen & System Audio Recording, then quit and reopen."
}

/// SCK delegate + output sink. A separate `@unchecked Sendable` class because SCK
/// callbacks arrive on background queues; it maps the SCK output type to `SourceType`,
/// forwards every buffer to the router, and hands unexpected stream death to the actor
/// (which owns termination). Stateless beyond its injected dependencies.
private final class StreamHandler: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private let router: SampleRouter
    private let onStreamStopped: @Sendable (Error) -> Void

    init(router: SampleRouter, onStreamStopped: @escaping @Sendable (Error) -> Void) {
        self.router = router
        self.onStreamStopped = onStreamStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let source: SourceType
        switch type {
        case .screen: source = .screen
        case .audio: source = .systemAudio
        case .microphone: source = .microphone
        @unknown default: return
        }
        router.route(sampleBuffer, type: source)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped(error)
    }
}

/// Emits `.started` on the first complete video frame it sees. Attached to the engine's
/// router; the router has already dropped incomplete frames, so the first `.screen`
/// buffer here is the first real frame. A `.started` yielded after the stream finished is
/// a harmless no-op (AsyncStream drops post-finish yields).
private final class StartedDetector: SampleConsumer, @unchecked Sendable {
    private let continuation: AsyncStream<EngineEvent>.Continuation
    private let lock = NSLock()
    private var emitted = false

    init(continuation: AsyncStream<EngineEvent>.Continuation) {
        self.continuation = continuation
    }

    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .screen else { return }
        lock.lock()
        let isFirst = !emitted
        emitted = true
        lock.unlock()
        if isFirst { continuation.yield(.started) }
    }
}

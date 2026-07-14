import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

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

    private enum State { case idle, starting, running, terminated }
    private var state: State = .idle
    /// Set if stop() arrives while start() is still suspended (actor reentrancy); start()
    /// honors it when it resumes rather than bringing up an unstoppable stream.
    private var stopRequested = false
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
        // `.started` = first complete video frame. The router already drops incomplete
        // frames, so the first `.screen` buffer the detector sees is exactly that.
        router.attach(StartedDetector(continuation: continuation))
    }

    public func start() async {
        guard state == .idle else { return }
        state = .starting
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if stopRequested { return terminate(.userStopped) }

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
                Task { await self?.terminate(.streamError(error.localizedDescription)) }
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
                return terminate(.userStopped)
            }
            self.stream = stream
            self.handler = handler
            state = .running
            sleepGuard.begin(reason: "Recording the screen")
        } catch {
            failToStart(Self.startErrorMessage(error))
        }
    }

    /// Clean, user-initiated stop. Safe at any point: during `start()`'s suspension it
    /// records a request that `start()` honors on resume; while running it stops the
    /// stream; after termination it is a no-op.
    public func stop() async {
        switch state {
        case .idle, .terminated:
            return
        case .starting:
            stopRequested = true
        case .running:
            if let stream {
                try? await stream.stopCapture()
            }
            terminate(.userStopped)
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

    private func terminate(_ reason: EndReason) {
        guard state != .terminated else { return }
        state = .terminated
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

    /// The primary live signal for missing Screen Recording permission is that
    /// `SCShareableContent` returns zero displays (docs/02 §1); it can also *throw*
    /// (see `startErrorMessage`). `.denied` is handled defensively though the public API
    /// can't currently produce it.
    static func startDecision(screenPermission: PermissionState, availableDisplays: Int) -> StartDecision {
        if screenPermission == .denied || availableDisplays == 0 {
            return .fail(permissionGuidance)
        }
        return .proceed
    }

    /// Maps a start-time error to a user-facing message. The ungranted-permission case
    /// arrives as a thrown SCK "user declined" error (docs/02 §2/§10) — translate it to
    /// actionable guidance instead of the raw TCC string. Matches by SCK domain+code with
    /// a message fallback so it holds even if the code constant shifts.
    static func startErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let isDecline = (nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3801)
            || error.localizedDescription.range(of: "declined", options: .caseInsensitive) != nil
        return isDecline ? permissionGuidance : error.localizedDescription
    }

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

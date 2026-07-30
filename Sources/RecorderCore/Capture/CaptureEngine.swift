import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import os

/// Owns the single `SCStream`'s lifecycle and publishes `EngineEvent`s.
public actor CaptureEngine {
    /// What this engine is for. Only reaches the sleep assertion's reason string, which is
    /// user-visible in `pmset -g assertions` — every stream holds one (ADR-018), so it has to
    /// name the right one.
    public enum Purpose: CaseIterable, Sendable {
        case recording
        case replayBuffer
        /// The CLI's `engine-smoke` / `probe-stream`.
        case diagnostic

        var assertionReason: String {
            switch self {
            case .recording: "Recording the screen"
            case .replayBuffer: "Instant replay is armed"
            case .diagnostic: "Capturing the screen"
            }
        }
    }

    /// Event stream. Unbounded-buffered, so events emitted before the caller iterates are
    /// still delivered; `nonisolated` so SCK callbacks yield without hopping onto the actor.
    public nonisolated let events: AsyncStream<EngineEvent>
    private nonisolated let continuation: AsyncStream<EngineEvent>.Continuation

    /// Fan-out for captured buffers; consumers attach here. Thread-safe, so `nonisolated`.
    public nonisolated let router: SampleRouter

    private let configuration: CaptureConfiguration
    private let purpose: Purpose
    private let sleepGuard = SleepGuard()
    private var stream: SCStream?
    private var handler: StreamHandler?

    /// Emits `.microphoneLost` if a selected mic stops delivering (docs/02 §4, ADR-012); nil
    /// when no mic was selected.
    private let microphoneWatchdog: MicrophoneWatchdog?
    private var microphoneWatchdogTask: Task<Void, Never>?
    /// Splices a returned mic back in via a mic-only stream (M8-T2); nil when no mic.
    private let microphoneRescue: MicrophoneRescue?

    /// Reports a mic that is connected but delivering nothing (M16-T4); nil when no mic.
    private let microphoneSilenceWatchdog: MicrophoneSilenceWatchdog?
    private var microphoneSilenceTask: Task<Void, Never>?

    /// Logs a wedged capture — video silent while the user is active (docs/02 §7). Diagnostic
    /// only: v1 never auto-restarts. Nil under an app filter (`attachesStallWatchdog`).
    private let stallWatchdog: StallWatchdog?
    private var stallWatchdogTask: Task<Void, Never>?

    /// App-scoped capture only: ends the session when the recorded app quits, since SCK keeps
    /// the stream alive and silent instead of erroring (docs/02 §1a). A window filter needs no
    /// equivalent — it *does* error when its window goes away (docs/02 §1c).
    private var appTerminationWatch: AppTerminationWatch?

    private static let log = Logger(subsystem: "dev.fcostantini.screenrec", category: "capture")

    private enum State { case idle, starting, running, terminated }
    private var state: State = .idle
    /// Set if stop() arrives while start() is still suspended (actor reentrancy); start()
    /// honors it on resume rather than bringing up an unstoppable stream.
    private var requestedStopReason: EndReason?
    /// Orthogonal to `state`: the stream stays `.running` while paused, still delivering
    /// buffers that the recorder drops. Gates `pause`/`resume` so each event fires once.
    private var isPaused = false

    // SCK requires per-output sample-handler queues, and handlers must stay light (docs/01).
    // Instance-scoped so two engines never serialize through shared globals.
    private let screenQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.screen")
    private let audioQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.audio")
    private let microphoneQueue = DispatchQueue(label: "dev.fcostantini.screenrec.capture.microphone")

    public init(configuration: CaptureConfiguration, purpose: Purpose) {
        self.configuration = configuration
        self.purpose = purpose
        (self.events, self.continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        self.router = SampleRouter()
        if case .device(let deviceID) = configuration.microphone {
            let continuation = self.continuation
            let rescue = MicrophoneRescue(
                policy: configuration.microphoneRecovery, pickedDeviceID: deviceID, router: router,
                onLoss: { continuation.yield(.microphoneLost) },
                onSpliced: { continuation.yield(.microphoneRecovered) })
            microphoneRescue = rescue
            microphoneWatchdog = rescue.watchdog
            microphoneSilenceWatchdog = MicrophoneSilenceWatchdog(
                onSilent: { continuation.yield(.microphoneSilent) },
                onAudible: { continuation.yield(.microphoneAudible) })
        } else {
            microphoneWatchdog = nil
            microphoneRescue = nil
            microphoneSilenceWatchdog = nil
        }
        if Self.attachesStallWatchdog(to: configuration.content) {
            stallWatchdog = StallWatchdog { seconds in
                Self.log.warning(
                    """
                    Capture stalled: no video for \(Int(seconds), privacy: .public)s while the user \
                    was active. The stream is likely wedged (docs/02 §7). Not restarting — v1 policy.
                    """)
            }
        } else {
            stallWatchdog = nil
        }
        router.attach(StartedDetector(continuation: continuation))
        if let microphoneWatchdog { router.attach(microphoneWatchdog) }
        if let microphoneSilenceWatchdog { router.attach(microphoneSilenceWatchdog) }
        if let stallWatchdog { router.attach(stallWatchdog) }
    }

    /// The live mic level for a UI meter (M16-T5); nil when no mic is selected. `nonisolated` so a
    /// menu-bar frame never awaits the actor to draw.
    public nonisolated var microphoneLevel: MicrophoneLevelSource? { microphoneSilenceWatchdog }

    public func start() async {
        guard state == .idle else { return }
        state = .starting
        do {
            let content = try await SCShareableContent.forCapture()
            if let requestedStopReason { return terminate(requestedStopReason) }

            switch Self.startDecision(
                screenPermission: Permissions.screenRecordingState(),
                availableDisplays: content.displays.count,
                content: configuration.content,
                runningBundleIDs: content.applications.map(\.bundleIdentifier)
            ) {
            case .fail(let message):
                return failToStart(message)
            case .proceed:
                break
            }

            let scope: CaptureScope
            switch resolveScope(from: content) {
            case .fail(let message): return failToStart(message)
            case .ok(let resolved): scope = resolved
            }

            // Hoisted: the handler is `@Sendable` and runs off the actor, so it can't read
            // `configuration` when a stream error arrives.
            let capturedContent = configuration.content
            let handler = StreamHandler(router: router) { [weak self] error in
                Task {
                    await self?.terminate(
                        Self.endReason(forStreamError: error, content: capturedContent))
                }
            }
            let filter = scope.filter
            let regionRender: RegionRender?
            if case .region(_, let rect) = configuration.content {
                switch Self.resolveRegion(
                    rect: rect, displayPointSize: filter.contentRect.size,
                    scale: CGFloat(filter.pointPixelScale)
                ) {
                case .fail(let message): return failToStart(message)
                case .ok(let render): regionRender = render
                }
            } else {
                regionRender = nil
            }
            let streamConfig = makeStreamConfiguration(for: filter, region: regionRender)
            let stream = SCStream(filter: filter, configuration: streamConfig, delegate: handler)
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: screenQueue)
            try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: audioQueue)
            if case .device = configuration.microphone {
                try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: microphoneQueue)
            }
            try await stream.startCapture()

            if let requestedStopReason {
                try? await stream.stopCapture()
                return terminate(requestedStopReason)
            }
            // `terminate()` can run reentrantly across the suspension (a stream error hops onto
            // the actor); don't resurrect a dead engine or arm watchdogs it will never cancel.
            guard state == .starting else {
                try? await stream.stopCapture()
                return
            }
            self.stream = stream
            self.handler = handler
            state = .running
            sleepGuard.begin(reason: purpose.assertionReason)
            startWatchdogs()
            if let owningApp = scope.owningApp {
                appTerminationWatch = AppTerminationWatch(processID: owningApp.processID) { [weak self] in
                    Task { await self?.stop(reason: .appQuit) }
                }
            }
        } catch {
            failToStart(Self.startErrorMessage(error))
        }
    }

    /// Clean stop carrying the end `reason`. Safe at any point: during `start()`'s suspension
    /// it records the request for `start()` to honor on resume; after termination it is a no-op.
    public func stop(reason: EndReason = .userStopped) async {
        switch state {
        case .idle, .terminated:
            return
        case .starting:
            requestedStopReason = reason
        case .running:
            // Disarm before teardown: `stopCapture` halts delivery and can take seconds
            // (Bluetooth), so watchdogs still polling across it would false-fire on a
            // perfectly complete recording.
            cancelWatchdogs()
            if let stream {
                try? await stream.stopCapture()
            }
            terminate(reason)
        }
    }

    /// Pause the recording. The `SCStream` keeps running (the recorder drops buffers) and the
    /// paused span is removed from the output timeline (docs/02 §5). Emits `.paused`.
    public func pause() {
        guard state == .running, !isPaused else { return }
        isPaused = true
        continuation.yield(.paused)
    }

    /// Resume after `pause()`; the recorder re-anchors on the next complete video frame.
    /// Emits `.resumed`.
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

    private func startWatchdogs() {
        if let microphoneWatchdog {
            microphoneWatchdogTask = pollingTask(every: MicrophoneWatchdog.checkInterval) {
                microphoneWatchdog.check()
            }
        }
        if let stallWatchdog {
            stallWatchdogTask = pollingTask(every: StallWatchdog.checkInterval) { stallWatchdog.check() }
        }
        if let microphoneSilenceWatchdog {
            microphoneSilenceTask = pollingTask(every: MicrophoneSilenceWatchdog.checkInterval) {
                microphoneSilenceWatchdog.check()
            }
        }
    }

    private func cancelWatchdogs() {
        microphoneWatchdogTask?.cancel()
        microphoneWatchdogTask = nil
        stallWatchdogTask?.cancel()
        stallWatchdogTask = nil
        microphoneSilenceTask?.cancel()
        microphoneSilenceTask = nil
        appTerminationWatch?.cancel()
        appTerminationWatch = nil
        microphoneRescue?.cancel()
    }

    /// Dropping a `Task` reference does not cancel it: an engine released while running would
    /// otherwise leave the poll loops waking forever.
    deinit {
        microphoneWatchdogTask?.cancel()
        stallWatchdogTask?.cancel()
        microphoneSilenceTask?.cancel()
        appTerminationWatch?.cancel()
        microphoneRescue?.cancel()
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

    /// A resolved `ContentSelection`: the SCK filter, plus the app whose termination ends the
    /// session (`.app` only — nil everywhere else).
    private struct CaptureScope {
        let filter: SCContentFilter
        let owningApp: SCRunningApplication?
    }

    private enum ScopeResolution {
        case ok(CaptureScope)
        case fail(String)
    }

    /// Binds the configured content against the live shareable content. Every failure here is
    /// loud: a missing app, window or display never falls back to capturing something else
    /// (docs/02 §1a, §1b, §1c).
    private func resolveScope(from content: SCShareableContent) -> ScopeResolution {
        switch configuration.content {
        case .window(let windowID, let ownerBundleID):
            // Desktop-independent: no display is resolved, and the filter's `contentRect` is the
            // window's rather than a display's.
            guard let window = content.windows.first(where: { $0.windowID == windowID }),
                  Self.windowOwnerMatches(window.owningApplication?.bundleIdentifier, ownerBundleID)
            else {
                return .fail(Self.windowUnavailableMessage)
            }
            Self.connectToWindowServer()
            // No `AppTerminationWatch`: SCK ends a window stream itself when the window goes —
            // whether it was closed or its app quit — and always beats a process watch.
            return .ok(CaptureScope(
                filter: SCContentFilter(desktopIndependentWindow: window), owningApp: nil))
        case .app(let bundleID):
            guard let display = resolveDisplay(.main, from: content) else {
                return .fail(Self.noDisplayMatchedMessage)
            }
            guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
                return .fail(Self.appUnavailableMessage(bundleID: bundleID))
            }
            return .ok(CaptureScope(
                filter: SCContentFilter(display: display, including: [app], exceptingWindows: []),
                owningApp: app))
        case .display(let selection), .region(let selection, _):
            guard let display = resolveDisplay(selection, from: content) else {
                return .fail(Self.noDisplayMatchedMessage)
            }
            return .ok(CaptureScope(
                filter: SCContentFilter(display: display, excludingWindows: []), owningApp: nil))
        case .displayExcluding(let selection, let bundleID):
            guard let display = resolveDisplay(selection, from: content) else {
                return .fail(Self.noDisplayMatchedMessage)
            }
            // An app that isn't listed can't be excluded, and losing the whole take over it would
            // be the worse outcome (the ADR-012 trade): record everything and report the gap.
            guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleID })
            else {
                continuation.yield(.excludedAppUnavailable(bundleID: bundleID))
                return .ok(CaptureScope(
                    filter: SCContentFilter(display: display, excludingWindows: []), owningApp: nil))
            }
            return .ok(CaptureScope(
                filter: SCContentFilter(
                    display: display, excludingApplications: [app], exceptingWindows: []),
                owningApp: nil))
        }
    }

    /// ⚠️ `SCContentFilter(desktopIndependentWindow:)` **traps** with `CGS_REQUIRE_INIT` in a
    /// process that has never talked to the window server — a plain CLI binary, which is exactly
    /// the headless verify surface (docs/02 §1c). Any CoreGraphics display call establishes the
    /// connection; a GUI host already has it, so this is a no-op there. Enumeration and
    /// `SCWindow.frame` do *not* need it, so the trap only appears at filter construction.
    private static func connectToWindowServer() {
        _ = CGMainDisplayID()
    }

    private func resolveDisplay(
        _ selection: DisplaySelection, from content: SCShareableContent
    ) -> SCDisplay? {
        switch selection {
        case .main:
            let main = content.displays.first { $0.displayID == CGMainDisplayID() }
            // A region's rect is tied to one display's geometry; never fall back to another display
            // for it (M13-T4) — that would crop the wrong content. Whole-screen/app may fall back.
            return Self.allowsDisplayFallback(for: configuration.content)
                ? (main ?? content.displays.first) : main
        case .id(let id):
            return content.displays.first { $0.displayID == id }
        }
    }

    /// Whether a missing `.main` display may fall back to any available display. Whole-screen and
    /// app capture can (record whatever's there); a region cannot — a wrong display would crop the
    /// wrong content, so it fails loud instead ("No display matched"). A window resolves no
    /// display at all, and a substitute one would not contain it.
    static func allowsDisplayFallback(for content: ContentSelection) -> Bool {
        switch content {
        case .display, .app, .displayExcluding: true
        case .region, .window: false
        }
    }

    private func makeStreamConfiguration(
        for filter: SCContentFilter, region: RegionRender?
    ) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        if let region {
            // Crop to the region: SCK captures `sourceRect` (display points) into a
            // region-sized output. `width`/`height` already match the crop 1:1 (docs/02 §1b).
            config.sourceRect = region.sourceRect
            config.width = region.width
            config.height = region.height
        } else {
            let (width, height) = CaptureConfiguration.pixelDimensions(
                pointSize: filter.contentRect.size,
                pointPixelScale: CGFloat(filter.pointPixelScale)
            )
            // A window can be an odd number of points wide and encoders want even chroma
            // dimensions (docs/02 §1c). Displays are even already; regions floor in `resolveRegion`.
            let snapped: Bool
            if case .window = configuration.content { snapped = true } else { snapped = false }
            config.width = snapped ? Self.evenFloor(width) : width
            config.height = snapped ? Self.evenFloor(height) : height
        }
        // Clamp the public, unvalidated fps: 0/negative yields a CMTime SCK rejects, and a
        // value above Int32.max traps the CMTimeScale initializer.
        let fps = min(max(configuration.frameRateCap, 1), 240)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5
        config.showsCursor = true
        var microphoneID: String?
        if case .device(let id) = configuration.microphone { microphoneID = id }
        config.applyAudioCapture(
            systemAudio: configuration.capturesSystemAudio, microphoneID: microphoneID)
        return config
    }

    // MARK: - Pure decisions (unit-tested with injected state)

    enum StartDecision: Equatable {
        case proceed
        case fail(String)
    }

    /// Zero shareable displays never proves a missing grant: an ungranted process makes
    /// `SCShareableContent` throw "user declined" (docs/02 §10), handled by `startErrorMessage`.
    /// The only measured zero-display state is a locked *and* slept screen (docs/02 §7).
    /// Deliberately ignores `CGPreflightScreenCaptureAccess()` — it false-negatives for
    /// freshly-built CLI binaries that capture fine (docs/02 §10). `.denied` is handled
    /// defensively; `Permissions.screenRecordingState()` cannot currently return it.
    static func startDecision(
        screenPermission: PermissionState, availableDisplays: Int,
        content: ContentSelection, runningBundleIDs: [String]
    ) -> StartDecision {
        if screenPermission == .denied { return .fail(permissionGuidance) }
        guard availableDisplays > 0 else { return .fail(noDisplaysGuidance) }
        if case .app(let bundleID) = content, !runningBundleIDs.contains(bundleID) {
            return .fail(appUnavailableMessage(bundleID: bundleID))
        }
        return .proceed
    }

    /// The shareable applications only list apps with on-screen content, so "not listed"
    /// covers both not-running and nothing-visible. Surface-neutral copy (M6-T3).
    static func appUnavailableMessage(bundleID: String) -> String {
        "\"\(bundleID)\" isn't running or has nothing on screen to capture. "
            + "Open the app, then try again."
    }

    /// A window id is not stable across a relaunch of its app (docs/02 §1c), so a stale pick is
    /// the failure this path will mostly see — the copy names it. Surface-neutral (M6-T3).
    /// Whether a resolved window's owner satisfies the pick's expectation. Nil expectation ⇒ the
    /// caller named a freshly-listed id and there is nothing to check; otherwise the owners must
    /// match, which is what stops a **reused** window id binding a different app's window to a
    /// pick restored from disk (docs/02 §1c).
    static func windowOwnerMatches(_ actual: String?, _ expected: String?) -> Bool {
        guard let expected else { return true }
        return actual == expected
    }

    static let windowUnavailableMessage =
        "That window isn't on screen any more. It was closed, or its app was relaunched and "
        + "gave it a new number — choose the window again."

    static let noDisplayMatchedMessage = "No display matched the requested selection."

    /// The stall watchdog's premise — user active ⇒ frames expected — only holds for
    /// whole-display capture: under an app filter the user can be active all day in an app
    /// that isn't being recorded (docs/02 §7). A `.region` is a display-filter capture
    /// (frame-on-change from the whole display), so it inherits the display path's behavior.
    /// A `.window` can be minimised or fully occluded while the user works elsewhere, so it
    /// follows `.app`.
    static func attachesStallWatchdog(to content: ContentSelection) -> Bool {
        switch content {
        // An excluding filter is the display path with a hole in it: same frame-on-change
        // delivery, so the same watchdog (docs/02 §1a's `.app` continuous rate doesn't apply).
        case .display, .region, .displayExcluding: true
        case .app, .window: false
        }
    }

    /// A region resolved against its display: the crop in display points plus the output pixel
    /// size (even-snapped). `sourceRect` is trimmed so it maps 1:1 onto `width`×`height`.
    struct RegionRender: Equatable {
        let sourceRect: CGRect
        let width: Int
        let height: Int
    }

    enum RegionDecision: Equatable {
        case ok(RegionRender)
        case fail(String)
    }

    /// Resolves a region (display points, top-left origin — docs/02 §1b) against the display,
    /// clamping an edge-straddle. Fails loud when non-finite/non-positive, off the display, or
    /// under 2 px. Output pixels floor even (encoders want even chroma dims) and `sourceRect` is
    /// trimmed to `evenPx / scale`, floored so it never overruns the clamped edge.
    static func resolveRegion(
        rect: CGRect, displayPointSize: CGSize, scale: CGFloat
    ) -> RegionDecision {
        // `scale` is a display's backing factor (≥ 1); a width == 0 short-circuits before the
        // division below, so scale is never a divide-by-zero here and needs no guard.
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0 else {
            return .fail(regionInvalidSizeMessage(rect: rect))
        }
        let clamped = rect.intersection(CGRect(origin: .zero, size: displayPointSize))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else {
            return .fail(regionOffScreenMessage(rect: rect, displayPointSize: displayPointSize))
        }
        // Floor (not round) to whole even pixels so `sourceRect = px / scale` can never overrun
        // the clamped edge; the epsilon absorbs float error so an exact N.0 keeps N, not N−1.
        let width = evenFloor(Int(clamped.width * scale + 1e-6))
        let height = evenFloor(Int(clamped.height * scale + 1e-6))
        guard width > 0, height > 0 else { return .fail(regionTooSmallMessage) }
        let sourceRect = CGRect(
            x: clamped.origin.x, y: clamped.origin.y,
            width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return .ok(RegionRender(sourceRect: sourceRect, width: width, height: height))
    }

    /// Largest even integer ≤ `value` (assumed ≥ 0).
    private static func evenFloor(_ value: Int) -> Int { value - (value % 2) }

    static func regionInvalidSizeMessage(rect: CGRect) -> String {
        "The capture region needs a positive width and height "
            + "(got width \(coordinate(rect.width)), height \(coordinate(rect.height)))."
    }

    static func regionOffScreenMessage(rect: CGRect, displayPointSize: CGSize) -> String {
        "The capture region (x \(coordinate(rect.origin.x)), y \(coordinate(rect.origin.y)), "
            + "\(coordinate(rect.width))×\(coordinate(rect.height)) pt) doesn't overlap the "
            + "\(coordinate(displayPointSize.width))×\(coordinate(displayPointSize.height))-pt "
            + "display. Pick a region that's on screen."
    }

    static let regionTooSmallMessage =
        "The capture region is too small — it rounds to fewer than 2 pixels. Choose a larger region."

    /// Formats a coordinate without a trailing `.0` for whole values; guards the `Int` cast
    /// against non-finite/huge inputs so an off-screen message can't trap.
    private static func coordinate(_ value: CGFloat) -> String {
        guard value.isFinite else { return "\(value)" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    /// Maps a start-time error to user-facing guidance. Ungranted permission arrives as a
    /// thrown SCK "user declined" error (docs/02 §2/§10). Matches by SCK domain+code with a
    /// message fallback, in case the code constant shifts.
    static func startErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let isSCK = nsError.domain == SCStreamError.errorDomain
        let isDecline = (isSCK && nsError.code == SCStreamError.Code.userDeclined.rawValue)
            || error.localizedDescription.range(of: "declined", options: .caseInsensitive) != nil
        if isDecline { return permissionGuidance }
        // The display can vanish *inside* the start window: enumeration succeeds, then
        // `startCapture` throws.
        if isSCK, nsError.code == SCStreamError.Code.noCaptureSource.rawValue { return noDisplaysGuidance }
        return error.localizedDescription
    }

    /// Classifies an unexpected stream death into the most specific `EndReason` (docs/01).
    /// Measured: a display going away ends the stream with `.noCaptureSource`. Lid-close and
    /// monitor-unplug are unobserved and may use other codes — unmapped errors keep their raw
    /// code in the message so it can be identified rather than guessed. Display sleep, screen lock
    /// and lid-close all arrive as the same code, so none of them gets its own reason (docs/02 §7).
    ///
    /// `content` disambiguates: the same "no capture source" code means the *display* went away
    /// under a display filter and the *window* went away under a window filter (docs/02 §1c) —
    /// measured both ways. Reporting a closed window as a disconnected display would be a lie.
    static func endReason(forStreamError error: Error, content: ContentSelection) -> EndReason {
        let nsError = error as NSError
        guard nsError.domain == SCStreamError.errorDomain else {
            return .streamError(error.localizedDescription)
        }
        let sourceGone: EndReason
        if case .window = content { sourceGone = .windowClosed } else { sourceGone = .displayDisconnected }
        switch nsError.code {
        case SCStreamError.Code.noCaptureSource.rawValue:  // measured: the source went away
            return sourceGone
        case SCStreamError.Code.noDisplayList.rawValue:    // same family; unobserved, by kinship
            return sourceGone
        case SCStreamError.Code.userStopped.rawValue:
            // Stopped from the system's screen-recording indicator: an ordinary stop, not a
            // fail-stop (ADR-007).
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

/// SCK delegate + output sink: forwards buffers to the router and hands unexpected stream
/// death to the actor, which owns termination. `@unchecked Sendable` because SCK callbacks
/// arrive on background queues; stateless beyond its injected dependencies.
private final class StreamHandler: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private let router: SampleRouter
    private let onStreamStopped: @Sendable (Error) -> Void
    /// Normalizes mic buffers to the one fixed format before fan-out (M8-T1), so no consumer
    /// ever sees a device format. Touched only on the microphone queue.
    private let microphoneResampler = ResampledMicInput()

    init(router: SampleRouter, onStreamStopped: @escaping @Sendable (Error) -> Void) {
        self.router = router
        self.onStreamStopped = onStreamStopped
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            router.route(sampleBuffer, type: .screen)
        case .audio:
            router.route(sampleBuffer, type: .systemAudio)
        case .microphone:
            // A failed conversion drops one ~20 ms buffer — better than routing a format the
            // welded writer input can't take.
            guard let normalized = microphoneResampler.convert(sampleBuffer) else { return }
            router.route(normalized, type: .microphone)
        @unknown default:
            return
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamStopped(error)
    }
}

/// Emits `.started` on the first complete video frame. The router drops incomplete frames,
/// so the first `.screen` buffer here is the first real frame. Yielding after the stream
/// finished is a harmless no-op (AsyncStream drops post-finish yields).
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

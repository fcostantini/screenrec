import CoreGraphics
import CoreMedia
import Foundation

/// Reports a capture that has silently stopped delivering video while the user is active —
/// the rare multi-hour SCK stall (docs/02 §7). v1 only reports it; no auto-restart.
///
/// "No frames" alone means nothing: SCK is frame-on-change, so a static screen legitimately
/// delivers nothing for minutes. Silence is only evidence when crossed with user input.
///
/// Known false positive on multiple displays: the idle probe is machine-wide but capture is
/// scoped to one display, so a user working on an uncaptured display reads as active while the
/// captured one is legitimately static. macOS exposes no per-display input signal; the cost is
/// noise in a diagnostic log, never a lost recording.
///
/// Re-arms on the next frame, unlike the mic watchdog's one-shot latch: a stall may pass.
final class StallWatchdog: SampleConsumer, @unchecked Sendable {
    /// docs/02 §7. Long enough that ordinary hitches (a slow app, a Spaces switch) don't trip it.
    static let defaultTimeout: TimeInterval = 30
    /// Suggested `check()` cadence; detection latency is bounded by `timeout` + this.
    static let checkInterval: TimeInterval = 5

    private let timeout: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let secondsSinceUserInput: @Sendable () -> TimeInterval
    private let onStall: @Sendable (TimeInterval) -> Void

    private let lock = NSLock()
    private var lastFrameAt: TimeInterval?
    private var hasReported = false

    /// `secondsSinceUserInput` defaults to CoreGraphics, not `NSEvent`: its global monitors are
    /// AppKit (banned in RecorderCore, docs/01) and permission-gated, adding a TCC prompt.
    /// Spelled as a closure literal because a bare `Self.systemIdleSeconds` method reference
    /// converts a non-Sendable function value and warns.
    init(
        timeout: TimeInterval = StallWatchdog.defaultTimeout,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        secondsSinceUserInput: @escaping @Sendable () -> TimeInterval = { StallWatchdog.systemIdleSeconds() },
        onStall: @escaping @Sendable (TimeInterval) -> Void
    ) {
        self.timeout = timeout
        self.now = now
        self.secondsSinceUserInput = secondsSinceUserInput
        self.onStall = onStall
    }

    /// Seconds since a *human* last did anything (key, mouse, trackpad).
    ///
    /// `.hidSystemState`, not `.combinedSessionState`: the combined state also counts
    /// programmatically posted events, so a mouse jiggler on an unattended machine would read
    /// as "someone is here" and manufacture a false stall. HID state is hardware only.
    static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEventType)
    }

    /// `kCGAnyInputEventType` — CoreGraphics ships no Swift symbol, so it is spelled via its raw
    /// value (0xFFFFFFFF). Non-nil by invariant: `CGEventType` defines a case at that value
    /// (`.tapDisabledByUserInput`), but naming it directly would misstate intent.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    /// A video frame is proof the stream is alive. Runs on the screen queue.
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .screen else { return }
        lock.lock(); defer { lock.unlock() }
        lastFrameAt = now()
        hasReported = false  // re-arm: the stream is back
    }

    /// Report once per stall episode if video has been silent past `timeout` *while the user was
    /// active*. Silent before the first frame: a capture that never started isn't a stall.
    func check() {
        let currentTime = now()          // probes stay outside the lock — one is a syscall
        let idleSeconds = secondsSinceUserInput()
        lock.lock()
        var stalledFor: TimeInterval?
        if !hasReported, let last = lastFrameAt {
            let silence = currentTime - last
            // The test is *recent* activity, not "any input since the last frame"
            // (`idleSeconds < silence`): one inert keypress yields no frame and leaves idle
            // permanently behind silence, reporting a stall forever on an untouched machine.
            if silence >= timeout, idleSeconds < timeout {
                hasReported = true
                stalledFor = silence
            }
        }
        lock.unlock()
        if let stalledFor { onStall(stalledFor) }  // outside the lock — it is non-reentrant
    }
}

import CoreGraphics
import CoreMedia
import Foundation

/// Reports a capture that has silently stopped delivering video while the user is actively
/// using the machine — the rare multi-hour SCK stall OBS sees on Sequoia (docs/02 §7).
///
/// ⚠️ **"No frames" on its own means nothing.** SCK is frame-on-change, so a static screen
/// legitimately delivers nothing for minutes — G2 §3.4 measured 14 s of it, and the tail-frame
/// patch exists precisely because of it. Silence is only evidence when crossed with **user
/// input**: if nobody has touched the machine, no frames is the correct behavior; if they are
/// typing and moving the mouse and we *still* see nothing, the stream is wedged.
///
/// v1 only reports it — **no auto-restart** (docs/02 §7). The point is that a 2-hour soak
/// (M6-T2) can be diagnosed afterwards instead of guessed at.
///
/// ⚠️ **Known false positive: multiple displays.** The idle probe is machine-wide but capture is
/// scoped to one display, so a user working on an *uncaptured* second display reads as "active"
/// while the captured display is legitimately static — and each repaint re-arms us, so a long
/// session can log this repeatedly. macOS exposes no per-display input signal to cross-check
/// against, so this is accepted rather than faked: the cost is noise in a diagnostic log, never
/// a user-visible failure or a lost recording. Weigh it when reading a multi-display soak.
///
/// Re-arms on the next frame, unlike the mic watchdog's one-shot latch: a mic disconnect is
/// permanent (measured, 02 §4) but a stall may pass, and a second one is worth a second report.
///
/// Clock and idle probe are both injected, so tests need neither real time nor real input.
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

    /// `secondsSinceUserInput` defaults to CoreGraphics. ⚠️ Not `NSEvent`: its global monitors
    /// are AppKit (banned in RecorderCore, docs/01) *and* permission-gated, which would drag a
    /// whole new TCC prompt into a diagnostic nobody asked for (docs/02 §7).
    ///
    /// The default is spelled as a closure literal rather than a bare `Self.systemIdleSeconds`
    /// method reference: the reference form converts a non-Sendable function value and warns,
    /// and with no CI the build loop is the only gate we have (CLAUDE.md) — a standing warning
    /// is how the next real one gets scrolled past.
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
    /// `.hidSystemState`, not `.combinedSessionState`: the combined state also counts events
    /// **posted programmatically** into the session, so a mouse jiggler / keep-awake utility —
    /// or anything else synthesising input — would read as "someone is here" on an unattended
    /// machine and manufacture the exact false stall this cross-check exists to prevent.
    /// HID state is hardware only, which is the question actually being asked.
    static func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInputEventType)
    }

    /// `kCGAnyInputEventType` — "any input event at all". CoreGraphics ships no Swift symbol for
    /// it, so it must be spelled via its raw value (0xFFFFFFFF). The initializer cannot return
    /// nil: `CGEventType` defines a case at exactly that value (`.tapDisabledByUserInput`), which
    /// is why naming that case directly would compile but read as a flat lie about intent.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    /// `SampleConsumer`: a video frame is proof the stream is alive. Runs on the screen queue.
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .screen else { return }
        lock.lock(); defer { lock.unlock() }
        lastFrameAt = now()
        hasReported = false  // re-arm: whatever we may have reported, the stream is back
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
            // ⚠️ The test is **recent** activity, not "any input since the last frame". The
            // latter (`idleSeconds < silence`) looks equivalent and is not: one inert keypress —
            // a lone modifier changes nothing on screen, so it yields no frame — leaves idle
            // permanently one second behind silence, so it stays true forever *after the user
            // walks away*, and every poll then reports a stall on an untouched machine. That is
            // the coffee-break cry-wolf this class exists to avoid.
            if silence >= timeout, idleSeconds < timeout {
                hasReported = true
                stalledFor = silence
            }
        }
        lock.unlock()
        if let stalledFor { onStall(stalledFor) }  // outside the lock — it is non-reentrant
    }
}

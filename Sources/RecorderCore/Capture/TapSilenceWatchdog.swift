import Foundation

/// Decides when a running process tap has stopped carrying audio (M27-T4).
///
/// 🔴 Silence alone cannot be the signal. An **ungranted tap delivers zeros while reporting
/// `OSStatus 0`** (measured, docs/07) — and so does a Mac with nothing playing. The two are
/// identical on the wire, so the cross-check is what makes the notice trustworthy: **the audio
/// system says something is producing output, and the tap hears nothing**. Without it this would
/// fire on every quiet recording, and a warning nobody believes is a warning nobody reads.
///
/// Pure decision, injected clocks and probes — the tap owns one and polls it.
final class TapSilenceWatchdog: @unchecked Sendable {
    /// Suggested `check()` cadence; notice latency is the run length plus this.
    static let checkInterval: TimeInterval = 1
    /// Below this a buffer counts as carrying nothing. Matches `MicrophoneSilence.floor`'s intent:
    /// far under anything audible, above float noise.
    static let floor: Float = 0.0005

    private let duration: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let isAnythingPlaying: @Sendable () -> Bool
    private let onSilent: @Sendable () -> Void

    private let lock = NSLock()
    /// When the current unbroken run of silent buffers began; nil once anything audible lands.
    private var quietSince: TimeInterval?
    private var hasReported = false

    /// `systemUptime` is monotonic and doesn't advance across system sleep, so a napping Mac
    /// doesn't wake to a complaint about the nap.
    init(
        duration: TimeInterval = 5,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        isAnythingPlaying: @escaping @Sendable () -> Bool,
        onSilent: @escaping @Sendable () -> Void
    ) {
        self.duration = duration
        self.now = now
        self.isAnythingPlaying = isAnythingPlaying
        self.onSilent = onSilent
    }

    /// One buffer's loudest sample, from the tap's callback. Cheap by contract: the caller scans a
    /// subset, because this runs on a real-time audio thread.
    func note(peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        if peak >= Self.floor {
            quietSince = nil
            hasReported = false  // audible again: a later outage can be reported afresh
        } else if quietSince == nil {
            quietSince = now()
        }
    }

    /// Polled. Reports at most once per outage, and only when the silence is contradicted by
    /// something actually playing.
    func check() {
        lock.lock()
        guard !hasReported, let since = quietSince, now() - since >= duration else {
            lock.unlock()
            return
        }
        lock.unlock()

        // Probed outside the lock: it reads Core Audio, and the tap's callback must never wait.
        guard isAnythingPlaying() else { return }

        lock.lock()
        guard !hasReported else { return lock.unlock() }
        hasReported = true
        lock.unlock()
        onSilent()
    }
}

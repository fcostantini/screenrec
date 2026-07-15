import CoreMedia
import Foundation

/// Detects a microphone that was delivering buffers and then stopped. A lost mic does not
/// hand over to another device — its buffers simply stop (docs/02 §4) — so starvation is the
/// only available signal. Firing is a notification, not a termination: recording continues
/// and the mic track ends at the disconnect (ADR-012). One-shot: SCK never re-attaches a
/// pinned `microphoneCaptureDeviceID` once the device goes away, so there is nothing to
/// re-arm for. Pausing never stops the `SCStream`, so heartbeats continue while paused.
///
/// `consume` runs on the mic capture queue: state is lock-guarded (docs/01) and `onLoss`
/// fires outside the lock.
final class MicrophoneWatchdog: SampleConsumer, @unchecked Sendable {
    /// A mic quiet this long is disconnected, not merely silent: SCK delivers mic buffers
    /// continuously (~40/s) regardless of speech, and the worst measured starvation under
    /// heavy load (< 1 s) stays well clear.
    static let defaultTimeout: TimeInterval = 3
    /// Suggested `check()` cadence; detection latency is bounded by `timeout` + this.
    static let checkInterval: TimeInterval = 1

    private let timeout: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let onLoss: @Sendable () -> Void

    private let lock = NSLock()
    private var lastBufferAt: TimeInterval?
    private var hasFired = false

    /// `systemUptime` is monotonic and does not advance during system sleep, so a machine that
    /// slept for an hour doesn't wake and report the mic as lost.
    init(
        timeout: TimeInterval = MicrophoneWatchdog.defaultTimeout,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onLoss: @escaping @Sendable () -> Void
    ) {
        self.timeout = timeout
        self.now = now
        self.onLoss = onLoss
    }

    /// Every mic buffer is a heartbeat. Runs on the mic capture queue. The type filter is
    /// load-bearing: system-audio and screen buffers keep flowing after the mic dies.
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .microphone else { return }
        lock.lock(); defer { lock.unlock() }
        lastBufferAt = now()
    }

    /// Fire `onLoss` once if the mic has been quiet past `timeout`. Stays silent until at least
    /// one heartbeat lands: a mic that never delivered is covered by MovieRecorder's startup grace.
    func check() {
        lock.lock()
        let lost: Bool
        if !hasFired, let last = lastBufferAt, now() - last >= timeout {
            hasFired = true
            lost = true
        } else {
            lost = false
        }
        lock.unlock()
        if lost { onLoss() }  // outside the lock — it is non-reentrant
    }
}

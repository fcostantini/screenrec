import CoreMedia
import Foundation

/// Detects a microphone that was delivering buffers and then stopped. A lost mic does not
/// hand over to another device — its buffers simply stop (docs/02 §4) — so starvation is the
/// only available signal. Firing is a notification, not a termination: recording continues
/// (ADR-012). One-shot per loss: SCK never re-attaches a pinned device to the SAME stream —
/// `rearm()` restarts the cycle once a rescue stream splices (M8-T2), so repeated
/// case/uncase cycles each fire. Pausing never stops the `SCStream`, so heartbeats continue
/// while paused.
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

    private let lock = NSLock()
    private var onLoss: @Sendable () -> Void
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

    /// Replaces the loss handler — `MicrophoneRescue` chains itself behind the engine's event
    /// yield after both exist (neither can capture the other during its own init).
    func setOnLoss(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onLoss = handler
        lock.unlock()
    }

    /// Restart the loss cycle after a rescue splices (M8-T2). Clearing `lastBufferAt` keeps the
    /// re-armed watchdog silent until the rescue stream's first heartbeat actually lands.
    func rearm() {
        lock.lock()
        hasFired = false
        lastBufferAt = nil
        lock.unlock()
    }

    /// Fire `onLoss` once if the mic has been quiet past `timeout`. Stays silent until at least
    /// one heartbeat lands: a mic that never delivered is covered by MovieRecorder's startup grace.
    func check() {
        lock.lock()
        var fire: (@Sendable () -> Void)?
        if !hasFired, let last = lastBufferAt, now() - last >= timeout {
            hasFired = true
            fire = onLoss
        }
        lock.unlock()
        fire?()  // outside the lock — it is non-reentrant
    }
}

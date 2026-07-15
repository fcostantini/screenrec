import CoreMedia
import Foundation

/// Detects a microphone that was delivering buffers and then stopped — i.e. the device went
/// away. A lost mic does **not** hand over to another device; its buffers simply stop
/// (docs/02 §4, proved by the §4.2 run), so comparing formats can never catch this and
/// starvation is the only available signal.
///
/// Firing is a *notification*, not a termination: the recording continues and the mic track
/// just ends at the disconnect (ADR-012).
///
/// One-shot, and that is safe rather than merely convenient: a disconnect really is permanent
/// for the life of the stream. Verified 2026-07-15 — AirPods cased mid-recording and then
/// *reconnected* 20 s later never resumed delivery (mic track ended at 21.8 s of a 59.8 s
/// file). SCK does not re-attach a pinned `microphoneCaptureDeviceID` once the device goes
/// away, so there is no recovery to re-arm for.
///
/// Pause needs no handling here: pausing never stops the `SCStream` (M3-T1), so SCK keeps
/// delivering mic buffers and this keeps seeing heartbeats.
///
/// The clock is injectable and `check()` is driven by the owner, so tests exercise it without
/// real time. Attach to a `SampleRouter`: `consume` runs on the mic capture queue, so state is
/// lock-guarded (docs/01) and `onLoss` fires outside the lock.
final class MicrophoneWatchdog: SampleConsumer, @unchecked Sendable {
    /// A mic quiet this long has been disconnected, not merely silent: SCK delivers mic
    /// buffers continuously (~40/s) whether or not anyone is speaking, and the worst audio
    /// starvation measured under heavy load (< 1 s, M3-T1) stays well clear of it.
    static let defaultTimeout: TimeInterval = 3
    /// Suggested `check()` cadence; detection latency is bounded by `timeout` + this.
    static let checkInterval: TimeInterval = 1

    private let timeout: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let onLoss: @Sendable () -> Void

    private let lock = NSLock()
    private var lastBufferAt: TimeInterval?
    private var hasFired = false

    /// `systemUptime` is deliberate: it is monotonic (immune to wall-clock jumps) and does not
    /// advance while the system sleeps, so a machine that slept for an hour doesn't wake up and
    /// report the mic as lost — only time the mic could actually have been delivering counts.
    init(
        timeout: TimeInterval = MicrophoneWatchdog.defaultTimeout,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onLoss: @escaping @Sendable () -> Void
    ) {
        self.timeout = timeout
        self.now = now
        self.onLoss = onLoss
    }

    /// `SampleConsumer`: every mic buffer is a heartbeat. Runs on the mic capture queue.
    /// The type filter is load-bearing — system-audio and screen buffers keep flowing long
    /// after the mic dies, so counting them would mask exactly the loss we exist to catch.
    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        guard type == .microphone else { return }
        lock.lock(); defer { lock.unlock() }
        lastBufferAt = now()
    }

    /// Fire `onLoss` once if the mic has been quiet past `timeout`. A mic that never delivered
    /// at all is not "lost" — that is a mic that never worked, and `MovieRecorder`'s startup
    /// grace already covers it — so this stays silent until at least one heartbeat has landed.
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

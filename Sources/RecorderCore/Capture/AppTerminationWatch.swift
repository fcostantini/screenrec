import Foundation

/// Fires `onExit` exactly once when the watched process terminates. Event-driven
/// (`DispatchSourceProcess` over kqueue `NOTE_EXIT`) — no polling, no AppKit.
///
/// A source armed against an already-dead pid never signals, so liveness is probed with
/// `kill(pid, 0)` both before arming (fire immediately) and after (close the race where the
/// process exits mid-arm); the once-latch keeps the probe and the source from both firing.
final class AppTerminationWatch: @unchecked Sendable {
    private final class OnceLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        /// True exactly once, for the first caller.
        func firstFire() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let isFirst = !fired
            fired = true
            return isFirst
        }
    }

    private var source: DispatchSourceProcess?

    init(processID: pid_t, onExit: @escaping @Sendable () -> Void) {
        let latch = OnceLatch()
        let fireOnce: @Sendable () -> Void = {
            if latch.firstFire() { onExit() }
        }
        func hasExited() -> Bool { kill(processID, 0) != 0 && errno == ESRCH }

        guard !hasExited() else {
            fireOnce()
            return
        }
        // No private queue: the once-latch already serializes the handler against the probes.
        let source = DispatchSource.makeProcessSource(identifier: processID, eventMask: .exit)
        source.setEventHandler(handler: fireOnce)
        self.source = source
        source.activate()
        if hasExited() { fireOnce() }
    }

    /// Idempotent. A fire already in flight is harmless to this class's callers: the engine's
    /// `stop(reason:)` no-ops once terminated.
    func cancel() {
        source?.cancel()
        source = nil
    }

    deinit {
        source?.cancel()
    }
}

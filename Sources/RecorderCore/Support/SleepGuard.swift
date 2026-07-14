import Foundation

/// Holds a system activity assertion so the Mac won't idle-sleep mid-capture (docs/02 §7).
/// Display sleep / lid close can still end the stream — that's a clean finalize, which is
/// acceptable (ADR-007). `begin`/`end` are idempotent and thread-safe.
public final class SleepGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var token: NSObjectProtocol?

    public init() {}

    /// True while an assertion is held. Exposed for tests.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return token != nil
    }

    public func begin(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )
    }

    public func end() {
        lock.lock()
        let current = token
        token = nil
        lock.unlock()
        if let current {
            ProcessInfo.processInfo.endActivity(current)
        }
    }
}

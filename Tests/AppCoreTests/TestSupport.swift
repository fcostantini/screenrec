import Foundation

/// Records what an injected `@Sendable` closure was handed, since the models take their side
/// effects as closures and a plain `var` can't be captured by one.
final class Box<Value>: @unchecked Sendable {
    var value: Value?
}

/// A thread-safe latch for `withObservationTracking`'s `@Sendable onChange`.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    func raise() { lock.lock(); raised = true; lock.unlock() }
}

/// Records the *order* an injected `@Sendable` closure was called in — `Box` holds one value, and a
/// queue's contract is a sequence. Lock-guarded because the export closures are `@Sendable`.
final class Trail: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var items: [String] { lock.lock(); defer { lock.unlock() }; return entries }
    func append(_ entry: String) { lock.lock(); entries.append(entry); lock.unlock() }
}

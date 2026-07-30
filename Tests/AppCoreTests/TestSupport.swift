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

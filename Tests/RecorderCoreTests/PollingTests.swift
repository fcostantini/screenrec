import Foundation
import Testing
@testable import RecorderCore

/// Every watchdog in the app rides this loop — the disk guard, the mic watchdogs, the stall
/// detector. Two properties matter: it keeps ticking, and it *stops* on cancel. A loop that
/// survived cancellation would report on a recording that already finished (docs/01).
@Suite struct PollingTests {

    /// Ticks are counted from the polling task; the test thread reads them.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    @Test func ticksRepeatedlyUntilCancelled() async throws {
        let counter = Counter()
        let task = pollingTask(every: 0.01) { counter.increment() }
        defer { task.cancel() }

        try await Task.sleep(for: .milliseconds(150))
        #expect(counter.value >= 3, "a loop that fires once is not a poll")
    }

    @Test func cancellationExitsTheLoopInsteadOfTickingOnce() async throws {
        // ⚠️ The window is deliberately much shorter than the interval. `Task.sleep` throws the
        // *instant* the task is cancelled, so a loop that swallowed that error (`try?` instead of
        // `catch { return }`) ticks immediately — landing after teardown, when the owner still
        // looks alive. A loop that returns can't tick again until +300 ms, long after this check.
        let counter = Counter()
        let task = pollingTask(every: 0.3) { counter.increment() }

        try await Task.sleep(for: .milliseconds(400))
        let atCancel = counter.value
        #expect(atCancel == 1)

        task.cancel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(counter.value == atCancel, "ticked after cancel")
    }

    @Test func doesNotTickBeforeTheFirstInterval() async throws {
        // The sleep comes first on purpose — a watchdog that fires at t=0 reports on a session
        // that hasn't produced anything yet.
        let counter = Counter()
        let task = pollingTask(every: 5) { counter.increment() }
        defer { task.cancel() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.value == 0)
    }
}

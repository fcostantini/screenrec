import Foundation
import Testing
@testable import RecorderCore

/// Every watchdog in the app rides this loop — the disk guard, the mic watchdogs, the stall
/// detector. Two properties matter: it keeps ticking, and it *stops* on cancel. A loop that
/// survived cancellation would report on a recording that already finished (docs/01).
///
/// ⚠️ These run alongside the whole suite, so nothing here may assume a tick lands on schedule:
/// wait for observations with a generous deadline, and never assert a count from a fixed sleep
/// (that flaked the gate once — docs/07).
@Suite struct PollingTests {

    /// Ticks are counted from the polling task; the test thread reads them.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    /// Polls until `condition` holds, or gives up after `seconds`. Returns whether it held.
    private func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func ticksRepeatedlyUntilCancelled() async {
        let counter = Counter()
        let task = pollingTask(every: 0.01) { counter.increment() }
        defer { task.cancel() }

        // Deadline, not a fixed sleep: a loaded machine may deliver these late, but a loop that
        // fires once and stops never reaches three however long we wait.
        #expect(await waitUntil(5) { counter.value >= 3 }, "a loop that fires once is not a poll")
    }

    @Test func cancellationExitsTheLoopInsteadOfTickingOnce() async throws {
        // `Task.sleep` throws the *instant* the task is cancelled, so a loop that swallowed that
        // error (`try?` instead of `catch { return }`) ticks immediately — landing after teardown,
        // when the owner still looks alive. This waits for a real tick first, so the loop is known
        // to be a full interval away from its next one, then cancels and looks in a window far
        // shorter than that interval: only the broken form can tick there.
        let counter = Counter()
        let task = pollingTask(every: 1) { counter.increment() }
        defer { task.cancel() }

        #expect(await waitUntil(10) { counter.value >= 1 })
        let atCancel = counter.value
        task.cancel()

        try await Task.sleep(for: .milliseconds(150))
        #expect(counter.value == atCancel, "ticked after cancel")
    }

    @Test func doesNotTickBeforeTheFirstInterval() async throws {
        // The sleep comes first on purpose — a watchdog that fires at t=0 reports on a session
        // that hasn't produced anything yet. (Load can only delay a tick, so this can't flake.)
        let counter = Counter()
        let task = pollingTask(every: 5) { counter.increment() }
        defer { task.cancel() }

        try await Task.sleep(for: .milliseconds(50))
        #expect(counter.value == 0)
    }
}

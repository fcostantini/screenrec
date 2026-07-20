import Foundation
import Testing
@testable import RecorderCore

@Suite struct AppTerminationWatchTests {

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var value: Bool {
            lock.lock(); defer { lock.unlock() }
            return raised
        }
        func raise() {
            lock.lock(); defer { lock.unlock() }
            raised = true
        }
    }

    @Test func firesWhenTheWatchedProcessExits() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.2"]
        try process.run()

        let fired = Flag()
        let watch = AppTerminationWatch(processID: process.processIdentifier) { fired.raise() }
        defer { watch.cancel() }

        let deadline = Date().addingTimeInterval(5)
        while !fired.value, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(fired.value)
    }

    @Test func firesImmediatelyForAnAlreadyExitedProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()  // reaped — the pid is genuinely gone, not a zombie

        let fired = Flag()
        let watch = AppTerminationWatch(processID: process.processIdentifier) { fired.raise() }
        defer { watch.cancel() }
        #expect(fired.value)
    }
}

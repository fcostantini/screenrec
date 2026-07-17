import Foundation
import Testing

@testable import RecorderCore

/// Real files, real dispatch sources, no TCC — the sentinel is fully headless-testable.
struct RecordingFileSentinelTests {

    private final class IncidentLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [RecordingFileSentinel.Incident] = []
        let signal = DispatchSemaphore(value: 0)

        func record(_ incident: RecordingFileSentinel.Incident) {
            lock.lock(); stored.append(incident); lock.unlock()
            signal.signal()
        }
        var incidents: [RecordingFileSentinel.Incident] {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }

    private func makeTempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Recording test.mov.partial")
        try Data("payload".utf8).write(to: url)
        return url
    }

    @Test func moveIsRestoredAndReported() throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let latch = IncidentLatch()
        let sentinel = try #require(RecordingFileSentinel(url: url) { latch.record($0) })
        defer { sentinel.cancel() }

        let elsewhere = url.deletingLastPathComponent().appendingPathComponent("stolen.mov.partial")
        try FileManager.default.moveItem(at: url, to: elsewhere)

        #expect(latch.signal.wait(timeout: .now() + 5) == .success)
        // The `from` path comes from F_GETPATH, which resolves the /var → /private/var symlink
        // while Foundation's resolvingSymlinksInPath refuses to — so match on the name, not
        // the prefix.
        #expect(latch.incidents.count == 1)
        guard case .movedAndRestored(let from)? = latch.incidents.first else {
            Issue.record("expected movedAndRestored, got \(latch.incidents)")
            return
        }
        #expect(from.hasSuffix("/stolen.mov.partial"))
        // The file is back where it belongs, contents intact.
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: url) == Data("payload".utf8))
    }

    @Test func deleteIsFatalAndReported() throws {
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let latch = IncidentLatch()
        let sentinel = try #require(RecordingFileSentinel(url: url) { latch.record($0) })
        defer { sentinel.cancel() }

        try FileManager.default.removeItem(at: url)

        #expect(latch.signal.wait(timeout: .now() + 5) == .success)
        #expect(latch.incidents == [.deleted])
    }

    @Test func cancelSilencesTheSentinel() throws {
        // The owner's own finalize rename must not be reported — cancel comes first.
        let url = try makeTempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let latch = IncidentLatch()
        let sentinel = try #require(RecordingFileSentinel(url: url) { latch.record($0) })

        sentinel.cancel()
        let final = url.deletingPathExtension()
        try FileManager.default.moveItem(at: url, to: final)

        #expect(latch.signal.wait(timeout: .now() + 1) == .timedOut)
        #expect(latch.incidents.isEmpty)
        #expect(FileManager.default.fileExists(atPath: final.path))   // rename stood
    }

    @Test func missingFileYieldsNilNotACrash() {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("never-existed-\(UUID().uuidString).mov.partial")
        #expect(RecordingFileSentinel(url: ghost) { _ in } == nil)
    }
}

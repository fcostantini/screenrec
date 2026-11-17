import Foundation
import RecorderCore
import UploadCore

@testable import AppCore

// Stand-ins the upload tests share: what was posted, what the uploader and the exporter were
// handed, and a gate that holds a fake open.

final class Posted: @unchecked Sendable {
    private let lock = NSLock()
    private var notices: [RecordingNotification] = []

    func append(_ notice: RecordingNotification) { lock.withLock { notices.append(notice) } }
    var all: [RecordingNotification] { lock.withLock { notices } }
}

final class Calls: @unchecked Sendable {
    struct Call {
        let file: URL
        let metadata: VideoMetadata
        let accessToken: String
    }

    private let lock = NSLock()
    private var calls: [Call] = []

    func record(file: URL, metadata: VideoMetadata, accessToken: String) {
        lock.withLock { calls.append(Call(file: file, metadata: metadata, accessToken: accessToken)) }
    }
    var all: [Call] { lock.withLock { calls } }
}

final class Exported: @unchecked Sendable {
    struct Export {
        let source: URL
        let range: ExportRange?
        let crop: CropRect?
    }

    private let lock = NSLock()
    private var exports: [Export] = []

    func record(source: URL, range: ExportRange?, crop: CropRect?) {
        lock.withLock { exports.append(Export(source: source, range: range, crop: crop)) }
    }
    var all: [Export] { lock.withLock { exports } }
}

/// Holds a fake transfer open until the test lets it through.
final class Gate: @unchecked Sendable {
    private let (stream, continuation) = AsyncStream<Void>.makeStream()

    func wait() async { for await _ in stream { return } }
    func open() { continuation.yield() }

    /// The test's side of a step it expects the code to reach: one that never comes has to fail
    /// the test, not hang the suite. The limit is long because the whole suite shares the main
    /// actor, and a step can queue for seconds behind other tests.
    func reached() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.wait() }
            group.addTask { try? await Task.sleep(nanoseconds: 30_000_000_000) }
            await group.next()
            group.cancelAll()
        }
    }
}

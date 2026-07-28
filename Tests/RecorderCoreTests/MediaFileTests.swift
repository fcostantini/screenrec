import AVFoundation
import Foundation
import Testing
@testable import RecorderCore

/// What the menu's recent rows read to say `— 23:04` (M18-T3). Every failure mode here is a row
/// that lies or a menu open that stalls, so nil has to mean nil for each of them.
@Suite struct MediaFileTests {

    @Test func readsTheLengthOfARealRecording() async throws {
        let url = try await makeAudioOnlyClip(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let duration = try #require(await MediaFile.duration(of: url))
        #expect(duration > 1.5 && duration < 2.5)
    }

    @Test func returnsNilForAFileThatIsNotMedia() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notmedia-\(UUID().uuidString).mov")
        try Data("this is not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // A `.mov` extension on arbitrary bytes is exactly what a torn file looks like; the row
        // must fall back to name + size rather than print a made-up length.
        #expect(await MediaFile.duration(of: url) == nil)
    }

    @Test func returnsNilForAFileThatIsGone() async {
        // The menu holds URLs across opens, so a trashed file is read at least once (M18-T3).
        #expect(await MediaFile.duration(
            of: URL(fileURLWithPath: "/tmp/gone-\(UUID().uuidString).mov")) == nil)
    }
}

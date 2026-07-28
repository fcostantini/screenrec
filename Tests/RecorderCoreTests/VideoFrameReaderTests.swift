import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// The frame source behind `Save as GIF`. Its own logic is the fps subsample — the composition
/// scales, but `AVAssetReaderVideoCompositionOutput` ignores `frameDuration` and emits one frame
/// per *source* frame, so the cap is `readFrames`' own PTS gate. Break that and a GIF silently
/// carries every source frame.
@Suite struct VideoFrameReaderTests {

    @Test func refusesAFileWithNoVideoTrack() async throws {
        let url = try await makeAudioOnlyClip(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: VideoFrameReader.ReaderError.noVideoTrack) {
            _ = try await VideoFrameReader.make(
                input: url, maxWidth: 480, maxHeight: 480, fps: 15, maxSeconds: 30)
        }
    }

    @Test func reportsAnUnreadableFileByName() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notaclip-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // The message reaches the user, so it has to name the file rather than quote CoreMedia.
        do {
            _ = try await VideoFrameReader.make(
                input: url, maxWidth: 480, maxHeight: 480, fps: 15, maxSeconds: 30)
            Issue.record("expected a throw")
        } catch let error as VideoFrameReader.ReaderError {
            guard case .unreadable(let message) = error else {
                Issue.record("expected .unreadable, got \(error)")
                return
            }
            #expect(message.contains(url.lastPathComponent))
        }
    }

    /// Gated like the other encoder-backed suites: building the fixture runs the VT encoder.
    /// `SCREENREC_HW_ENCODE_TESTS=1 swift test --filter VideoFrameReaderTests`, and the release
    /// gate runs it on every cut.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func capsTheFrameRateAndScalesToTheFittedSize() async throws {
        let source = try await Self.makeClip(width: 640, height: 360, frames: 60)  // 2 s at 30 fps
        defer { try? FileManager.default.removeItem(at: source) }

        let reader = try await VideoFrameReader.make(
            input: source, maxWidth: 320, maxHeight: 320, fps: 10, maxSeconds: 30)

        #expect(reader.size.width == 320)          // 640×360 fitted under 320
        #expect(reader.size.height == 180)
        #expect(reader.frameDuration == 0.1)
        #expect(reader.sourceSeconds > 1.5)

        var frames = 0
        var sizes: Set<String> = []
        try reader.readFrames { image in
            frames += 1
            sizes.insert("\(image.width)×\(image.height)")
        }
        // 2 s at 10 fps ≈ 20 frames, not the 60 the source holds: the gate subsampled.
        #expect(frames >= 17 && frames <= 23, "read \(frames) frames")
        #expect(sizes == ["320×180"])
    }

    // MARK: - Fixture

    private static let fps = 30

    private static func makeClip(width: Int, height: Int, frames: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vfr-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: fps, preset: .balanced,
            includesMicrophone: false, includesSystemAudio: false)
        for index in 0..<frames {
            recorder.consume(
                makeVideoSampleBuffer(
                    width: width, height: height,
                    pts: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)),
                    duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                    shade: UInt8(index * 4)),
                type: .screen)
            // Pace the feed so the encoder keeps up — an instant burst drops most frames to
            // warmup, leaving a source too sparse to exercise the subsample (GifExporterTests).
            usleep(12_000)
        }
        return try await recorder.finish()
    }
}

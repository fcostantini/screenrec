import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import RecorderCore

@Suite struct TrimmerTests {

    // MARK: - Pure / guards

    @Test func trimmedSiblingAppendsTrimmed() {
        let input = URL(fileURLWithPath: "/tmp/Recording 2026.mov")
        #expect(Trimmer.trimmedSibling(of: input).lastPathComponent == "Recording 2026 trimmed.mov")
    }

    @Test func rejectsOutputEqualToInput() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-same-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: TrimError.outputCollidesWithInput) {
            _ = try await Trimmer.trim(from: url, to: url, start: 0, end: 1)
        }
    }

    @Test func rejectsAnEmptyRange() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-empty-\(UUID().uuidString).mov")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-empty-out-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: source) }

        await #expect(throws: TrimError.emptyRange) {
            _ = try await Trimmer.trim(from: source, to: output, start: 5, end: 5)
        }
    }

    // MARK: - Integration (gated — the fixture build uses the VT encoder; the trim itself doesn't)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func trimsLosslesslyPreservingTheCodec() async throws {
        let source = try await Self.makeClip(seconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-out-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await Trimmer.trim(from: source, to: output, start: 0.5, end: 1.5)

        let asset = AVURLAsset(url: output)
        let videoTrack = try #require(
            try await asset.load(.tracks).first { $0.mediaType == .video })
        // Same codec as the source — a copy, not a re-encode.
        #expect(try await Self.subtype(of: videoTrack) == kCMVideoCodecType_HEVC)
        #expect(try await asset.load(.isPlayable))

        // Exact 1 s window (the passthrough export trims via an edit list).
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 1.0) < 0.2)
        #expect(abs(result.duration - duration) < 0.05)

        // A start past the clip end clamps to the asset duration → an empty range (the second
        // guard, after the duration is loaded), not a truncated or empty file.
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-past-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: empty) }
        await #expect(throws: TrimError.emptyRange) {
            _ = try await Trimmer.trim(from: source, to: empty, start: 100, end: 101)
        }
    }

    // MARK: - Fixtures

    private static func makeClip(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let fps = 30
        let recorder = try MovieRecorder(
            outputURL: url, frameRate: fps, preset: .balanced, includesMicrophone: false)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        for index in 0..<(fps * seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            recorder.consume(
                makeVideoSampleBuffer(
                    width: 640, height: 360, pts: pts,
                    duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                    shade: UInt8(truncatingIfNeeded: index * 8)),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 48_000 / fps, pts: pts),
                type: .systemAudio)
            usleep(8_000)  // pace the feed so frames survive encoder warmup (a ~2 s clip)
        }
        return try await recorder.finish()
    }

    private static func subtype(of track: AVAssetTrack) async throws -> FourCharCode {
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetMediaSubType(descriptions[0])
    }
}

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

    @Test func theSiblingKeepsTheInputsContainer() {
        // M24-T5: trimming the .mp4 you made to share must not hand back the .mov you converted
        // away from. Anything we don't write becomes .mov, which every source here can be.
        let cases = [
            ("/tmp/Clip.mp4", "Clip trimmed.mp4"),
            ("/tmp/Clip.m4v", "Clip trimmed.m4v"),
            ("/tmp/Clip.MP4", "Clip trimmed.mp4"),
            ("/tmp/Clip.mkv", "Clip trimmed.mov"),
        ]
        for (path, expected) in cases {
            #expect(Trimmer.trimmedSibling(of: URL(fileURLWithPath: path)).lastPathComponent
                == expected, "\(path)")
        }
    }

    @Test func aSecondTrimDoesNotStutterTheSuffix() {
        // Reachable from the menu: the export receipt's own row carries Trim… (found live, M24-T1).
        let once = Trimmer.trimmedSibling(of: URL(fileURLWithPath: "/tmp/Recording 2026.mp4"))
        #expect(once.lastPathComponent == "Recording 2026 trimmed.mp4")
        #expect(Trimmer.trimmedSibling(of: once).lastPathComponent == "Recording 2026 trimmed.mp4")
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func aPreciseTrimKeepsOnlyTheRangeAndBothAudioTracks() async throws {
        let source = try await Self.makeClip(seconds: 2, withMicrophone: true)
        defer { try? FileManager.default.removeItem(at: source) }
        func output(_ label: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("trim-\(label)-\(UUID().uuidString).mov")
        }
        let lossless = output("lossless"), precise = output("precise")
        defer {
            try? FileManager.default.removeItem(at: lossless)
            try? FileManager.default.removeItem(at: precise)
        }

        _ = try await Trimmer.trim(from: source, to: lossless, start: 0.5, end: 1.5)
        _ = try await Trimmer.trim(from: source, to: precise, start: 0.5, end: 1.5, mode: .precise)

        // The difference the mode makes: a lossless trim keeps the frames back to the previous
        // keyframe inside the file (the edit list starts past them), a precise one holds only the
        // range. Both present the same 1 s.
        #expect(try await Self.editedLeadIn(of: lossless) > 0.1)
        #expect(try await Self.editedLeadIn(of: precise) < 0.05)
        for url in [lossless, precise] {
            let asset = AVURLAsset(url: url)
            #expect(try await asset.load(.isPlayable))
            #expect(abs(try await asset.load(.duration).seconds - 1.0) < 0.2)
        }

        // Re-encoding must not flatten the two audio tracks into one (ADR-004) or resize the video.
        let tracks = try await AVURLAsset(url: precise).load(.tracks)
        let audio = tracks.filter { $0.mediaType == .audio }
        #expect(audio.count == 2)
        var channelCounts: Set<Int> = []
        for track in audio { channelCounts.insert(try await Self.channels(of: track)) }
        #expect(channelCounts == [1, 2])
        let video = try #require(tracks.first { $0.mediaType == .video })
        #expect(try await Self.subtype(of: video) == kCMVideoCodecType_HEVC)
        #expect(try await video.load(.naturalSize) == CGSize(width: 640, height: 360))
    }

    // MARK: - Fixtures

    private static func makeClip(seconds: Int, withMicrophone: Bool = false) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let fps = 30
        let recorder = try MovieRecorder(
            outputURL: url, frameRate: fps, preset: .balanced,
            includesMicrophone: withMicrophone, includesSystemAudio: true)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let micFormat = makeAudioFormat(sampleRate: 48_000, channels: 1)
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
            if withMicrophone {
                recorder.consume(
                    makeAudioSampleBuffer(format: micFormat, frames: 48_000 / fps, pts: pts),
                    type: .microphone)
            }
            usleep(8_000)  // pace the feed so frames survive encoder warmup (a ~2 s clip)
        }
        return try await recorder.finish()
    }

    /// How much of the video track the file stores but never presents — the edit list's offset into
    /// the stored timeline.
    private static func editedLeadIn(of url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.load(.tracks).first { $0.mediaType == .video })
        let segment = try #require(try await track.load(.segments).first)
        return segment.timeMapping.source.start.seconds
    }

    private static func channels(of track: AVAssetTrack) async throws -> Int {
        let descriptions = try await track.load(.formatDescriptions)
        return Int(CMAudioFormatDescriptionGetStreamBasicDescription(descriptions[0])?
            .pointee.mChannelsPerFrame ?? 0)
    }

    private static func subtype(of track: AVAssetTrack) async throws -> FourCharCode {
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetMediaSubType(descriptions[0])
    }
}

import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import RecorderCore

@Suite struct ExporterTests {

    // MARK: - Sizing (pure)

    @Test func fittedSizeDownscalesCaptureToTargetWidth() {
        // 4112×2570 (the dev display) → 1920 wide, aspect preserved. Also clears the H.264
        // 4096×2304 cap (02 §3) that a native-size encode would hit.
        let size = Exporter.fittedSize(width: 4112, height: 2570, configuration: ExportConfiguration())
        #expect(size.width == 1920)
        #expect(size.height == 1200)
    }

    @Test func fittedSizeNeverUpscalesAndRoundsEven() {
        let config = ExportConfiguration()
        #expect(Exporter.fittedSize(width: 800, height: 600, configuration: config) == (800, 600))
        let odd = Exporter.fittedSize(width: 641, height: 361, configuration: config)
        #expect(odd.width % 2 == 0)
        #expect(odd.height % 2 == 0)
    }

    @Test func fittedSizeHeightCeilingCapsTallSources() {
        let size = Exporter.fittedSize(width: 1000, height: 5000, configuration: ExportConfiguration())
        #expect(size.width <= 1920)
        #expect(size.height <= 2304)
    }

    // MARK: - Output path (pure + filesystem)

    @Test func mp4SiblingSwapsExtension() {
        let input = URL(fileURLWithPath: "/tmp/Recording 2026.mov")
        #expect(Exporter.mp4Sibling(of: input).lastPathComponent == "Recording 2026.mp4")
    }

    @Test func availableURLResolvesCollisions() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-avail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("Clip.mp4")
        #expect(Exporter.availableURL(basedOn: base) == base)
        FileManager.default.createFile(atPath: base.path, contents: Data())
        #expect(Exporter.availableURL(basedOn: base).lastPathComponent == "Clip 2.mp4")
    }

    @Test func rejectsOutputEqualToInput() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-same-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: ExportError.outputCollidesWithInput) {
            _ = try await Exporter.exportToMP4(from: url, to: url)
        }
    }

    @Test func rejectsOutputThatAliasesInputViaSymlink() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-alias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let real = dir.appendingPathComponent("Rec.mov")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8))
        let alias = dir.appendingPathComponent("Alias.mov")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)

        // A string compare would pass (different names), but the paths resolve to one file — the
        // guard must refuse it before the pre-write delete could destroy the recording.
        await #expect(throws: ExportError.outputCollidesWithInput) {
            _ = try await Exporter.exportToMP4(from: real, to: alias)
        }
    }

    // MARK: - Integration

    /// One transcode covering the whole contract, off a >1920 source so it also proves the
    /// encoder scales native frames (not just that `fittedSize` computes a number): 2400×1500 →
    /// H.264 High `.mp4`, 1920×1200, the two audio tracks mixed to one AAC, playable, faststart.
    /// Kept a single hardware-encode so the suite doesn't oversubscribe the VT encoder pool.
    @Test func transcodesRecordingToShareableMP4() async throws {
        let source = try await Self.makeThreeTrackMov(width: 2400, height: 1500)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-out-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await Exporter.exportToMP4(from: source, to: output)
        #expect(result.width == 1920)  // downscaled from 2400 wide
        #expect(result.height == 1200)

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        #expect(videoTracks.count == 1)
        #expect(audioTracks.count == 1)  // the two source tracks are mixed down to one
        #expect(try await Self.subtype(of: videoTracks[0]) == kCMVideoCodecType_H264)
        #expect(try await Self.subtype(of: audioTracks[0]) == kAudioFormatMPEG4AAC)

        // The encoded track really is the fitted size (not just the reported number).
        let naturalSize = try await videoTracks[0].load(.naturalSize)
        #expect(Int(naturalSize.width.rounded()) == 1920)
        #expect(Int(naturalSize.height.rounded()) == 1200)

        #expect(try await asset.load(.isPlayable))
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - result.duration) < 0.2)

        // The mixed audio track spans the clip — proves the mix actually emitted audio, not just
        // that a single empty track exists.
        let audioSpan = try await audioTracks[0].load(.timeRange).duration.seconds
        #expect(abs(audioSpan - duration) < 0.2)

        // +faststart: the moov atom precedes mdat.
        let atoms = try Self.topLevelAtoms(of: output)
        let moov = try #require(atoms.firstIndex(of: "moov"))
        let mdat = try #require(atoms.firstIndex(of: "mdat"))
        #expect(moov < mdat)
    }

    // MARK: - Fixtures

    private static let fps = 30
    // A short clip: enough frames for a valid multi-frame HEVC while keeping the encode brief,
    // so these VT-heavy fixtures don't starve the shared encoder pool under parallel test runs.
    private static let frameCount = 12

    /// A real 3-track HEVC `.mov` (screen + system + mic) via MovieRecorder — the fixture path
    /// MovieRecorderTests exercises, reused here as the Exporter's input.
    private static func makeThreeTrackMov(width: Int, height: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: fps, preset: .balanced, includesMicrophone: true)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let micFormat = makeAudioFormat(sampleRate: 24_000, channels: 1)
        // Prime the lazy mic input pre-epoch (dropped), as the recorder suite does.
        recorder.consume(makeAudioSampleBuffer(format: micFormat, frames: 800, pts: .zero), type: .microphone)

        for index in 0..<frameCount {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            recorder.consume(
                makeVideoSampleBuffer(
                    width: width, height: height, pts: pts,
                    duration: CMTime(value: 1, timescale: CMTimeScale(fps))),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 48_000 / fps, pts: pts),
                type: .systemAudio)
            recorder.consume(
                makeAudioSampleBuffer(format: micFormat, frames: 24_000 / fps, pts: pts),
                type: .microphone)
        }
        return try await recorder.finish()
    }

    private static func subtype(of track: AVAssetTrack) async throws -> FourCharCode {
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetMediaSubType(descriptions[0])
    }

    /// Top-level atom types in file order — enough to assert moov precedes mdat (faststart).
    private static func topLevelAtoms(of url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var atoms: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            let size =
                Int(data[offset]) << 24 | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let type = String(bytes: data[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? "????"
            atoms.append(type)
            let advance =
                size == 1
                ? Int(data[(offset + 8)..<(offset + 16)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
                : size
            if advance < 8 { break }  // size 0 (extends to EOF) or garbage — stop
            offset += advance
        }
        return atoms
    }
}

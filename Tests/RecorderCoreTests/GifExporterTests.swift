import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import RecorderCore

@Suite struct GifExporterTests {

    // MARK: - Pure

    @Test func gifSiblingSwapsExtension() {
        let input = URL(fileURLWithPath: "/tmp/Replay 2026.mov")
        #expect(GifExporter.gifSibling(of: input).lastPathComponent == "Replay 2026.gif")
    }

    @Test func fittedSizeCapsWidthForGif() {
        // 640×360 under a 480 ceiling → 480×270 (aspect preserved, even).
        let size = Exporter.fittedSize(width: 640, height: 360, maxWidth: 480, maxHeight: 480)
        #expect(size.width == 480)
        #expect(size.height == 270)
    }

    @Test func rejectsOutputEqualToInput() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-same-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: GifExportError.outputCollidesWithInput) {
            _ = try await GifExporter.exportGIF(from: url, to: url)
        }
    }

    // MARK: - Integration (gated — the fixture build uses the VT encoder; see ExporterTests)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func encodesALoopingScaledGif() async throws {
        let source = try await Self.makeClip(width: 640, height: 360, frames: 30)  // 1 s
        defer { try? FileManager.default.removeItem(at: source) }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-out-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await GifExporter.exportGIF(from: source, to: output)
        #expect(result.width == 480)   // 640 fitted under the 480 cap
        #expect(result.height == 270)
        #expect(!result.truncated)     // 1 s is under the 30 s ceiling

        let imageSource = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect((CGImageSourceGetType(imageSource) as String?) == UTType.gif.identifier)
        let frames = CGImageSourceGetCount(imageSource)
        #expect(frames == result.frameCount)
        // ~15 fps over 1 s of 30 fps source: the fps cap subsampled it to half, not all 30.
        #expect(frames >= 13)
        #expect(frames <= 17)
        let first = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(first.width == 480)

        // Loops forever: the GIF loop-count extension is present and zero.
        let props = CGImageSourceCopyProperties(imageSource, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect((gif?[kCGImagePropertyGIFLoopCount] as? Int) == 0)
    }

    // MARK: - Fixtures

    private static let fps = 30

    private static func makeClip(width: Int, height: Int, frames: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: fps, preset: .balanced, includesMicrophone: false)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        for index in 0..<frames {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
            recorder.consume(
                makeVideoSampleBuffer(
                    width: width, height: height, pts: pts,
                    duration: CMTime(value: 1, timescale: CMTimeScale(fps)), shade: UInt8(index * 8)),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 48_000 / fps, pts: pts),
                type: .systemAudio)
            // Pace the feed so the HEVC encoder keeps up — an instant burst drops most frames to
            // warmup, leaving a source too sparse to exercise the fps subsampling.
            usleep(12_000)
        }
        return try await recorder.finish()
    }
}

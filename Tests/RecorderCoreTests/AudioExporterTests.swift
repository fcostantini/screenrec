import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import RecorderCore

/// The audio-only export (M38-T2).
///
/// The fixtures here carry **no video**, so they build without the hardware encoder and these run
/// in the default suite — unlike the MP4/GIF integration tests, which are gated behind
/// `SCREENREC_HW_ENCODE_TESTS`. The one test that needs a picture (to have none of the sound) is
/// gated with them.
@Suite struct AudioExporterTests {

    // MARK: - Pure

    @Test func theSiblingSwapsTheExtension() {
        let input = URL(fileURLWithPath: "/tmp/Replay 2026.mov")
        #expect(AudioExporter.m4aSibling(of: input).lastPathComponent == "Replay 2026.m4a")
    }

    @Test func aRangesAudioIsNamedAfterTheTrimmedClipNotTheTake() {
        // The M21-T1 rule: a clip's sound must not sit in the folder looking like the whole take's.
        let input = URL(fileURLWithPath: "/tmp/Replay 2026.mov")
        let range = ExportRange(start: 1, end: 2)
        #expect(
            AudioExporter.m4aSibling(of: input, range: range).lastPathComponent
                == "Replay 2026 trimmed.m4a")
    }

    @Test func rejectsOutputEqualToInput() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-same-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: AudioExportError.outputCollidesWithInput) {
            _ = try await AudioExporter.exportAudio(from: url, to: url)
        }
    }

    @Test func rejectsAnInvertedRangeBeforeReadingAnything() async throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-range-\(UUID().uuidString).mov")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: input) }
        let output = input.deletingPathExtension().appendingPathExtension("m4a")

        await #expect(throws: AudioExportError.emptyRange) {
            _ = try await AudioExporter.exportAudio(
                from: input, to: output, range: ExportRange(start: 3, end: 1))
        }
    }

    // MARK: - Integration

    @Test func writesOneAacTrackAndNoVideo() async throws {
        let source = try Self.makeAudioClip(systemSeconds: 1, micSeconds: 1)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = AudioExporter.m4aSibling(of: source)
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await AudioExporter.exportAudio(from: source, to: output)
        #expect(result.byteCount > 0)
        #expect(abs(result.duration - 1) < 0.2)

        let asset = AVURLAsset(url: result.url)
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.isEmpty)
        let audio = tracks.filter { $0.mediaType == .audio }
        #expect(audio.count == 1)                                  // both source tracks mixed to one
        let format = try #require(try await audio.first?.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.2)
    }

    @Test func withoutTheMicrophoneTheMonoTrackIsLeftOut() async throws {
        // The mic outlasts the system audio here, so dropping it is *visible* in the duration —
        // the mix is only ever one track either way.
        let source = try Self.makeAudioClip(systemSeconds: 1, micSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let withMic = AudioExporter.m4aSibling(of: source)
        // Named, not derived: `availableURL` would hand back `withMic` itself here, since nothing
        // has been written yet when the path is chosen.
        let withoutMic = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-nomic-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: withMic)
            try? FileManager.default.removeItem(at: withoutMic)
        }

        let kept = try await AudioExporter.exportAudio(from: source, to: withMic)
        #expect(abs(kept.duration - 2) < 0.2)
        let dropped = try await AudioExporter.exportAudio(
            from: source, to: withoutMic,
            configuration: ExportConfiguration(includesMicrophone: false))
        #expect(dropped.url == withoutMic)          // it wrote where it was asked to
        #expect(abs(dropped.duration - 1) < 0.2)
        let heard = try await AVURLAsset(url: dropped.url).load(.duration).seconds
        #expect(abs(heard - 1) < 0.2)
    }

    @Test func aRangeWritesOnlyThatRange() async throws {
        let source = try Self.makeAudioClip(systemSeconds: 2, micSeconds: 2)
        defer { try? FileManager.default.removeItem(at: source) }
        let range = ExportRange(start: 0.5, end: 1.5)
        let output = AudioExporter.m4aSibling(of: source, range: range)
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await AudioExporter.exportAudio(from: source, to: output, range: range)
        #expect(abs(result.duration - 1) < 0.05)
        #expect(abs(try await AVURLAsset(url: result.url).load(.duration).seconds - 1) < 0.2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCREENREC_HW_ENCODE_TESTS"] == "1"))
    func aRecordingWithNoSoundIsRefusedRatherThanWrittenSilent() async throws {
        // System audio is optional (ADR-019) and the mic is opt-in, so this is a real recording,
        // not a corrupt one.
        let source = try await Self.makeSilentClip(frames: 6)
        defer { try? FileManager.default.removeItem(at: source) }
        let output = AudioExporter.m4aSibling(of: source)
        defer { try? FileManager.default.removeItem(at: output) }

        await #expect(throws: AudioExportError.noAudioTrack) {
            _ = try await AudioExporter.exportAudio(from: source, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: - Fixtures

    /// A recording without its picture: two AAC tracks in a `.mov`, stereo "system audio" and mono
    /// "microphone" (ADR-004), each as long as asked. Unequal lengths are what makes the
    /// microphone rule observable.
    private static func makeAudioClip(systemSeconds: Double, micSeconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-src-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        func track(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: AudioEncodingSettings.aac(
                    sampleRate: 48_000, channels: channels, bitRate: 128_000))
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            return input
        }
        let system = track(channels: 2)
        let microphone = track(channels: 1)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let chunk = 4800  // 0.1 s at 48 kHz
        for (input, channels, seconds) in [(system, UInt32(2), systemSeconds),
                                           (microphone, UInt32(1), micSeconds)] {
            let format = makeAudioFormat(sampleRate: 48_000, channels: channels)
            var frames = 0
            while Double(frames) / 48_000 < seconds {
                while !input.isReadyForMoreMediaData { usleep(2_000) }
                precondition(
                    input.append(
                        makeAudioSampleBuffer(
                            format: format, frames: chunk,
                            pts: CMTime(value: CMTimeValue(frames), timescale: 48_000))))
                frames += chunk
            }
            input.markAsFinished()
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        precondition(writer.status == .completed)
        return url
    }

    /// A take with a picture and no sound — the ADR-019 case. Uses the VT encoder, hence the gate.
    private static func makeSilentClip(frames: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-silent-\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: url)

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: 30, preset: .balanced,
            includesMicrophone: false, includesSystemAudio: false)
        for index in 0..<frames {
            recorder.consume(
                makeVideoSampleBuffer(
                    width: 320, height: 240,
                    pts: CMTime(value: CMTimeValue(index), timescale: 30),
                    duration: CMTime(value: 1, timescale: 30), shade: UInt8(index * 8)),
                type: .screen)
            usleep(12_000)
        }
        return try await recorder.finish()
    }
}

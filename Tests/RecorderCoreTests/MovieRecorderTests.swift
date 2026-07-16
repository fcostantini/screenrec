import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import RecorderCore

/// Exercises `MovieRecorder` end-to-end WITHOUT ScreenCaptureKit: it feeds 2 s of synthetic
/// buffers (solid-color frames + PCM silence in two distinct audio formats) and asserts the
/// finalized `.mov` via `AVAsset` — proving the writer independently of capture (M2-T2).
@Suite struct MovieRecorderTests {

    // Modest geometry keeps the HEVC encode fast; the assertions are on tracks, not pixels.
    private static let width = 640
    private static let height = 360
    private static let fps = 30
    private static let seconds = 2

    @Test func writesThreeTrackHEVCMovie() async throws {
        let url = Self.temporaryOutputURL()
        // Fresh path each run; the writer refuses to overwrite an existing file.
        try? FileManager.default.removeItem(at: url)
        let keep = ProcessInfo.processInfo.environment["KEEP_RECORDING"] != nil
        defer { if !keep { try? FileManager.default.removeItem(at: url) } }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced, includesMicrophone: true)

        // System audio: 48 kHz stereo. Mic: 24 kHz mono — a deliberately different format,
        // so the lazily-built mic input can't share the system input (docs/02 §4).
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let micFormat = makeAudioFormat(sampleRate: 24_000, channels: 1)

        // Prime the lazy mic input with one throwaway buffer so the writer can start before
        // the first video frame; it's pre-epoch (no session yet) and is dropped by design.
        recorder.consume(
            makeAudioSampleBuffer(format: micFormat,
                             frames: 800, pts: .zero),
            type: .microphone)

        let frameCount = Self.fps * Self.seconds
        for index in 0..<frameCount {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height,
                                 pts: pts, duration: frameDuration),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat,
                                 frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
            recorder.consume(
                makeAudioSampleBuffer(format: micFormat,
                                 frames: 24_000 / Self.fps, pts: pts),
                type: .microphone)
        }

        let finalURL = try await recorder.finish()
        if keep { print("KEPT recording at: \(finalURL.path)") }

        let asset = AVURLAsset(url: finalURL)
        let tracks = try await asset.load(.tracks)
        let videoTracks = tracks.filter { $0.mediaType == .video }
        let audioTracks = tracks.filter { $0.mediaType == .audio }

        #expect(videoTracks.count == 1)
        #expect(audioTracks.count == 2)

        for track in videoTracks {
            #expect(try await Self.subtype(of: track) == kCMVideoCodecType_HEVC)
        }
        for track in audioTracks {
            #expect(try await Self.subtype(of: track) == kAudioFormatMPEG4AAC)
        }

        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - Double(Self.seconds)) < 0.1)
    }

    @Test func noMicrophoneYieldsTwoTracks() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // includesMicrophone: false ⇒ every input exists at init, so writing starts eagerly
        // and no mic track appears (the M2-T5 `--no-mic` path).
        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced, includesMicrophone: false)
        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat,
                                 frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
        }

        let asset = AVURLAsset(url: try await recorder.finish())
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.count == 1)
        #expect(tracks.filter { $0.mediaType == .audio }.count == 1)
    }

    @Test func microphoneFormatChangeFiresOnceAndStillFinalizes() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let micA = makeAudioFormat(sampleRate: 24_000, channels: 1)  // e.g. AirPods
        let micB = makeAudioFormat(sampleRate: 48_000, channels: 1)  // built-in mic takes over
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.fps))

        // The handler fires exactly once: not on the buffer that establishes the format, once on
        // the first mismatched buffer, and never again — a device switch is fail-stop, not
        // per-buffer (docs/02 §4, ADR-007). Detection only runs once the writer session is
        // underway, so record real content first, then swap the device.
        try await confirmation("mic device switch detected exactly once") { detected in
            let recorder = try MovieRecorder(
                outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: true,
                onMicrophoneFormatChange: { detected() })

            let frames = Self.fps * Self.seconds
            for index in 0..<frames {
                let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
                recorder.consume(
                    makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                     duration: frameDuration),
                    type: .screen)
                recorder.consume(
                    makeAudioSampleBuffer(format: systemFormat,
                                     frames: 48_000 / Self.fps, pts: pts),
                    type: .systemAudio)
                recorder.consume(
                    makeAudioSampleBuffer(format: micA,
                                     frames: 24_000 / Self.fps, pts: pts),
                    type: .microphone)
            }
            // Device switched: every later mic buffer carries the new format.
            for index in frames..<(frames + 3) {
                let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
                recorder.consume(
                    makeAudioSampleBuffer(format: micB,
                                     frames: 48_000 / Self.fps, pts: pts),
                    type: .microphone)
            }

            // Fail-stop's promise (ADR-007): the file is still finalizable and playable — video
            // + system audio, plus the mic track up to the moment the device changed.
            let asset = AVURLAsset(url: try await recorder.finish())
            let tracks = try await asset.load(.tracks)
            #expect(tracks.filter { $0.mediaType == .video }.count == 1)
            #expect(tracks.filter { $0.mediaType == .audio }.count == 2)
        }
    }

    @Test func microphoneFormatChangeBeforeWritingDoesNotFailStop() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let micA = makeAudioFormat(sampleRate: 24_000, channels: 1)
        let micB = makeAudioFormat(sampleRate: 48_000, channels: 1)

        // A swap before the first video frame starts the writer session must NOT fail-stop:
        // nothing is written yet, so stopping would discard the whole recording as `.failed`
        // purely on sub-frame timing. These buffers are dropped by the writing gate instead,
        // and capture carries on until there is something worth saving.
        try await confirmation("no fail-stop before the session starts", expectedCount: 0) { detected in
            let recorder = try MovieRecorder(
                outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: true,
                onMicrophoneFormatChange: { detected() })
            recorder.consume(
                makeAudioSampleBuffer(format: micA, frames: 800,
                                 pts: CMTime(value: 1, timescale: 100)),
                type: .microphone)
            recorder.consume(
                makeAudioSampleBuffer(format: micB, frames: 1600,
                                 pts: CMTime(value: 2, timescale: 100)),
                type: .microphone)
            recorder.cancel()
        }
    }

    @Test func finishWithoutFramesThrows() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: false)

        // Only audio was fed — no video frame ever started the session, so there is nothing
        // to finalize and finish() reports it rather than emitting an empty file.
        recorder.consume(
            makeAudioSampleBuffer(format: makeAudioFormat(sampleRate: 48_000, channels: 2), frames: 1600, pts: .zero),
            type: .systemAudio)

        await #expect(throws: MovieRecorderError.noFramesWritten) {
            _ = try await recorder.finish()
        }
    }

    @Test func failedFinishRemovesReservationPlaceholder() async throws {
        let fileManager = FileManager.default
        let url = Self.temporaryOutputURL()
        fileManager.createFile(atPath: url.path, contents: Data())  // OutputLocation's O_EXCL placeholder
        defer { try? fileManager.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: false)
        // Only audio — no video frame ever starts the session, so nothing is written.
        recorder.consume(
            makeAudioSampleBuffer(format: makeAudioFormat(sampleRate: 48_000, channels: 2), frames: 1600, pts: .zero),
            type: .systemAudio)
        await #expect(throws: MovieRecorderError.noFramesWritten) { _ = try await recorder.finish() }
        // The reservation placeholder must be cleaned up, not left as 0-byte litter that would
        // block retrying an explicit output path.
        #expect(!fileManager.fileExists(atPath: url.path))
    }

    @Test func cancelRemovesReservationPlaceholder() throws {
        let fileManager = FileManager.default
        let url = Self.temporaryOutputURL()
        fileManager.createFile(atPath: url.path, contents: Data())
        defer { try? fileManager.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: false)
        recorder.cancel()
        #expect(!fileManager.fileExists(atPath: url.path))
    }

    @Test func unwritableOutputReportsWriteFailureExactlyOnce() async throws {
        let fileManager = FileManager.default
        // A read-only directory: `AVAssetWriter` init succeeds (it touches no disk) but
        // `startWriting()` — the call that creates the file — fails, exactly as an ungranted
        // Desktop does (02 §2). The failure must be surfaced, not swallowed: a swallowed `false`
        // leaves the stream running with no terminal event for the owner to act on.
        let dir = fileManager.temporaryDirectory
            .appendingPathComponent("moverec-readonly-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? fileManager.removeItem(at: dir)
        }
        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let url = dir.appendingPathComponent("Recording.mov")

        // Fires exactly once (default confirmation count) even across two frames — the second
        // proves it neither re-attempts the writer nor re-notifies after the first failure.
        try await confirmation("write failure reported exactly once") { failed in
            let recorder = try MovieRecorder(
                outputURL: url, frameRate: Self.fps, preset: .efficient, includesMicrophone: false,
                onWriteFailure: { failed() })
            for index in 0..<2 {
                let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
                recorder.consume(
                    makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                     duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                    type: .screen)
            }
            #expect(recorder.failedToBeginWriting)   // the failure is surfaced for the owner
            #expect(!recorder.hasStartedSession)     // nothing playable exists
            recorder.cancel()
        }
    }

    // MARK: - Synthetic buffer fixtures

    private static func temporaryOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moverec-test-\(UUID().uuidString).mov")
    }

    private static func subtype(of track: AVAssetTrack) async throws -> FourCharCode {
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetMediaSubType(descriptions[0])
    }

}

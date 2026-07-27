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
            outputURL: url, frameRate: Self.fps, preset: .balanced,
            includesMicrophone: true, includesSystemAudio: true)

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
            outputURL: url, frameRate: Self.fps, preset: .balanced,
            includesMicrophone: false, includesSystemAudio: true)
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

    @Test func systemAudioOffYieldsVideoAndMicOnly() async throws {
        // ADR-019: the input must not exist at all — one that never receives a buffer would still
        // write an empty AAC track, which is what a viewer sees as a silent second track.
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced, includesMicrophone: true,
            includesSystemAudio: false)
        let micFormat = makeAudioFormat(sampleRate: 48_000, channels: 1)
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: micFormat, frames: 48_000 / Self.fps, pts: pts),
                type: .microphone)
        }

        let asset = AVURLAsset(url: try await recorder.finish())
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.count == 1)
        #expect(tracks.filter { $0.mediaType == .audio }.count == 1)
    }

    @Test func allAudioOffYieldsAPlayableSilentRecording() async throws {
        // A silent screen recording is legitimate (ADR-019), not an error.
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced, includesMicrophone: false,
            includesSystemAudio: false)
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
        }

        let asset = AVURLAsset(url: try await recorder.finish())
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.count == 1)
        #expect(tracks.filter { $0.mediaType == .audio }.isEmpty)
        #expect(try await asset.load(.duration).seconds > 0)
    }

    @Test func aMicrophoneMissingItsGraceFiresTheDropAndYieldsNoMicTrack() async throws {
        // A selected mic that never delivers within the 0.75 s grace: the recorder starts without
        // it and fires the drop signal (M13-T4) — surfaced as a notice, not a silent mic-less take.
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced,
            includesMicrophone: true, includesSystemAudio: true)
        let dropped = LockedBox<Bool>()
        recorder.onMicrophoneDroppedAtStart = { dropped.set(true) }

        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        // 2 s of video + system audio, NO mic buffer ever — well past the 0.75 s grace.
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
        }

        #expect(dropped.value == true)
        let asset = AVURLAsset(url: try await recorder.finish())
        let audio = try await asset.load(.tracks).filter { $0.mediaType == .audio }
        #expect(audio.count == 1)     // system audio only — no mic track
    }

    @Test func aMicrophoneArrivingInTimeDoesNotFireTheDrop() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .balanced,
            includesMicrophone: true, includesSystemAudio: true)
        let dropped = LockedBox<Bool>()
        recorder.onMicrophoneDroppedAtStart = { dropped.set(true) }

        let systemFormat = makeAudioFormat(sampleRate: 48_000, channels: 2)
        let micFormat = makeAudioFormat(sampleRate: 24_000, channels: 1)
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
            recorder.consume(
                makeAudioSampleBuffer(format: systemFormat, frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
            recorder.consume(
                makeAudioSampleBuffer(format: micFormat, frames: 24_000 / Self.fps, pts: pts),
                type: .microphone)
        }

        _ = try await recorder.finish()
        #expect(dropped.value != true)     // the mic made it in within the grace — no drop
    }

    @Test func finishWithoutFramesThrows() async throws {
        let url = Self.temporaryOutputURL()
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .efficient,
            includesMicrophone: false, includesSystemAudio: true)

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
            outputURL: url, frameRate: Self.fps, preset: .efficient,
            includesMicrophone: false, includesSystemAudio: true)
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
            outputURL: url, frameRate: Self.fps, preset: .efficient,
            includesMicrophone: false, includesSystemAudio: true)
        recorder.cancel()
        #expect(!fileManager.fileExists(atPath: url.path))
    }

    /// Discard routes to `cancel()` mid-recording: once the writer has begun, `cancelWriting()`
    /// removes its own file, so no `.mov`/`.partial` is left behind (M6-T12).
    @Test func cancelAfterWritingRemovesTheFile() throws {
        let fileManager = FileManager.default
        let url = Self.temporaryOutputURL()
        try? fileManager.removeItem(at: url)
        defer { try? fileManager.removeItem(at: url) }

        let recorder = try MovieRecorder(
            outputURL: url, frameRate: Self.fps, preset: .efficient,
            includesMicrophone: false, includesSystemAudio: true)

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
        for index in 0..<5 {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                makeVideoSampleBuffer(width: Self.width, height: Self.height,
                                 pts: pts, duration: frameDuration),
                type: .screen)
        }
        #expect(recorder.hasStartedSession)                  // the writer created the real file
        #expect(fileManager.fileExists(atPath: url.path))

        recorder.cancel()
        #expect(!fileManager.fileExists(atPath: url.path))   // and cancel() dropped it
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
                outputURL: url, frameRate: Self.fps, preset: .efficient,
                includesMicrophone: false, includesSystemAudio: true,
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

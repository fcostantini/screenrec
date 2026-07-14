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
        let systemFormat = Self.audioFormat(sampleRate: 48_000, channels: 2)
        let micFormat = Self.audioFormat(sampleRate: 24_000, channels: 1)

        // Prime the lazy mic input with one throwaway buffer so the writer can start before
        // the first video frame; it's pre-epoch (no session yet) and is dropped by design.
        recorder.consume(
            Self.audioSample(format: micFormat, sampleRate: 24_000, channels: 1,
                             frames: 800, pts: .zero),
            type: .microphone)

        let frameCount = Self.fps * Self.seconds
        for index in 0..<frameCount {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
            recorder.consume(
                Self.videoSample(width: Self.width, height: Self.height,
                                 pts: pts, duration: frameDuration),
                type: .screen)
            recorder.consume(
                Self.audioSample(format: systemFormat, sampleRate: 48_000, channels: 2,
                                 frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
            recorder.consume(
                Self.audioSample(format: micFormat, sampleRate: 24_000, channels: 1,
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
        let systemFormat = Self.audioFormat(sampleRate: 48_000, channels: 2)
        for index in 0..<(Self.fps * Self.seconds) {
            let pts = CMTime(value: CMTimeValue(index), timescale: CMTimeScale(Self.fps))
            recorder.consume(
                Self.videoSample(width: Self.width, height: Self.height, pts: pts,
                                 duration: CMTime(value: 1, timescale: CMTimeScale(Self.fps))),
                type: .screen)
            recorder.consume(
                Self.audioSample(format: systemFormat, sampleRate: 48_000, channels: 2,
                                 frames: 48_000 / Self.fps, pts: pts),
                type: .systemAudio)
        }

        let asset = AVURLAsset(url: try await recorder.finish())
        let tracks = try await asset.load(.tracks)
        #expect(tracks.filter { $0.mediaType == .video }.count == 1)
        #expect(tracks.filter { $0.mediaType == .audio }.count == 1)
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
            Self.audioSample(format: Self.audioFormat(sampleRate: 48_000, channels: 2),
                             sampleRate: 48_000, channels: 2, frames: 1600, pts: .zero),
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
            Self.audioSample(format: Self.audioFormat(sampleRate: 48_000, channels: 2),
                             sampleRate: 48_000, channels: 2, frames: 1600, pts: .zero),
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

    // MARK: - Synthetic buffer fixtures

    private static func temporaryOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moverec-test-\(UUID().uuidString).mov")
    }

    private static func subtype(of track: AVAssetTrack) async throws -> FourCharCode {
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetMediaSubType(descriptions[0])
    }

    private static func videoSample(
        width: Int, height: Int, pts: CMTime, duration: CMTime
    ) -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        let buffer = pixelBuffer!
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0x40,
               CVPixelBufferGetBytesPerRow(buffer) * height)
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescriptionOut: &formatDescription)
        var timing = CMSampleTimingInfo(
            duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription!,
            sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        return sampleBuffer!
    }

    private static func audioFormat(sampleRate: Double, channels: UInt32) -> CMAudioFormatDescription {
        let bytesPerFrame = 2 * channels  // 16-bit signed samples, interleaved
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        return format!
    }

    private static func audioSample(
        format: CMAudioFormatDescription, sampleRate: Double, channels: UInt32,
        frames: Int, pts: CMTime
    ) -> CMSampleBuffer {
        let dataSize = frames * Int(2 * channels)
        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: dataSize, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer)
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer!,
                                   offsetIntoDestination: 0, dataLength: dataSize)  // silence

        var sampleBuffer: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer!, formatDescription: format,
            sampleCount: frames, presentationTimeStamp: pts, packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer)
        return sampleBuffer!
    }
}

import AVFoundation
import CoreMedia
import Foundation

/// Errors from constructing or finalizing a `MovieRecorder`.
public enum MovieRecorderError: Error, Equatable {
    /// The writer refused an input (e.g. an unsupported codec/geometry combination).
    case cannotAddInput(SourceType)
    /// `finish()` was called but no video frame ever started the session — nothing to write.
    case noFramesWritten
    /// `finishWriting` ended in a non-`completed` state with no underlying error to surface.
    case finishFailed
    /// `finish()` was called more than once.
    case alreadyFinished
}

/// Writes captured sample buffers to a three-track `.mov` (HEVC video + two AAC audio
/// tracks) via a single `AVAssetWriter`. This is the M2-T2 skeleton: it owns the writer,
/// its inputs, and the session lifecycle. Timestamp rebasing (`TimestampRebaser`, M2-T3),
/// `SampleConsumer` wiring, the tail-frame patch, dropped-frame reporting, and event
/// emission (M2-T4) are layered on later — callers here drive `append(_:type:)` directly.
///
/// Concurrency: buffers arrive on ScreenCaptureKit's three serial output queues, so every
/// mutable field is guarded by `lock` rather than actor isolation (docs/01) — appends stay
/// on the calling queue with no async hop.
public final class MovieRecorder: @unchecked Sendable {
    /// The `.mov` this recorder writes. Stable for the recorder's lifetime.
    public let outputURL: URL

    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput
    private let includesMicrophone: Bool

    /// Built from the first microphone buffer's format description — device-native audio
    /// format varies (docs/02 §4), and inputs can't be added after `startWriting()`, which
    /// is why writing is deferred until this exists when a mic is in play.
    private var microphoneInput: AVAssetWriterInput?

    private var didStartWriting = false
    private var didStartSession = false
    private var isFinished = false

    /// - Parameters:
    ///   - width/height: capture pixel dimensions (`CaptureConfiguration.pixelDimensions`).
    ///   - frameRate: the fps cap, for the bitrate model and the encoder's source-rate hint.
    ///   - includesMicrophone: whether a mic track is expected; gates when writing starts.
    public init(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int,
        preset: QualityPreset,
        includesMicrophone: Bool
    ) throws {
        self.outputURL = outputURL
        self.includesMicrophone = includesMicrophone

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // Fragmented .mov: a kill -9 mid-recording loses at most the last fragment, not the
        // whole file (docs/02 §5). Must be set before startWriting.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: Self.videoSettings(
                width: width, height: height, frameRate: frameRate, preset: preset))
        videoInput.expectsMediaDataInRealTime = true

        systemAudioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: Self.audioSettings(sampleRate: 48_000, channels: 2, bitRate: 192_000))
        systemAudioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else { throw MovieRecorderError.cannotAddInput(.screen) }
        writer.add(videoInput)
        guard writer.canAdd(systemAudioInput) else { throw MovieRecorderError.cannotAddInput(.systemAudio) }
        writer.add(systemAudioInput)

        // Without a mic, every input exists now, so writing can begin. With a mic we wait
        // for its first buffer to build that input (see `appendMicrophoneLocked`).
        if !includesMicrophone {
            startWritingIfNeeded()
        }
    }

    // MARK: - Append

    /// Hand a captured buffer to the matching track. Safe to call from the separate screen /
    /// system-audio / microphone capture queues concurrently. Buffers that can't yet be
    /// written (pre-session audio, an input that isn't ready) are dropped — M2-T4 counts them.
    public func append(_ buffer: CMSampleBuffer, type: SourceType) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }

        switch type {
        case .screen:
            appendVideoLocked(buffer)
        case .systemAudio:
            appendAudioLocked(buffer, to: systemAudioInput)
        case .microphone:
            appendMicrophoneLocked(buffer)
        }
    }

    private func appendVideoLocked(_ buffer: CMSampleBuffer) {
        // The session epoch is the first video frame's PTS (docs/02 §5). It needs the writer
        // started; with a mic that only happens once the mic input exists, so the earliest
        // frames may be dropped until the mic's first buffer arrives.
        if !didStartSession {
            guard didStartWriting else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(buffer))
            didStartSession = true
        }
        appendIfReadyLocked(buffer, to: videoInput)
    }

    private func appendAudioLocked(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        // No session yet ⇒ audio would lead video (docs/02 §5) and can't be appended — drop it.
        guard didStartSession else { return }
        appendIfReadyLocked(buffer, to: input)
    }

    private func appendMicrophoneLocked(_ buffer: CMSampleBuffer) {
        guard includesMicrophone else { return }
        if microphoneInput == nil {
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let input = Self.makeMicrophoneInput(format: format),
                  writer.canAdd(input) else { return }
            writer.add(input)
            microphoneInput = input
            startWritingIfNeeded()
        }
        guard didStartSession, let input = microphoneInput else { return }
        appendIfReadyLocked(buffer, to: input)
    }

    private func appendIfReadyLocked(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(buffer)
    }

    /// Begins writing once every input has been added. Call under `lock` (or from `init`,
    /// before any concurrent access) — inputs can't be added after this point.
    private func startWritingIfNeeded() {
        guard !didStartWriting else { return }
        didStartWriting = writer.startWriting()
    }

    // MARK: - Finish

    /// Finalizes the movie and returns its URL. Marks each input finished, flushes the
    /// writer, and fails if the session never started or the writer didn't complete. The
    /// tail-frame patch and `finished` event (docs/01) are added in M2-T4.
    public func finish() async throws -> URL {
        guard try beginFinish() else {
            if writer.status == .writing { writer.cancelWriting() }
            throw MovieRecorderError.noFramesWritten
        }
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? MovieRecorderError.finishFailed
        }
        return outputURL
    }

    /// Synchronous, lock-guarded prologue to `finish()`: marks each input finished and
    /// reports whether the session ever started. Split out so the lock is never held across
    /// an `await` — `NSLock` is not async-safe.
    private func beginFinish() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { throw MovieRecorderError.alreadyFinished }
        isFinished = true
        guard didStartSession else { return false }
        videoInput.markAsFinished()
        systemAudioInput.markAsFinished()
        microphoneInput?.markAsFinished()
        return true
    }

    // MARK: - Encoder settings

    private static func videoSettings(
        width: Int, height: Int, frameRate: Int, preset: QualityPreset
    ) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: BitrateModel.averageBitrate(
                    width: width, height: height, frameRate: frameRate, preset: preset),
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ]
    }

    private static func audioSettings(sampleRate: Double, channels: Int, bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: supportedAACBitRate(target: bitRate, sampleRate: sampleRate, channels: channels),
        ]
    }

    /// Snaps `target` to a bitrate the AAC encoder actually accepts for this sample rate and
    /// channel count. Apple's encoder exposes only a discrete set that shrinks with the
    /// format — e.g. a 24 kHz mono AirPods mic tops out at 64 kbps — and an out-of-set value
    /// fails the writer with "encoding parameters not supported" (-12651). Picks the highest
    /// supported rate not exceeding the target; falls back to the target if the encoder can't
    /// be queried (the writer would then surface any real incompatibility itself).
    private static func supportedAACBitRate(target: Int, sampleRate: Double, channels: Int) -> Int {
        let bytesPerFrame = UInt32(2 * channels)
        var sourceASBD = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        guard let source = AVAudioFormat(streamDescription: &sourceASBD),
              let destination = AVAudioFormat(settings: [
                  AVFormatIDKey: kAudioFormatMPEG4AAC,
                  AVSampleRateKey: sampleRate,
                  AVNumberOfChannelsKey: channels,
              ]),
              let converter = AVAudioConverter(from: source, to: destination),
              let rates = converter.applicableEncodeBitRates?.compactMap({ $0.intValue }),
              !rates.isEmpty else {
            return target
        }
        return rates.filter { $0 <= target }.max() ?? rates.min() ?? target
    }

    /// Builds the mic AAC input matching the device-native sample rate/channel count read
    /// from its first buffer (docs/02 §4). Returns nil if the format carries no audio ASBD.
    private static func makeMicrophoneInput(format: CMFormatDescription) -> AVAssetWriterInput? {
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            return nil
        }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings(
                sampleRate: asbd.mSampleRate,
                channels: Int(asbd.mChannelsPerFrame),
                bitRate: 160_000))
        input.expectsMediaDataInRealTime = true
        return input
    }
}

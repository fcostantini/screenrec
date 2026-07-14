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
/// tracks) via a single `AVAssetWriter`. Attach it to a `SampleRouter` and it self-configures
/// from the buffers it receives: the video input is built from the first frame's format
/// (dimensions), the mic input from the first mic buffer's format (docs/02 §4), and the
/// system-audio input up front. Every buffer is rebased through a `TimestampRebaser` and
/// retimed before it is appended, so the file starts at zero and stays monotonic (docs/02 §5).
///
/// Concurrency: buffers arrive on ScreenCaptureKit's three serial output queues, so every
/// mutable field is guarded by `lock` rather than actor isolation (docs/01) — appends stay
/// on the calling queue with no async hop.
public final class MovieRecorder: SampleConsumer, @unchecked Sendable {
    /// The `.mov` this recorder writes. Stable for the recorder's lifetime.
    public let outputURL: URL

    private let frameRate: Int
    private let preset: QualityPreset
    private let includesMicrophone: Bool

    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let systemAudioInput: AVAssetWriterInput
    /// Built lazily from the first buffer of each kind — inputs can't be added after
    /// `startWriting()`, so writing is deferred until every expected input exists.
    private var videoInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?

    private var rebaser = TimestampRebaser()
    private var didStartWriting = false
    private var didStartSession = false
    private var isFinished = false
    private var droppedFrames = 0

    /// The most recent raw video buffer and its rebased PTS, plus the latest rebased PTS on
    /// any track — retained for the stop-time tail-frame patch (docs/02 §5): a static screen
    /// stops delivering frames, so on finish the last frame is re-appended at the end time to
    /// keep the video track as long as the audio.
    private var lastVideoBuffer: CMSampleBuffer?
    private var lastVideoRebasedPTS: CMTime?
    private var latestRebasedPTS: CMTime = .zero

    /// Raw PTS of the first video frame, and how long to wait past it for a selected mic's
    /// first buffer before giving up on the mic track (below).
    private var firstVideoRawPTS: CMTime?
    private static let microphoneGrace = CMTime(seconds: 0.75, preferredTimescale: 600)

    public init(
        outputURL: URL,
        frameRate: Int,
        preset: QualityPreset,
        includesMicrophone: Bool
    ) throws {
        self.outputURL = outputURL
        self.frameRate = frameRate
        self.preset = preset
        self.includesMicrophone = includesMicrophone

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // Fragmented .mov: a kill -9 mid-recording loses at most the last fragment, not the
        // whole file (docs/02 §5). Must be set before startWriting.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        systemAudioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: Self.audioSettings(sampleRate: 48_000, channels: 2, bitRate: 192_000))
        systemAudioInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(systemAudioInput) else { throw MovieRecorderError.cannotAddInput(.systemAudio) }
        writer.add(systemAudioInput)
    }

    /// Video frames dropped because the encoder wasn't ready — reported at stop (docs/01).
    public var droppedFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return droppedFrames
    }

    // MARK: - Consume

    /// Route a captured buffer to its track (`SampleConsumer`). Safe to call from the separate
    /// screen / system-audio / microphone capture queues concurrently.
    public func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }

        // Build this track's input from its first buffer, if it isn't up yet.
        switch type {
        case .screen where videoInput == nil:
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let input = Self.makeVideoInput(format: format, frameRate: frameRate, preset: preset),
                  writer.canAdd(input) else { return }
            writer.add(input)
            videoInput = input
        case .microphone where includesMicrophone && microphoneInput == nil:
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let input = Self.makeMicrophoneInput(format: format),
                  writer.canAdd(input) else { return }
            writer.add(input)
            microphoneInput = input
        default:
            break
        }

        if type == .screen, firstVideoRawPTS == nil { firstVideoRawPTS = bufferPTS(buffer) }

        // Start writing once every expected input exists (video always; mic if enabled; system
        // already added). Until then, drop — these are startup frames, not encoder drops. A
        // selected mic that never delivers a buffer would otherwise block the whole recording;
        // after a short grace past the first video frame, proceed WITHOUT the mic track rather
        // than discard the screen+system capture entirely.
        let micSettled = !includesMicrophone || microphoneInput != nil
            || microphoneGraceExpired(now: bufferPTS(buffer))
        if !didStartWriting, videoInput != nil, micSettled { beginWriting() }
        guard didStartWriting else { return }

        guard case .emit(let rebasedPTS) = rebaser.rebase(rawPTS: bufferPTS(buffer), source: type)
        else { return }

        if !didStartSession {
            // The rebaser drops pre-epoch audio, so the first emitted buffer is the epoch
            // video frame; anchor the session at zero on it.
            guard type == .screen else { return }
            writer.startSession(atSourceTime: rebasedPTS)
            didStartSession = true
        }

        append(buffer, retimedTo: rebasedPTS, source: type)
    }

    /// Retime `buffer` onto the recording timeline and append it, counting a video frame that
    /// the encoder can't accept right now. Must hold `lock`.
    private func append(_ buffer: CMSampleBuffer, retimedTo rebasedPTS: CMTime, source: SourceType) {
        let input: AVAssetWriterInput?
        switch source {
        case .screen: input = videoInput
        case .systemAudio: input = systemAudioInput
        case .microphone: input = microphoneInput
        }
        guard let input else { return }
        guard input.isReadyForMoreMediaData else {
            if source == .screen { droppedFrames += 1 }
            return
        }
        guard let retimed = Self.retimed(buffer, to: rebasedPTS) else { return }
        input.append(retimed)

        if source == .screen {
            lastVideoBuffer = buffer
            lastVideoRebasedPTS = rebasedPTS
        }
        if CMTimeCompare(rebasedPTS, latestRebasedPTS) > 0 { latestRebasedPTS = rebasedPTS }
    }

    // MARK: - Finish

    /// Finalizes the movie and returns its URL. Applies the tail-frame patch, marks each input
    /// finished, flushes the writer, and fails if the session never started or the writer
    /// didn't complete. `droppedFrameCount` holds the reported drop count.
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

    /// Abort without finalizing — used when recording failed before any media was written.
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        if writer.status == .writing { writer.cancelWriting() }
    }

    /// Synchronous, lock-guarded prologue to `finish()`: applies the tail-frame patch, marks
    /// each input finished, and reports whether the session ever started. Split out so the
    /// lock is never held across an `await` — `NSLock` is not async-safe.
    private func beginFinish() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { throw MovieRecorderError.alreadyFinished }
        isFinished = true
        guard didStartSession else { return false }

        // Tail-frame patch: if audio ran past the last video frame (static screen), extend the
        // video track by re-appending that frame at the end time.
        if let buffer = lastVideoBuffer, let lastPTS = lastVideoRebasedPTS,
           let input = videoInput, input.isReadyForMoreMediaData,
           CMTimeCompare(latestRebasedPTS, lastPTS) > 0,
           let tail = Self.retimed(buffer, to: latestRebasedPTS) {
            input.append(tail)
        }

        videoInput?.markAsFinished()
        systemAudioInput.markAsFinished()
        microphoneInput?.markAsFinished()
        return true
    }

    // MARK: - Timing helpers

    private func bufferPTS(_ buffer: CMSampleBuffer) -> CMTime {
        CMSampleBufferGetPresentationTimeStamp(buffer)
    }

    /// Whether the mic-wait grace has elapsed since the first video frame — after which a
    /// selected-but-silent mic is abandoned so the rest of the capture is still saved.
    private func microphoneGraceExpired(now: CMTime) -> Bool {
        guard let first = firstVideoRawPTS, now.isNumeric else { return false }
        return CMTimeCompare(CMTimeSubtract(now, first), Self.microphoneGrace) > 0
    }

    /// Starts the writer, dropping the O_EXCL reservation placeholder in the same synchronous
    /// breath as `startWriting()` creates the real file — `AVAssetWriter` refuses a pre-existing
    /// file, so the reserved name (`OutputLocation.reserveRecordingURL`) is free only for the
    /// microseconds between the remove and the create, not the whole capture-startup window.
    private func beginWriting() {
        try? FileManager.default.removeItem(at: outputURL)
        didStartWriting = writer.startWriting()
    }

    /// Copies `buffer` shifting every timing entry so its presentation timestamp becomes
    /// `newPTS` — sample data is shared, not copied. Returns nil if the buffer has no numeric
    /// timing or the copy fails.
    private static func retimed(_ buffer: CMSampleBuffer, to newPTS: CMTime) -> CMSampleBuffer? {
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard originalPTS.isNumeric else { return nil }
        let delta = CMTimeSubtract(newPTS, originalPTS)

        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0
        else { return nil }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count) == noErr
        else { return nil }
        for index in timings.indices {
            if timings[index].presentationTimeStamp.isNumeric {
                timings[index].presentationTimeStamp = CMTimeAdd(timings[index].presentationTimeStamp, delta)
            }
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = CMTimeAdd(timings[index].decodeTimeStamp, delta)
            }
        }
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: buffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &out) == noErr
        else { return nil }
        return out
    }

    // MARK: - Encoder settings

    private static func makeVideoInput(
        format: CMFormatDescription, frameRate: Int, preset: QualityPreset
    ) -> AVAssetWriterInput? {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoSettings(
                width: Int(dimensions.width), height: Int(dimensions.height),
                frameRate: frameRate, preset: preset))
        input.expectsMediaDataInRealTime = true
        return input
    }

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

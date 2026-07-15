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
    /// Fired once when a mic buffer's format no longer matches the mic input's — a device
    /// switch mid-recording (docs/02 §4). The owner stops cleanly (ADR-007); this recorder
    /// can't hot-swap the input. Invoked on a capture queue with `lock` already released, so
    /// it must still not block that queue (the owner hops to a `Task`).
    private let onMicrophoneFormatChange: (@Sendable () -> Void)?

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

    /// Newest raw PTS seen on any track — the anchor a `pause()` hands the rebaser (docs/02 §5).
    private var latestRawPTS: CMTime = .invalid

    /// The mic input's established audio format, captured when the input is built, and a
    /// one-shot latch so a device switch fires `onMicrophoneFormatChange` exactly once and
    /// then drops the mismatched buffers rather than corrupting the track (docs/02 §4).
    private var microphoneASBD: AudioStreamBasicDescription?
    private var microphoneChangeDetected = false

    public init(
        outputURL: URL,
        frameRate: Int,
        preset: QualityPreset,
        includesMicrophone: Bool,
        onMicrophoneFormatChange: (@Sendable () -> Void)? = nil
    ) throws {
        self.outputURL = outputURL
        self.frameRate = frameRate
        self.preset = preset
        self.includesMicrophone = includesMicrophone
        self.onMicrophoneFormatChange = onMicrophoneFormatChange

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        // Fragmented .mov for crash safety: a fragment is flushed to disk every second, so a
        // kill -9 loses at most ~1 s, not the whole recording, and the file is playable from
        // the first flush on (docs/02 §5). A larger interval (the original 10 s) left anything
        // killed before the first flush unparseable — the §3.2 kill test proved it. Must be set
        // before startWriting.
        writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)

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

    /// Media duration written so far, for a progress ticker. `.invalid` (NaN seconds) until the
    /// first frame starts the session, so callers must guard the conversion (docs/02 §10).
    public var recordedDuration: CMTime {
        lock.lock(); defer { lock.unlock() }
        return didStartSession ? latestRebasedPTS : .invalid
    }

    /// Whether the writer has a session — i.e. a first frame landed and there is now something
    /// worth saving. Ask this rather than decoding `recordedDuration`'s NaN sentinel: callers
    /// were spelling the same question three different ways (`.isNaN`, `.isFinite`,
    /// `!= .invalid`) over a `CMTime → Double` round trip, which is a convention to rediscover
    /// rather than a question to ask. ⚠️ NOT the same as `EngineEvent.started`, which fires on
    /// the first frame — the writer can still be waiting out the mic grace at that point.
    public var hasStartedSession: Bool {
        lock.lock(); defer { lock.unlock() }
        return didStartSession
    }

    // MARK: - Consume

    /// Route a captured buffer to its track (`SampleConsumer`). Safe to call from the separate
    /// screen / system-audio / microphone capture queues concurrently.
    public func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        lock.lock()
        // Notify OUTSIDE the lock: defers run LIFO, so registering this one *before* the unlock
        // makes it run *after* it. `lock` is non-reentrant, and firing a handler under it would
        // deadlock this capture queue if the handler ever touched the recorder.
        var notifyMicrophoneChange = false
        defer { if notifyMicrophoneChange { onMicrophoneFormatChange?() } }
        defer { lock.unlock() }
        guard !isFinished else { return }

        // Newest raw PTS on any track = the pause anchor (docs/02 §5). System audio flows
        // continuously (~43 buffers/s), so this stays within a buffer of real time even while
        // video (frame-on-change) is momentarily idle.
        let rawPTS = bufferPTS(buffer)
        if rawPTS.isNumeric, !latestRawPTS.isNumeric || CMTimeCompare(rawPTS, latestRawPTS) > 0 {
            latestRawPTS = rawPTS
        }

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
            microphoneASBD = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        default:
            break
        }

        if type == .screen, firstVideoRawPTS == nil { firstVideoRawPTS = rawPTS }

        // Start writing once every expected input exists (video always; mic if enabled; system
        // already added). Until then, drop — these are startup frames, not encoder drops. A
        // selected mic that never delivers a buffer would otherwise block the whole recording;
        // after a short grace past the first video frame, proceed WITHOUT the mic track rather
        // than discard the screen+system capture entirely.
        let micSettled = !includesMicrophone || microphoneInput != nil
            || microphoneGraceExpired(now: rawPTS)
        if !didStartWriting, videoInput != nil, micSettled { beginWriting() }
        guard didStartWriting else { return }

        // Mic device swap mid-recording (AirPods die → built-in takes over) changes the audio
        // format; a differently-formatted buffer can't go into the established mic input without
        // corrupting the track (docs/02 §4). v1 is fail-stop (ADR-007): notify once so the owner
        // stops cleanly, and drop the offending buffers — the file finalizes playable. Sits after
        // the writing gate on purpose: a swap before the session starts would otherwise stop a
        // recording with nothing written (a `.failed`, output discarded) purely on sub-frame
        // timing; those buffers are already dropped above, so the recording just carries on.
        if type == .microphone, microphoneInput != nil {
            if microphoneChangeDetected { return }
            if microphoneFormatDiffers(buffer) {
                microphoneChangeDetected = true
                notifyMicrophoneChange = true
                return
            }
        }

        guard case .emit(let rebasedPTS) = rebaser.rebase(rawPTS: rawPTS, source: type)
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

    // MARK: - Pause / resume

    /// Pause the recording timeline: incoming buffers are dropped until `resume()`, and the
    /// paused span is removed from the output (docs/02 §5), anchored at the newest raw PTS seen.
    /// Returns whether it took effect — `false` before the first frame, when already paused, or
    /// after finishing — so a caller can keep a user-visible "paused" signal honest.
    @discardableResult
    public func pause() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isFinished else { return false }
        return rebaser.pause(atRawPTS: latestRawPTS)
    }

    /// Resume after `pause()`: the next complete video frame re-anchors the timeline (docs/02
    /// §5). Returns whether it took effect (`false` when not paused or after finishing).
    @discardableResult
    public func resume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !isFinished else { return false }
        return rebaser.resume()
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
        removeReservationPlaceholderIfUnused()
    }

    /// If the writer never created the real file, the reservation placeholder
    /// (`OutputLocation.reserveRecordingURL`/`reserveExact`) is still on disk — remove it so a
    /// recording that failed before writing leaves no 0-byte litter, and an explicit output
    /// path can be retried. Call under `lock`. When the writer did start, `cancelWriting()`
    /// (not this) removes its own partial file.
    private func removeReservationPlaceholderIfUnused() {
        if !didStartWriting { try? FileManager.default.removeItem(at: outputURL) }
    }

    /// Synchronous, lock-guarded prologue to `finish()`: applies the tail-frame patch, marks
    /// each input finished, and reports whether the session ever started. Split out so the
    /// lock is never held across an `await` — `NSLock` is not async-safe.
    private func beginFinish() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { throw MovieRecorderError.alreadyFinished }
        isFinished = true
        guard didStartSession else {
            removeReservationPlaceholderIfUnused()
            return false
        }

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

    /// Whether `buffer`'s audio format differs from the mic input's established format — a
    /// changed sample rate, channel count, or format ID means the capture device switched
    /// (docs/02 §4). Must hold `lock`.
    private func microphoneFormatDiffers(_ buffer: CMSampleBuffer) -> Bool {
        guard let established = microphoneASBD,
              let format = CMSampleBufferGetFormatDescription(buffer),
              let current = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return false }
        return current.mSampleRate != established.mSampleRate
            || current.mChannelsPerFrame != established.mChannelsPerFrame
            || current.mFormatID != established.mFormatID
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

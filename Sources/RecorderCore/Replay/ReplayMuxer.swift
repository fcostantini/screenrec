import AVFoundation
import CoreMedia
import Foundation

/// Errors a replay save surfaces to the user (docs/06's "Couldn't save replay" copy at T5).
public enum ReplayMuxerError: Error, Equatable {
    /// The video ring holds nothing encodable yet — armed moments ago, or the screen never
    /// delivered a frame.
    case nothingBuffered
    /// The writer refused an input or ended in a failed state; message is user-facing.
    case writerFailed(String)
}

/// Turns the replay rings into a playable `Replay … .mov` on demand (02 §9, docs/01): snapshot
/// → keyframe-aligned trim → rebase to zero → one `AVAssetWriter` pass with passthrough video
/// (no re-encode) and AAC audio. The rings keep rolling — a save only ever reads snapshots.
///
/// The clip window ends at the newest pts across all rings, and a screen that sat still gets
/// the tail-frame treatment (frozen frame under live audio) — the same frame-on-change
/// accounting as MovieRecorder (docs/02 §5).
///
/// Concurrency: `requestSave` is thread-safe and returns immediately; the mux runs on a
/// utility queue. Concurrent requests coalesce (02 §9: ignore while one is in flight) — that
/// is §6.3's two-rapid-triggers requirement.
public final class ReplayMuxer: @unchecked Sendable {
    /// A completed save: where it landed and the clip's media duration.
    public struct SavedReplay: Sendable {
        public let url: URL
        public let duration: Double

        public init(url: URL, duration: Double) {
            self.url = url
            self.duration = duration
        }
    }

    private let encoder: ReplayEncoder
    private let systemRing: ReplayAudioRing
    private let microphoneRing: ReplayAudioRing?
    private let seconds: Double
    private let outputLocation: OutputLocation

    private let lock = NSLock()
    private var isSaving = false
    private let muxQueue = DispatchQueue(label: "dev.fcostantini.screenrec.replay.mux", qos: .utility)

    /// Rebased gap above which the last frame is re-appended at the clip end so video and audio
    /// end together; below it, the video is effectively current and a patch would collide.
    private static let tailPatchThreshold = CMTime(seconds: 0.25, preferredTimescale: 600)

    public init(
        encoder: ReplayEncoder,
        systemRing: ReplayAudioRing,
        microphoneRing: ReplayAudioRing?,
        seconds: Double,
        outputDirectory: URL
    ) {
        self.encoder = encoder
        self.systemRing = systemRing
        self.microphoneRing = microphoneRing
        self.seconds = seconds
        outputLocation = OutputLocation(directory: outputDirectory)
    }

    /// Kicks off a save of the last `seconds` and returns immediately: `true` if accepted,
    /// `false` if a save is already in flight — the request is dropped and **its `completion`
    /// is never invoked** (the in-flight save's own completion covers the outcome). An accepted
    /// request's `completion` fires exactly once, on the mux queue.
    @discardableResult
    public func requestSave(completion: @escaping @Sendable (Result<SavedReplay, Error>) -> Void) -> Bool {
        lock.lock()
        guard !isSaving else {
            lock.unlock()
            return false
        }
        isSaving = true
        lock.unlock()

        muxQueue.async { [self] in
            let result = Result { try performSave() }
            lock.lock()
            isSaving = false
            lock.unlock()
            completion(result)
        }
        return true
    }

    /// Blocks until no save is in flight. The CLI calls this before exiting so a stop can't
    /// kill the writer mid-file; a no-op when idle.
    public func waitUntilIdle() {
        muxQueue.sync {}
    }

    private func performSave() throws -> SavedReplay {
        // Drain the VT pipeline first: the frames nearest the trigger are the point of the save.
        encoder.completePendingFrames()

        // The window ends at the newest pts across ALL rings — audio flows continuously, so
        // this is ≈ the trigger time even when a static screen has left the video ring stale
        // (frame-on-change). Anchoring at the video ring alone would save old content.
        let anchor = [encoder.newestPTS(), systemRing.newestPTS(), microphoneRing?.newestPTS()]
            .compactMap { $0 }
            .max { CMTimeCompare($0, $1) < 0 }
        guard let anchor else { throw ReplayMuxerError.nothingBuffered }

        var video = encoder.clip(seconds: seconds, endingAt: anchor)
        guard let firstVideo = video.first, let lastVideo = video.last,
              let videoFormat = CMSampleBufferGetFormatDescription(firstVideo.element)
        else { throw ReplayMuxerError.nothingBuffered }

        // Video is always rebased by its own keyframe start. Audio shares that origin — except
        // when the screen sat still for the whole window (the retained GOP predates it): then
        // the audio takes the true last N seconds while the stale GOP plays frozen at the top.
        let windowStart = CMTimeSubtract(anchor, CMTime(seconds: seconds, preferredTimescale: 600))
        let videoIsStale = CMTimeCompare(lastVideo.pts, windowStart) <= 0
        let videoOffset = firstVideo.pts
        let audioOffset = videoIsStale ? windowStart : firstVideo.pts
        // The clip's end in file time — also its duration.
        let clipEnd = CMTimeSubtract(anchor, audioOffset)

        // Tail patch (docs/02 §5): if the video ends meaningfully before the clip does,
        // re-append the last frame at the end so the frozen screen spans the full clip. The
        // patch carries an explicit duration: VT samples have invalid durations and the writer
        // infers a track's LAST from the previous pts delta — the whole frozen gap, otherwise.
        let videoEndInFile = CMTimeSubtract(lastVideo.pts, videoOffset)
        if CMTimeCompare(CMTimeSubtract(clipEnd, videoEndInFile), Self.tailPatchThreshold) > 0 {
            let target = CMTimeAdd(videoOffset, clipEnd)
            if let patch = SampleTiming.retimed(
                lastVideo.element, to: target, duration: CMTime(value: 1, timescale: 30)) {
                video.append(RingEntry(element: patch, pts: target, isKeyframe: false))
            }
        }

        let url = try outputLocation.reserveRecordingURL(prefix: "Replay", date: Date())
        do {
            try write(
                to: url, videoFormat: videoFormat,
                video: video, videoOffset: videoOffset,
                systemAudio: systemRing.entries(startingAt: audioOffset),
                microphoneAudio: microphoneRing?.entries(startingAt: audioOffset) ?? [],
                audioOffset: audioOffset)
        } catch {
            // No torn files, no 0-byte reservation litter (§6.3 / OutputLocation's contract).
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        let duration = clipEnd.seconds
        return SavedReplay(url: url, duration: duration.isFinite ? duration : 0)
    }

    private func write(
        to url: URL,
        videoFormat: CMFormatDescription,
        video: [RingEntry<CMSampleBuffer>],
        videoOffset: CMTime,
        systemAudio: [RingEntry<CMSampleBuffer>],
        microphoneAudio: [RingEntry<CMSampleBuffer>],
        audioOffset: CMTime
    ) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Passthrough: the ring already holds encoded HEVC; `outputSettings: nil` +
        // `sourceFormatHint` writes it without a decode/re-encode pass (02 §9).
        let videoInput = AVAssetWriterInput(
            mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        var feeds: [(AVAssetWriterInput, [RingEntry<CMSampleBuffer>], CMTime)] = [
            (videoInput, video, videoOffset)
        ]
        if let input = Self.makeAACInput(for: systemAudio, bitRate: 192_000) {
            feeds.append((input, systemAudio, audioOffset))
        }
        if let input = Self.makeAACInput(for: microphoneAudio, bitRate: 160_000) {
            feeds.append((input, microphoneAudio, audioOffset))
        }
        for (input, _, _) in feeds {
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw ReplayMuxerError.writerFailed("The writer refused a \(input.mediaType.rawValue) track.")
            }
            writer.add(input)
        }

        // Drop the O_EXCL reservation placeholder in the same breath as `startWriting()`
        // creates the real file (the MovieRecorder pattern — the writer refuses existing files).
        try? FileManager.default.removeItem(at: url)
        guard writer.startWriting() else {
            throw ReplayMuxerError.writerFailed(
                writer.error?.localizedDescription ?? "The writer couldn't start.")
        }
        writer.startSession(atSourceTime: .zero)

        let group = DispatchGroup()
        let failure = AppendFailure()
        for (input, entries, offset) in feeds {
            append(entries, rebasedBy: offset, to: input, writer: writer, group: group, failure: failure)
        }
        group.wait()

        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw ReplayMuxerError.writerFailed(
                writer.error?.localizedDescription ?? "The writer didn't complete.")
        }
        // Checked after the writer settles: a dropped delta frame corrupts decode to the next
        // keyframe, so a save with any skipped sample must fail loudly, not announce ✓.
        if let message = failure.message {
            throw ReplayMuxerError.writerFailed(message)
        }
    }

    /// An AAC input matching the ring's PCM format, or nil when there's no audio to write
    /// (no track beats an empty track).
    private static func makeAACInput(
        for entries: [RingEntry<CMSampleBuffer>], bitRate: Int
    ) -> AVAssetWriterInput? {
        guard let first = entries.first,
              let format = CMSampleBufferGetFormatDescription(first.element),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return nil }
        return AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: AudioEncodingSettings.aac(
                sampleRate: asbd.mSampleRate,
                channels: Int(asbd.mChannelsPerFrame),
                bitRate: bitRate))
    }

    /// First append problem across the three drains; one message is enough to fail the save.
    private final class AppendFailure: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?

        var message: String? {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func report(_ message: String) {
            lock.lock()
            if stored == nil { stored = message }
            lock.unlock()
        }
    }

    /// Feeds one input from an in-memory entry list, rebasing each sample to `pts − offset`.
    /// `requestMediaDataWhenReady` re-invokes the block as the writer drains; the captured
    /// index and `done` flag carry progress across invocations (serial per input queue).
    private func append(
        _ entries: [RingEntry<CMSampleBuffer>],
        rebasedBy offset: CMTime,
        to input: AVAssetWriterInput,
        writer: AVAssetWriter,
        group: DispatchGroup,
        failure: AppendFailure
    ) {
        group.enter()
        let queue = DispatchQueue(label: "dev.fcostantini.screenrec.replay.mux.append")
        var index = 0
        var done = false
        input.requestMediaDataWhenReady(on: queue) {
            guard !done else { return }
            func finish() {
                done = true
                input.markAsFinished()
                group.leave()
            }
            while input.isReadyForMoreMediaData {
                // A failed writer may never call this block again — leave now or the
                // group.wait() above deadlocks and the isSaving latch wedges every later save.
                guard writer.status == .writing else { return finish() }
                guard index < entries.count else { return finish() }
                let entry = entries[index]
                index += 1
                guard let sample = SampleTiming.retimed(
                    entry.element, to: CMTimeSubtract(entry.pts, offset)) else {
                    failure.report("Couldn't retime a \(input.mediaType.rawValue) sample.")
                    return finish()
                }
                input.append(sample)
            }
        }
    }
}

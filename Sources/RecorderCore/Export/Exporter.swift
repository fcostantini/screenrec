import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Failures a share-export surfaces; messages are user-facing (docs/06 copy discipline).
public enum ExportError: Error, Equatable {
    case unreadable(String)
    case noVideoTrack
    case outputCollidesWithInput
    case readerFailed(String)
    case writerFailed(String)
}

/// Knobs for a "share" transcode. Defaults are the messaging profile (ADR-016): H.264 High +
/// AAC `.mp4`, downscaled, `+faststart` — the ffmpeg recipe this replaces.
public struct ExportConfiguration: Sendable {
    /// The output is scaled to fit within `maxWidth × maxHeight`, aspect preserved; a smaller
    /// source is never upscaled. 1920 wide is the recipe's value; the height ceiling keeps us
    /// under AVAssetWriter's 4096×2304 H.264 cap (02 §3), which capture (4112×2570) exceeds.
    public var maxWidth: Int
    public var maxHeight: Int
    public var videoBitRate: Int
    public var audioBitRate: Int
    public var keyFrameIntervalSeconds: Double

    public init(
        maxWidth: Int = 1920,
        maxHeight: Int = 2304,
        videoBitRate: Int = 6_000_000,
        audioBitRate: Int = 160_000,
        keyFrameIntervalSeconds: Double = 2
    ) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.videoBitRate = videoBitRate
        self.audioBitRate = audioBitRate
        self.keyFrameIntervalSeconds = keyFrameIntervalSeconds
    }
}

/// A completed export.
public struct ExportResult: Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let duration: Double
    public let byteCount: Int
}

/// Transcodes an existing recording to a messaging/web-friendly `.mp4` (ADR-016): read the
/// `.mov` with `AVAssetReader`, re-encode video to H.264 High and mix every audio track down to
/// one AAC track, write with `+faststart`. Capture stays HEVC `.mov` (ADR-004) — this only
/// derives a share copy. The `AVAssetReader` read side is what M10-T3 (GIF) and M10-T4 (trim)
/// build on.
public enum Exporter {
    /// The `.mp4` sibling of an input path (same folder, extension swapped). Pure.
    public static func mp4Sibling(of input: URL) -> URL {
        input.deletingPathExtension().appendingPathExtension("mp4")
    }

    /// `preferred` if free, else the first ` 2`, ` 3`… variant that doesn't exist — so a repeat
    /// export never clobbers an earlier one.
    public static func availableURL(basedOn preferred: URL) -> URL {
        let manager = FileManager.default
        guard manager.fileExists(atPath: preferred.path) else { return preferred }
        let ext = preferred.pathExtension
        let stemPath = preferred.deletingPathExtension().path
        var index = 2
        while true {
            let next = URL(fileURLWithPath: "\(stemPath) \(index)").appendingPathExtension(ext)
            if !manager.fileExists(atPath: next.path) { return next }
            index += 1
        }
    }

    /// The output pixel size for a `width × height` source under `configuration`: scaled to fit
    /// the ceilings, aspect preserved, never upscaled, both dimensions rounded to even (H.264
    /// requires even dimensions). Pure.
    static func fittedSize(
        width: Int, height: Int, configuration: ExportConfiguration
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(
            1.0,
            Double(configuration.maxWidth) / Double(width),
            Double(configuration.maxHeight) / Double(height))
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// Transcodes `input` to `output`. `progress` (0…1, on a background queue) tracks the video
    /// pass. Blocking work runs off the cooperative pool. Throws before writing on a bad input,
    /// leaving no partial file.
    public static func exportToMP4(
        from input: URL,
        to output: URL,
        configuration: ExportConfiguration = ExportConfiguration(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ExportResult {
        // Identity, not string equality: a symlink, the /tmp→/private/tmp alias, or a
        // case-insensitive volume can make two different paths the same file, and the pre-write
        // delete would then destroy the input recording.
        guard !sameFile(output, input) else { throw ExportError.outputCollidesWithInput }

        let asset = AVURLAsset(url: input)
        let tracks: [AVAssetTrack]
        let assetDuration: CMTime
        do {
            tracks = try await asset.load(.tracks)
            assetDuration = try await asset.load(.duration)
        } catch {
            throw ExportError.unreadable(
                "Couldn't read “\(input.lastPathComponent)”. \(error.localizedDescription)")
        }
        guard let videoTrack = tracks.first(where: { $0.mediaType == .video }) else {
            throw ExportError.noVideoTrack
        }
        let audioTracks = tracks.filter { $0.mediaType == .audio }
        let (naturalSize, videoRange) = try await videoTrack.load(.naturalSize, .timeRange)
        let target = fittedSize(
            width: Int(naturalSize.width.rounded()),
            height: Int(naturalSize.height.rounded()),
            configuration: configuration)

        let plan = try TranscodePlan(
            asset: asset, videoTrack: videoTrack, audioTracks: audioTracks,
            output: output, target: target, sessionStart: videoRange.start,
            configuration: configuration)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                transcodeQueue.async {
                    continuation.resume(with: Result {
                        try plan.run(durationSeconds: assetDuration.seconds, progress: progress)
                    })
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: output)  // no torn file on failure
            throw error
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))
            .flatMap { $0[.size] as? Int } ?? 0
        // The file is rebased to zero from `sessionStart`, so the clip's duration is what remains
        // after it — identical to the source when the recording starts at PTS 0, as ours do.
        let clip = CMTimeSubtract(assetDuration, videoRange.start).seconds
        return ExportResult(
            url: output, width: target.width, height: target.height,
            duration: clip.isFinite ? max(0, clip) : 0, byteCount: bytes)
    }

    /// True when both URLs resolve to the same file on disk (not merely the same string). Resolve
    /// symlinks first: `resourceValues` reports a symlink's own identity, not its target's.
    private static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.resolvingSymlinksInPath()
        let right = rhs.resolvingSymlinksInPath()
        let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        if let idL = (try? left.resourceValues(forKeys: key))?.fileResourceIdentifier,
            let idR = (try? right.resourceValues(forKeys: key))?.fileResourceIdentifier {
            return idL.isEqual(idR)
        }
        // One side doesn't exist yet (no identity to read) — fall back to a resolved-path compare.
        return left.standardizedFileURL == right.standardizedFileURL
    }

    private static let transcodeQueue = DispatchQueue(
        label: "dev.fcostantini.screenrec.export", qos: .userInitiated)
}

/// A configured reader/writer pair, ready to drain. Split out so the async property loads sit in
/// `Exporter` and the blocking pass sits here, off the cooperative pool.
private struct TranscodePlan {
    let reader: AVAssetReader
    let videoOutput: AVAssetReaderTrackOutput
    let audioOutput: AVAssetReaderAudioMixOutput?
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
    let sessionStart: CMTime
    let output: URL

    init(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTracks: [AVAssetTrack],
        output: URL,
        target: (width: Int, height: Int),
        sessionStart: CMTime,
        configuration: ExportConfiguration
    ) throws {
        reader = try AVAssetReader(asset: asset)
        // A pixel-format hint forces decode (nil would pass compressed HEVC through). The writer
        // then re-encodes; the encoder scales the source frames to the input's configured size.
        videoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw ExportError.readerFailed("The reader refused the video track.")
        }
        reader.add(videoOutput)

        if audioTracks.isEmpty {
            audioOutput = nil
        } else {
            // Mix every audio track (system + mic) down to one stereo PCM stream — messaging
            // apps expect a single track (recipe's `amix=inputs=2`).
            let mix = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks,
                audioSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ])
            mix.alwaysCopiesSampleData = false
            guard reader.canAdd(mix) else {
                throw ExportError.readerFailed("The reader refused the mixed audio track.")
            }
            reader.add(mix)
            audioOutput = mix
        }

        writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true  // +faststart: moov ahead of mdat.

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: target.width,
                AVVideoHeightKey: target.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: configuration.videoBitRate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalDurationKey: configuration.keyFrameIntervalSeconds,
                    // No B-frames: a share clip is bitrate-capped (they barely help size) and
                    // monotonic decode order is the most compatible, cleanest output.
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ])
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else {
            throw ExportError.writerFailed("The writer refused the video track.")
        }
        writer.add(videoInput)

        if audioOutput != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: AudioEncodingSettings.aac(
                    sampleRate: 48_000, channels: 2, bitRate: configuration.audioBitRate))
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else {
                throw ExportError.writerFailed("The writer refused the audio track.")
            }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        self.sessionStart = sessionStart
        self.output = output
    }

    /// Reads both tracks to exhaustion, feeding the writer; blocks until the file is finalized.
    func run(durationSeconds: Double, progress: (@Sendable (Double) -> Void)?) throws {
        // Free the hardware decode/encode sessions promptly on any early return (repeated
        // exports, M10); a clean finish leaves both terminal, so this no-ops on success.
        var completed = false
        defer {
            if !completed {
                if reader.status == .reading { reader.cancelReading() }
                if writer.status == .writing { writer.cancelWriting() }
            }
        }

        guard reader.startReading() else {
            throw ExportError.readerFailed(
                reader.error?.localizedDescription ?? "The reader couldn't start.")
        }
        // Clear a stale target in the same breath as starting to write (the ReplayMuxer idiom):
        // a construction failure above leaves an existing file untouched, and the writer refuses
        // to overwrite otherwise.
        try? FileManager.default.removeItem(at: output)
        guard writer.startWriting() else {
            throw ExportError.writerFailed(
                writer.error?.localizedDescription ?? "The writer couldn't start.")
        }
        // The writer maps each sample to `pts − sessionStart`, so the file starts at zero even
        // when the source doesn't. Samples before this time (rare stray audio) are trimmed.
        writer.startSession(atSourceTime: sessionStart)

        let group = DispatchGroup()
        let failure = FailureBox()
        drain(videoOutput, into: videoInput, label: "video", group: group, failure: failure) { sample in
            guard let progress, durationSeconds > 0 else { return }
            let elapsed = CMTimeGetSeconds(
                CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), sessionStart))
            progress(min(1, max(0, elapsed / durationSeconds)))
        }
        if let audioInput, let audioOutput {
            drain(audioOutput, into: audioInput, label: "audio", group: group, failure: failure, onSample: nil)
        }
        group.wait()

        guard reader.status != .failed else {
            throw ExportError.readerFailed(
                reader.error?.localizedDescription ?? "Reading the recording failed.")
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw ExportError.writerFailed(
                writer.error?.localizedDescription ?? "Writing the MP4 didn't complete.")
        }
        if let message = failure.message { throw ExportError.writerFailed(message) }
        completed = true
        progress?(1)
    }

    /// Pumps one reader output into one writer input on its own serial queue, re-invoked by
    /// `requestMediaDataWhenReady` as the writer drains. The `done` flag guards the single
    /// `group.leave()` against a re-fire after finishing (the ReplayMuxer pattern).
    private func drain(
        _ source: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        label: String,
        group: DispatchGroup,
        failure: FailureBox,
        onSample: (@Sendable (CMSampleBuffer) -> Void)?
    ) {
        group.enter()
        let queue = DispatchQueue(label: "dev.fcostantini.screenrec.export.\(label)")
        var done = false
        input.requestMediaDataWhenReady(on: queue) {
            guard !done else { return }
            func finish() {
                done = true
                input.markAsFinished()
                group.leave()
            }
            while input.isReadyForMoreMediaData {
                guard reader.status == .reading else { return finish() }
                guard let sample = source.copyNextSampleBuffer() else { return finish() }
                guard input.append(sample) else {
                    failure.report(
                        writer.error?.localizedDescription
                            ?? "The writer refused a \(input.mediaType.rawValue) sample.")
                    return finish()
                }
                onSample?(sample)
            }
        }
    }

    /// First append/writer error across the two drains; one message fails the export.
    private final class FailureBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?
        var message: String? { lock.withLock { stored } }
        func report(_ message: String) { lock.withLock { if stored == nil { stored = message } } }
    }
}

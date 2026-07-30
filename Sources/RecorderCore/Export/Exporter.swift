import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Failures a share-export surfaces; messages are user-facing (docs/06 copy discipline).
public enum ExportError: Error, Equatable {
    case unreadable(String)
    case noVideoTrack
    case outputCollidesWithInput
    case emptyRange
    case readerFailed(String)
    case writerFailed(String)
}

/// The part of a recording to export, in seconds from the start of the file (M21-T1). A struct
/// rather than a `ClosedRange`, which traps on construction — an inverted range has to reach
/// `exportToMP4` to be refused as `emptyRange` instead of crashing its caller.
public struct ExportRange: Sendable, Equatable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

/// Knobs for a "share" transcode. Defaults are the messaging profile (ADR-016): H.264 High +
/// AAC `.mp4`, downscaled, `+faststart` — the ffmpeg recipe this replaces.
public struct ExportConfiguration: Sendable {
    /// The output is scaled to fit within `maxWidth × maxHeight`, aspect preserved; a smaller
    /// source is never upscaled. `maxHeight` is the compatibility ceiling, not an API limit: the
    /// writer will encode 4112×2570 H.264 quite happily, but only by moving to Level 6.0, which
    /// most phone decoders refuse. 4096×2304 is exactly Level 5.2's frame size (02 §3).
    public var maxWidth: Int
    public var maxHeight: Int
    /// The video rate at `referenceSize`; the real rate scales with the output's pixel count
    /// (M18-T2), so a 3686-wide export isn't encoded at a 1920-wide budget.
    public var referenceVideoBitRate: Int
    public var audioBitRate: Int
    public var keyFrameIntervalSeconds: Double

    /// The size `referenceVideoBitRate` is quoted at.
    static let referenceSize = (width: 1920, height: 1200)
    static let maximumVideoBitRate = 24_000_000

    public init(
        maxWidth: Int = 1920,
        maxHeight: Int = 2304,
        referenceVideoBitRate: Int = 6_000_000,
        audioBitRate: Int = 160_000,
        keyFrameIntervalSeconds: Double = 2
    ) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.referenceVideoBitRate = referenceVideoBitRate
        self.audioBitRate = audioBitRate
        self.keyFrameIntervalSeconds = keyFrameIntervalSeconds
    }

    /// The rate for a `width × height` output: the reference scaled by pixel count, but never
    /// *below* the reference — a smaller output than 1920×1200 keeps the rate it has always had,
    /// so no existing export gets softer (region and window recordings are mostly smaller).
    func videoBitRate(forWidth width: Int, height: Int) -> Int {
        guard width > 0, height > 0 else { return referenceVideoBitRate }
        let referencePixels = Self.referenceSize.width * Self.referenceSize.height
        let scaled = Double(referenceVideoBitRate) * Double(width * height) / Double(referencePixels)
        return min(max(Int(scaled.rounded()), referenceVideoBitRate), Self.maximumVideoBitRate)
    }

    /// What a minute of `width × height` output costs at these rates — what the Size picker quotes
    /// (M19-T4). A budget, not a promise: VideoToolbox spends less on easy content (12.9 Mbps
    /// against a 22.1 Mbps target on a static desktop, docs/07), so quote it via `ApproximateBytes`.
    public func bytesPerMinute(forWidth width: Int, height: Int) -> Int64 {
        Int64(videoBitRate(forWidth: width, height: height) + audioBitRate) * 60 / 8
    }

    /// What an export of a `sourceWidth × sourceHeight` source lasting `seconds` can weigh at these
    /// settings — the rate budget over the length, at the size the export will really produce.
    /// One definition, so a row that *quotes* a weight and a guard that *refuses* on one can't drift.
    ///
    /// ⚠️ Inherits `bytesPerMinute`'s ceiling: measured ~3.7× over a real take on quiet content
    /// (docs/07). That is the intended direction — under-quoting would let a doomed export start.
    public func projectedBytes(sourceWidth: Int, sourceHeight: Int, seconds: Double) -> Int64 {
        let fitted = Exporter.fittedSize(
            width: sourceWidth, height: sourceHeight, configuration: self)
        let perMinute = bytesPerMinute(forWidth: fitted.width, height: fitted.height)
        return Int64(Double(perMinute) * seconds / 60)
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

    /// Where a share export of `input` belongs: its `.mp4` sibling, or the ` trimmed` one when only
    /// `range` is written (M21-T1) — a clip must not sit in the folder looking like an export of the
    /// whole take. One rule, so the app and the CLI can't name the same export differently.
    public static func mp4Sibling(of input: URL, range: ExportRange?) -> URL {
        mp4Sibling(of: range == nil ? input : Trimmer.trimmedSibling(of: input))
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

    /// The output pixel size for a `width × height` source fitted within `maxWidth × maxHeight`:
    /// aspect preserved, never upscaled, both dimensions rounded to even (H.264 requires even; GIF
    /// tolerates it). Pure — shared by the MP4 and GIF (M10-T3) paths.
    static func fittedSize(
        width: Int, height: Int, maxWidth: Int, maxHeight: Int
    ) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1.0, Double(maxWidth) / Double(width), Double(maxHeight) / Double(height))
        func even(_ value: Double) -> Int { max(2, Int((value / 2).rounded()) * 2) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// The share export's fit, clamped to `levelSafeBox` — no configuration can opt out of the
    /// ceiling, because exceeding it is silent (the encoder just emits Level 6.0) and only shows up
    /// on someone else's phone. Public so a surface can state the size a pick will really produce:
    /// the Size picker's "Largest" row is a fit, not a number (M18-T2).
    public static func fittedSize(
        width: Int, height: Int, configuration: ExportConfiguration
    ) -> (width: Int, height: Int) {
        fittedSize(
            width: width, height: height,
            maxWidth: min(configuration.maxWidth, levelSafeBox.width),
            maxHeight: min(configuration.maxHeight, levelSafeBox.height))
    }

    /// The largest frame H.264 Level 5.2 allows — 36 864 macroblocks (docs/02 §3). One definition,
    /// so the CLI flag, the Settings list and the encode can't drift apart.
    public static let levelSafeBox = (width: 4096, height: 2304)

    /// Transcodes `input` to `output`, or just `range` of it (M21-T1). `progress` (0…1, on a
    /// background queue) tracks the video pass. Blocking work runs off the cooperative pool. Throws
    /// before writing on a bad input, leaving no partial file.
    public static func exportToMP4(
        from input: URL,
        to output: URL,
        configuration: ExportConfiguration = ExportConfiguration(),
        range: ExportRange? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ExportResult {
        // Identity, not string equality: a symlink, the /tmp→/private/tmp alias, or a
        // case-insensitive volume can make two different paths the same file, and the pre-write
        // delete would then destroy the input recording.
        guard !sameFile(output, input) else { throw ExportError.outputCollidesWithInput }
        // Judged before the asset loads, and not covered by the clamp below: a negative start would
        // clamp to the first sample and quietly export a range nobody asked for.
        if let range {
            guard range.start >= 0, range.end > range.start else { throw ExportError.emptyRange }
        }

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

        // What to write, in asset time: the whole file, or the requested range clamped to the media
        // that exists. A ranged read starts wherever it is asked to — the reader decodes from the
        // preceding sync sample and clips the samples it hands back (measured, docs/07) — so no
        // frames from before the in-point reach the file.
        let clipStart = range.map {
            CMTimeMaximum(CMTime(seconds: $0.start, preferredTimescale: 600), videoRange.start)
        } ?? videoRange.start
        let clipEnd = range.map {
            CMTimeMinimum(CMTime(seconds: $0.end, preferredTimescale: 600), assetDuration)
        } ?? assetDuration
        guard CMTimeCompare(clipEnd, clipStart) > 0 else { throw ExportError.emptyRange }
        let clipDuration = CMTimeSubtract(clipEnd, clipStart)
        // Only a ranged export narrows the read; a whole-file one keeps the reader's own default,
        // so its behaviour is untouched.
        let readRange = range == nil ? nil : CMTimeRange(start: clipStart, end: clipEnd)

        // Write to the `.partial` companion and rename only once the file is complete (M15-T3, the
        // recording path's discipline): a crash or quit mid-export then leaves nothing at the final
        // name for the menu's Recent Exports to offer as a finished file.
        let scratch = OutputLocation.partialURL(for: output)
        let plan = try TranscodePlan(
            asset: asset, videoTrack: videoTrack, audioTracks: audioTracks,
            output: scratch, target: target, sessionStart: clipStart,
            readRange: readRange, configuration: configuration)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                transcodeQueue.async {
                    continuation.resume(with: Result {
                        try plan.run(durationSeconds: clipDuration.seconds, progress: progress)
                    })
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: scratch)  // no torn file on failure
            OutputLocation.removeWriterScratch(beside: scratch)
            throw error
        }

        OutputLocation.removeWriterScratch(beside: scratch)
        let output = try OutputLocation.finalizePartial(scratch)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))
            .flatMap { $0[.size] as? Int } ?? 0
        // The file is rebased to zero from `sessionStart`, so what it holds is the span written.
        let clip = clipDuration.seconds
        return ExportResult(
            url: output, width: target.width, height: target.height,
            duration: clip.isFinite ? max(0, clip) : 0, byteCount: bytes)
    }

    /// True when both URLs resolve to the same file on disk (not merely the same string). Resolve
    /// symlinks first: `resourceValues` reports a symlink's own identity, not its target's. Shared
    /// with the GIF path (M10-T3) as the delete-source guard.
    static func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
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
        readRange: CMTimeRange?,
        configuration: ExportConfiguration
    ) throws {
        reader = try AVAssetReader(asset: asset)
        if let readRange { reader.timeRange = readRange }  // must precede `startReading`
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
                    AVVideoAverageBitRateKey: configuration.videoBitRate(
                        forWidth: target.width, height: target.height),
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
        let failure = FirstError()
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

    /// Pumps one reader output into one writer input on its own serial queue; `WriterDrain` owns the
    /// group/finish discipline. A reader that left `.reading`, an exhausted source, or a refused
    /// append ends the pump — the last after recording the writer's error.
    private func drain(
        _ source: AVAssetReaderOutput,
        into input: AVAssetWriterInput,
        label: String,
        group: DispatchGroup,
        failure: FirstError,
        onSample: (@Sendable (CMSampleBuffer) -> Void)?
    ) {
        let queue = DispatchQueue(label: "dev.fcostantini.screenrec.export.\(label)")
        WriterDrain.drain(into: input, on: queue, group: group) {
            guard reader.status == .reading else { return false }
            guard let sample = source.copyNextSampleBuffer() else { return false }
            guard input.append(sample) else {
                failure.report(
                    writer.error?.localizedDescription
                        ?? "The writer refused a \(input.mediaType.rawValue) sample.")
                return false
            }
            onSample?(sample)
            return true
        }
    }
}

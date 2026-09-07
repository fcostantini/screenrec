import AVFoundation
import CoreMedia
import Foundation

/// Failures an audio export surfaces; messages are user-facing (docs/06 copy discipline).
public enum AudioExportError: Error, Equatable {
    case unreadable(String)
    /// The recording has no sound at all. A real state, not a corrupt file: system audio is
    /// optional (ADR-019) and the microphone is opt-in.
    case noAudioTrack
    case outputCollidesWithInput
    case emptyRange
    case readerFailed(String)
    case writerFailed(String)
}

/// A completed audio export.
public struct AudioExportResult: Sendable {
    public let url: URL
    public let duration: Double
    public let byteCount: Int
}

/// Writes a recording's sound on its own as an `.m4a` (M38-T2) — the share export's audio half,
/// with no video read, decoded or encoded.
///
/// AAC because macOS has **no MP3 encoder at all** (docs/07). The rate and the microphone rule come
/// from `ExportConfiguration`, so this and the MP4 export can't disagree about either.
public enum AudioExporter {

    /// Where an audio export of `input` belongs: its `.m4a` sibling, or the ` trimmed` one when only
    /// `range` is written — `mp4Sibling(of:range:)`'s rule, so a range's audio can't sit in the
    /// folder looking like the whole take's.
    public static func m4aSibling(of input: URL, range: ExportRange? = nil) -> URL {
        (range == nil ? input : Trimmer.trimmedSibling(of: input))
            .deletingPathExtension()
            .appendingPathExtension("m4a")
    }

    /// Mixes every audio track `configuration` keeps into one AAC track and writes it to `output`,
    /// or just `range` of it. Blocking work runs off the cooperative pool. Throws before writing on
    /// a bad input, leaving no partial file.
    public static func exportAudio(
        from input: URL,
        to output: URL,
        configuration: ExportConfiguration = ExportConfiguration(),
        range: ExportRange? = nil
    ) async throws -> AudioExportResult {
        // Identity, not string equality — see `Exporter.sameFile`: the pre-write delete would
        // otherwise be able to destroy the input recording.
        guard !Exporter.sameFile(output, input) else {
            throw AudioExportError.outputCollidesWithInput
        }
        if let range {
            guard range.start >= 0, range.end > range.start else { throw AudioExportError.emptyRange }
        }

        let asset = AVURLAsset(url: input)
        let tracks: [AVAssetTrack]
        let assetDuration: CMTime
        do {
            tracks = try await asset.load(.tracks)
            assetDuration = try await asset.load(.duration)
        } catch {
            throw AudioExportError.unreadable(
                "Couldn't read “\(input.lastPathComponent)”. \(error.localizedDescription)")
        }
        let audioTracks = await Exporter.mixedTracks(
            from: tracks.filter { $0.mediaType == .audio }, configuration: configuration)
        guard !audioTracks.isEmpty else { throw AudioExportError.noAudioTrack }

        // Rebased from the picture's start, where the MP4 export rebases (`Exporter`): the same
        // range exported both ways has to line up, so the sound is never moved earlier than the
        // frames it came from. A source with no picture keeps its own timeline.
        var mediaStart = CMTime.zero
        if let video = tracks.first(where: { $0.mediaType == .video }),
            let start = try? await video.load(.timeRange).start {
            mediaStart = start
        }
        // The end, though, is the sound's and not the asset's: a `.mov`'s duration follows its
        // longest track — normally the video — so a take whose audio stops early would otherwise be
        // quoted a length the file doesn't hold.
        var soundEnd: CMTime?
        for track in audioTracks {
            guard let end = try? await track.load(.timeRange).end else { continue }
            soundEnd = soundEnd.map { CMTimeMaximum($0, end) } ?? end
        }
        let mediaEnd = soundEnd ?? assetDuration
        let clipStart = range.map {
            CMTimeMaximum(CMTime(seconds: $0.start, preferredTimescale: 600), mediaStart)
        } ?? mediaStart
        let clipEnd = range.map {
            CMTimeMinimum(CMTime(seconds: $0.end, preferredTimescale: 600), mediaEnd)
        } ?? mediaEnd
        guard CMTimeCompare(clipEnd, clipStart) > 0 else { throw AudioExportError.emptyRange }
        let clipDuration = CMTimeSubtract(clipEnd, clipStart)
        // Only a ranged export narrows the read; a whole-file one keeps the reader's own default.
        let readRange = range == nil ? nil : CMTimeRange(start: clipStart, end: clipEnd)

        // The `.partial` companion, renamed only once the file is complete (M15-T3): a crash
        // mid-export leaves nothing at the final name for Recent Exports to offer.
        let scratch = OutputLocation.partialURL(for: output)
        // Confined, not shared: built here, handed to `audioQueue`, used only there, and no other
        // reference exists.
        nonisolated(unsafe) let plan = try AudioPlan(
            asset: asset, audioTracks: audioTracks, output: scratch, sessionStart: clipStart,
            readRange: readRange, configuration: configuration)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioQueue.async { continuation.resume(with: Result { try plan.run() }) }
            }
        } catch {
            try? FileManager.default.removeItem(at: scratch)  // no torn file on failure
            OutputLocation.removeWriterScratch(beside: scratch)
            throw error
        }

        OutputLocation.removeWriterScratch(beside: scratch)
        let written = try OutputLocation.finalizePartial(scratch)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: written.path))
            .flatMap { $0[.size] as? Int } ?? 0
        let clip = clipDuration.seconds
        return AudioExportResult(
            url: written, duration: clip.isFinite ? max(0, clip) : 0, byteCount: bytes)
    }

    private static let audioQueue = DispatchQueue(
        label: "dev.fcostantini.screenrec.export.audio", qos: .userInitiated)
}

/// A configured reader/writer pair for the audio pass, ready to drain. Split out so the async
/// property loads sit in `AudioExporter` and the blocking pass sits here, off the cooperative pool.
private struct AudioPlan {
    let reader: AVAssetReader
    let mix: AVAssetReaderAudioMixOutput
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let sessionStart: CMTime
    let output: URL

    init(
        asset: AVAsset,
        audioTracks: [AVAssetTrack],
        output: URL,
        sessionStart: CMTime,
        readRange: CMTimeRange?,
        configuration: ExportConfiguration
    ) throws {
        reader = try AVAssetReader(asset: asset)
        if let readRange { reader.timeRange = readRange }  // must precede `startReading`

        // Both tracks (system + mic) mixed down to one stereo stream, as the MP4 export does —
        // a file with two audio tracks is not what anything plays as "the audio".
        mix = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: AudioEncodingSettings.mixedPCM(sampleRate: 48_000, channels: 2))
        mix.alwaysCopiesSampleData = false
        guard reader.canAdd(mix) else {
            throw AudioExportError.readerFailed("The reader refused the audio tracks.")
        }
        reader.add(mix)

        writer = try AVAssetWriter(outputURL: output, fileType: .m4a)
        writer.shouldOptimizeForNetworkUse = true
        input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: AudioEncodingSettings.aac(
                sampleRate: 48_000, channels: 2, bitRate: configuration.audioBitRate))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw AudioExportError.writerFailed("The writer refused the audio track.")
        }
        writer.add(input)

        self.sessionStart = sessionStart
        self.output = output
    }

    /// Reads the mix to exhaustion, feeding the writer; blocks until the file is finalized.
    func run() throws {
        // Free the encoder promptly on any early return; a clean finish leaves both terminal.
        var completed = false
        defer {
            if !completed {
                if reader.status == .reading { reader.cancelReading() }
                if writer.status == .writing { writer.cancelWriting() }
            }
        }

        guard reader.startReading() else {
            throw AudioExportError.readerFailed(
                reader.error?.localizedDescription ?? "The reader couldn't start.")
        }
        // Clear a stale target in the same breath as starting to write (the ReplayMuxer idiom):
        // the writer refuses to overwrite, and a construction failure above must leave it alone.
        try? FileManager.default.removeItem(at: output)
        guard writer.startWriting() else {
            throw AudioExportError.writerFailed(
                writer.error?.localizedDescription ?? "The writer couldn't start.")
        }
        // Maps each sample to `pts − sessionStart`, so the file starts at zero even when the range
        // doesn't.
        writer.startSession(atSourceTime: sessionStart)

        let group = DispatchGroup()
        let failure = FirstError()
        let queue = DispatchQueue(label: "dev.fcostantini.screenrec.export.audio.drain")
        WriterDrain.drain(into: input, on: queue, group: group) {
            guard reader.status == .reading else { return false }
            guard let sample = mix.copyNextSampleBuffer() else { return false }
            guard input.append(sample) else {
                failure.report(
                    writer.error?.localizedDescription ?? "The writer refused an audio sample.")
                return false
            }
            return true
        }
        group.wait()

        guard reader.status != .failed else {
            throw AudioExportError.readerFailed(
                reader.error?.localizedDescription ?? "Reading the recording failed.")
        }
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw AudioExportError.writerFailed(
                writer.error?.localizedDescription ?? "Writing the audio didn't complete.")
        }
        if let message = failure.message { throw AudioExportError.writerFailed(message) }
        completed = true
    }
}

import AVFoundation
import CoreMedia
import Foundation

/// Failures a trim surfaces; messages are user-facing (docs/06 copy discipline).
public enum TrimError: Error, Equatable {
    case unreadable(String)
    case noVideoTrack
    case outputCollidesWithInput
    case emptyRange
    case trimFailed(String)
}

/// A completed trim.
public struct TrimResult: Sendable {
    public let url: URL
    public let duration: Double
    public let byteCount: Int
}

/// What a trim writes (M18-T1). Both modes start playback exactly at the in-point; they differ in
/// what the file holds.
public enum TrimMode: Sendable {
    /// Copies the streams. The file also keeps the frames between the preceding sync sample and
    /// the in-point, hidden behind an edit list (`KeyframeIndex`, docs/02 §6a).
    case lossless
    /// Re-encodes, so the file holds only the kept range — at the source's own dimensions and
    /// codec, with both audio tracks separate (ADR-004). Slower, and on quiet content larger.
    case precise
}

/// Trims a recording to `[start, end]` (M10-T4; precise mode M18-T1). The original is only read; a
/// new file is written. Both modes are `AVAssetExportSession` with a `timeRange`.
public enum Trimmer {
    /// `<stem> trimmed.mov` beside the input — always `.mov`, because the passthrough export writes
    /// a QuickTime container regardless of the input's extension. Pure.
    public static func trimmedSibling(of input: URL) -> URL {
        let stem = input.deletingPathExtension().lastPathComponent
        return input.deletingLastPathComponent()
            .appendingPathComponent("\(stem) trimmed")
            .appendingPathExtension("mov")
    }

    public static func trim(
        from input: URL, to output: URL, start: Double, end: Double, mode: TrimMode = .lossless
    ) async throws -> TrimResult {
        guard !Exporter.sameFile(output, input) else { throw TrimError.outputCollidesWithInput }
        guard start >= 0, end > start else { throw TrimError.emptyRange }

        let asset = AVURLAsset(url: input)
        let duration: CMTime
        let hasVideo: Bool
        do {
            duration = try await asset.load(.duration)
            hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty
        } catch {
            throw TrimError.unreadable(
                "Couldn't read “\(input.lastPathComponent)”. \(error.localizedDescription)")
        }
        guard hasVideo else { throw TrimError.noVideoTrack }

        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let endTime = CMTimeMinimum(CMTime(seconds: end, preferredTimescale: 600), duration)
        guard CMTimeCompare(endTime, startTime) > 0 else { throw TrimError.emptyRange }

        let session = try await makeSession(for: mode, asset: asset)
        session.timeRange = CMTimeRange(start: startTime, end: endTime)

        // Write to the `.partial` companion and rename only on success (M15-T3) — see `Exporter`.
        let scratch = OutputLocation.partialURL(for: output)
        try? FileManager.default.removeItem(at: scratch)
        do {
            try await session.export(to: scratch, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: scratch)  // no torn file on failure
            throw TrimError.trimFailed(error.localizedDescription)
        }

        let output = try OutputLocation.finalizePartial(scratch)
        let outputDuration = (try? await AVURLAsset(url: output).load(.duration).seconds) ?? 0
        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))
            .flatMap { $0[.size] as? Int } ?? 0
        return TrimResult(
            url: output, duration: outputDuration.isFinite ? max(0, outputDuration) : 0,
            byteCount: bytes)
    }

    /// One place per mode, exhaustively: a preset and its composition must not drift apart.
    /// `AVAssetExportPresetHEVCHighestQuality` alone passes an HEVC source straight through
    /// (measured: byte-identical output), so precise mode needs the composition to encode at all.
    private static func makeSession(
        for mode: TrimMode, asset: AVAsset
    ) async throws -> AVAssetExportSession {
        func session(preset: String) throws -> AVAssetExportSession {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                throw TrimError.trimFailed("Couldn't set up the trim.")
            }
            return session
        }
        switch mode {
        case .lossless:
            return try session(preset: AVAssetExportPresetPassthrough)
        case .precise:
            let session = try session(preset: AVAssetExportPresetHEVCHighestQuality)
            do {
                session.videoComposition = try await AVVideoComposition.videoComposition(
                    withPropertiesOf: asset)
            } catch {
                throw TrimError.trimFailed(
                    "Couldn't set up a precise trim. \(error.localizedDescription)")
            }
            return session
        }
    }
}

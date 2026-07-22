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

/// Losslessly trims a recording to `[start, end]` by COPYING the streams — no decode, no
/// re-encode (M10-T4). `AVAssetExportSession` in passthrough is exactly this: it can only cut at a
/// sync sample, so the start snaps to the keyframe at/before it (docs/02 §9, ADR-015). The original
/// is only read; a new file is written.
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
        from input: URL, to output: URL, start: Double, end: Double
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

        guard let session = AVAssetExportSession(
            asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw TrimError.trimFailed("Couldn't set up the trim.")
        }
        session.timeRange = CMTimeRange(start: startTime, end: endTime)

        try? FileManager.default.removeItem(at: output)
        do {
            try await session.export(to: output, as: .mov)
        } catch {
            try? FileManager.default.removeItem(at: output)  // no torn file on failure
            throw TrimError.trimFailed(error.localizedDescription)
        }

        let outputDuration = (try? await AVURLAsset(url: output).load(.duration).seconds) ?? 0
        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))
            .flatMap { $0[.size] as? Int } ?? 0
        return TrimResult(
            url: output, duration: outputDuration.isFinite ? max(0, outputDuration) : 0,
            byteCount: bytes)
    }
}

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Failures a GIF export surfaces; messages are user-facing (docs/06 copy discipline).
public enum GifExportError: Error, Equatable {
    case unreadable(String)
    case noVideoTrack
    case outputCollidesWithInput
    case noFrames
    case writeFailed(String)
}

/// Knobs for a GIF export (M10-T3). Defaults are the "drop it in a thread" profile: small,
/// looping, short.
public struct GifConfiguration: Sendable {
    public var maxWidth: Int
    public var maxHeight: Int
    public var fps: Int
    /// A GIF is a short thing — a longer clip takes its first `maxSeconds` (the result flags it).
    public var maxSeconds: Double

    public init(maxWidth: Int = 480, maxHeight: Int = 480, fps: Int = 15, maxSeconds: Double = 30) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.fps = fps
        self.maxSeconds = maxSeconds
    }
}

/// A completed GIF export.
public struct GifResult: Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let frameCount: Int
    public let byteCount: Int
    /// The source ran past `maxSeconds`, so the GIF is its opening window.
    public let truncated: Bool
}

/// Turns a clip into a looping animated GIF (M10-T3): read scaled, fps-capped frames via
/// `VideoFrameReader`, encode with `ImageIO` (256-color palette, infinite loop). Zero-dep — ImageIO
/// is a system framework (ADR-010). Audio is dropped (GIF has none).
public enum GifExporter {
    /// The `.gif` sibling of an input path (same folder, extension swapped). Pure.
    public static func gifSibling(of input: URL) -> URL {
        input.deletingPathExtension().appendingPathExtension("gif")
    }

    public static func exportGIF(
        from input: URL,
        to output: URL,
        configuration: GifConfiguration = GifConfiguration()
    ) async throws -> GifResult {
        guard !Exporter.sameFile(output, input) else { throw GifExportError.outputCollidesWithInput }

        // Confined, not shared: built here, handed to `gifQueue`, used only there, and no other
        // reference exists. The assertion is about this value's single owner, not about the type.
        nonisolated(unsafe) let reader: VideoFrameReader
        do {
            reader = try await VideoFrameReader.make(
                input: input, maxWidth: configuration.maxWidth, maxHeight: configuration.maxHeight,
                fps: configuration.fps, maxSeconds: configuration.maxSeconds)
        } catch VideoFrameReader.ReaderError.noVideoTrack {
            throw GifExportError.noVideoTrack
        } catch VideoFrameReader.ReaderError.unreadable(let message) {
            throw GifExportError.unreadable(message)
        } catch VideoFrameReader.ReaderError.readFailed(let message) {
            throw GifExportError.writeFailed(message)
        }

        let truncated = reader.sourceSeconds.isFinite && reader.sourceSeconds > configuration.maxSeconds
        let window = truncated ? configuration.maxSeconds : reader.sourceSeconds
        // Only a capacity hint for the destination; guard the trapping Int() against a non-finite
        // source duration (an indefinite asset never sets a finite `sourceSeconds`).
        let expectedFrames =
            window.isFinite ? max(1, Int((window * Double(configuration.fps)).rounded())) : 1

        // Write to the `.partial` companion and rename only on success (M15-T3) — see `Exporter`.
        let scratch = OutputLocation.partialURL(for: output)
        let frameCount = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Int, Error>) in
            gifQueue.async {
                continuation.resume(with: Result {
                    try encode(reader, to: scratch, expectedFrames: expectedFrames)
                })
            }
        }

        let output = try OutputLocation.finalizePartial(scratch)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path))
            .flatMap { $0[.size] as? Int } ?? 0
        return GifResult(
            url: output, width: reader.size.width, height: reader.size.height,
            frameCount: frameCount, byteCount: bytes, truncated: truncated)
    }

    /// Streams the reader's frames straight into a GIF destination — one frame in memory at a time,
    /// never the whole clip. Returns the number of frames written.
    private static func encode(
        _ reader: VideoFrameReader, to output: URL, expectedFrames: Int
    ) throws -> Int {
        try? FileManager.default.removeItem(at: output)
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, expectedFrames, nil)
        else { throw GifExportError.writeFailed("Couldn't create the GIF file.") }

        // Loop forever (count 0); per-frame delay is the reader's fixed cadence.
        CGImageDestinationSetProperties(
            destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties =
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: reader.frameDuration]]
            as CFDictionary

        var written = 0
        do {
            try reader.readFrames { image in
                CGImageDestinationAddImage(destination, image, frameProperties)
                written += 1
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw GifExportError.writeFailed(error.localizedDescription)
        }

        guard written > 0 else {
            try? FileManager.default.removeItem(at: output)
            throw GifExportError.noFrames
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: output)
            throw GifExportError.writeFailed("The GIF didn't finish writing.")
        }
        return written
    }

    private static let gifQueue = DispatchQueue(
        label: "dev.fcostantini.screenrec.export.gif", qos: .userInitiated)
}

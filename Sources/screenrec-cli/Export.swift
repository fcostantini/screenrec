import Foundation
import RecorderCore

/// Throttled one-line progress on stdout (unbuffered — 02 §10), redrawn with a carriage return.
private final class ProgressPrinter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReport = Date.distantPast

    func report(_ fraction: Double) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= 0.5 else { return }
        lastReport = now
        print("\r  encoding \(Int((fraction * 100).rounded()))%   ", terminator: "")
    }

    func finish() { print("\r  encoding 100%     ") }
}

private func exportErrorMessage(_ error: Error) -> String {
    switch error {
    case ExportError.unreadable(let message),
        ExportError.readerFailed(let message),
        ExportError.writerFailed(let message),
        GifExportError.unreadable(let message),
        GifExportError.writeFailed(let message):
        return "Couldn't export: \(message)"
    case ExportError.noVideoTrack, GifExportError.noVideoTrack:
        return "Couldn't export: that file has no video track."
    case ExportError.outputCollidesWithInput, GifExportError.outputCollidesWithInput:
        return "The output path matches the input — choose a different name."
    case GifExportError.noFrames:
        return "Couldn't export: the clip has no frames to encode."
    default:
        return "Couldn't export: \(error.localizedDescription)"
    }
}

/// `export (--to-mp4 | --to-gif) <in> [<out>]` — derive a shareable file from a recording (ADR-016,
/// M10-T3). Default output is the input's `.mp4`/`.gif` sibling, collision-resolved; the source is
/// only read.
func runExport(_ args: [String]) async {
    var toMP4 = false
    var toGIF = false
    var positionals: [String] = []
    for arg in args {
        switch arg {
        case "--to-mp4": toMP4 = true
        case "--to-gif": toGIF = true
        case let flag where flag.hasPrefix("--"): die("Unknown export option: \(flag)")
        default: positionals.append(arg)
        }
    }
    guard toMP4 != toGIF else { die("export needs exactly one of --to-mp4 or --to-gif") }
    guard let inputPath = positionals.first else { die("export needs an input path") }

    let input = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: input.path) else {
        die("No file at \(input.path)")
    }
    let explicitOutput = positionals.count > 1
        ? URL(fileURLWithPath: (positionals[1] as NSString).expandingTildeInPath)
        : nil

    print("Reading   \(input.lastPathComponent)")
    do {
        if toGIF {
            try await runGIF(input: input, explicitOutput: explicitOutput)
        } else {
            try await runMP4(input: input, explicitOutput: explicitOutput)
        }
    } catch {
        die(exportErrorMessage(error), code: 70)
    }
}

private func runMP4(input: URL, explicitOutput: URL?) async throws {
    let output = explicitOutput ?? Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: input))
    let progress = ProgressPrinter()
    let result = try await Exporter.exportToMP4(
        from: input, to: output, progress: { progress.report($0) })
    progress.finish()
    print(
        String(
            format: "Wrote     %@  (H.264 %d×%d + AAC, %.1f MB)",
            result.url.lastPathComponent, result.width, result.height,
            Double(result.byteCount) / 1_000_000))
}

private func runGIF(input: URL, explicitOutput: URL?) async throws {
    let output = explicitOutput ?? Exporter.availableURL(basedOn: GifExporter.gifSibling(of: input))
    let result = try await GifExporter.exportGIF(from: input, to: output)
    let window = result.truncated ? " · first \(Int(GifConfiguration().maxSeconds))s" : ""
    print(
        String(
            format: "Wrote     %@  (GIF %d×%d, %d frames, %.1f MB)%@",
            result.url.lastPathComponent, result.width, result.height,
            result.frameCount, Double(result.byteCount) / 1_000_000, window))
}

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
    var gifFPS: Int?
    var width: Int?
    var gifSeconds: Double?

    var index = 0
    func value(after flag: String) -> String {
        index += 1
        guard index < args.count else { die("\(flag) needs a value") }
        return args[index]
    }
    while index < args.count {
        switch args[index] {
        case "--to-mp4": toMP4 = true
        case "--to-gif": toGIF = true
        // Round, don't truncate, and floor at 1: a sub-1.0 value would otherwise become 0 → a
        // broken GIF (fps 0 keeps one frame; width 0 floors to a 2px clip).
        case "--fps":
            gifFPS = max(1, Int(parsePositive(value(after: "--fps"), flag: "--fps", unit: "fps", max: 120).rounded()))
        case "--width":
            width = max(1, Int(parsePositive(value(after: "--width"), flag: "--width", unit: "pixels", max: 4096).rounded()))
        case "--seconds": gifSeconds = parsePositive(value(after: "--seconds"), flag: "--seconds", max: 900)
        case let flag where flag.hasPrefix("--"): die("Unknown export option: \(flag)")
        default: positionals.append(args[index])
        }
        index += 1
    }
    guard toMP4 != toGIF else { die("export needs exactly one of --to-mp4 or --to-gif") }
    guard !toMP4 || (gifFPS == nil && gifSeconds == nil) else {
        die("--fps/--seconds only apply to --to-gif")
    }
    guard let inputPath = positionals.first else { die("export needs an input path") }
    guard positionals.count <= 2 else { die("Unexpected extra argument: \(positionals[2])") }

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
            try await runGIF(
                input: input, explicitOutput: explicitOutput,
                fps: gifFPS, width: width, seconds: gifSeconds)
        } else {
            try await runMP4(input: input, explicitOutput: explicitOutput, width: width)
        }
    } catch {
        die(exportErrorMessage(error), code: 70)
    }
}

private func runMP4(input: URL, explicitOutput: URL?, width: Int?) async throws {
    let output = explicitOutput ?? Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: input))
    let progress = ProgressPrinter()
    let configuration = width.map { ExportConfiguration(maxWidth: $0) } ?? ExportConfiguration()
    let result = try await Exporter.exportToMP4(
        from: input, to: output, configuration: configuration, progress: { progress.report($0) })
    progress.finish()
    print(
        String(
            format: "Wrote     %@  (H.264 %d×%d + AAC, %.1f MB)",
            result.url.lastPathComponent, result.width, result.height,
            Double(result.byteCount) / 1_000_000))
}

private func runGIF(
    input: URL, explicitOutput: URL?, fps: Int?, width: Int?, seconds: Double?
) async throws {
    let output = explicitOutput ?? Exporter.availableURL(basedOn: GifExporter.gifSibling(of: input))
    let defaults = GifConfiguration()
    let configuration = GifConfiguration(
        maxWidth: width ?? defaults.maxWidth,
        maxHeight: width ?? defaults.maxHeight,
        fps: fps ?? defaults.fps,
        maxSeconds: seconds ?? defaults.maxSeconds)
    let result = try await GifExporter.exportGIF(from: input, to: output, configuration: configuration)
    let window = result.truncated ? " · first \(Int(configuration.maxSeconds))s" : ""
    print(
        String(
            format: "Wrote     %@  (GIF %d×%d, %d frames, %.1f MB)%@",
            result.url.lastPathComponent, result.width, result.height,
            result.frameCount, Double(result.byteCount) / 1_000_000, window))
}

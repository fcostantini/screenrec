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
        ExportError.writerFailed(let message):
        return "Couldn't export: \(message)"
    case ExportError.noVideoTrack:
        return "Couldn't export: that file has no video track."
    case ExportError.outputCollidesWithInput:
        return "The output path matches the input — choose a different name."
    default:
        return "Couldn't export: \(error.localizedDescription)"
    }
}

/// `export --to-mp4 <in> [<out>]` — transcode a recording to a shareable H.264/AAC `.mp4`
/// (ADR-016). Default output is the input's `.mp4` sibling, collision-resolved; the source is
/// only read.
func runExport(_ args: [String]) async {
    var toMP4 = false
    var positionals: [String] = []
    for arg in args {
        switch arg {
        case "--to-mp4": toMP4 = true
        case let flag where flag.hasPrefix("--"): die("Unknown export option: \(flag)")
        default: positionals.append(arg)
        }
    }
    guard toMP4 else { die("export needs --to-mp4 (the only export format so far)") }
    guard let inputPath = positionals.first else { die("export --to-mp4 needs an input path") }

    let input = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: input.path) else {
        die("No file at \(input.path)")
    }
    let output =
        positionals.count > 1
        ? URL(fileURLWithPath: (positionals[1] as NSString).expandingTildeInPath)
        : Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: input))

    print("Reading   \(input.lastPathComponent)")
    let progress = ProgressPrinter()
    do {
        let result = try await Exporter.exportToMP4(
            from: input, to: output, progress: { progress.report($0) })
        progress.finish()
        print(
            String(
                format: "Wrote     %@  (H.264 %d×%d + AAC, %.1f MB)",
                result.url.lastPathComponent, result.width, result.height,
                Double(result.byteCount) / 1_000_000))
    } catch {
        die(exportErrorMessage(error), code: 70)
    }
}

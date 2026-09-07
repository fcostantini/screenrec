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
    case AudioExportError.unreadable(let message),
        AudioExportError.readerFailed(let message),
        AudioExportError.writerFailed(let message):
        return "Couldn't export: \(message)"
    case ExportError.noVideoTrack, GifExportError.noVideoTrack:
        return "Couldn't export: that file has no video track."
    case AudioExportError.noAudioTrack:
        return "Couldn't export: that recording has no sound."
    case ExportError.outputCollidesWithInput, GifExportError.outputCollidesWithInput,
        AudioExportError.outputCollidesWithInput:
        return "The output path matches the input — choose a different name."
    case ExportError.emptyRange, AudioExportError.emptyRange:
        return "Couldn't export: the time range is empty."
    case ExportError.cropOutOfBounds(let message):
        return "Couldn't export: \(message)"
    case GifExportError.noFrames:
        return "Couldn't export: the clip has no frames to encode."
    default:
        return "Couldn't export: \(error.localizedDescription)"
    }
}

/// `export (--to-mp4 | --to-gif | --to-audio) <in> [<out>]` — derive a shareable file from a
/// recording (ADR-016, M10-T3, M38-T2). `--to-mp4` and `--to-audio` also take `--from`/`--to`,
/// writing only that range (M21-T1); `--crop` keeps only that rectangle of each frame (M26-T1).
/// Default output is the input's `.mp4`/`.gif`/`.m4a` sibling, collision-resolved; the source is
/// only read.
func runExport(_ args: [String]) async {
    var toMP4 = false
    var toGIF = false
    var toAudio = false
    var positionals: [String] = []
    var gifFPS: Int?
    var width: Int?
    var gifSeconds: Double?
    var from: Double?
    var to: Double?
    var crop: CropRect?
    var detectsCrop = false
    var includesMicrophone = true

    var index = 0
    func value(after flag: String) -> String {
        index += 1
        guard index < args.count else { die("\(flag) needs a value") }
        return args[index]
    }
    while index < args.count {
        switch args[index] {
        case "--to-mp4": toMP4 = true
        case "--no-microphone":
            includesMicrophone = false
        case "--to-gif": toGIF = true
        case "--to-audio": toAudio = true
        // Round, don't truncate, and floor at 1: a sub-1.0 value would otherwise become 0 → a
        // broken GIF (fps 0 keeps one frame; width 0 floors to a 2px clip).
        case "--fps":
            gifFPS = max(1, Int(parsePositive(value(after: "--fps"), flag: "--fps", unit: "fps", max: 120).rounded()))
        case "--width":
            width = max(1, Int(parsePositive(value(after: "--width"), flag: "--width", unit: "pixels", max: 4096).rounded()))
        case "--seconds": gifSeconds = parsePositive(value(after: "--seconds"), flag: "--seconds", max: 900)
        case "--from":
            guard let parsed = parseTimecode(value(after: "--from")) else {
                die("--from must be M:SS or seconds (≥ 0)")
            }
            from = parsed
        case "--to":
            guard let parsed = parseTimecode(value(after: "--to")) else {
                die("--to must be M:SS or seconds (≥ 0)")
            }
            to = parsed
        case "--crop":
            // `detect` finds the letterbox itself (M26-T3); anything else is an explicit rect.
            let spec = value(after: "--crop")
            if spec == "detect" { detectsCrop = true } else { crop = parseCropRect(spec) }
        case let flag where flag.hasPrefix("--"): die("Unknown export option: \(flag)")
        default: positionals.append(args[index])
        }
        index += 1
    }
    guard [toMP4, toGIF, toAudio].filter({ $0 }).count == 1 else {
        die("export needs exactly one of --to-mp4, --to-gif or --to-audio")
    }
    guard toGIF || (gifFPS == nil && gifSeconds == nil) else {
        die("--fps/--seconds only apply to --to-gif")
    }
    guard !toGIF || (from == nil && to == nil) else {
        die("--from/--to only apply to --to-mp4 or --to-audio")
    }
    guard toMP4 || (crop == nil && !detectsCrop) else { die("--crop only applies to --to-mp4") }
    // Audio has no picture to size.
    guard !toAudio || width == nil else { die("--width doesn't apply to --to-audio") }
    guard (from == nil) == (to == nil) else { die("a range needs both --from and --to") }
    if let from, let to { guard to > from else { die("--to must be after --from") } }
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
        let range: ExportRange? = if let from, let to {
            ExportRange(start: from, end: to)
        } else {
            nil
        }
        if toGIF {
            try await runGIF(
                input: input, explicitOutput: explicitOutput,
                fps: gifFPS, width: width, seconds: gifSeconds)
        } else if toAudio {
            try await runAudio(
                input: input, explicitOutput: explicitOutput, range: range,
                includesMicrophone: includesMicrophone)
        } else {
            try await runMP4(
                input: input, explicitOutput: explicitOutput, width: width, range: range,
                crop: crop, detectsCrop: detectsCrop, includesMicrophone: includesMicrophone)
        }
    } catch {
        die(exportErrorMessage(error), code: 70)
    }
}

private func runMP4(
    input: URL, explicitOutput: URL?, width: Int?, range: ExportRange?, crop: CropRect?,
    detectsCrop: Bool = false, includesMicrophone: Bool = true
) async throws {
    var crop = crop
    if detectsCrop {
        crop = try await BarDetector.detect(in: input)
        print(crop.map { "Detected  bars → \($0.width) × \($0.height) px at \($0.x),\($0.y)" }
            ?? "Detected  no bars — exporting the whole frame")
    }
    let output = explicitOutput
        ?? Exporter.availableURL(basedOn: Exporter.mp4Sibling(of: input, range: range))
    let progress = ProgressPrinter()
    let configuration = ExportConfiguration(
        maxWidth: width ?? ExportConfiguration().maxWidth, includesMicrophone: includesMicrophone)
    if let range {
        print("Range     \(Timecode.cutPoint(range.start)) – \(Timecode.cutPoint(range.end))")
    }
    if let crop {
        print("Crop      x\(crop.x) y\(crop.y) · \(crop.width) × \(crop.height) px")
    }
    let result = try await Exporter.exportToMP4(
        from: input, to: output, configuration: configuration, range: range, crop: crop,
        progress: { progress.report($0) })
    progress.finish()
    print(
        String(
            format: "Wrote     %@  (H.264 %d×%d + AAC, %.2fs, %.1f MB)",
            result.url.lastPathComponent, result.width, result.height, result.duration,
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

/// `--to-audio`: the take's sound on its own, as an `.m4a` (M38-T2). No `--width` — there is no
/// picture — and no progress line: the pass is short enough that one would only ever print 100%.
private func runAudio(
    input: URL, explicitOutput: URL?, range: ExportRange?, includesMicrophone: Bool
) async throws {
    let output = explicitOutput
        ?? Exporter.availableURL(basedOn: AudioExporter.m4aSibling(of: input, range: range))
    if let range {
        print("Range     \(Timecode.cutPoint(range.start)) – \(Timecode.cutPoint(range.end))")
    }
    let result = try await AudioExporter.exportAudio(
        from: input, to: output,
        configuration: ExportConfiguration(includesMicrophone: includesMicrophone), range: range)
    // The rate the file carries, not the one that was asked for: the encoder snaps the request to
    // a rate it supports, and AAC spends fewer bits on quiet content.
    let kbps = result.duration > 0 ? Double(result.byteCount) * 8 / result.duration / 1000 : 0
    print(
        String(
            format: "Wrote     %@  (AAC %.0f kbps, %.2fs, %.1f MB)",
            result.url.lastPathComponent, kbps, result.duration,
            Double(result.byteCount) / 1_000_000))
}

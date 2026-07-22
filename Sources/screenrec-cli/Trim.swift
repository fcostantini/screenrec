import Foundation
import RecorderCore

/// `M:SS` or a plain, non-negative seconds value; nil if neither. `"0:12"` → 12, `"12"` → 12,
/// `"1:05.5"` → 65.5. Rejects negatives so a bad value fails as invalid, not as an empty range.
private func parseTimecode(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let value: Double
    if trimmed.contains(":") {
        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let minutes = Double(parts[0]),
              let seconds = Double(parts[1]), seconds >= 0, seconds < 60
        else { return nil }
        value = minutes * 60 + seconds
    } else {
        guard let seconds = Double(trimmed) else { return nil }
        value = seconds
    }
    return value >= 0 ? value : nil
}

private func timecode(_ seconds: Double) -> String {
    let whole = Int(seconds.rounded())
    return String(format: "%d:%02d", whole / 60, whole % 60)
}

private func trimErrorMessage(_ error: Error) -> String {
    switch error {
    case TrimError.unreadable(let message), TrimError.trimFailed(let message):
        return "Couldn't trim: \(message)"
    case TrimError.noVideoTrack:
        return "Couldn't trim: that file has no video track."
    case TrimError.outputCollidesWithInput:
        return "The output path matches the input — choose a different name."
    case TrimError.emptyRange:
        return "Couldn't trim: the time range is empty."
    default:
        return "Couldn't trim: \(error.localizedDescription)"
    }
}

/// `trim <in> --from <t> --to <t> [<out>]` — losslessly trim a recording to `[from, to]` by copying
/// the streams (M10-T4). Default `<out>` is the input's ` trimmed` sibling; the source is read-only.
func runTrim(_ args: [String]) async {
    var positionals: [String] = []
    var from: Double?
    var to: Double?

    var index = 0
    func value(after flag: String) -> String {
        index += 1
        guard index < args.count else { die("\(flag) needs a value") }
        return args[index]
    }
    while index < args.count {
        switch args[index] {
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
        case let flag where flag.hasPrefix("--"): die("Unknown trim option: \(flag)")
        default: positionals.append(args[index])
        }
        index += 1
    }
    guard let inputPath = positionals.first else { die("trim needs an input path") }
    guard positionals.count <= 2 else { die("Unexpected extra argument: \(positionals[2])") }
    guard let from else { die("trim needs --from <M:SS|seconds>") }
    guard let to else { die("trim needs --to <M:SS|seconds>") }
    guard to > from else { die("--to must be after --from") }

    let input = URL(fileURLWithPath: (inputPath as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: input.path) else {
        die("No file at \(input.path)")
    }
    let output = positionals.count > 1
        ? URL(fileURLWithPath: (positionals[1] as NSString).expandingTildeInPath)
        : Exporter.availableURL(basedOn: Trimmer.trimmedSibling(of: input))

    print("Trimming  \(input.lastPathComponent)  [\(timecode(from)) – \(timecode(to))]")
    do {
        let result = try await Trimmer.trim(from: input, to: output, start: from, end: to)
        print(
            String(
                format: "Wrote     %@  (%.2fs, %.1f MB) — passthrough, no re-encode. In snaps to a keyframe.",
                result.url.lastPathComponent, result.duration, Double(result.byteCount) / 1_000_000))
    } catch {
        die(trimErrorMessage(error), code: 70)
    }
}

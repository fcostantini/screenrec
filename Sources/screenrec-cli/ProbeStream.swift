import AVFoundation
import CoreMedia
import Foundation
import RecorderCore

/// Accumulates per-source stats: buffer count, first/last PTS, min/max consecutive-PTS
/// delta, and the first format description seen. Thread-safe — buffers arrive on SCK's
/// background queues.
private final class ProbeConsumer: SampleConsumer, @unchecked Sendable {
    struct Stats {
        var count = 0
        var firstPTS: CMTime?
        var lastPTS: CMTime?
        var minDelta = Double.greatestFiniteMagnitude
        var maxDelta = 0.0
        var format: String?
    }

    private let lock = NSLock()
    private var stats: [SourceType: Stats] = [:]

    func consume(_ buffer: CMSampleBuffer, type: SourceType) {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        let format = Self.describeFormat(buffer)
        lock.lock()
        var entry = stats[type] ?? Stats()
        entry.count += 1
        if entry.firstPTS == nil { entry.firstPTS = pts }
        if let last = entry.lastPTS, last.isValid, pts.isValid {
            let delta = (pts - last).seconds
            if delta.isFinite {
                entry.minDelta = min(entry.minDelta, delta)
                entry.maxDelta = max(entry.maxDelta, delta)
            }
        }
        entry.lastPTS = pts
        if entry.format == nil { entry.format = format }
        stats[type] = entry
        lock.unlock()
    }

    func snapshot() -> [SourceType: Stats] {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    static func describeFormat(_ buffer: CMSampleBuffer) -> String {
        guard let format = CMSampleBufferGetFormatDescription(buffer) else { return "—" }
        switch CMFormatDescriptionGetMediaType(format) {
        case kCMMediaType_Audio:
            guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return "audio" }
            return "\(Int(asbd.mSampleRate)) Hz, \(asbd.mChannelsPerFrame) ch, \(asbd.mBitsPerChannel)-bit"
        case kCMMediaType_Video:
            let dims = CMVideoFormatDescriptionGetDimensions(format)
            return "\(dims.width)×\(dims.height) \(fourCC(CMFormatDescriptionGetMediaSubType(format)))"
        default:
            return "—"
        }
    }
}

private func fourCC(_ code: FourCharCode) -> String {
    let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff), UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
    return (String(bytes: bytes, encoding: .ascii) ?? "\(code)").trimmingCharacters(in: .whitespaces)
}

private func label(_ type: SourceType) -> String {
    switch type {
    case .screen: return "Screen video"
    case .systemAudio: return "System audio"
    case .microphone: return "Microphone  "
    }
}

/// Captures for `--duration` seconds and prints per-source buffer counts, formats, and
/// PTS deltas. The diagnostic every later capture task leans on (M1-T4).
func runProbeStream(_ args: [String]) async {
    var duration = 5.0
    var micID: String?
    var micEnabled = true

    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--duration":
            duration = parsePositive(iterator.next(), flag: "--duration")
        case "--mic":
            guard let value = iterator.next() else { die("--mic needs a device id") }
            micID = value
        case "--no-mic":
            micEnabled = false
        default:
            die("Unknown option: \(arg)")
        }
    }

    var microphone = MicrophoneSelection.none
    if micEnabled {
        switch Permissions.resolvedMicrophoneID(preferred: micID) {
        case .explicit(let id): microphone = .device(id: id)
        case .noDevice(let reason): print("(no microphone: \(reason))")
        }
    }

    let engine = CaptureEngine(configuration: CaptureConfiguration(microphone: microphone))
    let probe = ProbeConsumer()
    engine.router.attach(probe)

    print("probe-stream: capturing \(Int(duration))s… (move the mouse so video frames flow)")

    let events = Task { () -> Bool in
        var ok = true
        for await event in engine.events {
            switch event {
            case .failed(let message): print("  failed: \(message)"); ok = false
            case .stopped(.userStopped): break
            case .stopped(let reason): print("  stream ended early: \(reason)")
            default: break
            }
        }
        return ok
    }

    await engine.start()
    let stopTimer = Task {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        await engine.stop()
    }
    let ok = await events.value
    stopTimer.cancel()
    engine.router.detach(probe)

    let stats = probe.snapshot()
    print("\nResults after \(String(format: "%.1f", duration))s:")
    for type in [SourceType.screen, .systemAudio, .microphone] {
        guard let entry = stats[type] else {
            print("  \(label(type)): no buffers")
            continue
        }
        let rate = Double(entry.count) / duration
        let deltas = entry.count > 1
            ? String(format: "PTS Δ min %.4fs / max %.4fs", entry.minDelta, entry.maxDelta)
            : "PTS Δ n/a"
        print(String(format: "  %@: %d buffers (%.1f/s)  |  %@  |  %@",
                     label(type), entry.count, rate, entry.format ?? "—", deltas))
    }
    exit(ok ? 0 : 1)
}

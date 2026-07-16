import Darwin
import Foundation
import RecorderCore

struct ReplayArmOptions {
    var seconds = 60.0
    var duration: Double?
}

func parseReplayArmOptions(_ args: [String]) -> ReplayArmOptions {
    var options = ReplayArmOptions()
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--seconds":
            // 600 s at Balanced on this display (~19 Mbps measured) is already a ~1.4 GB ring;
            // anything bigger is a mistake. docs/06's largest offered buffer is 120 s.
            options.seconds = parsePositive(iterator.next(), flag: "--seconds", max: 600)
        case "--duration":
            options.duration = parsePositive(iterator.next(), flag: "--duration", max: 86_400)
        default:
            die("Unknown option: \(arg)")
        }
    }
    return options
}

/// Physical memory footprint of this process — the number `footprint(1)` and Activity Monitor
/// report, which is what gate §6.1's RSS plateau is measured in.
func currentMemoryFootprint() -> Int64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Int64(info.phys_footprint)
}

/// One occupancy line every 2 s — a scrolling log rather than `record`'s in-place ticker,
/// because the §6.1 verify asserts a series (climb, then plateau) from the captured output.
private func runReplayTicker(_ encoder: ReplayEncoder) async {
    let clock = ContinuousClock()
    let start = clock.now
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if Task.isCancelled { return }
        let elapsed = Int(start.duration(to: clock.now).components.seconds)
        let stats = encoder.stats()
        let line = String(
            format: "  ⟳ %02d:%02d   ring %5.1fs · %4d samples · %3d keyframes · %6.1f MB · RSS %4d MB",
            elapsed / 60, elapsed % 60,
            stats.spanSeconds, stats.sampleCount, stats.keyframeCount,
            Double(stats.compressedBytes) / 1_048_576,
            currentMemoryFootprint() / 1_048_576)
        print(line)
    }
}

/// Arms instant replay: boots the capture engine with ONLY the replay consumer attached — no
/// MovieRecorder, no file (docs/03 M5-T2). Audio rings arrive in M5-T3, saving in M5-T4.
func runReplayArm(_ args: [String]) async {
    let options = parseReplayArmOptions(args)

    let configuration = CaptureConfiguration()
    let engine = CaptureEngine(configuration: configuration)
    // Route encoder failure through the engine's stop seam so the event loop prints it and the
    // process exits once from the main flow — never exit() from a VT/capture thread. `weak`
    // breaks the engine → router → encoder → engine cycle.
    let encoder = ReplayEncoder(seconds: options.seconds, frameRateCap: configuration.frameRateCap) {
        [weak engine] message in
        Task { await engine?.stop(reason: .streamError("replay encoder failed: \(message)")) }
    }
    engine.router.attach(encoder)

    let interactive = isatty(STDIN_FILENO) != 0
    var stopHints: [String] = []
    if let duration = options.duration { stopHints.append("auto-stop \(Int(duration))s") }
    if interactive { stopHints.append("Return stops early") }
    if stopHints.isEmpty { stopHints.append("until the stream ends") }
    print("replay-arm: balanced HEVC → \(Int(options.seconds)) s ring  (\(stopHints.joined(separator: " · ")))")

    await engine.start()

    var controls: [Task<Void, Never>] = []
    if let duration = options.duration {
        controls.append(stopTimer(after: duration) { await engine.stop() })
    }
    // Only on a terminal, so a piped/automated run isn't stopped by stdin EOF.
    if interactive {
        controls.append(Task.detached {
            _ = readLine()
            await engine.stop()
        })
    }

    var exitCode: Int32 = 0
    var ticker: Task<Void, Never>?
    for await event in engine.events {
        switch event {
        case .started:
            ticker = Task { await runReplayTicker(encoder) }
        case .stopped(let reason):
            print("replay-arm: stopped (\(describe(reason))) — ring discarded (saving arrives in M5-T4)")
            if reason != .userStopped { exitCode = 1 }
        case .failed(let message):
            FileHandle.standardError.write(Data("  ✗ \(message)\n".utf8))
            exitCode = 1
        default:
            break
        }
    }
    ticker?.cancel()
    controls.forEach { $0.cancel() }
    encoder.invalidate()
    exit(exitCode)
}

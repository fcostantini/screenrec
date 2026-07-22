import CoreGraphics
import Darwin
import Foundation
import RecorderCore

struct ReplayArmOptions {
    var seconds = 60.0
    var duration: Double?
    var appBundleID: String?
    var region: CGRect?
    var micID: String?
    var micEnabled = true
    var outputDir = OutputLocation.defaultDirectory()
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
        case "--app":
            guard let value = iterator.next() else { die("--app needs a bundle id (see list-apps)") }
            options.appBundleID = value
        case "--region":
            options.region = parseRegion(iterator.next())
        case "--mic":
            guard let value = iterator.next() else { die("--mic needs a device id") }
            options.micID = value
        case "--no-mic":
            options.micEnabled = false
        case "--output":
            options.outputDir = parseOutputDirectory(iterator.next())
        default:
            die("Unknown option: \(arg)")
        }
    }
    if options.region != nil, options.appBundleID != nil {
        die("--region and --app can't be combined "
            + "(a region captures the screen; an app captures its windows)")
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

/// The one-time format announcement for an audio ring, printed when its first buffer latches —
/// it's what makes the "bytes = duration × rate" verify readable straight off the log.
private func formatAnnouncement(_ label: String, _ format: ReplayAudioRing.Format, note: String?) -> String {
    String(
        format: "  · %@ %4.1f kHz × %d ch × %d B  → %3d KB/s%@",
        label, format.sampleRate / 1000, format.channels, format.bytesPerSample,
        format.bytesPerSecond / 1024, note.map { "   (\($0))" } ?? "")
}

/// Trouble suffix for an audio ring's segment — format changes and copy failures must surface
/// in the log or a dead audio path looks healthy right up to a bad M5-T4 save.
private func audioTrouble(_ stats: ReplayAudioRing.Stats) -> String {
    var notes: [String] = []
    if stats.formatChanges > 0 { notes.append("format ×\(stats.formatChanges)") }
    if stats.copyFailures > 0 { notes.append("\(stats.copyFailures) copy-failed") }
    return notes.isEmpty ? "" : " (⚠︎ \(notes.joined(separator: ", ")))"
}

/// One occupancy line every 2 s — a scrolling log rather than `record`'s in-place ticker,
/// because the §6.1 verify asserts a series (climb, then plateau) from the captured output.
private func runReplayTicker(
    _ encoder: ReplayEncoder, system: ReplayAudioRing, mic: ReplayAudioRing?, micName: String?
) async {
    let clock = ContinuousClock()
    let start = clock.now
    var announcedSystem = false
    var announcedMic = false
    while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        if Task.isCancelled { return }
        let elapsed = Int(start.duration(to: clock.now).components.seconds)
        let video = encoder.stats()
        let systemStats = system.stats()
        let micStats = mic?.stats()

        if !announcedSystem, let format = systemStats.format {
            print(formatAnnouncement("system audio:", format, note: nil))
            announcedSystem = true
        }
        if !announcedMic, let format = micStats?.format {
            print(formatAnnouncement("microphone:  ", format, note: micName))
            announcedMic = true
        }

        var line = String(
            format: "  ⟳ %02d:%02d   video %5.1fs ×%-4d %6.1fMB (%d kf) · system %5.1fs %4.1fMB%@",
            elapsed / 60, elapsed % 60,
            video.spanSeconds, video.sampleCount,
            Double(video.compressedBytes) / 1_048_576, video.keyframeCount,
            systemStats.spanSeconds, Double(systemStats.bytes) / 1_048_576,
            audioTrouble(systemStats))
        if let micStats {
            line += String(
                format: " · mic %5.1fs %4.1fMB%@",
                micStats.spanSeconds, Double(micStats.bytes) / 1_048_576, audioTrouble(micStats))
        }
        line += String(format: " · RSS %4dMB", currentMemoryFootprint() / 1_048_576)
        print(line)
    }
}

/// Arms instant replay: boots the capture engine with only replay consumers attached (encoder
/// + audio rings) — no MovieRecorder. SIGUSR1 or `s`+Return saves the last N seconds via
/// `ReplayMuxer`; concurrent triggers coalesce.
func runReplayArm(_ args: [String]) async {
    let options = parseReplayArmOptions(args)

    let mic = resolveMicrophone(micEnabled: options.micEnabled, preferredID: options.micID)
    if let unavailable = mic.unavailable { print("(no microphone: \(unavailable))") }
    let content = contentSelection(appBundleID: options.appBundleID, region: options.region)
    let configuration = CaptureConfiguration(
        content: content, microphone: mic.selection, microphoneRecovery: mic.recovery)
    let engine = CaptureEngine(configuration: configuration)
    // Route encoder failure through the engine's stop seam so the event loop prints it and the
    // process exits once from the main flow — never exit() from a VT/capture thread. `weak`
    // breaks the engine → router → encoder → engine cycle.
    let encoder = ReplayEncoder(seconds: options.seconds, frameRateCap: configuration.frameRateCap) {
        [weak engine] message in
        Task { await engine?.stop(reason: .streamError("replay encoder failed: \(message)")) }
    }
    engine.router.attach(encoder)

    let systemRing = ReplayAudioRing(source: .systemAudio, seconds: options.seconds)
    engine.router.attach(systemRing)
    var micRing: ReplayAudioRing?
    var micName: String?
    if case .device(let id) = mic.selection {
        let ring = ReplayAudioRing(source: .microphone, seconds: options.seconds)
        engine.router.attach(ring)
        micRing = ring
        micName = AudioInputs.available().first { $0.uniqueID == id }?.name
    }

    if case .inaccessible(let reason) = OutputLocation.preflight(options.outputDir) {
        die(reason, code: 74)
    }
    let muxer = ReplayMuxer(
        encoder: encoder, systemRing: systemRing, microphoneRing: micRing,
        seconds: options.seconds, outputDirectory: options.outputDir)

    // Both triggers (SIGUSR1 and s+Return) funnel here; the muxer coalesces overlaps (§6.3).
    let requestSave: @Sendable () -> Void = {
        let clock = ContinuousClock()
        let start = clock.now
        let accepted = muxer.requestSave { result in
            switch result {
            case .success(let saved):
                let parts = start.duration(to: clock.now).components
                let elapsed = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
                print(String(
                    format: "  ✓ replay saved in %.2f s → %@  (%.1f s)",
                    elapsed, saved.url.path, saved.duration))
            case .failure(let error):
                let message = (error as? ReplayMuxerError) == .nothingBuffered
                    ? "nothing buffered yet — the ring needs at least one frame"
                    : error.localizedDescription
                print("  ✗ replay save failed: \(message)")
            }
        }
        print(accepted ? "  ⏺ saving replay…" : "  (save already in progress — coalesced)")
    }

    let interactive = isatty(STDIN_FILENO) != 0
    var stopHints: [String] = []
    if let duration = options.duration { stopHints.append("auto-stop \(Int(duration))s") }
    if interactive { stopHints.append("s+Return saves · Return stops") }
    if stopHints.isEmpty { stopHints.append("until the stream ends") }
    print("replay-arm: balanced HEVC → \(Int(options.seconds)) s ring  (\(stopHints.joined(separator: " · ")))")
    if let bundleID = options.appBundleID { print("  capturing app: \(bundleID)") }
    if let region = options.region { print("  capturing region: \(describeRegion(region)) on the main display") }
    let pid = ProcessInfo.processInfo.processIdentifier
    print("  pid \(pid) — save from another shell:  kill -USR1 \(pid)")

    // SIG_IGN first: the dispatch source only works once the default terminate action is off.
    signal(SIGUSR1, SIG_IGN)
    let saveSignal = DispatchSource.makeSignalSource(
        signal: SIGUSR1, queue: DispatchQueue(label: "dev.fcostantini.screenrec.replay.signal"))
    saveSignal.setEventHandler(handler: requestSave)
    saveSignal.resume()

    await engine.start()

    var controls: [Task<Void, Never>] = []
    if let duration = options.duration {
        controls.append(stopTimer(after: duration) { await engine.stop() })
    }
    // Only on a terminal, so a piped/automated run isn't stopped by stdin EOF.
    if interactive {
        controls.append(Task.detached {
            while let line = readLine() {
                guard line.trimmingCharacters(in: .whitespaces).lowercased() == "s" else { break }
                requestSave()
            }
            await engine.stop()   // non-"s" line, or EOF
        })
    }

    var exitCode: Int32 = 0
    var ticker: Task<Void, Never>?
    for await event in engine.events {
        switch event {
        case .started:
            ticker = Task {
                await runReplayTicker(encoder, system: systemRing, mic: micRing, micName: micName)
            }
        case .microphoneLost:
            // Same warning record prints (ADR-012): screen + system audio keep buffering; the
            // mic ring just stops filling — without this line its frozen column looks healthy.
            print("  ⚠️  microphone disconnected — replay continues (screen + system audio)")
        case .microphoneRecovered:
            print("  🎤 microphone reconnected — the mic ring is filling again")
        case .stopped(let reason):
            print("replay-arm: stopped (\(describe(reason))) — ring discarded")
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
    // A save triggered moments before stop may still be writing; exiting now would tear it.
    muxer.waitUntilIdle()
    encoder.invalidate()
    exit(exitCode)
}

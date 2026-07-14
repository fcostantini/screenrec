import Foundation
import RecorderCore

// Unbuffered stdout so diagnostics survive crashes and pipes (docs/02 §10).
setvbuf(stdout, nil, _IONBF, 0)

func printUsage() {
    print("""
    screenrec-cli — dev harness for screenrec (M0 skeleton)

    USAGE:
      screenrec-cli record [options]   Dry-run: print the recording config that would be used
      screenrec-cli list-mics          List audio input devices
      screenrec-cli engine-smoke [--duration N]   Start/stop the capture engine (default 2s)
      screenrec-cli probe-stream [--duration N] [--mic <id>] [--no-mic]
                                       Capture and report per-source buffers/formats/PTS
      screenrec-cli --help

    record options:
      --duration <sec>   Stop after N seconds (config only; real capture lands in M2)
      --preset <name>    efficient | balanced | high   (default: balanced)
      --mic <id>         Use a specific microphone (see list-mics)
      --no-mic           Record without a microphone
      --output <dir>     Output directory (default: ~/Movies)
    """)
}

func die(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

func describe(_ state: PermissionState) -> String {
    switch state {
    case .granted: return "granted"
    case .denied: return "denied"
    case .notDetermined: return "not determined"
    }
}

func describe(_ reason: EndReason) -> String {
    switch reason {
    case .userStopped: return "userStopped"
    case .displayDisconnected: return "displayDisconnected"
    case .microphoneChanged: return "microphoneChanged"
    case .diskAlmostFull: return "diskAlmostFull"
    case .systemSleep: return "systemSleep"
    case .streamError(let message): return "streamError(\(message))"
    }
}

func describe(_ event: EngineEvent) -> String {
    switch event {
    case .started: return "started"
    case .paused: return "paused"
    case .resumed: return "resumed"
    case .fileProgress(let seconds, let bytes):
        return "fileProgress(\(seconds.isFinite ? Int(seconds) : 0)s, \(bytes) bytes)"
    case .stopped(let reason): return "stopped(\(describe(reason)))"
    case .finished(let url, let reason, let dropped):
        return "finished(\(url.lastPathComponent), \(describe(reason)), dropped \(dropped))"
    case .failed(let message): return "failed: \(message)"
    }
}

/// Starts the capture engine, prints each event, stops after `--duration` seconds.
/// Instrument for M1-T2: proves the SCStream lifecycle works (and, from the CLI,
/// whether capture runs under the terminal's grant).
func runEngineSmoke(_ args: [String]) async {
    var duration = 2.0
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--duration":
            guard let value = iterator.next(), let seconds = Double(value), seconds.isFinite, seconds > 0 else {
                die("--duration needs a positive number of seconds")
            }
            duration = seconds
        default:
            die("Unknown option: \(arg)")
        }
    }

    let engine = CaptureEngine(configuration: CaptureConfiguration())
    print("engine-smoke: starting (\(Int(duration))s)…")

    // OK requires: a video frame captured (.started) AND a clean user stop, with no
    // failure or stream error. The consumer completes when the event stream finishes.
    let consumer = Task { () -> Bool in
        var sawStarted = false
        var cleanStop = false
        var problem: String?
        for await event in engine.events {
            print("  event: \(describe(event))")
            switch event {
            case .started: sawStarted = true
            case .stopped(.userStopped): cleanStop = true
            case .stopped(let reason): problem = "stream ended: \(describe(reason))"
            case .failed(let message): problem = message
            default: break
            }
        }
        if let problem { print("  ✗ \(problem)"); return false }
        if !sawStarted { print("  ✗ no video frame captured (.started never fired)"); return false }
        if !cleanStop { print("  ✗ did not stop cleanly"); return false }
        return true
    }

    await engine.start()
    // Stop after `duration`, but if the stream already ended (e.g. failed to start) the
    // consumer completes immediately and we cancel the timer instead of waiting it out.
    let stopTimer = Task {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        await engine.stop()
    }
    let ok = await consumer.value
    stopTimer.cancel()

    print(ok ? "engine-smoke: OK" : "engine-smoke: FAILED")
    exit(ok ? 0 : 1)
}

func listMics() {
    let devices = AudioInputs.available()
    guard !devices.isEmpty else {
        print("No audio input devices found.")
        return
    }
    for device in devices {
        print("\(device.uniqueID)  —  \(device.name)\(device.isDefault ? "  (default)" : "")")
    }
}

func runRecordDryRun(_ args: [String]) {
    var duration: Double?
    var preset: QualityPreset = .balanced
    var micID: String?
    var micEnabled = true
    var outputDir = OutputLocation.defaultDirectory()

    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--duration":
            guard let value = iterator.next(), let seconds = Double(value) else { die("--duration needs a number") }
            duration = seconds
        case "--preset":
            guard let value = iterator.next() else { die("--preset needs a value") }
            guard let parsed = QualityPreset(rawValue: value) else {
                die("--preset must be one of: \(QualityPreset.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            preset = parsed
        case "--mic":
            guard let value = iterator.next() else { die("--mic needs a device id") }
            micID = value
        case "--no-mic":
            micEnabled = false
        case "--output":
            guard let value = iterator.next() else { die("--output needs a path") }
            outputDir = URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        default:
            die("Unknown option: \(arg)")
        }
    }

    print("Recording configuration (dry-run — no capture yet):")
    print("  Screen recording permission: \(describe(Permissions.screenRecordingState()))")
    print("  Preset:   \(preset.rawValue)")
    print("  FPS cap:  60")
    print("  Duration: \(duration.map { "\(Int($0))s" } ?? "until stopped")")

    if micEnabled {
        print("  Microphone permission: \(describe(Permissions.microphoneState()))")
        switch Permissions.resolvedMicrophoneID(preferred: micID) {
        case .explicit(let id):
            let name = AudioInputs.available().first { $0.uniqueID == id }?.name ?? "unknown"
            print("  Microphone: \(name)  [\(id)]")
        case .noDevice(let reason):
            print("  Microphone: none — \(reason)")
        }
    } else {
        print("  Microphone: off (--no-mic)")
    }

    print("  Output dir: \(outputDir.path)")
    switch OutputLocation.preflight(outputDir) {
    case .accessible:
        print("  Output preflight: OK")
    case .inaccessible(let reason):
        print("  Output preflight: FAILED — \(reason)")
    }
    let outputURL = OutputLocation(directory: outputDir).newRecordingURL(date: Date())
    print("  Would write: \(outputURL.lastPathComponent)")
}

// MARK: - Dispatch

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(64)
}

switch command {
case "record":
    runRecordDryRun(Array(arguments.dropFirst()))
case "list-mics", "--list-mics":
    listMics()
case "engine-smoke":
    await runEngineSmoke(Array(arguments.dropFirst()))
case "probe-stream":
    await runProbeStream(Array(arguments.dropFirst()))
case "-h", "--help":
    printUsage()
default:
    die("Unknown command: \(command)")
}

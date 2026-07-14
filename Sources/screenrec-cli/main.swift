import Foundation
import RecorderCore

// Unbuffered stdout so diagnostics survive crashes and pipes (docs/02 §10).
setvbuf(stdout, nil, _IONBF, 0)

// M1-T1 replaces this with the shared quality-preset enum.
let validPresets = ["efficient", "balanced", "high"]

func printUsage() {
    print("""
    screenrec-cli — dev harness for screenrec (M0 skeleton)

    USAGE:
      screenrec-cli record [options]   Dry-run: print the recording config that would be used
      screenrec-cli list-mics          List audio input devices
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
    var preset = "balanced"
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
            guard validPresets.contains(value) else {
                die("--preset must be one of: \(validPresets.joined(separator: ", "))")
            }
            preset = value
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
    print("  Preset:   \(preset)")
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
case "-h", "--help":
    printUsage()
default:
    die("Unknown command: \(command)")
}

import Foundation
import RecorderCore

// Unbuffered stdout so diagnostics survive crashes and pipes (docs/02 §10).
setvbuf(stdout, nil, _IONBF, 0)

func printUsage() {
    print("""
    screenrec-cli — dev harness for screenrec (M0 skeleton)

    USAGE:
      screenrec-cli record [options] [path]   Record screen + audio to a .mov
      screenrec-cli list-mics          List audio input devices
      screenrec-cli engine-smoke [--duration N]   Start/stop the capture engine (default 2s)
      screenrec-cli probe-stream [--duration N] [--mic <id>] [--no-mic]
                                       Capture and report per-source buffers/formats/PTS
      screenrec-cli replay-arm [--seconds N] [--duration N] [--mic <id>] [--no-mic]
                               [--output <dir>]
                                       Arm instant replay: screen + system audio + mic into
                                       rolling N-second rings (default 60). Prints occupancy
                                       every 2 s.
                                       Save the last N seconds anytime with 's'+Return or
                                       `kill -USR1 <pid>` → "Replay <date>.mov" in --output
                                       (default ~/Movies); any other line (or Return) stops.
      screenrec-cli mic-swap-spike [mode]  How SCK binds mic devices (M3-T7 evidence, 02 §4)
      screenrec-cli --help

    mic-swap-spike modes:
      (default)      Re-point between two live devices mid-capture
      --reconnect    Re-bind a device that died and came back        (human: case/uncase)
      --fallback     Re-point to a never-died device after mic loss  (human: case)
      --nil-device   Is a nil microphoneCaptureDeviceID accepted?
      --nil-follow   Does nil follow the system default as it changes? (human: case)
      --two-streams  Can a mic-only stream coexist with the recording stream?

    record options:
      --duration <sec>   Stop after N seconds (else p/r/Return on a terminal, or stream end)
      --preset <name>    efficient | balanced | high   (default: balanced)
      --mic <id>         Use a specific microphone (see list-mics)
      --no-mic           Record without a microphone
      --output <dir>     Output directory when no [path] is given (default: ~/Movies)
      --script <steps>   Unattended pause timeline, e.g. rec10,pause5,rec10 (seconds each)
      --test-disk-floor <GB>  Trip the disk guard on demand: stop cleanly when free space
                         is below <GB> (real floor is 2 GB — pass a huge value to test)
      --dry-run          Print the config that would be used, without capturing
      [path]             Explicit output file, or an existing directory to write into

    While recording on a terminal: 'p'+Return pauses, 'r'+Return resumes, Return stops.
    """)
}

func die(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(code)
}

/// Parses a flag's positive, finite number, or dies with a usage error.
/// `max` bounds values that later feed trapping conversions (`UInt64(seconds * 1e9)`, byte counts).
func parsePositive(
    _ value: String?, flag: String, unit: String = "seconds", max: Double? = nil
) -> Double {
    guard let value, let parsed = Double(value), parsed.isFinite, parsed > 0,
          max.map({ parsed <= $0 }) ?? true else {
        die("\(flag) needs a positive number of \(unit)\(max.map { " (max \(Int($0)))" } ?? "")")
    }
    return parsed
}

/// Parses `--output`'s directory argument — one resolver so record and replay-arm can't drift.
func parseOutputDirectory(_ value: String?) -> URL {
    guard let value else { die("--output needs a path") }
    return URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
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
    case .microphoneLost: return "microphoneLost"
    case .recordingFileRestored: return "recordingFileRestored"
    case .fileProgress(let seconds, let bytes):
        return "fileProgress(\(seconds.isFinite ? Int(seconds) : 0)s, \(bytes) bytes)"
    case .stopped(let reason): return "stopped(\(describe(reason)))"
    case .finished(let url, let reason, let dropped):
        return "finished(\(url.lastPathComponent), \(describe(reason)), dropped \(dropped))"
    case .failed(let message): return "failed: \(message)"
    }
}

/// Starts the capture engine, prints each event, stops after `--duration` seconds.
func runEngineSmoke(_ args: [String]) async {
    var duration = 2.0
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--duration":
            duration = parsePositive(iterator.next(), flag: "--duration")
        default:
            die("Unknown option: \(arg)")
        }
    }

    let engine = CaptureEngine(configuration: CaptureConfiguration())
    print("engine-smoke: starting (\(Int(duration))s)…")

    // OK requires a captured video frame (.started) and a clean user stop.
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
    // Cancelled if the stream ends first, so a failed start doesn't wait out the timer.
    let timer = stopTimer(after: duration) { await engine.stop() }
    let ok = await consumer.value
    timer.cancel()

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

/// One step of a `--script` timeline (04 §4.1): record for N seconds, or pause for N seconds.
enum ScriptStep {
    case record(Double)
    case pause(Double)
}

struct RecordOptions {
    var duration: Double?
    var preset: QualityPreset = .balanced
    var micID: String?
    var micEnabled = true
    var outputDir = OutputLocation.defaultDirectory()
    var path: String?
    var dryRun = false
    var script: [ScriptStep]?
    var diskFloorBytes: Int64?
}

/// Parses `rec10,pause5,rec10` into steps.
func parseScript(_ raw: String) -> [ScriptStep] {
    let steps = raw.split(separator: ",").map { token -> ScriptStep in
        let text = token.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("rec"), let seconds = Double(text.dropFirst(3)), seconds.isFinite, seconds >= 0 {
            return .record(seconds)
        }
        if text.hasPrefix("pause"), let seconds = Double(text.dropFirst(5)), seconds.isFinite, seconds >= 0 {
            return .pause(seconds)
        }
        die("--script step must be rec<seconds> or pause<seconds>, got: \(text)")
    }
    guard !steps.isEmpty else { die("--script needs at least one step, e.g. rec10,pause5,rec10") }
    return steps
}

func parseRecordOptions(_ args: [String]) -> RecordOptions {
    var options = RecordOptions()
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--duration":
            // Upper bound keeps `seconds * 1e9` well inside UInt64 for the sleep timer.
            options.duration = parsePositive(iterator.next(), flag: "--duration", max: 86_400)
        case "--preset":
            guard let value = iterator.next() else { die("--preset needs a value") }
            guard let parsed = QualityPreset(rawValue: value) else {
                die("--preset must be one of: \(QualityPreset.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            options.preset = parsed
        case "--mic":
            guard let value = iterator.next() else { die("--mic needs a device id") }
            options.micID = value
        case "--no-mic":
            options.micEnabled = false
        case "--output":
            options.outputDir = parseOutputDirectory(iterator.next())
        case "--script":
            guard let value = iterator.next() else { die("--script needs a value like rec10,pause5,rec10") }
            options.script = parseScript(value)
        case "--test-disk-floor":
            // Test hook (04 §4.4): a floor above the volume's free space trips the disk guard.
            // Bounded at 1 PB so GB→bytes can't overflow Int64.
            let gigabytes = parsePositive(
                iterator.next(), flag: "--test-disk-floor", unit: "GB", max: 1_000_000)
            options.diskFloorBytes = Int64(gigabytes * 1_073_741_824)
        case "--dry-run":
            options.dryRun = true
        default:
            guard !arg.hasPrefix("-") else { die("Unknown option: \(arg)") }
            guard options.path == nil else { die("Unexpected extra argument: \(arg)") }
            options.path = arg     // positional: an explicit output file, or a directory
        }
    }
    // A script owns its own timeline, so a duration bound would race it.
    if options.script != nil, options.duration != nil {
        die("--script and --duration can't be combined (the script controls timing)")
    }
    return options
}

enum CLIError: Error { case message(String) }

/// Where a recording writes: an auto-named file in a directory, or an exact user-given file.
/// A positional path that is an existing directory means the former; otherwise the latter.
enum OutputTarget {
    case directory(URL)
    case file(URL)
}

func outputTarget(_ options: RecordOptions) -> OutputTarget {
    guard let path = options.path else { return .directory(options.outputDir) }
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
        return .directory(url)
    }
    return .file(url)
}

/// Resolves and atomically reserves the output file, running the write preflight first.
func reserveOutputURL(_ options: RecordOptions) throws -> URL {
    func preflight(_ directory: URL) throws {
        if case .inaccessible(let reason) = OutputLocation.preflight(directory) {
            throw CLIError.message(reason)
        }
    }
    switch outputTarget(options) {
    case .directory(let directory):
        try preflight(directory)
        return try OutputLocation(directory: directory).reserveRecordingURL(date: Date())
    case .file(let url):
        try preflight(url.deletingLastPathComponent())
        return try OutputLocation.reserveExact(url)
    }
}

/// Microphone selection, plus the reason when a mic was requested but none is usable.
/// Shared by record (dry-run and real capture) and replay-arm so they can't disagree.
func resolveMicrophone(micEnabled: Bool, preferredID: String?) -> (selection: MicrophoneSelection, unavailable: String?) {
    guard micEnabled else { return (.none, nil) }
    switch Permissions.resolvedMicrophoneID(preferred: preferredID) {
    case .explicit(let id): return (.device(id: id), nil)
    case .noDevice(let reason): return (.none, reason)
    }
}

func printRecordDryRun(_ options: RecordOptions) {
    print("Recording configuration (dry-run — no capture):")
    print("  Screen recording permission: \(describe(Permissions.screenRecordingState()))")
    print("  Preset:   \(options.preset.rawValue)")
    print("  FPS cap:  \(CaptureConfiguration().frameRateCap)")
    print("  Duration: \(options.duration.map { "\(Int($0))s" } ?? "until stopped")")

    if options.micEnabled {
        print("  Microphone permission: \(describe(Permissions.microphoneState()))")
        let mic = resolveMicrophone(micEnabled: options.micEnabled, preferredID: options.micID)
        switch mic.selection {
        case .device(let id):
            let name = AudioInputs.available().first { $0.uniqueID == id }?.name ?? "unknown"
            print("  Microphone: \(name)  [\(id)]")
        case .none:
            print("  Microphone: none — \(mic.unavailable ?? "unavailable")")
        }
    } else {
        print("  Microphone: off (--no-mic)")
    }

    let planned = plannedOutputURL(options)
    let directory = planned.deletingLastPathComponent()
    print("  Output dir: \(directory.path)")
    switch OutputLocation.preflight(directory) {
    case .accessible:
        print("  Output preflight: OK")
    case .inaccessible(let reason):
        print("  Output preflight: FAILED — \(reason)")
    }
    print("  Would write: \(planned.lastPathComponent)")
}

/// The URL a real recording would use, for the dry-run. Reserves nothing.
func plannedOutputURL(_ options: RecordOptions) -> URL {
    switch outputTarget(options) {
    case .directory(let directory): return OutputLocation(directory: directory).newRecordingURL(date: Date())
    case .file(let url): return url
    }
}

/// Current on-disk size of the growing recording (fragmented .mov grows as it's written).
/// The in-progress file is the `.partial` companion; the final name exists only after
/// finalize, so probe the partial first.
func recordingFileSize(_ url: URL) -> Int64 {
    for candidate in [OutputLocation.partialURL(for: url), url] {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path),
           let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }
    }
    return 0
}

/// In-place progress line, refreshed twice a second. `recordedDuration` is NaN before the first
/// frame (docs/02 §10), so the duration is guarded.
func runProgressTicker(_ session: RecordingSession, outputURL: URL) async {
    while !Task.isCancelled {
        let raw = session.recordedDuration.seconds
        let seconds = raw.isFinite ? raw : 0
        let size = ByteCountFormatter.string(fromByteCount: recordingFileSize(outputURL), countStyle: .file)
        let line = String(format: "\r  ⏺ %02d:%02d   %@      ", Int(seconds) / 60, Int(seconds) % 60, size)
        FileHandle.standardOutput.write(Data(line.utf8))
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
}

/// Sleeps `seconds` with a tight tolerance. The default `Task.sleep` wake-up slack inflates the
/// measured file duration past the ±0.2 s pause-math gate (04 §4.1).
func preciseSleep(_ seconds: Double) async {
    let clock = ContinuousClock()
    try? await clock.sleep(until: clock.now.advanced(by: .seconds(seconds)), tolerance: .milliseconds(2))
}

/// A timer task that stops capture after `seconds` — the `--duration` stop control shared by
/// engine-smoke, record and replay-arm.
func stopTimer(after seconds: Double, stop: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
    Task {
        await preciseSleep(seconds)
        await stop()
    }
}

/// Runs a `--script` timeline against a live session, then stops it. A record step is a wait;
/// a pause step brackets its wait with `pause()`/`resume()`.
func runScript(_ steps: [ScriptStep], session: RecordingSession) async {
    // Anchor to the first captured frame, not to start() returning: SCK startup latency would
    // otherwise shorten the file below the ±0.2 s gate. Bounded ~5 s so a dead stream can't hang.
    var waited = 0
    while !session.hasStartedSession, waited < 1000 {
        await preciseSleep(0.005)
        waited += 1
    }
    for step in steps {
        switch step {
        case .record(let seconds):
            await preciseSleep(seconds)
        case .pause(let seconds):
            await session.pause()
            await preciseSleep(seconds)
            await session.resume()
        }
    }
    await session.stop()
}

/// Line-based stdin control on a TTY: `p` pauses, `r` resumes, any other line (or EOF) stops.
func runInteractiveControls(_ session: RecordingSession) async {
    while let line = readLine() {
        switch line.trimmingCharacters(in: .whitespaces).lowercased() {
        case "p": await session.pause()
        case "r": await session.resume()
        default: await session.stop(); return
        }
    }
    await session.stop()   // EOF
}

/// Real capture: reserve the output file, run a `RecordingSession`, and drive it via `--script`,
/// `--duration`, or interactive p/r/Return on a TTY (else until the stream ends).
func performRecording(_ options: RecordOptions) async {
    let outputURL: URL
    do {
        // Crashed runs leave `.partial`s only an app launch would otherwise sweep; the CLI
        // sweeps its own target folder so a CLI-only user gets their recordings back too.
        let targetDirectory: URL
        switch outputTarget(options) {
        case .directory(let directory): targetDirectory = directory
        case .file(let url): targetDirectory = url.deletingLastPathComponent()
        }
        for recovered in OutputLocation(directory: targetDirectory).recoverOrphanedPartials() {
            print("recovered interrupted recording: \(recovered.path)")
        }
        outputURL = try reserveOutputURL(options)
    } catch CLIError.message(let reason) {
        die(reason, code: 74)
    } catch OutputLocation.ReservationError.alreadyExists(let path) {
        die("Output file already exists: \(path)", code: 74)
    } catch {
        die("Couldn't create the output file: \(error.localizedDescription)", code: 74)
    }

    let mic = resolveMicrophone(micEnabled: options.micEnabled, preferredID: options.micID)
    if let unavailable = mic.unavailable { print("(no microphone: \(unavailable))") }
    let configuration = CaptureConfiguration(microphone: mic.selection, quality: options.preset)
    let session: RecordingSession
    do {
        session = try RecordingSession(
            configuration: configuration, outputURL: outputURL, diskFloorBytes: options.diskFloorBytes)
    } catch {
        // Drop the unused reservation placeholder — it lives at the `.partial` companion.
        try? FileManager.default.removeItem(at: OutputLocation.partialURL(for: outputURL))
        die("Couldn't set up the recorder: \(error.localizedDescription)", code: 74)
    }

    // A script drives its own stop, so interactive keys are off in that mode.
    let interactive = options.script == nil && isatty(STDIN_FILENO) != 0
    let stopHint: String
    if options.script != nil {
        stopHint = "scripted"
    } else if let duration = options.duration {
        stopHint = "\(Int(duration))s"
    } else {
        stopHint = interactive ? "p pause · r resume · Return stop" : "until the stream ends"
    }
    print("record: \(options.preset.rawValue) → \(outputURL.path)  (\(stopHint))")

    await session.start()
    let ticker = Task { await runProgressTicker(session, outputURL: outputURL) }

    var controls: [Task<Void, Never>] = []
    if let steps = options.script {
        controls.append(Task { await runScript(steps, session: session) })
    } else {
        if let duration = options.duration {
            controls.append(stopTimer(after: duration) { await session.stop() })
        }
        // Only when stdin is a terminal, so a piped/automated run isn't stopped by stdin EOF.
        if interactive {
            controls.append(Task.detached { await runInteractiveControls(session) })
        }
    }

    var exitCode: Int32 = 0
    for await event in session.events {
        switch event {
        case .paused:
            print("\n  ⏸  paused")
        case .resumed:
            print("\n  ▶  resumed")
        case .microphoneLost:
            // Not a stop: screen + system audio keep recording, the mic track ends here (ADR-012).
            print("\n  ⚠️  microphone disconnected — still recording (screen + system audio)")
        case .recordingFileRestored:
            print("\n  ⚠️  recording file was moved — moved it back (recording continues)")
        case .finished(let url, let reason, let dropped):
            ticker.cancel()
            print("\n  ✓ finished (\(describe(reason))), dropped frames: \(dropped)")
            print("  \(url.path)")
        case .failed(let message):
            ticker.cancel()
            FileHandle.standardError.write(Data("\n  ✗ \(message)\n".utf8))
            exitCode = 1
        default:
            break
        }
    }
    ticker.cancel()
    controls.forEach { $0.cancel() }
    exit(exitCode)
}

// MARK: - Dispatch

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    printUsage()
    exit(64)
}

switch command {
case "record":
    let options = parseRecordOptions(Array(arguments.dropFirst()))
    if options.dryRun {
        printRecordDryRun(options)
    } else {
        await performRecording(options)
    }
case "list-mics", "--list-mics":
    listMics()
case "engine-smoke":
    await runEngineSmoke(Array(arguments.dropFirst()))
case "probe-stream":
    await runProbeStream(Array(arguments.dropFirst()))
case "replay-arm":
    await runReplayArm(Array(arguments.dropFirst()))
case "mic-swap-spike":
    await runMicSwapSpike(Array(arguments.dropFirst()))
case "-h", "--help":
    printUsage()
default:
    die("Unknown command: \(command)")
}

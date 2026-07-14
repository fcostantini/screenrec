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
      screenrec-cli --help

    record options:
      --duration <sec>   Stop after N seconds (else p/r/Return on a terminal, or stream end)
      --preset <name>    efficient | balanced | high   (default: balanced)
      --mic <id>         Use a specific microphone (see list-mics)
      --no-mic           Record without a microphone
      --output <dir>     Output directory when no [path] is given (default: ~/Movies)
      --script <steps>   Unattended pause timeline, e.g. rec10,pause5,rec10 (seconds each)
      --dry-run          Print the config that would be used, without capturing
      [path]             Explicit output file, or an existing directory to write into

    While recording on a terminal: 'p'+Return pauses, 'r'+Return resumes, Return stops.
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

/// One step of a `--script` timeline: record for N seconds, or pause for N seconds (a pause
/// step brackets its wait with pause/resume). Drives the unattended pause-math gate (04 §4.1).
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
}

/// Parses `rec10,pause5,rec10` into steps. Each token is `rec<seconds>` or `pause<seconds>`
/// with a finite, non-negative count; anything else is a usage error.
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
            guard let value = iterator.next(), let seconds = Double(value),
                  seconds.isFinite, seconds > 0, seconds <= 86_400 else {
                die("--duration needs a positive number of seconds (max 86400)")
            }
            options.duration = seconds
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
            guard let value = iterator.next() else { die("--output needs a path") }
            options.outputDir = URL(fileURLWithPath: (value as NSString).expandingTildeInPath, isDirectory: true)
        case "--script":
            guard let value = iterator.next() else { die("--script needs a value like rec10,pause5,rec10") }
            options.script = parseScript(value)
        case "--dry-run":
            options.dryRun = true
        default:
            guard !arg.hasPrefix("-") else { die("Unknown option: \(arg)") }
            guard options.path == nil else { die("Unexpected extra argument: \(arg)") }
            options.path = arg     // positional: an explicit output file, or a directory
        }
    }
    // A script owns the whole timeline (its own pauses and stop), so a duration bound would
    // just race it — reject the ambiguous combination rather than silently pick one.
    if options.script != nil, options.duration != nil {
        die("--script and --duration can't be combined (the script controls timing)")
    }
    return options
}

enum CLIError: Error { case message(String) }

/// Where a recording writes: an auto-named file in a directory, or an exact user-given file.
/// An explicit positional path that is an existing directory means the former; otherwise the
/// latter. With no path, the `--output` directory (default ~/Movies) is used.
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

/// Resolves and atomically reserves the output file for a real recording, running the write
/// preflight on its directory first.
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

/// Pure microphone resolution: the selection plus, when a mic was requested but no device is
/// usable, the reason. Both the dry-run and real capture go through this so they can't disagree.
func resolveMicrophone(_ options: RecordOptions) -> (selection: MicrophoneSelection, unavailable: String?) {
    guard options.micEnabled else { return (.none, nil) }
    switch Permissions.resolvedMicrophoneID(preferred: options.micID) {
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
        let mic = resolveMicrophone(options)
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

/// The output URL a real recording WOULD use, for the dry-run — same resolution as
/// `reserveOutputURL` but with no side effects (check-then-act naming, reserves nothing).
func plannedOutputURL(_ options: RecordOptions) -> URL {
    switch outputTarget(options) {
    case .directory(let directory): return OutputLocation(directory: directory).newRecordingURL(date: Date())
    case .file(let url): return url
    }
}

/// Current on-disk size of the growing recording (fragmented .mov grows as it's written).
func recordingFileSize(_ url: URL) -> Int64 {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber else { return 0 }
    return size.int64Value
}

/// In-place progress line: `⏺ MM:SS  <size>`, refreshed twice a second. Guards the duration
/// against NaN seconds before the first frame (docs/02 §10) so it can never print "NaN".
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

/// Sleeps `seconds` with a tight tolerance. The default `Task.sleep` grants the scheduler
/// generous wake-up slack, which — under the capture's CPU load — inflates the measured file
/// duration; over a script's two record segments that overshoot pushed past the ±0.2 s
/// pause-math gate (04 §4.1). A 2 ms tolerance keeps the `--script` and `--duration` stop
/// boundaries honest.
func preciseSleep(_ seconds: Double) async {
    let clock = ContinuousClock()
    try? await clock.sleep(until: clock.now.advanced(by: .seconds(seconds)), tolerance: .milliseconds(2))
}

/// Runs a `--script` timeline against a live session, then stops it. A record step is just a
/// wait (capture continues); a pause step brackets its wait with `pause()`/`resume()`.
func runScript(_ steps: [ScriptStep], session: RecordingSession) async {
    // Anchor the timeline to the first captured frame, not to start() returning: SCK startup
    // latency (the first frame lands ~0.1–0.5 s after capture begins, more on a cold start)
    // would otherwise shorten the file below the ±0.2 s gate. recordedDuration is NaN until the
    // session starts. Bounded (~5 s) so a stream that never starts can't hang the script.
    var waited = 0
    while session.recordedDuration.seconds.isNaN, waited < 1000 {
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

/// Interactive stdin control on a TTY: `p`+Return pauses, `r`+Return resumes, any other line
/// (a bare Return, `q`, EOF, …) stops — matching the pre-pause "Return to stop" behavior.
/// Line-based, so no raw-terminal handling is needed.
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

/// Real capture: reserve the output file, run a `RecordingSession` with a live progress ticker,
/// drive it via `--script`, `--duration`, or interactive p/r/Return on a TTY (else stream end),
/// then report the finalized file.
func performRecording(_ options: RecordOptions) async {
    let outputURL: URL
    do {
        outputURL = try reserveOutputURL(options)
    } catch CLIError.message(let reason) {
        die(reason, code: 74)
    } catch OutputLocation.ReservationError.alreadyExists(let path) {
        die("Output file already exists: \(path)", code: 74)
    } catch {
        die("Couldn't create the output file: \(error.localizedDescription)", code: 74)
    }

    let mic = resolveMicrophone(options)
    if let unavailable = mic.unavailable { print("(no microphone: \(unavailable))") }
    let configuration = CaptureConfiguration(microphone: mic.selection, quality: options.preset)
    let session: RecordingSession
    do {
        session = try RecordingSession(configuration: configuration, outputURL: outputURL)
    } catch {
        try? FileManager.default.removeItem(at: outputURL)  // drop the unused reservation placeholder
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

    // Control tasks: a script owns the whole timeline; otherwise a `--duration` timer and/or
    // interactive keys. All are cancelled once the session finishes.
    var controls: [Task<Void, Never>] = []
    if let steps = options.script {
        controls.append(Task { await runScript(steps, session: session) })
    } else {
        if let duration = options.duration {
            controls.append(Task {
                await preciseSleep(duration)
                await session.stop()
            })
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
case "-h", "--help":
    printUsage()
default:
    die("Unknown command: \(command)")
}

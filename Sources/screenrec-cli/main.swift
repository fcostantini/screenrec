import CoreGraphics
import Foundation
import RecorderCore

// Unbuffered stdout so diagnostics survive crashes and pipes (docs/02 §10).
setvbuf(stdout, nil, _IONBF, 0)

func printUsage() {
    print("""
    screenrec-cli — dev harness for screenrec (M0 skeleton)

    USAGE:
      screenrec-cli record [options] [path]   Record screen + audio to a .mov
      screenrec-cli export --to-mp4 <in> [--width <px>] [<out>]  Transcode a recording to a
                                       shareable H.264 + AAC .mp4 (yuv420p, faststart): 1920 wide
                                       by default, the two audio tracks mixed to one. --width sets
                                       the cap (height follows the aspect, capped at 2304 so the
                                       output stays inside H.264 Level 5.2); bitrate scales with
                                       the output size. Default <out> is the input's .mp4 sibling.
                                       The source is read-only.
      screenrec-cli export --to-gif <in> [<out>]  Save a clip as a looping animated .gif
                                       (default 480 wide, 15 fps, first 30 s). Override with
                                       --fps <n> --width <px> --seconds <n>. Default <out> is the
                                       input's .gif sibling. The source is read-only.
      screenrec-cli trim <in> --from <t> --to <t> [--precise] [<out>]  Trim a recording to
                                       [from, to]; times are M:SS or seconds. Both modes start at
                                       [from] exactly. Lossless (default) copies the streams, so
                                       the file also keeps the frames back to the preceding
                                       keyframe (the run prints how many). --precise re-encodes at
                                       the source's size and codec, so the file holds only
                                       [from, to] — slower, and larger on quiet content.
                                       Default <out> is the input's " trimmed" sibling; read-only.
      screenrec-cli list-mics          List audio input devices
      screenrec-cli list-apps          List running apps capturable with record --app
      screenrec-cli list-windows       List on-screen windows capturable with record --window
      screenrec-cli engine-smoke [--duration N]   Start/stop the capture engine (default 2s)
      screenrec-cli probe-stream [--duration N] [--mic <id>] [--no-mic]
                                       Capture and report per-source buffers/formats/PTS
      screenrec-cli replay-arm [--seconds N] [--duration N] [--app <bundle-id>]
                               [--region <x,y,w,h>] [--window <id>] [--mic <id>] [--no-mic]
                               [--no-system-audio] [--output <dir>]
                                       Arm instant replay: screen + system audio + mic into
                                       rolling N-second rings (default 60). Prints occupancy
                                       every 2 s. --app scopes video + system audio to one
                                       app (see list-apps); if that app quits, the armed
                                       stream ends (no auto-retry — that's the GUI's job).
                                       --region records a rectangle of the main display
                                       (display points). --window records one window, which
                                       the capture follows as it moves (see list-windows).
                                       --app, --region and --window are mutually exclusive.
                                       Save the last N seconds anytime with 's'+Return or
                                       `kill -USR1 <pid>` → "Replay <date>.mov" in --output
                                       (default ~/Movies); any other line (or Return) stops.
      screenrec-cli --help

    record options:
      --duration <sec>   Stop after N seconds (else p/r/Return on a terminal, or stream end)
      --preset <name>    efficient | balanced | high   (default: balanced)
      --app <bundle-id>  Record one app instead of the whole screen — its windows and
                         its audio only (see list-apps)
      --region <x,y,w,h> Record a rectangle of the main display (display points, top-left
                         origin). Off-screen/empty fails.
      --window <id>      Record one window and nothing else — the capture follows it as it
                         moves (see list-windows). --app, --region and --window are
                         mutually exclusive.
      --mic <id>         Use a specific microphone (see list-mics)
      --no-mic           Record without a microphone
      --no-system-audio  Record without capturing what the Mac is playing
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

/// Parses `--region x,y,w,h` into a display-point rect (top-left origin — docs/02 §1b). The
/// engine clamps/off-screen-checks it; here we only reject a malformed or non-positive spec.
/// Shared by record and replay-arm so the two harnesses can't drift.
func parseRegion(_ value: String?) -> CGRect {
    guard let value else { die("--region needs x,y,w,h, e.g. 40,60,800,500") }
    let fields = value.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard fields.count == 4 else {
        die("--region needs four comma-separated numbers x,y,w,h, e.g. 40,60,800,500")
    }
    let numbers = fields.map { Double($0) }
    guard let x = numbers[0], let y = numbers[1], let w = numbers[2], let h = numbers[3],
          x.isFinite, y.isFinite, w.isFinite, h.isFinite else {
        die("--region values must be numbers, e.g. 40,60,800,500")
    }
    guard w > 0, h > 0 else {
        die("--region needs a positive width and height, e.g. 40,60,800,500 "
            + "(got width \(w), height \(h))")
    }
    // Keep the four values inside the point-space the engine will clamp against, so a stray
    // huge number is a clear usage error rather than a far-off-screen fail at start.
    let limit = 1_000_000.0
    guard abs(x) <= limit, abs(y) <= limit, w <= limit, h <= limit else {
        die("--region values are out of range (max \(Int(limit)) points)")
    }
    return CGRect(x: x, y: y, width: w, height: h)
}

/// Parses `--window <id>` into an `SCWindow.windowID`. `UInt32` rejects negatives and overflow;
/// 0 is never a real window. Shared by record and replay-arm so the two harnesses can't drift.
func parseWindowID(_ value: String?) -> CGWindowID {
    guard let value, let parsed = UInt32(value), parsed > 0 else {
        die("--window needs a window number (see list-windows)")
    }
    return CGWindowID(parsed)
}

/// Builds the capture content from the mutually-exclusive source flags: a window, or a region or
/// an app on the main display, else the whole main screen. The caller rejects combinations.
func contentSelection(appBundleID: String?, region: CGRect?, windowID: CGWindowID?) -> ContentSelection {
    // The CLI lists and binds in one breath, so there is no stale-pick hazard to guard
    // against — the owner check exists for picks restored from disk (docs/02 §1c).
    if let windowID { return .window(id: windowID, ownerBundleID: nil) }
    if let region { return .region(display: .main, rect: region) }
    if let appBundleID { return .app(bundleID: appBundleID) }
    return .display(.main)
}

/// Rejects two source flags given together — one message shape for all three pairs.
func rejectConflictingSources(appBundleID: String?, region: CGRect?, windowID: CGWindowID?) {
    if windowID != nil, appBundleID != nil {
        die("--window and --app can't be combined "
            + "(a window captures one window; an app captures all of its windows)")
    }
    if windowID != nil, region != nil {
        die("--window and --region can't be combined "
            + "(a window captures one window; a region captures a rectangle of the screen)")
    }
    if region != nil, appBundleID != nil {
        die("--region and --app can't be combined "
            + "(a region captures the screen; an app captures its windows)")
    }
}

/// Formats a coordinate without a trailing `.0` for whole values.
func pointValue(_ value: CGFloat) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

/// Human-readable "x,y w×h pt" for the CLI's region echo/dry-run.
func describeRegion(_ rect: CGRect) -> String {
    "\(pointValue(rect.origin.x)),\(pointValue(rect.origin.y)) "
        + "\(pointValue(rect.width))×\(pointValue(rect.height)) pt"
}

/// "920×436 pt" — a window's point size, the column in `list-windows` and part of its echo.
func describeSize(_ size: CGSize) -> String {
    "\(pointValue(size.width))×\(pointValue(size.height)) pt"
}

/// `37 — Finder “Movies” (920×436 pt)` for the CLI's window echo/dry-run, or the bare id when it
/// can't be resolved — the engine reports a gone window properly at start.
func describeWindow(_ id: CGWindowID) async -> String {
    guard let window = try? await CapturableWindows.available().first(where: { $0.id == id }) else {
        return String(id)
    }
    return "\(id) — \(window.appName) “\(window.title)” (\(describeSize(window.pointSize)))"
}

/// Trims a window title so one long title can't break `list-windows`' columns.
func truncated(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    return text.prefix(limit - 1) + "…"
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
    case .appQuit: return "appQuit"
    case .windowClosed: return "windowClosed"
    case .diskAlmostFull: return "diskAlmostFull"
    case .streamError(let message): return "streamError(\(message))"
    }
}

func describe(_ event: EngineEvent) -> String {
    switch event {
    case .started: return "started"
    case .paused: return "paused"
    case .resumed: return "resumed"
    case .microphoneLost: return "microphoneLost"
    case .microphoneRecovered: return "microphoneRecovered"
    case .microphoneSilent: return "microphoneSilent"
    case .microphoneAudible: return "microphoneAudible"
    case .microphoneDroppedAtStart: return "microphoneDroppedAtStart"
    case .recordingFileRestored: return "recordingFileRestored"
    case .stopped(let reason): return "stopped(\(describe(reason)))"
    case .finished(let url, let reason, let dropped):
        return "finished(\(url.lastPathComponent), \(describe(reason)), dropped \(dropped))"
    case .discarded: return "discarded"
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

    let engine = CaptureEngine(configuration: CaptureConfiguration(), purpose: .diagnostic)
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

func listApps() async {
    let apps: [CapturableApp]
    do {
        apps = try await CapturableApps.available()
    } catch {
        die("Couldn't list apps: \(error.localizedDescription)", code: 1)
    }
    guard !apps.isEmpty else {
        print("No capturable apps found.")
        return
    }
    let idWidth = apps.map(\.bundleID.count).max() ?? 0
    for app in apps {
        print("\(app.bundleID.padding(toLength: idWidth, withPad: " ", startingAt: 0))  \(app.name)")
    }
}

func listWindows() async {
    let windows: [CapturableWindow]
    do {
        windows = try await CapturableWindows.available()
    } catch {
        die("Couldn't list windows: \(error.localizedDescription)", code: 1)
    }
    guard !windows.isEmpty else {
        print("No capturable windows found.")
        return
    }
    // App and title get their own columns rather than "App — Title": real titles contain em
    // dashes, so a separator that appears inside the data isn't one.
    let titles = windows.map { truncated($0.title, to: 44) }
    let idWidth = windows.map { String($0.id).count }.max() ?? 0
    let appWidth = windows.map(\.appName.count).max() ?? 0
    let titleWidth = titles.map(\.count).max() ?? 0
    for (window, title) in zip(windows, titles) {
        let id = String(window.id).padding(toLength: idWidth, withPad: " ", startingAt: 0)
        let app = window.appName.padding(toLength: appWidth, withPad: " ", startingAt: 0)
        print("\(id)  \(app)  \(title.padding(toLength: titleWidth, withPad: " ", startingAt: 0))"
            + "  \(describeSize(window.pointSize))")
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
    var appBundleID: String?
    var region: CGRect?
    var windowID: CGWindowID?
    var micID: String?
    var micEnabled = true
    var systemAudioEnabled = true
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
        case "--app":
            guard let value = iterator.next() else { die("--app needs a bundle id (see list-apps)") }
            options.appBundleID = value
        case "--region":
            options.region = parseRegion(iterator.next())
        case "--window":
            options.windowID = parseWindowID(iterator.next())
        case "--mic":
            guard let value = iterator.next() else { die("--mic needs a device id") }
            options.micID = value
        case "--no-mic":
            options.micEnabled = false
        case "--no-system-audio":
            options.systemAudioEnabled = false
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
    rejectConflictingSources(
        appBundleID: options.appBundleID, region: options.region, windowID: options.windowID)
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

/// Microphone selection + recovery policy, plus the reason when a mic was requested but none
/// is usable. Shared by record (dry-run and real capture) and replay-arm so they can't
/// disagree. Policy (M8-T2): an explicit --mic recovers only onto itself; a resolved default
/// follows whatever is default at return time.
func resolveMicrophone(
    micEnabled: Bool, preferredID: String?
) -> (selection: MicrophoneSelection, recovery: MicrophoneRecovery, unavailable: String?) {
    let recovery: MicrophoneRecovery = preferredID != nil ? .sameDevice : .systemDefault
    guard micEnabled else { return (.none, recovery, nil) }
    switch Permissions.resolvedMicrophoneID(preferred: preferredID) {
    case .explicit(let id): return (.device(id: id), recovery, nil)
    case .noDevice(let reason): return (.none, recovery, reason)
    }
}

func printRecordDryRun(_ options: RecordOptions) async {
    print("Recording configuration (dry-run — no capture):")
    print("  Screen recording permission: \(describe(Permissions.screenRecordingState()))")
    print("  Preset:   \(options.preset.rawValue)")
    let captureDescription: String
    if let windowID = options.windowID {
        captureDescription = "window \(await describeWindow(windowID))"
    } else if let region = options.region {
        captureDescription = "region \(describeRegion(region)) on the main display"
    } else if let bundleID = options.appBundleID {
        captureDescription = "app \(bundleID)"
    } else {
        captureDescription = "entire screen"
    }
    print("  Capture:  \(captureDescription)")
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
    print("  System audio: \(options.systemAudioEnabled ? "on" : "off (--no-system-audio)")")

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


/// In-place progress line, refreshed twice a second. `recordedDuration` is NaN before the first
/// frame (docs/02 §10), so the duration is guarded.
func runProgressTicker(_ session: RecordingSession, outputURL: URL) async {
    while !Task.isCancelled {
        let raw = session.recordedDuration.seconds
        let seconds = raw.isFinite ? raw : 0
        let size = ByteCountFormatter.string(
            fromByteCount: OutputLocation.currentFileSize(for: outputURL), countStyle: .file)
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
    let content = contentSelection(
        appBundleID: options.appBundleID, region: options.region, windowID: options.windowID)
    let configuration = CaptureConfiguration(
        content: content, microphone: mic.selection,
        microphoneRecovery: mic.recovery, capturesSystemAudio: options.systemAudioEnabled,
        quality: options.preset)
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
    if let bundleID = options.appBundleID { print("  capturing app: \(bundleID)") }
    if let region = options.region { print("  capturing region: \(describeRegion(region)) on the main display") }
    if let windowID = options.windowID { print("  capturing window: \(await describeWindow(windowID))") }

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
            // Not a stop: screen + system audio keep recording (ADR-012); the rescue may
            // resume the mic track (M8-T2).
            print("\n  ⚠️  microphone disconnected — still recording (screen + system audio)")
        case .microphoneRecovered:
            print("\n  🎤 microphone reconnected — mic track resumed")
        case .microphoneSilent:
            // Connected and delivering, but carrying nothing (M16-T4) — muted, gain at zero, or
            // the wrong input. Still recording; this is a notice.
            print("\n  ⚠️  microphone is silent — still recording (check that it isn't muted)")
        case .microphoneAudible:
            print("\n  🎤 microphone is picking up sound again")
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
        await printRecordDryRun(options)
    } else {
        await performRecording(options)
    }
case "list-mics", "--list-mics":
    listMics()
case "list-apps":
    await listApps()
case "list-windows":
    await listWindows()
case "engine-smoke":
    await runEngineSmoke(Array(arguments.dropFirst()))
case "probe-stream":
    await runProbeStream(Array(arguments.dropFirst()))
case "replay-arm":
    await runReplayArm(Array(arguments.dropFirst()))
case "export":
    await runExport(Array(arguments.dropFirst()))
case "trim":
    await runTrim(Array(arguments.dropFirst()))
case "-h", "--help":
    printUsage()
default:
    die("Unknown command: \(command)")
}

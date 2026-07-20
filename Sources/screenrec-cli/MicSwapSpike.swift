import AVFoundation
import CoreMedia
import Foundation
import RecorderCore
import ScreenCaptureKit

// Spike: can a live `SCStream` be re-pointed at another microphone via `updateConfiguration`?
// SCK binds the mic once at startCapture and never re-resolves it (02 §4 / ADR-012).
//
// Lives in the CLI, not `tools/`: mic access needs the `NSMicrophoneUsageDescription` embedded in
// this binary — a bare `swift tools/x.swift` is killed on first mic access (02 §2).

/// Tallies mic buffer formats and tracks mic silence. Thread-safe — SCK delivers on its own queues.
private final class MicFormatProbe: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var order: [String] = []
    private var lastBufferAt: TimeInterval?
    private var streamError: String?
    private var screenCount = 0
    private var systemAudioCount = 0
    // Latest host-clock PTS seen per output (seconds) — for the two-stream coherence spike.
    private var latestScreenPTS: Double?
    private var latestSystemAudioPTS: Double?
    private var latestMicPTS: Double?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        switch type {
        case .screen:
            lock.lock(); screenCount += 1; if pts.isFinite { latestScreenPTS = pts }; lock.unlock()
            return
        case .audio:
            lock.lock(); systemAudioCount += 1; if pts.isFinite { latestSystemAudioPTS = pts }; lock.unlock()
            return
        default:
            break
        }
        guard type == .microphone,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return }
        let key = "\(Int(asbd.mSampleRate))Hz/\(asbd.mChannelsPerFrame)ch"
        lock.lock()
        if counts[key] == nil { order.append(key) }
        counts[key, default: 0] += 1
        lastBufferAt = ProcessInfo.processInfo.systemUptime
        if pts.isFinite { latestMicPTS = pts }
        lock.unlock()
    }

    /// The most recent video / system-audio / mic host-clock PTS (seconds), for cross-stream drift.
    var latestPTS: (screen: Double?, systemAudio: Double?, mic: Double?) {
        lock.lock(); defer { lock.unlock() }
        return (latestScreenPTS, latestSystemAudioPTS, latestMicPTS)
    }

    /// Non-mic buffer tallies — used to show a co-running stream stays healthy.
    var otherCounts: (screen: Int, systemAudio: Int) {
        lock.lock(); defer { lock.unlock() }
        return (screenCount, systemAudioCount)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); streamError = error.localizedDescription; lock.unlock()
    }

    /// Mic formats seen since the last `reset()`, in first-seen order, with buffer counts.
    func snapshot() -> (formats: [(format: String, count: Int)], error: String?) {
        lock.lock(); defer { lock.unlock() }
        return (order.map { ($0, counts[$0] ?? 0) }, streamError)
    }

    /// Seconds since the last mic buffer; nil if none has ever arrived.
    var quietFor: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        guard let last = lastBufferAt else { return nil }
        return ProcessInfo.processInfo.systemUptime - last
    }

    /// Clears format tallies. `lastBufferAt` survives — silence tracking spans phases.
    func reset() {
        lock.lock(); counts = [:]; order = []; lock.unlock()
    }
}

private func summarize(_ formats: [(format: String, count: Int)]) -> String {
    formats.isEmpty ? "NONE (no mic buffers at all)"
        : formats.map { "\($0.format) ×\($0.count)" }.joined(separator: ", ")
}

/// Mirrors CaptureEngine's audio setup so findings generalize; only the video geometry is shrunk.
/// Shared by every leg, so their verdicts stay comparable. `micID: nil` leaves
/// `microphoneCaptureDeviceID` unset — Apple's "the default microphone".
private func spikeConfiguration(micID: String? = nil) -> SCStreamConfiguration {
    let config = SCStreamConfiguration()
    config.width = 640
    config.height = 360
    config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
    config.queueDepth = 5
    config.showsCursor = true
    config.capturesAudio = true
    config.sampleRate = 48_000
    config.channelCount = 2
    config.excludesCurrentProcessAudio = true
    config.captureMicrophone = true
    if let micID { config.microphoneCaptureDeviceID = micID }
    return config
}

/// The display every leg captures.
private func firstSpikeDisplay() async -> SCDisplay {
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
        die("SCShareableContent failed: \(error.localizedDescription)", code: 74)
    }
    guard let display = content.displays.first else { die("no displays available", code: 74) }
    return display
}

/// Attaches the probe to the outputs every mic leg needs.
private func attachMicOutputs(_ stream: SCStream, probe: MicFormatProbe) throws {
    try stream.addStreamOutput(probe, type: .screen, sampleHandlerQueue: DispatchQueue(label: "spike.screen"))
    try stream.addStreamOutput(probe, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "spike.mic"))
}

private func startSpikeStream(micID: String, probe: MicFormatProbe) async -> SCStream {
    let display = await firstSpikeDisplay()
    let stream = SCStream(
        filter: SCContentFilter(display: display, excludingWindows: []),
        configuration: spikeConfiguration(micID: micID),
        delegate: probe)
    do {
        try attachMicOutputs(stream, probe: probe)
        try await stream.startCapture()
    } catch {
        die("startCapture failed: \(error.localizedDescription)", code: 74)
    }
    return stream
}

/// Polls until the mic has been quiet for `quiet` seconds. False if it never goes quiet.
private func waitForMicSilence(_ probe: MicFormatProbe, quiet: TimeInterval, giveUpAfter: TimeInterval) async -> Bool {
    let start = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - start < giveUpAfter {
        try? await Task.sleep(for: .milliseconds(500))
        if let gap = probe.quietFor, gap >= quiet { return true }
    }
    return false
}

/// Retries `updateConfiguration` at `micID` and reports the mic formats that resume, if any.
/// Legs 2 and 2b share this retry policy so they differ in only one variable.
private func retryRepoint(
    _ stream: SCStream, to micID: String, probe: MicFormatProbe
) async -> [(format: String, count: Int)] {
    probe.reset()
    for attempt in 1...8 {
        do {
            try await stream.updateConfiguration(spikeConfiguration(micID: micID))
            print("    attempt \(attempt): updateConfiguration OK")
        } catch {
            print("    attempt \(attempt): threw — \(error.localizedDescription)")
        }
        try? await Task.sleep(for: .seconds(2))
        let now = probe.snapshot()
        if !now.formats.isEmpty { return now.formats }
    }
    return []
}

/// Which experiment to run.
private enum SpikeMode { case swap, reconnect, fallback, nilDevice, nilFollow, twoStreams, twoStreamsPTS }

func runMicSwapSpike(_ args: [String]) async {
    var seconds = 4.0
    var mode = SpikeMode.swap
    var iterator = args.makeIterator()
    while let arg = iterator.next() {
        switch arg {
        case "--reconnect":
            mode = .reconnect
        case "--fallback":
            mode = .fallback
        case "--nil-device":
            mode = .nilDevice
        case "--nil-follow":
            mode = .nilFollow
        case "--two-streams":
            mode = .twoStreams
        case "--two-streams-pts":
            mode = .twoStreamsPTS
        case "--seconds":
            seconds = parsePositive(iterator.next(), flag: "--seconds")
        default:
            die("Unknown option: \(arg)")
        }
    }
    switch mode {
    case .swap: await runMicDeviceSwapSpike(seconds: seconds)
    case .reconnect: await runMicReconnectSpike()
    case .fallback: await runMicFallbackSpike()
    case .nilDevice: await runNilDeviceSpike(seconds: seconds)
    case .nilFollow: await runNilFollowSpike()
    case .twoStreams: await runTwoStreamSpike(seconds: seconds)
    case .twoStreamsPTS: await runTwoStreamPTSSpike(seconds: seconds)
    }
}

// MARK: - Experiment: does a nil microphoneCaptureDeviceID work on 15.6.1?

/// Retests 02 §1's finding that a nil `microphoneCaptureDeviceID` throws "invalid parameter".
private func runNilDeviceSpike(seconds: Double) async {
    let display = await firstSpikeDisplay()

    let config = spikeConfiguration()
    let probe = MicFormatProbe()
    let stream = SCStream(
        filter: SCContentFilter(display: display, excludingWindows: []),
        configuration: config, delegate: probe)
    print("nil-device spike: captureMicrophone = true, microphoneCaptureDeviceID left nil")
    do {
        try attachMicOutputs(stream, probe: probe)
        try await stream.startCapture()
    } catch {
        print("    startCapture THREW: \(error.localizedDescription)")
        print("")
        print("  VERDICT: 02 §1 still holds — nil is rejected; an explicit device id is mandatory.")
        exit(0)
    }
    try? await Task.sleep(for: .seconds(seconds))
    let seen = probe.snapshot()
    try? await stream.stopCapture()
    print("    mic formats: \(summarize(seen.formats))")
    print("")
    if seen.formats.isEmpty {
        print("  VERDICT: PARTIAL — nil is accepted but delivers no mic buffers. Useless; 02 §1 stands.")
    } else {
        print("  VERDICT: CHANGED — nil is accepted AND delivers! 02 §1's 'nil throws' no longer holds")
        print("  on this OS. Worth testing whether it FOLLOWS the system default when a device dies —")
        print("  that would make fallback automatic.")
    }
    exit(0)
}

// MARK: - Experiment: does a nil device FOLLOW the system default as it changes?

/// Does `microphoneCaptureDeviceID = nil` follow the system default as it changes, or resolve it
/// once at `startCapture`? macOS repoints its default to the built-in when AirPods vanish.
private func runNilFollowSpike() async {
    let display = await firstSpikeDisplay()

    let probe = MicFormatProbe()
    let stream = SCStream(
        filter: SCContentFilter(display: display, excludingWindows: []),
        configuration: spikeConfiguration(), delegate: probe)
    do {
        try attachMicOutputs(stream, probe: probe)
        try await stream.startCapture()
    } catch {
        die("startCapture failed: \(error.localizedDescription)", code: 74)
    }

    print("nil-follow spike: does microphoneCaptureDeviceID = nil FOLLOW the system default,")
    print("or just resolve it once at startCapture?")
    try? await Task.sleep(for: .seconds(3))
    let initial = probe.snapshot()
    print("    starting mic: \(summarize(initial.formats))   (expect 24000Hz = AirPods)")
    guard let startFormat = initial.formats.first?.format else {
        try? await stream.stopCapture()
        die("no mic buffers at all — are the AirPods connected and the default input?", code: 74)
    }
    guard startFormat.hasPrefix("24000") else {
        try? await stream.stopCapture()
        die("expected AirPods (24000Hz) as the default input, got \(startFormat). Connect AirPods first.", code: 74)
    }

    print("")
    print("  >>> PUT THE AIRPODS IN THE CASE AND *CLOSE THE LID* <<<")
    print("      (an open case keeps them connected — the lid is what disconnects them)")
    print("      Watching up to 60s for EITHER outcome, rather than assuming a duration:")
    print("        · a non-24kHz format appears  → nil FOLLOWED the default")
    print("        · the mic goes quiet for 3s   → nil pinned, and the device is simply gone")
    probe.reset()
    enum Outcome { case followed([(format: String, count: Int)]), died, timedOut }
    var outcome = Outcome.timedOut
    for tick in 1...120 {
        try? await Task.sleep(for: .milliseconds(500))
        let now = probe.snapshot()
        if let switched = now.formats.first(where: { !$0.format.hasPrefix("24000") }) {
            print("    t+\(tick / 2)s: FOLLOWED → \(switched.format)")
            outcome = .followed(now.formats)
            break
        }
        // `reset()` deliberately keeps the heartbeat, so silence is measured across it.
        if let quiet = probe.quietFor, quiet >= 3 {
            print("    t+\(tick / 2)s: mic went quiet (no follow)")
            outcome = .died
            break
        }
        if tick % 20 == 0 { print("    t+\(tick / 2)s: still \(summarize(now.formats))") }
    }
    let final = probe.snapshot()
    try? await stream.stopCapture()
    if let error = final.error { print("    stream error: \(error)") }

    print("")
    switch outcome {
    case .followed(let formats):
        print("  VERDICT: YES — nil FOLLOWS the system default (\(summarize(formats))). A dying mic")
        print("  falls back to the built-in for free: no watchdog trigger, no re-point, no new ADR.")
        print("  But the format changes under us (24k → 48k), so it still needs the fixed-format input.")
    case .died:
        print("  VERDICT: NO — nil resolves the default ONCE at startCapture and pins it, exactly")
        print("  like naming the device: the mic simply died rather than following to the built-in.")
        print("  nil buys nothing for recovery; rebuild-the-mic-stream is the only route left.")
    case .timedOut:
        print("  VERDICT: INCONCLUSIVE — the AirPods never disconnected within 60s, so the event")
        print("  under test never happened. Close the case LID and re-run; an open case keeps them")
        print("  connected. (Do not read this as a NO.)")
    }
    print("  (record in docs/02 §1 + §4 + STATUS either way)")
    exit(0)
}

// MARK: - Experiment: can a mic-only stream coexist with the recording stream?

/// Mic-path poisoning is per-stream, so rebuilding a mic-only stream is a candidate recovery.
/// Checks the precondition: can two SCStreams run at once and both deliver?
private func runTwoStreamSpike(seconds: Double) async {
    let devices = AudioInputs.available()
    guard let mic = devices.first(where: { $0.isDefault }) ?? devices.first else {
        die("no input devices", code: 74)
    }

    let display = await firstSpikeDisplay()
    let filter = SCContentFilter(display: display, excludingWindows: [])

    // Stream A — the "real recording": screen + system audio, no mic. Must stay untouched.
    let configA = SCStreamConfiguration()
    configA.width = 640
    configA.height = 360
    configA.minimumFrameInterval = CMTime(value: 1, timescale: 10)
    configA.queueDepth = 5
    configA.capturesAudio = true
    configA.sampleRate = 48_000
    configA.channelCount = 2
    configA.excludesCurrentProcessAudio = true

    let probeA = MicFormatProbe()
    let streamA = SCStream(filter: filter, configuration: configA, delegate: probeA)

    // Stream B — mic only. A filter is required regardless, so keep it minimal and add no
    // .screen output.
    let probeB = MicFormatProbe()
    let streamB = SCStream(filter: filter, configuration: spikeConfiguration(micID: mic.uniqueID), delegate: probeB)

    print("two-stream spike: can a mic-only SCStream run alongside the recording stream?")
    print("  stream A: screen + system audio (no mic)")
    print("  stream B: microphone only — \(mic.name)")
    do {
        try streamA.addStreamOutput(probeA, type: .screen, sampleHandlerQueue: DispatchQueue(label: "spike.a.screen"))
        try streamA.addStreamOutput(probeA, type: .audio, sampleHandlerQueue: DispatchQueue(label: "spike.a.audio"))
        try await streamA.startCapture()
        print("    stream A: started")
    } catch {
        die("stream A startCapture failed: \(error.localizedDescription)", code: 74)
    }
    do {
        try streamB.addStreamOutput(probeB, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "spike.b.mic"))
        try await streamB.startCapture()
        print("    stream B: started")
    } catch {
        try? await streamA.stopCapture()
        print("    stream B startCapture THREW: \(error.localizedDescription)")
        print("")
        print("  VERDICT: NO — a second concurrent SCStream is rejected. Rebuild-the-mic-stream is dead.")
        exit(0)
    }

    try? await Task.sleep(for: .seconds(seconds))
    let a = probeA.otherCounts
    let b = probeB.snapshot()
    let aError = probeA.snapshot().error
    try? await streamB.stopCapture()
    try? await streamA.stopCapture()

    print("    stream A delivered: screen ×\(a.screen), system audio ×\(a.systemAudio)")
    print("    stream B delivered: \(summarize(b.formats))")
    if let aError { print("    stream A error: \(aError)") }
    if let bError = b.error { print("    stream B error: \(bError)") }

    print("")
    if a.screen > 0 && a.systemAudio > 0 && !b.formats.isEmpty {
        print("  VERDICT: YES — both streams delivered concurrently. A mic-only stream is viable,")
        print("  so a dead mic could be recovered by REBUILDING stream B (a fresh stream binds a")
        print("  previously-died device — leg 1 proved that) while the recording stream never blinks.")
    } else {
        print("  VERDICT: NO — concurrent streams don't both deliver (A screen ×\(a.screen)/audio ×\(a.systemAudio),")
        print("  B mic \(b.formats.isEmpty ? "none" : "ok")). Rebuild-the-mic-stream is not viable.")
    }
    exit(0)
}

/// Slope of a linear fit y = a + b·t (least squares); `b` is the drift rate. nil if degenerate.
private func driftSlope(_ points: [(t: Double, y: Double)]) -> Double? {
    let n = Double(points.count)
    guard n >= 2 else { return nil }
    let sumT = points.reduce(0) { $0 + $1.t }
    let sumY = points.reduce(0) { $0 + $1.y }
    let sumTT = points.reduce(0) { $0 + $1.t * $1.t }
    let sumTY = points.reduce(0) { $0 + $1.t * $1.y }
    let denom = n * sumTT - sumT * sumT
    guard abs(denom) > 1e-9 else { return nil }
    return (n * sumTY - sumT * sumY) / denom
}

/// Route 2 gate (M6-T4): does a mic-only 2nd `SCStream` (B) stay time-coherent with the recording
/// stream (A)? Both carry host-clock PTS on macOS 15 (docs/02 §5) — this measures the drift of
/// (A's PTS − B's mic PTS) across two SEPARATE streams over the run. Slope ≈ 0 ⇒ coherent, so a
/// mic can be rebuilt on reconnect without disturbing the replay buffer (ADR-001's concern settled).
private func runTwoStreamPTSSpike(seconds: Double) async {
    let devices = AudioInputs.available()
    guard let mic = devices.first(where: { $0.isDefault }) ?? devices.first else {
        die("no input devices", code: 74)
    }
    let display = await firstSpikeDisplay()
    let filter = SCContentFilter(display: display, excludingWindows: [])

    let configA = SCStreamConfiguration()
    configA.width = 640; configA.height = 360
    configA.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    configA.queueDepth = 6
    configA.capturesAudio = true
    configA.sampleRate = 48_000; configA.channelCount = 2
    configA.excludesCurrentProcessAudio = true

    let probeA = MicFormatProbe()
    let streamA = SCStream(filter: filter, configuration: configA, delegate: probeA)
    let probeB = MicFormatProbe()
    let streamB = SCStream(filter: filter, configuration: spikeConfiguration(micID: mic.uniqueID), delegate: probeB)

    print("two-stream PTS-coherence spike (Route 2 gate): mic-only stream B vs recording stream A")
    print("  mic: \(mic.name)  ·  sampling every 5 s for \(Int(seconds)) s")
    do {
        try streamA.addStreamOutput(probeA, type: .screen, sampleHandlerQueue: DispatchQueue(label: "pts.a.screen"))
        try streamA.addStreamOutput(probeA, type: .audio, sampleHandlerQueue: DispatchQueue(label: "pts.a.audio"))
        try await streamA.startCapture()
        try streamB.addStreamOutput(probeB, type: .microphone, sampleHandlerQueue: DispatchQueue(label: "pts.b.mic"))
        try await streamB.startCapture()
    } catch {
        die("startCapture failed: \(error.localizedDescription)", code: 74)
    }

    // delta = (stream A PTS) − (stream B mic PTS). Video is frame-on-change (jittery on a static
    // screen); system audio is continuous, so it's the cleaner measure. Track both.
    var audioVsMic: [(t: Double, y: Double)] = []
    var videoVsMic: [(t: Double, y: Double)] = []
    let start = ProcessInfo.processInfo.systemUptime
    while ProcessInfo.processInfo.systemUptime - start < seconds {
        try? await Task.sleep(for: .seconds(5))
        let t = ProcessInfo.processInfo.systemUptime - start
        let a = probeA.latestPTS, b = probeB.latestPTS
        guard let micPTS = b.mic else { continue }
        if let sa = a.systemAudio { audioVsMic.append((t, sa - micPTS)) }
        if let sc = a.screen { videoVsMic.append((t, sc - micPTS)) }
        let saStr = a.systemAudio.map { String(format: "%+.4f", $0 - micPTS) } ?? "  —   "
        let scStr = a.screen.map { String(format: "%+.4f", $0 - micPTS) } ?? "  —   "
        print(String(format: "  t=%5.0fs  sysAudio−mic=%@s  video−mic=%@s", t, saStr, scStr))
    }
    try? await streamB.stopCapture()
    try? await streamA.stopCapture()

    print("")
    guard let audioSlope = driftSlope(audioVsMic) else {
        print("  VERDICT: INCONCLUSIVE — too few paired samples (a stream didn't deliver).")
        exit(0)
    }
    print(String(format: "  sysAudio↔mic drift: %+.6f s/s  (%+.1f ms/min)  over %d samples",
                 audioSlope, audioSlope * 60_000, audioVsMic.count))
    if let videoSlope = driftSlope(videoVsMic) {
        print(String(format: "  video↔mic    drift: %+.6f s/s  (%+.1f ms/min)  over %d samples",
                     videoSlope, videoSlope * 60_000, videoVsMic.count))
    }
    print("")
    // Coherent host clocks tick at one rate ⇒ slope ≈ 0. Threshold 0.5 ms/s (30 ms/min) sits well
    // above measurement jitter and well below the drift two unsynced clocks would show.
    if abs(audioSlope) < 0.0005 {
        print("  VERDICT: PASS — the two streams share a coherent host clock (no relative drift).")
        print("  Route 2 is viable: a mic-only 2nd stream stays in sync with the recording stream,")
        print("  so a dead mic can be rebuilt on reconnect without disturbing the replay buffer.")
    } else {
        print("  VERDICT: FAIL — the streams drift apart. Route 2 needs resync/resampling before it's")
        print("  viable; a naive 2nd-stream mux would desync over a long capture.")
    }
    exit(0)
}

// MARK: - Leg 1: swap between two present devices (headless)

private func runMicDeviceSwapSpike(seconds: Double) async {
    let devices = AudioInputs.available()
    guard devices.count >= 2 else {
        die("mic-swap-spike needs two input devices; found \(devices.count). Connect a second mic.")
    }
    // Start on the built-in: the 48 kHz → 24 kHz jump (AirPods) makes a real swap unmistakable.
    let first = devices.first { $0.uniqueID == "BuiltInMicrophoneDevice" } ?? devices[0]
    guard let second = devices.first(where: { $0.uniqueID != first.uniqueID }) else {
        die("couldn't find a second distinct input device")
    }

    let probe = MicFormatProbe()
    let stream = await startSpikeStream(micID: first.uniqueID, probe: probe)

    print("mic-swap spike (M3-T7 leg 1): can updateConfiguration re-point a live stream's mic?")
    print("  phase 1 — capturing with: \(first.name)  [\(first.uniqueID)]")
    try? await Task.sleep(for: .seconds(seconds))
    let before = probe.snapshot()
    print("    mic formats: \(summarize(before.formats))")

    print("  phase 2 — updateConfiguration → \(second.name)  [\(second.uniqueID)]")
    probe.reset()
    var swapThrew: String?
    do {
        try await stream.updateConfiguration(spikeConfiguration(micID: second.uniqueID))
        print("    updateConfiguration: returned OK")
    } catch {
        swapThrew = error.localizedDescription
        print("    updateConfiguration: THREW — \(error.localizedDescription)")
    }
    try? await Task.sleep(for: .seconds(seconds))
    let after = probe.snapshot()
    print("    mic formats after swap: \(summarize(after.formats))")
    try? await stream.stopCapture()
    if let error = after.error ?? before.error { print("    stream error: \(error)") }

    let beforeFormats = Set(before.formats.map(\.format))
    let afterFormats = Set(after.formats.map(\.format))
    print("")
    if swapThrew != nil {
        print("  VERDICT: NO — updateConfiguration rejects a mic device change outright.")
    } else if !afterFormats.isEmpty && !afterFormats.isSubset(of: beforeFormats) {
        print("  VERDICT: YES — buffers switched to the new device's format. Live mic re-point works.")
    } else if afterFormats.isEmpty {
        print("  VERDICT: NO — mic delivery STOPPED after the swap (config accepted, capture dead).")
    } else {
        print("  VERDICT: NO — updateConfiguration accepted but buffers kept the OLD device's format.")
    }
    exit(0)
}

// MARK: - Leg 2: re-bind a device that died and came back (needs a human)

private func runMicReconnectSpike() async {
    let devices = AudioInputs.available()
    guard let target = devices.first(where: { $0.uniqueID != "BuiltInMicrophoneDevice" }) else {
        die("--reconnect needs a removable mic (e.g. AirPods) connected; only the built-in is present.")
    }

    let probe = MicFormatProbe()
    let stream = await startSpikeStream(micID: target.uniqueID, probe: probe)

    print("mic-reconnect spike (M3-T7 leg 2): can a device that DIED and came back be re-bound?")
    print("  capturing with: \(target.name)  [\(target.uniqueID)]")
    try? await Task.sleep(for: .seconds(3))
    let initial = probe.snapshot()
    print("    mic alive: \(summarize(initial.formats))")
    guard !initial.formats.isEmpty else {
        try? await stream.stopCapture()
        die("no mic buffers at all — is \(target.name) really the active mic?", code: 74)
    }

    print("")
    print("  >>> PUT THE AIRPODS IN THE CASE NOW <<<   (waiting up to 45s for the mic to die)")
    guard await waitForMicSilence(probe, quiet: 3, giveUpAfter: 45) else {
        try? await stream.stopCapture()
        die("the mic never went quiet — were they cased?", code: 74)
    }
    print("    ✓ mic went quiet")

    // Phase A: passive — confirm a returning device delivers nothing on its own, so any resume
    // in phase B is unambiguously due to the re-point.
    print("")
    print("  >>> TAKE THE AIRPODS BACK OUT NOW <<<")
    print("  phase A — watching 12s WITHOUT re-pointing (expect: nothing, per 02 §4)…")
    probe.reset()
    try? await Task.sleep(for: .seconds(12))
    let passive = probe.snapshot()
    print("    passive resume: \(summarize(passive.formats))")

    // Phase B: active. Same device id — SCK may re-resolve it to the new CoreAudio object.
    print("  phase B — retrying updateConfiguration with the SAME device id every 2s…")
    let resumed = await retryRepoint(stream, to: target.uniqueID, probe: probe)
    try? await stream.stopCapture()

    print("")
    if !passive.formats.isEmpty {
        print("  VERDICT: the mic resumed on its OWN (\(summarize(passive.formats))) — 02 §4's")
        print("  'a lost mic never returns' finding needs revisiting; re-point wasn't even needed.")
    } else if !resumed.isEmpty {
        print("  VERDICT: YES — re-pointing at the SAME device id revived it: \(summarize(resumed)).")
        print("  Reconnect-recovery is viable, and needs no resampling (same device, same format).")
    } else {
        print("  VERDICT: NO — a device that died stays dead for the stream's life, even when it")
        print("  comes back and even with an explicit updateConfiguration. ADR-012 stands as-is.")
    }
    print("  (record in docs/02 §4 + STATUS either way — M3-T7's deliverable is the finding)")
    exit(0)
}

// MARK: - Leg 2b: re-point to a device that never died, after the current one dies

/// Re-points a dead stream at a device that never died — separates "the target is poisoned" from
/// "the stream's mic path is torn down".
private func runMicFallbackSpike() async {
    let devices = AudioInputs.available()
    guard let target = devices.first(where: { $0.uniqueID != "BuiltInMicrophoneDevice" }) else {
        die("--fallback needs a removable mic (e.g. AirPods) connected as the starting device.")
    }
    guard let fallback = devices.first(where: { $0.uniqueID == "BuiltInMicrophoneDevice" }) else {
        die("--fallback needs the built-in microphone present as the fallback target.")
    }

    let probe = MicFormatProbe()
    let stream = await startSpikeStream(micID: target.uniqueID, probe: probe)

    print("mic-fallback spike (M3-T7 leg 2b): once the mic dies, can the stream be re-pointed")
    print("at a device that NEVER died? This decides whether mic recovery is possible at all.")
    print("  capturing with: \(target.name)  [\(target.uniqueID)]")
    try? await Task.sleep(for: .seconds(3))
    let initial = probe.snapshot()
    print("    mic alive: \(summarize(initial.formats))")
    guard !initial.formats.isEmpty else {
        try? await stream.stopCapture()
        die("no mic buffers at all — is \(target.name) really the active mic?", code: 74)
    }

    print("")
    print("  >>> PUT THE AIRPODS IN THE CASE NOW — and LEAVE them in <<<")
    print("      (waiting up to 45s for the mic to die)")
    guard await waitForMicSilence(probe, quiet: 3, giveUpAfter: 45) else {
        try? await stream.stopCapture()
        die("the mic never went quiet — were they cased?", code: 74)
    }
    print("    ✓ mic went quiet")

    print("")
    print("  re-pointing to \(fallback.name) [\(fallback.uniqueID)] — alive the whole time…")
    let resumed = await retryRepoint(stream, to: fallback.uniqueID, probe: probe)
    let final = probe.snapshot()
    try? await stream.stopCapture()
    if let error = final.error { print("    stream error: \(error)") }

    print("")
    if !resumed.isEmpty {
        print("  VERDICT: YES — a dead mic path CAN be revived by re-pointing at a live device:")
        print("  \(summarize(resumed)). 'AirPods die → keep recording on the built-in' is possible,")
        print("  which reopens ADR-012. Cost: the new device's format differs (48k vs the input's")
        print("  24k), so it needs the fixed-format resampled mic input first.")
    } else {
        print("  VERDICT: NO — the stream's mic path is torn down for good when its device dies;")
        print("  not even a device that never died can be bound to it. No mic recovery is possible")
        print("  for a running stream, so ADR-012's notify-and-continue is FINAL for v1 and the")
        print("  resampling question closes with it.")
    }
    print("  (record in docs/02 §4 + STATUS either way)")
    exit(0)
}

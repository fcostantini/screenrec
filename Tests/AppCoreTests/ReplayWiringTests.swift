import Foundation
import Testing

@testable import AppCore
import RecorderCore

/// AppState → ReplayControlling transition wiring, with a spy — the real controller spins live
/// capture engines, which is `replay-arm`'s job to verify, not a unit test's.
@MainActor
@Suite struct ReplayWiringTests {

    final class ReplaySpy: ReplayControlling {
        var onMicrophoneLost: (@MainActor () -> Void)?
        var onMicrophoneRecovered: (@MainActor () -> Void)?
        var onPipelineFailure: (@MainActor (String) -> Void)?

        enum Call: Equatable {
            case arm, disarm, recordingStarted, recordingEnded, configurationChanged,
                 windowChanged, setOutputDirectory
        }
        var calls: [Call] = []
        var lastConfiguration: CaptureConfiguration?
        var lastSeconds: Double?
        var lastOutputDirectory: URL?
        /// What the next requestSave completes with, synchronously; nil ⇒ swallow.
        var saveResult: Result<ReplayMuxer.SavedReplay, Error>?

        func arm(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL) {
            calls.append(.arm)
            (lastConfiguration, lastSeconds, lastOutputDirectory) = (configuration, seconds, outputDirectory)
        }
        func disarm() { calls.append(.disarm) }
        func recordingStarted(
            router: SampleRouter, configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL
        ) {
            calls.append(.recordingStarted)
        }
        func recordingEnded(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL) {
            calls.append(.recordingEnded)
        }
        func configurationChanged(configuration: CaptureConfiguration, seconds: Double, outputDirectory: URL) {
            calls.append(.configurationChanged)
            (lastConfiguration, lastSeconds) = (configuration, seconds)
        }
        func windowChanged(seconds: Double) {
            calls.append(.windowChanged)
            lastSeconds = seconds
        }
        func setOutputDirectory(_ url: URL) {
            calls.append(.setOutputDirectory)
            lastOutputDirectory = url
        }
        @discardableResult
        func requestSave(
            completion: @escaping @Sendable (Result<ReplayMuxer.SavedReplay, Error>) -> Void
        ) -> Bool {
            if let saveResult { completion(saveResult) }
            return true
        }
    }

    private func makeState() -> (AppState, ReplaySpy, UserDefaults) {
        // Invariant: a fresh UUID suite name is always a valid, unused domain.
        let defaults = UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!
        let spy = ReplaySpy()
        return (AppState(defaults: defaults, replayController: spy), spy, defaults)
    }

    @Test func armingCallsTheControllerWithTheCurrentPicksAndPersists() {
        let (state, spy, defaults) = makeState()
        state.quality = .high
        state.isReplayArmed = true

        #expect(spy.calls == [.arm])
        #expect(spy.lastConfiguration?.quality == .high)
        #expect(spy.lastSeconds == 60)
        #expect(defaults.bool(forKey: "replayArmed"))

        state.isReplayArmed = false
        #expect(spy.calls == [.arm, .disarm])
        #expect(!defaults.bool(forKey: "replayArmed"))
    }

    @Test func launchNeverArmsByItselfActivateDoes() {
        let defaults = UserDefaults(suiteName: "screenrec-tests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "replayArmed")
        let spy = ReplaySpy()
        let state = AppState(defaults: defaults, replayController: spy)

        // `init` must not spin capture — tests (and the app before its first render) construct
        // AppState freely. The app opts in explicitly at launch.
        #expect(state.isReplayArmed)
        #expect(spy.calls.isEmpty)

        state.activateReplayIfArmed()
        #expect(spy.calls == [.arm])
    }

    @Test func sourceAndQualityChangesRestartTheArmedStream() {
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.calls = []

        state.microphonePreference = .device(id: "some-mic")
        state.quality = .efficient
        state.frameRateCap = 30
        #expect(spy.calls == Array(repeating: .configurationChanged, count: 3))
        // The restart must carry the *current* window — a stale seconds here silently rebuilds
        // the armed buffer at the wrong length.
        #expect(spy.lastSeconds == 60)
    }

    @Test func aSourceSwitchRestartsTheArmedStreamExactlyOnce() {
        // App → different display writes TWO backing properties; unbatched, each didSet would
        // rebuild the armed stream (wiping the buffer, the first against a config that exists
        // for a microsecond). The `sourceChoice` setter batches them into one restart (M7-T2).
        let (state, spy, _) = makeState()
        state.selectedDisplayID = 1
        state.isReplayArmed = true
        spy.calls = []

        state.sourceChoice = .app(bundleID: "com.example.app")
        #expect(spy.calls == [.configurationChanged])

        spy.calls = []
        state.sourceChoice = .display(2)
        #expect(spy.calls == [.configurationChanged])
    }

    @Test func aRegionSwitchRestartsTheArmedStreamExactlyOnce() {
        // A region pick writes two backing properties (clear app, set region); the `sourceChoice`
        // setter batches them into one armed-stream rebuild, like the app/display switch (M11-T2).
        let (state, spy, _) = makeState()
        state.selectedAppBundleID = "com.example.app"
        state.isReplayArmed = true
        spy.calls = []

        state.sourceChoice = .region(display: nil, rect: CGRect(x: 40, y: 60, width: 800, height: 500))
        #expect(spy.calls == [.configurationChanged])
        #expect(spy.lastConfiguration?.content
            == .region(display: .main, rect: CGRect(x: 40, y: 60, width: 800, height: 500)))
    }

    @Test func windowChangesResizeInPlaceInsteadOfRestarting() {
        // A length change must never take the rebuild path — that wipes the buffer.
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.calls = []

        state.replaySeconds = 137          // M9-T8: an arbitrary length, not just 30/60/120
        #expect(spy.calls == [.windowChanged])
        #expect(spy.lastSeconds == 137)

        // Same value again ⇒ no churn.
        state.replaySeconds = 137
        #expect(spy.calls.count == 1)
    }

    @Test func sourceRehomingNeverRestartsTheArmedStreamNorForgetsThePick() {
        // `refreshSources` runs on every menu open. It must neither restart the armed stream
        // (wiping the buffer at the worst moment) nor clear the persisted mic pick — the pick
        // survives its device's absence so AirPods work automatically when they return.
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        state.microphonePreference = .device(id: "vanished-mic")
        spy.calls = []

        state.refreshSources(displays: [])   // picked mic absent from the fresh device list
        #expect(state.microphonePreference == .device(id: "vanished-mic"))  // pick kept
        #expect(state.presentMicrophonePreference == .none)                 // menu shows None, truthfully
        #expect(spy.calls.isEmpty)                              // buffer untouched
    }

    @Test func recordingStartedArmsADisarmedController() {
        // The mid-recording toggle's path: callers gate on the user's armed intent, so a
        // disarmed controller must treat recordingStarted as the arming act itself.
        let controller = ReplayController()
        #expect(!controller.isPipelineBuiltForTesting)
        controller.recordingStarted(
            router: SampleRouter(), configuration: CaptureConfiguration(microphone: .none),
            seconds: 30, outputDirectory: FileManager.default.temporaryDirectory)
        defer { controller.disarm() }
        #expect(controller.isPipelineBuiltForTesting)
    }

    @Test func recoveryActionRetriesResetsAndConcedes() {
        // The bounded-patience rule, pure: five transient failures retry, the sixth
        // concedes and clears; a failure after a healthy run starts a fresh count.
        var count = 0
        for expected in 1...5 {
            #expect(ReplayController.recoveryAction(
                failureCount: &count, elapsedSinceAttempt: .seconds(1)) == .retry)
            #expect(count == expected)
        }
        #expect(ReplayController.recoveryAction(
            failureCount: &count, elapsedSinceAttempt: .seconds(1)) == .concede)
        #expect(count == 0)

        count = 4
        #expect(ReplayController.recoveryAction(
            failureCount: &count,
            elapsedSinceAttempt: ReplayController.healthyRunThreshold + .seconds(1)) == .retry)
        #expect(count == 1)   // the healthy run wiped the stale streak
    }

    @Test func pipelineFailureRetriesBeforeConceding() {
        // Encoder death is transient more often than not (a dying process can hold the HW
        // encoder); the controller must stay armed until failure is persistent. Rebuilds
        // are interval-delayed, so mid-streak the pipeline is legitimately down.
        let controller = ReplayController()
        var surrendered = 0
        controller.onPipelineFailure = { _ in surrendered += 1 }
        controller.recordingStarted(
            router: SampleRouter(), configuration: CaptureConfiguration(microphone: .none),
            seconds: 30, outputDirectory: FileManager.default.temporaryDirectory)
        defer { controller.disarm() }

        for _ in 1...5 {
            controller.simulatePipelineFailureForTesting()
        }
        #expect(surrendered == 0)

        controller.simulatePipelineFailureForTesting()   // the sixth: persistent — concede
        #expect(surrendered == 1)
        #expect(!controller.isPipelineBuiltForTesting)
    }

    @Test func deliberateTransitionsClearTheFailureStreak() {
        // A stale streak from a previous outage must not make a fresh session concede on
        // its first hiccup.
        let controller = ReplayController()
        var surrendered = 0
        controller.onPipelineFailure = { _ in surrendered += 1 }
        controller.recordingStarted(
            router: SampleRouter(), configuration: CaptureConfiguration(microphone: .none),
            seconds: 30, outputDirectory: FileManager.default.temporaryDirectory)
        defer { controller.disarm() }

        for _ in 1...5 {
            controller.simulatePipelineFailureForTesting()
        }
        controller.recordingStarted(                     // deliberate fresh attach
            router: SampleRouter(), configuration: CaptureConfiguration(microphone: .none),
            seconds: 30, outputDirectory: FileManager.default.temporaryDirectory)
        for _ in 1...5 {
            controller.simulatePipelineFailureForTesting()
        }
        #expect(surrendered == 0)                        // 5 + 5 across a reset never concedes
    }

    @Test func changesWhileDisarmedTouchNothing() {
        let (state, spy, _) = makeState()
        state.quality = .efficient
        state.microphonePreference = .device(id: "some-mic")
        state.replaySeconds = 30
        #expect(spy.calls.isEmpty)
    }

    @Test func outputFolderChangeSwapsOnlyTheMuxer() {
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.calls = []

        let newFolder = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        state.outputDirectory = newFolder
        #expect(spy.calls == [.setOutputDirectory])   // not .configurationChanged — buffer survives
        #expect(spy.lastOutputDirectory == newFolder)
    }

    @Test func hotkeyRegistrationFollowsArmingAndRebinding() {
        let (state, spy, _) = makeState()
        _ = spy
        // Only the replay shortcut here; the record shortcut is nil (off), so it never registers.
        var registered: [Hotkey?] = []
        state.hotkeyRegistrar = { hotkey, kind in
            if kind == .saveReplay { registered.append(hotkey) }
            return true
        }

        state.isReplayArmed = true
        #expect(registered == [.standard])

        let custom = Hotkey(keyCode: 1, modifiers: 256)
        state.replayHotkey = custom
        #expect(registered == [.standard, custom])

        state.isReplayArmed = false
        #expect(registered == [.standard, custom, nil])

        // Rebinding while disarmed must not register a hotkey for a feature that's off.
        state.replayHotkey = .standard
        #expect(registered == [.standard, custom, nil])
    }

    @Test func recordHotkeyRegistersWhenSetAndUnregistersWhenCleared() {
        // M9-T4: the start/stop shortcut isn't tied to arming — set it, it registers; clear it, it
        // unregisters — and it persists either way.
        let (state, _, defaults) = makeState()
        var records: [Hotkey?] = []
        state.hotkeyRegistrar = { hotkey, kind in
            if kind == .toggleRecording { records.append(hotkey) }
            return true
        }

        state.recordHotkey = .recordDefault
        #expect(records == [.recordDefault])
        #expect(defaults.dictionary(forKey: "recordHotkey") != nil)

        state.recordHotkey = nil
        #expect(records == [.recordDefault, nil])            // unregistered
        #expect(defaults.object(forKey: "recordHotkey") == nil)
    }

    @Test func saveSuccessNotifiesWithTheReplayCopy() async {
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        let url = URL(fileURLWithPath: "/tmp/Replay 2026-07-16 at 14.02.11.mov")
        spy.saveResult = .success(ReplayMuxer.SavedReplay(url: url, duration: 60.4))

        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.saveReplay()
        await Task.yield()

        #expect(posted.count == 1)
        #expect(posted.first?.title == "Replay saved")
        #expect(posted.first?.body == "Replay 2026-07-16 at 14.02.11.mov — last 60 s. Click to reveal.")
        #expect(posted.first?.fileURL == url)
    }

    @Test func saveSuccessRecordsTheLastReplayForTheMenu() async {
        // M9-T2: the in-app receipt the banner-suppressed "Replay saved" can't be.
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        let url = URL(fileURLWithPath: "/tmp/Replay 2026-07-16 at 14.02.11.mov")
        spy.saveResult = .success(ReplayMuxer.SavedReplay(url: url, duration: 60.4))
        state.notifier = { _ in }

        state.saveReplay()
        await Task.yield()

        #expect(state.lastReplay?.url == url)
        #expect(state.lastReplay?.seconds == 60)                       // rounded from 60.4
        #expect(state.lastReplay?.menuTitle == "Replay saved · 60 s")
    }

    @Test func saveSuccessFlashesTheMenuBar() async {
        // M9-T3: a signal visible without opening the menu (the receipt row needs the menu open).
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.saveResult = .success(ReplayMuxer.SavedReplay(
            url: URL(fileURLWithPath: "/tmp/r.mov"), duration: 30))
        state.notifier = { _ in }

        state.saveReplay()
        await Task.yield()

        #expect(state.replaySavedFlash)
    }

    @Test func disarmingClearsTheLastReplayReceipt() async {
        // The receipt belongs to the armed session that produced it.
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.saveResult = .success(ReplayMuxer.SavedReplay(
            url: URL(fileURLWithPath: "/tmp/r.mov"), duration: 30))
        state.notifier = { _ in }
        state.saveReplay()
        await Task.yield()
        #expect(state.lastReplay != nil)

        state.isReplayArmed = false
        #expect(state.lastReplay == nil)
    }

    @Test func saveFailureNotifiesCouldnt() async {
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        spy.saveResult = .failure(ReplayMuxerError.nothingBuffered)

        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.saveReplay()
        await Task.yield()

        #expect(posted.first?.title == "Couldn't save replay")
        #expect(posted.first?.fileURL == nil)
    }

    @Test func saveWhileDisarmedDoesNothing() {
        let (state, spy, _) = makeState()
        spy.saveResult = .success(ReplayMuxer.SavedReplay(
            url: URL(fileURLWithPath: "/tmp/x.mov"), duration: 1))
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.saveReplay()
        #expect(posted.isEmpty)
    }

    @Test func microphoneLossAndPipelineDeathReachTheUser() {
        let (state, spy, _) = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        state.isReplayArmed = true

        spy.onMicrophoneLost?()
        #expect(posted.first?.title == "Replay still armed · microphone disconnected")

        spy.onPipelineFailure?("the encoder died")
        #expect(posted.last?.title == "Instant replay turned off")
        // The controller already tore itself down; the state must agree or the badge lies.
        #expect(!state.isReplayArmed)
    }
}

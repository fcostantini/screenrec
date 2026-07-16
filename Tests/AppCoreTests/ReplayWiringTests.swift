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
        var onPipelineFailure: (@MainActor (String) -> Void)?

        enum Call: Equatable {
            case arm, disarm, recordingStarted, recordingEnded, configurationChanged, setOutputDirectory
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

        state.selectedMicrophoneID = "some-mic"
        state.quality = .efficient
        state.frameRateCap = 30
        state.replaySeconds = 120
        #expect(spy.calls == Array(repeating: .configurationChanged, count: 4))
        #expect(spy.lastSeconds == 120)

        // Same value again ⇒ no churn; the stream restart wipes the buffer.
        state.replaySeconds = 120
        #expect(spy.calls.count == 4)
    }

    @Test func sourceRehomingNeverRestartsTheArmedStream() {
        // `refreshSources` re-homes stale picks on every menu open. Those writes are
        // housekeeping, not user intent — a restart here wipes the buffer on the first open
        // after launch, or right after a mic vanished (the moment someone opens the menu to
        // save what they still have).
        let (state, spy, _) = makeState()
        state.isReplayArmed = true
        state.selectedMicrophoneID = "vanished-mic"
        spy.calls = []

        state.refreshSources(displays: [])   // picked mic absent from the fresh list → nil re-home
        #expect(state.selectedMicrophoneID == nil)
        #expect(spy.calls.isEmpty)
    }

    @Test func changesWhileDisarmedTouchNothing() {
        let (state, spy, _) = makeState()
        state.quality = .efficient
        state.selectedMicrophoneID = "some-mic"
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
        var registered: [ReplayHotkey?] = []
        state.hotkeyRegistrar = { registered.append($0); return true }

        state.isReplayArmed = true
        #expect(registered == [.standard])

        let custom = ReplayHotkey(keyCode: 1, modifiers: 256)
        state.replayHotkey = custom
        #expect(registered == [.standard, custom])

        state.isReplayArmed = false
        #expect(registered == [.standard, custom, nil])

        // Rebinding while disarmed must not register a hotkey for a feature that's off.
        state.replayHotkey = .standard
        #expect(registered == [.standard, custom, nil])
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

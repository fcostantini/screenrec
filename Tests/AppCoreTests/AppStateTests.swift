import Foundation
import Testing
@testable import AppCore
import RecorderCore

/// Pure state folding — no capture, no UI host, no real time.
@MainActor
@Suite struct AppStateTests {

    private static let outputURL = URL(fileURLWithPath: "/tmp/screenrec-test.mov")

    /// Every way a session can end. All of them are `finished` — the fail-stops are ADR-007
    /// successes, not errors — so all of them must land on the same icon.
    private static let endReasons: [EndReason] = [
        .userStopped, .displayDisconnected, .microphoneChanged,
        .diskAlmostFull, .systemSleep, .streamError("-3815"),
    ]

    /// An AppState on a throwaway preferences domain.
    ///
    /// Never `AppState()` here: settings persist on `didSet` since M4-T4, so a bare AppState in
    /// a test writes to the real `UserDefaults.standard` — leaking one test's assignment into
    /// another's launch, and onto disk between runs. (That is exactly how this was found.)
    private func makeState() -> AppState {
        // Invariant: a fresh UUID suite name is always a valid, unused domain.
        AppState(defaults: UserDefaults(suiteName: "appstate-tests-\(UUID().uuidString)")!)
    }

    /// An AppState that has been through `started`, i.e. the first complete video frame landed.
    private func recordingState() -> AppState {
        let state = makeState()
        state.apply(.started)
        return state
    }

    @Test func idleBeforeAnythingHappens() {
        #expect(makeState().statusIcon == .idle)
    }

    @Test func firstFrameStartsRecording() {
        #expect(recordingState().statusIcon == .recording)
    }

    @Test func pauseAndResumeSwapTheIcon() {
        let state = recordingState()
        state.apply(.paused)
        #expect(state.statusIcon == .paused)
        state.apply(.resumed)
        #expect(state.statusIcon == .recording)
    }

    @Test(arguments: endReasons) func everyEndingReturnsToIdle(reason: EndReason) {
        let state = recordingState()
        state.apply(.finished(url: Self.outputURL, reason: reason, droppedFrames: 0))
        #expect(state.statusIcon == .idle)
    }

    @Test(arguments: endReasons) func aPausedSessionCanAlsoEnd(reason: EndReason) {
        // A fail-stop does not wait for the user to resume — the display can die, or the disk
        // fill, while paused. Pausing must not strand the icon on the amber state forever.
        let state = recordingState()
        state.apply(.paused)
        state.apply(.finished(url: Self.outputURL, reason: reason, droppedFrames: 0))
        #expect(state.statusIcon == .idle)
    }

    @Test func aStartFailureLeavesNothingRunning() {
        let state = makeState()
        state.apply(.failed(message: "No displays available"))
        #expect(state.statusIcon == .idle)
    }

    @Test func anEngineOnlyStopReturnsToIdle() {
        // `stopped` is the writer-less path (engine-smoke); RecordingSession folds it into
        // `finished` before the app ever sees it. Handled anyway — the icon must never be
        // left claiming a capture that has demonstrably ended.
        let state = recordingState()
        state.apply(.stopped(.userStopped))
        #expect(state.statusIcon == .idle)
    }

    @Test func losingTheMicrophoneKeepsRecording() {
        // ADR-012: mic loss notifies and the recording continues. An icon that dropped to idle
        // here would tell the user their 90-minute screen capture had stopped when it hadn't.
        let state = recordingState()
        state.apply(.microphoneLost)
        #expect(state.statusIcon == .recording)
    }

    @Test func losingTheMicrophoneWhilePausedKeepsTheTimelineFrozen() {
        // The two are independent: the mic dying is not a resume. Only the pinned-state tests
        // above would miss this, since each fixes one variable while the real session moves both.
        let state = recordingState()
        state.apply(.paused)
        state.apply(.microphoneLost)
        #expect(state.statusIcon == .paused)
    }

    @Test func progressDoesNotDisturbTheIcon() {
        let state = recordingState()
        state.apply(.paused)
        state.apply(.fileProgress(seconds: 12, bytes: 1_000_000))
        #expect(state.statusIcon == .paused)
    }

    // MARK: - The pickers → CaptureConfiguration (docs/06 items 5–7)

    @Test func defaultsMatchTheCaptureDefaults() {
        let state = makeState()
        #expect(state.captureConfiguration.display == .main)
        #expect(state.captureConfiguration.microphone == .none)
        #expect(state.captureConfiguration.quality == .balanced)
    }

    @Test func pickedSourcesReachTheConfiguration() {
        let state = makeState()
        state.selectedDisplayID = 42
        state.selectedMicrophoneID = "mic-uid"
        state.quality = .high

        #expect(state.captureConfiguration.display == .id(42))
        #expect(state.captureConfiguration.microphone == .device(id: "mic-uid"))
        #expect(state.captureConfiguration.quality == .high)
    }

    @Test func noMicrophoneMeansNoneNotADefaultDevice() {
        // `.none` has to survive as `.none`: SCK treats a nil/sentinel device ID as an error
        // (docs/02 §1), and "the user chose no mic" must not quietly become "some mic".
        let state = makeState()
        state.selectedMicrophoneID = nil
        #expect(state.captureConfiguration.microphone == .none)
    }

    @Test func firstRefreshChecksTheMainDisplay() {
        // docs/06 item 5 wants one row per screen with a checkmark on the current one — so the
        // selection must name a real row, not sit on nil.
        let state = makeState()
        state.refreshSources(displays: [
            DisplayOption(id: 1, name: "Sidecar", isMain: false),
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        #expect(state.selectedDisplayID == 2)
    }

    @Test func aPickedDisplayIsLeftAlone() {
        let state = makeState()
        state.refreshSources(displays: [
            DisplayOption(id: 1, name: "Sidecar", isMain: false),
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        state.selectedDisplayID = 1
        state.refreshSources(displays: [
            DisplayOption(id: 1, name: "Sidecar", isMain: false),
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        #expect(state.selectedDisplayID == 1)      // the user's choice survives a menu re-open
    }

    @Test func aVanishedDisplayFallsBackToMain() {
        // Unplug the display you picked and the submenu would otherwise show nothing checked
        // while the engine resolves an ID that no longer exists.
        let state = makeState()
        state.selectedDisplayID = 99
        state.refreshSources(displays: [
            DisplayOption(id: 2, name: "Built-in Retina Display", isMain: true),
        ])
        #expect(state.selectedDisplayID == 2)
    }

    @Test func aVanishedMicrophonePickIsKeptButDisplaysAsNone() {
        // The pick survives its device's absence (persisted; AirPods return and just work) —
        // the menu stays honest through `presentMicrophoneID`, and stream starts resolve
        // picked-device-or-nothing rather than falling back to the system default, so the
        // menu and the file always agree.
        let state = makeState()
        state.selectedMicrophoneID = "unplugged-device-uid"
        state.refreshSources(displays: [])
        #expect(state.selectedMicrophoneID == "unplugged-device-uid")
        #expect(state.presentMicrophoneID == nil)
    }

    @Test func noDisplaysAtAllLeavesTheConfigurationOnMain() {
        let state = makeState()
        state.refreshSources(displays: [])
        #expect(state.selectedDisplayID == nil)
        #expect(state.captureConfiguration.display == .main)
    }

    // MARK: - Session shape

    @Test func nothingIsActiveBeforeStarting() {
        let state = makeState()
        #expect(!state.isSessionActive)
        #expect(!state.isPaused)
    }

    @Test func pausedTracksTheIcon() {
        let state = recordingState()
        #expect(!state.isPaused)
        state.apply(.paused)
        #expect(state.isPaused)
        state.apply(.resumed)
        #expect(!state.isPaused)
    }

    @Test func aStartFailureIsSaidOutLoud() {
        // ADR-007: a recording that never happened must not fail silently. Until M4-T5's
        // notifications, the header row is the only place this can be said.
        let state = makeState()
        state.apply(.failed(message: "No displays available"))
        #expect(state.lastFailure == "No displays available")
    }

    @Test func losingTheMicrophoneIsReportedWithoutEndingTheRecording() {
        let state = recordingState()
        state.apply(.microphoneLost)
        #expect(state.statusIcon == .recording)      // ADR-012
        #expect(state.lastFailure != nil)            // …but never silently
    }

    @Test func consumesAWholeSessionFromItsEventStream() async {
        // The production path: RecordingSession hands over a stream, not loose events. It ends
        // by finishing the stream, so `consume` must return rather than hang the caller.
        let state = makeState()
        let (events, continuation) = AsyncStream.makeStream(of: EngineEvent.self)
        for event: EngineEvent in [
            .started, .fileProgress(seconds: 5, bytes: 500_000), .paused, .resumed,
            .microphoneLost,
            .finished(url: Self.outputURL, reason: .diskAlmostFull, droppedFrames: 3),
        ] {
            continuation.yield(event)
        }
        continuation.finish()

        await state.consume(events)
        #expect(state.statusIcon == .idle)
    }
}

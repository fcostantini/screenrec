import Foundation
import Observation
import Testing
@testable import AppCore
import RecorderCore

/// Pure state folding — no capture, no UI host, no real time.
@MainActor
@Suite struct AppStateTests {

    /// A thread-safe latch for `withObservationTracking`'s `@Sendable onChange`.
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return raised }
        func raise() { lock.lock(); raised = true; lock.unlock() }
    }

    private static let outputURL = URL(fileURLWithPath: "/tmp/screenrec-test.mov")

    /// Every way a session can end. All of them are `finished` — the fail-stops are ADR-007
    /// successes, not errors — so all of them must land on the same icon.
    private static let endReasons: [EndReason] = [
        .userStopped, .displayDisconnected, .appQuit, .microphoneChanged,
        .diskAlmostFull, .systemSleep, .streamError("-3815"),
    ]

    /// An AppState on a throwaway preferences domain.
    ///
    /// Never `AppState()` here: settings persist on `didSet` since M4-T4, so a bare AppState in
    /// a test writes to the real `UserDefaults.standard` — leaking one test's assignment into
    /// another's launch, and onto disk between runs. (That is exactly how this was found.)
    private func makeDefaults() -> UserDefaults {
        // Invariant: a fresh UUID suite name is always a valid, unused domain.
        UserDefaults(suiteName: "appstate-tests-\(UUID().uuidString)")!
    }

    private func makeState() -> AppState {
        AppState(defaults: makeDefaults())
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

    @Test func discardingReturnsToIdle() {
        let state = recordingState()
        state.apply(.discarded)
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
        #expect(state.captureConfiguration.content == .display(.main))
        #expect(state.captureConfiguration.microphone == .none)
        #expect(state.captureConfiguration.quality == .balanced)
    }

    @Test func pickedSourcesReachTheConfiguration() {
        let state = makeState()
        state.selectedDisplayID = 42
        state.microphonePreference = .device(id: "mic-uid")
        state.quality = .high

        #expect(state.captureConfiguration.content == .display(.id(42)))
        #expect(state.captureConfiguration.microphone == .device(id: "mic-uid"))
        #expect(state.captureConfiguration.quality == .high)
    }

    @Test func noMicrophoneMeansNoneNotADefaultDevice() {
        // `.none` has to survive as `.none`: SCK treats a nil/sentinel device ID as an error
        // (docs/02 §1), and "the user chose no mic" must not quietly become "some mic".
        let state = makeState()
        state.microphonePreference = .none
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
        // the menu stays honest through `presentMicrophonePreference`, and stream starts resolve
        // picked-device-or-nothing rather than falling back to the system default, so the
        // menu and the file always agree.
        let state = makeState()
        state.microphonePreference = .device(id: "unplugged-device-uid")
        state.refreshSources(displays: [])
        #expect(state.microphonePreference == .device(id: "unplugged-device-uid"))
        #expect(state.presentMicrophonePreference == .none)
    }

    @Test func noDisplaysAtAllLeavesTheConfigurationOnMain() {
        let state = makeState()
        state.refreshSources(displays: [])
        #expect(state.selectedDisplayID == nil)
        #expect(state.captureConfiguration.content == .display(.main))
    }

    // MARK: - Source picker: app capture (docs/06 item 5, M7-T2)

    @Test func aPickedAppReachesTheConfiguration() {
        let state = makeState()
        state.selectedAppBundleID = "com.example.app"
        #expect(state.captureConfiguration.content == .app(bundleID: "com.example.app"))
    }

    @Test func sourceChoiceRoundTripsAndRemembersTheDisplay() {
        let state = makeState()
        state.selectedDisplayID = 42
        state.sourceChoice = .app(bundleID: "com.example.app")
        #expect(state.sourceChoice == .app(bundleID: "com.example.app"))

        state.sourceChoice = .display(42)
        // Returning from an app detour lands on the remembered display, not back on main.
        #expect(state.selectedAppBundleID == nil)
        #expect(state.captureConfiguration.content == .display(.id(42)))
    }

    @Test func anAbsentPickedAppIsKeptAndShownAsNotRunning() {
        // The mic rule (docs/06): a pick survives absence — never re-homed to Entire Screen.
        // The menu shows it through `missingPickedApp`; a start while absent fails loud (M7-T1).
        let state = makeState()
        state.selectedAppBundleID = "com.example.gone"
        state.refreshApps([CapturableApp(bundleID: "com.other", name: "Other")], excluding: nil)
        #expect(state.selectedAppBundleID == "com.example.gone")
        #expect(state.missingPickedApp
            == CapturableApp(bundleID: "com.example.gone", name: "com.example.gone"))
    }

    @Test func missingPickedAppUsesTheInjectedNameResolver() {
        let state = makeState()
        state.appDisplayName = { $0 == "com.example.gone" ? "Gone" : nil }
        state.selectedAppBundleID = "com.example.gone"
        #expect(state.missingPickedApp?.name == "Gone")
    }

    @Test func aRunningPickedAppIsNotMissing() {
        let state = makeState()
        state.selectedAppBundleID = "com.example.app"
        state.refreshApps([CapturableApp(bundleID: "com.example.app", name: "App")], excluding: nil)
        #expect(state.missingPickedApp == nil)
    }

    @Test func refreshAppsExcludesTheAppItself() {
        let state = makeState()
        state.refreshApps(
            [CapturableApp(bundleID: "dev.fcostantini.screenrec.app", name: "ScreenRec"),
             CapturableApp(bundleID: "com.other", name: "Other")],
            excluding: "dev.fcostantini.screenrec.app")
        #expect(state.capturableApps == [CapturableApp(bundleID: "com.other", name: "Other")])
    }

    @Test func theAppPickPersistsAcrossLaunches() {
        let defaults = makeDefaults()
        let first = AppState(defaults: defaults)
        first.selectedAppBundleID = "com.example.app"

        let second = AppState(defaults: defaults)
        #expect(second.selectedAppBundleID == "com.example.app")
        #expect(second.captureConfiguration.content == .app(bundleID: "com.example.app"))
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

    @Test func refreshProgressPublishesOnlyOnRealChange() {
        // A publish rebuilds the open menu's AppKit rows and garbles hover state, so the
        // idle 1 Hz poll (values pinned at zero) must be observation-silent.
        let state = makeState()
        state.refreshProgress()

        let published = Flag()
        withObservationTracking {
            _ = state.elapsedSeconds
            _ = state.recordedBytes
        } onChange: {
            published.raise()
        }
        state.refreshProgress()
        #expect(!published.isRaised)
    }

    @Test func refreshSourcesAndRecentsAreSilentOnNoChange() {
        // Same open-menu-rebuild hazard as refreshProgress: identical displays/mics/recents
        // must not republish (M6-T10).
        let state = makeState()
        let displays = [DisplayOption(id: 1, name: "Main", isMain: true)]
        state.refreshSources(displays: displays)
        state.refreshRecentRecordings()

        let published = Flag()
        withObservationTracking {
            _ = state.displays
            _ = state.microphones
            _ = state.recentRecordings
        } onChange: {
            published.raise()
        }
        state.refreshSources(displays: displays)
        state.refreshRecentRecordings()
        #expect(!published.isRaised)
    }
}

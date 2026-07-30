import CoreGraphics
import Foundation
import Observation
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
        .userStopped, .displayDisconnected, .appQuit, .diskAlmostFull, .writeFailed,
        .streamError("-3815"),
    ]

    /// An AppState on a throwaway preferences domain.
    ///
    /// Never `AppState()` here: settings persist on `didSet` since M4-T4, so a bare AppState in
    /// a test writes to the real `UserDefaults.standard` — leaking one test's assignment into
    /// another's launch, and onto disk between runs. (That is exactly how this was found.)
    private func makeDefaults() -> UserDefaults {
        TestDefaults.make("appstate-tests")
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

    // MARK: - Recording clock for the menu-bar label (M9-T3)

    @Test func startBeginsARunningClockAtZero() {
        let state = recordingState()
        #expect(state.recordingClock?.accumulated == 0)
        #expect(state.recordingClock?.runningSince != nil)   // running
    }

    @Test func pauseFreezesTheClockAndResumeRunsItAgain() {
        let state = recordingState()
        state.apply(.paused)
        #expect(state.recordingClock?.runningSince == nil)   // frozen
        state.apply(.resumed)
        #expect(state.recordingClock?.runningSince != nil)   // running again
    }

    @Test(arguments: endReasons) func everyEndingClearsTheClock(reason: EndReason) {
        let state = recordingState()
        state.apply(.finished(url: Self.outputURL, reason: reason, droppedFrames: 0))
        #expect(state.recordingClock == nil)
    }

    @Test func aStartFailureLeavesNoClock() {
        let state = makeState()
        state.apply(.failed(message: "no displays"))
        #expect(state.recordingClock == nil)
    }

    // MARK: - Global start/stop shortcut (M9-T4)

    @Test func theStartStopToggleReadsOffSessionAndReadiness() {
        // Pure, so the three branches are testable without live capture (which start/stop need).
        #expect(AppState.recordToggleAction(isSessionActive: false, isReady: true) == .start)
        #expect(AppState.recordToggleAction(isSessionActive: true, isReady: true) == .stop)
        #expect(AppState.recordToggleAction(isSessionActive: true, isReady: false) == .stop)  // active wins
        #expect(AppState.recordToggleAction(isSessionActive: false, isReady: false) == .blockedNotify)
    }

    // MARK: - Global pause/resume shortcut (M12-T6)

    @Test func thePauseToggleReadsOffSessionAndPauseState() {
        // Pure, so the three branches are testable without live capture (which pause/resume need).
        #expect(AppState.pauseToggleAction(isSessionActive: true, isPaused: false) == .pause)
        #expect(AppState.pauseToggleAction(isSessionActive: true, isPaused: true) == .resume)
        #expect(AppState.pauseToggleAction(isSessionActive: false, isPaused: false) == .ignore)  // nothing to pause
        #expect(AppState.pauseToggleAction(isSessionActive: false, isPaused: true) == .ignore)
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

    // MARK: - The pickers → CaptureConfiguration (docs/06 items 5–7)

    @Test func defaultsMatchTheCaptureDefaults() {
        let state = makeState()
        #expect(state.captureConfiguration.content == .display(.main))
        #expect(state.captureConfiguration.microphone == .none)
        #expect(state.captureConfiguration.quality == .balanced)
    }

    // MARK: - Window pick (M17-T2)

    private func liveWindow(
        id: CGWindowID, bundleID: String = "com.apple.finder", app: String = "Finder",
        title: String = "Movies"
    ) -> CapturableWindow {
        CapturableWindow(id: id, bundleID: bundleID, appName: app, title: title,
                         pointSize: CGSize(width: 900, height: 500))
    }

    @Test func aWindowPickCarriesItsOwnerIntoTheConfiguration() {
        // The owner travels with the id so capture can refuse a REUSED id (docs/02 §1c) — an id
        // alone would let a restored pick bind another app's window.
        let state = makeState()
        state.sourceChoice = .window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        #expect(state.captureConfiguration.content
            == .window(id: 37, ownerBundleID: "com.apple.finder"))
    }

    @Test func pickingAWindowClearsTheAppAndRegionPicks() {
        // One Source at a time: a leftover app or region pick would win in `captureConfiguration`.
        let state = makeState()
        state.sourceChoice = .app(bundleID: "com.example.app")
        state.sourceChoice = .window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        #expect(state.selectedAppBundleID == nil)
        #expect(state.selectedRegion == nil)
        state.sourceChoice = .display(nil)
        #expect(state.selectedWindow == nil)
    }

    @Test func aGoneWindowIsStillListedAndStillChecked() {
        // The pick survives absence (the `(not running)` app rule); Start fails loud instead.
        let state = makeState()
        let pick = WindowSelection(id: 37, bundleID: "com.apple.finder")
        state.sourceChoice = .window(pick)
        state.refreshWindows([liveWindow(id: 99)], excluding: nil)
        #expect(state.missingPickedWindow == pick)
    }

    @Test func aReusedIdCountsAsGoneRatherThanAsThePick() {
        // Same number, different app: the dangerous case. Treating it as present would record
        // the wrong window while looking like it worked.
        let state = makeState()
        state.sourceChoice = .window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        state.refreshWindows([liveWindow(id: 37, bundleID: "com.apple.Safari", app: "Safari")],
                             excluding: nil)
        #expect(state.missingPickedWindow != nil)
    }

    @Test func theSourceLabelRelabelsARetitledWindowAndNamesTheAppOfAGoneOne() {
        // Title is display-only and never matched on, so a retitled window (every browser tab
        // switch) stays the pick and simply relabels. Gone, it can only name its app — the title
        // is not stored (M19-T5), and `(closed)` is what separates it from an app-scoped pick.
        let state = makeState()
        // The app names its own resolver from the installed bundle, so a closed window still says
        // "Finder"; with nothing able to name it, `appName(for:)` falls back to the bundle id.
        state.appDisplayName = { $0 == "com.apple.finder" ? "Finder" : nil }
        state.sourceChoice = .window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        state.refreshWindows([liveWindow(id: 37, title: "Downloads")], excluding: nil)
        #expect(state.missingPickedWindow == nil)
        #expect(state.sourceMenuLabel == "Finder — Downloads")
        state.refreshWindows([], excluding: nil)
        #expect(state.sourceMenuLabel == "Finder (closed)")
    }

    @Test func aRetitledWindowStillMatchesItsOwnMenuRow() {
        // The Picker tags each row from the LIVE window while the selection comes from the stored
        // pick, so any field that moves breaks the match and the checkmark vanishes — measured
        // before M19-T5 dropped `title` from the type. Fails if it ever comes back.
        let state = makeState()
        state.sourceChoice = .window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        state.refreshWindows([liveWindow(id: 37, title: "Downloads")], excluding: nil)

        let rowTag = SourceChoice.window(WindowSelection(id: 37, bundleID: "com.apple.finder"))
        #expect(state.sourceChoice == rowTag)
    }

    @Test func screenRecNeverOffersItsOwnWindows() {
        let state = makeState()
        state.refreshWindows(
            [liveWindow(id: 1, bundleID: "dev.fcostantini.screenrec.app", app: "ScreenRec"),
             liveWindow(id: 2)],
            excluding: "dev.fcostantini.screenrec.app")
        #expect(state.capturableWindows.map(\.id) == [2])
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

    @Test func recoveryPolicyHonorsThePick() {
        // M8-T2: Automatic follows the system default on recovery; a specific pick (and None,
        // vacuously) recovers only onto itself.
        let state = makeState()
        state.microphonePreference = .device(id: "mic-uid")
        #expect(state.captureConfiguration.microphoneRecovery == .sameDevice)
        state.microphonePreference = .automatic
        #expect(state.captureConfiguration.microphoneRecovery == .systemDefault)
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

    @Test func excludingAnAppIsAWholeScreenPickWithAHole() {
        // M21-T4: the exclusion rides the display pick rather than replacing it, so the display
        // choice has to survive it — and `Nothing` (a plain display tag) has to undo it.
        let state = makeState()
        state.selectedDisplayID = 42
        state.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")

        #expect(state.sourceChoice == .displayExcluding(bundleID: "com.spotify.client"))
        #expect(state.selectedDisplayID == 42)
        #expect(state.captureConfiguration.content
            == .displayExcluding(.id(42), bundleID: "com.spotify.client"))

        state.sourceChoice = .display(42)
        #expect(state.captureConfiguration.content == .display(.id(42)))
        #expect(state.excludedAppName == nil)
    }

    @Test func pickingAnotherSourceDropsTheExclusion() {
        // An app- or window-scoped take is already narrowed; a leftover exclusion would silently
        // ride along in `captureConfiguration`.
        let state = makeState()
        state.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")
        state.sourceChoice = .app(bundleID: "com.example.app")
        #expect(state.captureConfiguration.content == .app(bundleID: "com.example.app"))

        state.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")
        state.sourceChoice = .window(WindowSelection(id: 7, bundleID: "com.example.app"))
        #expect(state.captureConfiguration.content
            == .window(id: 7, ownerBundleID: "com.example.app"))
    }

    @Test func anExcludedAppWithNothingOnScreenIsKeptAndFlagged() {
        // The state the measurement found (M21-T4): a minimised app isn't in SCK's list, so it
        // cannot be excluded. The pick survives — absence never re-homes one — and the menu says so.
        let state = makeState()
        state.sourceChoice = .displayExcluding(bundleID: "com.spotify.client")
        state.refreshApps([CapturableApp(bundleID: "com.other", name: "Other")], excluding: nil)

        #expect(state.sourceChoice == .displayExcluding(bundleID: "com.spotify.client"))
        #expect(state.missingExcludedApp
            == CapturableApp(bundleID: "com.spotify.client", name: "com.spotify.client"))

        state.refreshApps(
            [CapturableApp(bundleID: "com.spotify.client", name: "Spotify")], excluding: nil)
        #expect(state.missingExcludedApp == nil)
        #expect(state.excludedAppName == "Spotify")
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

    // MARK: - Source picker: region capture (docs/06 item 5, M11-T2)

    @Test func aPickedRegionReachesTheConfiguration() {
        let state = makeState()
        let rect = CGRect(x: 40, y: 60, width: 800, height: 500)
        state.setRegion(displayID: 7, rect: rect)
        #expect(state.captureConfiguration.content == .region(display: .id(7), rect: rect))
    }

    @Test func aRegionWithoutADisplayResolvesToMain() {
        let state = makeState()
        let rect = CGRect(x: 0, y: 0, width: 640, height: 400)
        state.setRegion(displayID: nil, rect: rect)
        #expect(state.captureConfiguration.content == .region(display: .main, rect: rect))
    }

    @Test func sourceChoiceRegionRoundTripsAndClearsOtherPicks() {
        let state = makeState()
        state.selectedAppBundleID = "com.example.app"
        let rect = CGRect(x: 40, y: 60, width: 800, height: 500)

        state.sourceChoice = .region(display: nil, rect: rect)
        #expect(state.sourceChoice == .region(display: nil, rect: rect))
        #expect(state.selectedAppBundleID == nil)            // region clears the app pick

        state.sourceChoice = .display(1)                     // and switching away clears the region
        #expect(state.selectedRegion == nil)
        #expect(state.captureConfiguration.content == .display(.id(1)))
    }

    @Test func theRegionPickPersistsAcrossLaunches() {
        let defaults = makeDefaults()
        let rect = CGRect(x: 40, y: 60, width: 800, height: 500)
        let first = AppState(defaults: defaults)
        first.setRegion(displayID: 7, rect: rect)

        let second = AppState(defaults: defaults)
        #expect(second.selectedRegion == RegionSelection(displayID: 7, rect: rect))
        #expect(second.captureConfiguration.content == .region(display: .id(7), rect: rect))
    }

    @Test func sckRectFlipsAppKitBottomLeftToSckTopLeft() {
        // The overlay hands back AppKit points (bottom-left origin); the engine wants SCK points
        // (top-left, docs/02 §1b). The menu-bar case is the one M11-T1 proved live: an AppKit rect
        // at the TOP of a 1285-pt display maps to SCK y = 0.
        let top = RegionSelection.sckRect(
            fromViewRect: CGRect(x: 0, y: 1165, width: 1200, height: 120), displayHeightPoints: 1285)
        #expect(top == CGRect(x: 0, y: 0, width: 1200, height: 120))

        let mid = RegionSelection.sckRect(
            fromViewRect: CGRect(x: 40, y: 60, width: 800, height: 500), displayHeightPoints: 1285)
        #expect(mid == CGRect(x: 40, y: 725, width: 800, height: 500))   // 1285 − (60 + 500)
    }

    @Test func regionLabelFormatsThePointSize() {
        #expect(SourcesModel.regionLabel(CGSize(width: 820, height: 512)) == "820×512")
        #expect(SourcesModel.regionLabel(CGSize(width: 800.4, height: 499.6)) == "800×500")
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

    @Test func aFailedStartLeavesTheMessageWhereTheIDLEMenuRendersIt() {
        // The pair the menu branches on. A start that fails before a session exists is NOT
        // `isSessionActive`, so it draws the idle menu — which for a long time rendered
        // `lastFailure` nowhere, and Start looked like a no-op (M17-T2 found it live under a
        // stale window pick, where notification banners were suppressed by an armed replay).
        let state = makeState()
        let gone = "That window isn't on screen any more."
        state.apply(.failed(message: gone))
        #expect(!state.isSessionActive)
        #expect(state.lastFailure == gone)
    }

    @Test func aStartFailureSurvivesTheTeardownThatFollowsIt() {
        // The engine yields `.failed` *through* the session and then finishes the stream, so
        // teardown lands right on top of the message. Clearing it there left the user with a
        // Start that did nothing and said nothing (found live, M17-T2).
        let state = makeState()
        state.apply(.failed(message: "That window isn't on screen any more."))
        state.endSession()
        #expect(state.lastFailure == "That window isn't on screen any more.")
    }

    @Test func aTransientNoticeStillDiesWithItsRecording() {
        // The other half: a mic-loss notice describes a recording that has now ended, so leaving
        // it set would squat in the idle menu describing nothing.
        let state = recordingState()
        state.apply(.microphoneLost)
        #expect(state.lastFailure != nil)
        state.endSession()
        #expect(state.lastFailure == nil)
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
            .started, .paused, .resumed, .microphoneLost,
            .finished(url: Self.outputURL, reason: .diskAlmostFull, droppedFrames: 3),
        ] {
            continuation.yield(event)
        }
        continuation.finish()

        await state.consume(events)
        #expect(state.statusIcon == .idle)
    }

    @Test func aWriteFailedTakeIsNotOfferedForNamingOrSharing() {
        // M23-T1: the fold records what the take left behind so the naming prompt and Stop & Copy
        // can act on it — but both would write to the volume that just refused a write, and a
        // "what shall we call it?" over a take that died is the wrong moment (docs/06).
        let state = recordingState()
        state.apply(.finished(url: Self.outputURL, reason: .writeFailed, droppedFrames: 0))
        #expect(state.session.finishedRecording == nil)
        #expect(state.statusIcon == .idle)          // still an ending, and still the same icon
    }

    @Test func everyOtherEndingIsStillOfferedForNaming() {
        // The negative control: without it the guard above passes just as well by suppressing
        // every take, which would silently retire M21-T3.
        for reason in Self.endReasons where reason != .writeFailed {
            let state = recordingState()
            state.apply(.finished(url: Self.outputURL, reason: reason, droppedFrames: 0))
            #expect(state.session.finishedRecording?.url == Self.outputURL)
        }
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

    // MARK: - Recent row details (M18-T3)

    @Test func recentRowDetailsRideTheOpenAndSurviveAReopen() async throws {
        // The row read hangs off the menu open, where a quick reopen can put two passes in flight.
        // The app and window lists both guard against that (a stale pass landing last drops rows
        // while the menu is up); this one has to as well.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rows-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("x".utf8).write(to: directory.appendingPathComponent("Take.mov"))

        let state = makeState()
        state.outputDirectory = directory
        state.refreshRecentRecordings()
        // The URL the menu actually holds: a listing resolves /var → /private/var, and the details
        // are keyed by URL, so a hand-built path would key a different entry.
        let recording = try #require(state.recentRecordings.first)
        #expect(recording.lastPathComponent == "Take.mov")
        // Before the read lands, the row is its name — never a placeholder.
        #expect(state.rowTitle(for: recording) == "Take.mov")

        await state.refreshRecentDetails()
        #expect(state.rowTitle(for: recording) == "Take.mov — 1 byte")

        // Two passes at once must not leave a row without its detail.
        async let first: Void = state.refreshRecentDetails()
        async let second: Void = state.refreshRecentDetails()
        _ = await (first, second)
        #expect(state.rowTitle(for: recording) == "Take.mov — 1 byte")

        // A file that goes away loses its row rather than keeping a stale one.
        try FileManager.default.removeItem(at: recording)
        await state.refreshRecentDetails()
        #expect(state.rowTitle(for: recording) == "Take.mov")
    }

    // MARK: - Four small honesties (M18-T4)

    @Test func aCancelledCountInRecordsNothing() async {
        // The one action that could not be taken back once started. Cancelling must land back in
        // idle with no session — not merely skip the overlay.
        let state = makeState()
        state.countInEnabled = true
        state.runCountIn = { completion in completion(.cancelled) }
        await state.start()
        #expect(state.isSessionActive == false)

        // …and Start is immediately usable again: the count-in guard must not stay latched.
        var ranAgain = false
        state.runCountIn = { _ in ranAgain = true }
        await state.start()
        #expect(ranAgain)
    }

    @Test func aVanishedFileReportsItselfInsteadOfDoingNothing() throws {
        // Rows are stamped at menu open, so a file can go away under them; the click used to be a
        // silent no-op (M18-T4).
        let state = makeState()
        var posted: [RecordingNotification] = []
        state.notifier = { posted.append($0) }
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gone-\(UUID().uuidString).mov")
        try Data("x".utf8).write(to: file)

        #expect(state.fileStillExists(file))
        #expect(posted.isEmpty)

        try FileManager.default.removeItem(at: file)
        #expect(state.fileStillExists(file) == false)
        #expect(posted.count == 1)
        #expect(posted.first?.title == "That file isn't there any more")
        #expect(posted.first?.fileURL == nil)   // nothing to reveal
    }

    @Test func aBoundedTakeKnowsWhenItEnds() {
        // The deadline the recording menu states, without needing a capture session to compute it.
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(AppState.automaticStopDate(from: start, minutes: 0) == nil)   // Off is the default
        #expect(AppState.automaticStopDate(from: start, minutes: 30)
            == start.addingTimeInterval(1800))
    }

    @Test func theStopAfterPickReadsAsARow() {
        #expect(MenuHeader.stopAfter(0) == "Off")
        #expect(MenuHeader.stopAfter(5) == "5 min")
        #expect(MenuHeader.stopAfter(60) == "1 hour")
    }

    @Test func aRunningBoundIsStatedAsAClockTimeNotACountdown() throws {
        // A countdown would have to tick, which the menu never does (M6-T10). And the clock is
        // locale-formatted: a 24-hour figure on a 12-hour Mac reads like a duration.
        let utc = try #require(TimeZone(identifier: "UTC"))
        let at = Date(timeIntervalSince1970: 14 * 3600 + 32 * 60)
        #expect(MenuHeader.stopsAt(at, locale: Locale(identifier: "en_GB"), timeZone: utc)
            == "Stops at 14:32")
        // The formatter separates the meridiem with U+202F (narrow no-break space), not a space.
        let us = MenuHeader.stopsAt(at, locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(us.replacingOccurrences(of: "\u{202F}", with: " ") == "Stops at 2:32 PM")
    }
}

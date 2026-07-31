import Foundation
import Observation
import Testing
@testable import AppCore
import RecorderCore

/// The recording sub-model split from AppState (M22-T2), tested by name (M23-T4).
///
/// `AppStateTests` already drives this fold through `AppState` and keeps doing so — that redundancy
/// is what caught two inverted guards during M22-T2. These assert the same rules one layer down, so
/// a break here reports as `SessionModelTests` rather than as somebody else's failure.
///
/// No capture: the fold is hand-fed events, which is what `apply(_:)` is internal for.
@MainActor
@Suite struct SessionModelTests {

    private static let url = URL(fileURLWithPath: "/tmp/screenrec-session-test.mov")

    /// Every way a session can end. All are `finished` — fail-stops are ADR-007 successes.
    nonisolated private static let endReasons: [EndReason] = [
        .userStopped, .displayDisconnected, .appQuit, .windowClosed, .diskAlmostFull,
        .writeFailed, .streamError("-3815"),
    ]

    /// Records what the fold reported, since both outputs are injected closures.
    private func makeModel() -> (SessionModel, Reports) {
        let model = SessionModel()
        let reports = Reports()
        model.reportFailure = { reports.failures.append((message: $0, outlives: $1)) }
        model.notifier = { reports.notifications.append($0) }
        return (model, reports)
    }

    private final class Reports {
        var failures: [(message: String?, outlives: Bool)] = []
        var notifications: [RecordingNotification] = []
    }

    private func recording() -> (SessionModel, Reports) {
        let (model, reports) = makeModel()
        model.apply(.started)
        return (model, reports)
    }

    // MARK: - Clock and icon

    @Test func theFirstFrameStartsAClockAtZeroAndTurnsTheIconRecording() {
        let (model, _) = recording()
        #expect(model.recordingClock?.accumulated == 0)
        #expect(model.recordingClock?.runningSince != nil)   // running, not frozen
        #expect(model.statusIcon == .recording)
    }

    @Test func pauseFreezesTheClockAndResumeKeepsWhatWasBanked() async throws {
        let (model, _) = recording()
        // ⚠️ The wait is load-bearing. `apply` banks from `Date()`, so with no elapsed time the
        // banked span is ~0 — and "resume restarts the clock" then satisfies `accumulated == 0`
        // just as well as resuming does. Measured: without it, that break stays green.
        try await Task.sleep(for: .milliseconds(30))

        model.apply(.paused)
        #expect(model.statusIcon == .paused)
        #expect(model.recordingClock?.runningSince == nil)   // frozen
        let banked = try #require(model.recordingClock?.accumulated)
        #expect(banked > 0)                                  // there is something to lose

        model.apply(.resumed)
        #expect(model.statusIcon == .recording)
        #expect(model.recordingClock?.runningSince != nil)   // running again
        // Resuming must not restart the count — the paused span is removed from the file, but the
        // recorded time before it still happened.
        #expect(model.recordingClock?.accumulated == banked)
    }

    @Test(arguments: endReasons) func everyEndingClearsTheClockAndReturnsToIdle(reason: EndReason) {
        let (model, _) = recording()
        model.apply(.finished(url: Self.url, reason: reason, droppedFrames: 0))
        #expect(model.recordingClock == nil)
        #expect(model.statusIcon == .idle)
    }

    @Test func aDiscardAndAWriterlessStopAlsoReturnToIdle() {
        // Both share the `.finished` arm's fallthrough; losing either leaves the icon claiming a
        // capture that has demonstrably ended.
        for event: EngineEvent in [.discarded, .stopped(.userStopped)] {
            let (model, _) = recording()
            model.apply(event)
            #expect(model.statusIcon == .idle)
            #expect(model.recordingClock == nil)
        }
    }

    // MARK: - What the take leaves behind (M21-T3, amended M23-T1)

    @Test func anOrdinaryEndingRecordsTheFileAndItsLength() {
        let (model, _) = recording()
        model.apply(.finished(url: Self.url, reason: .userStopped, droppedFrames: 0))
        #expect(model.finishedRecording?.url == Self.url)
    }

    @Test func aWriteFailedEndingRecordsNothing() {
        // M23-T1: renaming or exporting onto the volume that just refused a write is the wrong
        // next move, so the naming prompt and Stop & Copy are never offered it.
        let (model, _) = recording()
        model.apply(.finished(url: Self.url, reason: .writeFailed, droppedFrames: 0))
        #expect(model.finishedRecording == nil)
    }

    @Test(arguments: endReasons.filter { $0 != .writeFailed })
    func everyOtherEndingStillRecordsIt(reason: EndReason) {
        // The negative control: without it, suppressing *every* ending passes the test above and
        // silently retires M21-T3.
        let (model, _) = recording()
        model.apply(.finished(url: Self.url, reason: reason, droppedFrames: 0))
        #expect(model.finishedRecording?.url == Self.url)
    }

    // MARK: - Failure routing: which notice outlives the session

    @Test func aStartFailureOutlivesTheSession() {
        let (model, reports) = makeModel()
        model.apply(.failed(message: "No displays available"))
        #expect(reports.failures.count == 1)
        #expect(reports.failures.first?.message == "No displays available")
        // False here would drop the reason a start failed at teardown — leaving the menu Ready
        // with no explanation (M17-T2).
        #expect(reports.failures.first?.outlives == true)
        #expect(model.statusIcon == .idle)
    }

    @Test func losingTheMicrophoneReportsWithoutEndingTheSession() {
        // ADR-012: the recording continues. An icon that dropped to idle here would tell the user
        // their 90-minute capture had stopped when it hadn't.
        let (model, reports) = recording()
        model.apply(.microphoneLost)
        #expect(model.statusIcon == .recording)
        #expect(model.recordingClock != nil)
        #expect(reports.failures.first?.message != nil)
        #expect(reports.failures.first?.outlives == false)   // must not survive the session
    }

    @Test func recoveryClearsTheNoticeRatherThanAddingOne() {
        // A message here would leave the loss notice standing after the mic came back.
        let (model, reports) = recording()
        model.apply(.microphoneLost)
        model.apply(.microphoneRecovered)
        #expect(reports.failures.last?.message == nil)
        #expect(reports.failures.last?.outlives == false)
    }

    @Test func aSilentMicrophoneAndItsRecoveryFollowTheSameShape() {
        let (model, reports) = recording()
        model.apply(.microphoneSilent)
        #expect(reports.failures.last?.message != nil)
        #expect(model.statusIcon == .recording)
        model.apply(.microphoneAudible)
        #expect(reports.failures.last?.message == nil)
    }

    @Test func aRestoredFileReportsNothingBecauseTheNotificationCarriesIt() {
        let (model, reports) = recording()
        model.apply(.recordingFileRestored)
        #expect(reports.failures.isEmpty)
        #expect(model.statusIcon == .recording)
    }

    // MARK: - Notification routing

    @Test func theFoldPostsTheNotificationAnEventWarrants() {
        let (model, reports) = recording()
        model.apply(.finished(url: Self.url, reason: .userStopped, droppedFrames: 0))
        #expect(reports.notifications.count == 1)
        #expect(reports.notifications.first?.title.hasPrefix("Recording saved") == true)
    }

    @Test func aDiscardPostsNothing() {
        // The confirmation alert was the acknowledgement; a banner would be noise (M6-T12).
        let (model, reports) = recording()
        model.apply(.discarded)
        #expect(reports.notifications.isEmpty)
    }

    // MARK: - Publish discipline (M6-T10: a publish rebuilds the OPEN menu's rows)

    @Test func refreshProgressPublishesNothingWhenTheValuesHaveNotMoved() {
        let (model, _) = makeModel()
        model.refreshProgress()

        let published = Flag()
        withObservationTracking {
            _ = model.elapsedSeconds
            _ = model.recordedBytes
        } onChange: {
            published.raise()
        }
        model.refreshProgress()      // idle: both values pinned at zero
        #expect(!published.isRaised)
    }

    @Test func aSessionWithNoCaptureReportsZeroRatherThanNaN() {
        // `recordedDuration` is NaN until the first frame (02 §10); leaking that into the menu
        // renders as "nan" in the clock.
        let (model, _) = makeModel()
        model.refreshProgress()
        #expect(model.elapsedSeconds == 0)
        #expect(model.recordedBytes == 0)
    }

    // MARK: - Lifecycle

    @Test func aFreshModelIsIdleAndInactive() {
        let (model, _) = makeModel()
        #expect(model.statusIcon == .idle)
        #expect(!model.isActive)          // no capture attached
        #expect(!model.isPaused)
        #expect(model.finishedRecording == nil)
    }

    @Test func clearDropsWhatTheNextSessionMustNotInherit() throws {
        // `activeMicrophoneName` and friends are fixed for a session (SCK binds once, 02 §4), so a
        // leftover would have the next take's menu naming a mic that isn't in it.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionmodel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("Recording.mov")

        let (model, _) = recording()
        // Constructed, never started: no capture hardware is touched until `start()`.
        let capture = try RecordingSession(
            configuration: CaptureConfiguration(), outputURL: output)
        model.attach(
            capture, outputURL: output, microphoneName: "AirPods Pro",
            appName: "Slack", region: CGSize(width: 100, height: 50))
        #expect(model.isActive)
        #expect(model.activeMicrophoneName == "AirPods Pro")

        model.clear()
        #expect(!model.isActive)
        #expect(model.currentOutputURL == nil)
        #expect(model.activeMicrophoneName == nil)
        #expect(model.activeAppName == nil)
        #expect(model.activeRegion == nil)
        #expect(model.finishedRecording == nil)
        #expect(model.elapsedSeconds == 0)
        #expect(model.recordedBytes == 0)
    }
}

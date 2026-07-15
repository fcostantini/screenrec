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

    /// An AppState that has been through `started`, i.e. the first complete video frame landed.
    private func recordingState() -> AppState {
        let state = AppState()
        state.apply(.started)
        return state
    }

    @Test func idleBeforeAnythingHappens() {
        #expect(AppState().statusIcon == .idle)
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
        let state = AppState()
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

    @Test func consumesAWholeSessionFromItsEventStream() async {
        // The production path: RecordingSession hands over a stream, not loose events. It ends
        // by finishing the stream, so `consume` must return rather than hang the caller.
        let state = AppState()
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
